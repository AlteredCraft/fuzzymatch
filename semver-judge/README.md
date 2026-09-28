# semver-judge

Decide the next semantic version from the commits since the last tag. Code reads what the commit
messages declare; Jev judges only what they don't; a human decides only the commits that are
uncertain **and** could change the answer.

```
commits since v1.4.2
   │
   ├─ "feat(cli)!: drop --legacy"   ← Conventional prefix: feat, flagged breaking. No kind/breaking question.
   ├─ "Handle empty config files"    ← no prefix: Jev picks the kind and P(breaking)
   └─ "chore: bump deps"             ← prefix says chore; Jev still asked P(breaking): unflagged breaks happen
   │
policy (code): major > minor > patch; 0.x breaking → minor; flag commits that could raise the bump
   │
bump=minor  next=v1.5.0  needs-review=true  + a changelog built from the commit subjects, verbatim
```

## Hypothesis

A single Jev call per commit (kind, breaking, user-visible) agrees with the bump a maintainer
would choose on commits **without** Conventional prefixes, and its confidence is good enough that
"review only when uncertain and it matters" flags a small minority of releases.

## Checks (done when)

1. **Accuracy.** On the tagged history of 3–5 public repos that don't use Conventional Commits,
   the computed bump for each release matches the bump the maintainers actually made, for ≥ 85% of
   releases, excluding releases the tool flags for review.
2. **Review rate.** At most 20% of those releases are flagged `needs-review`.
3. **Unflagged breaks.** On a hand-labelled set of commits that broke users without saying so,
   `P(breaking) ≥ 0.3` (review or major) for ≥ 80% of them.
4. **Cost and speed.** Median ≤ 1 s per commit, and a 100-commit release costs < $0.01.

## Use it

```yaml
# .github/workflows/release.yml
- uses: actions/checkout@v4
  with: { fetch-depth: 0 }          # needs tags and history
- id: version
  uses: AlteredCraft/system-one-experiments/semver-judge@main
  env:
    TYPESAFE_API_KEY: ${{ secrets.TYPESAFE_API_KEY }}
  with:
    model: jev-1.13.0               # pin it: confidence can shift between versions
    fail-on-review: true
- run: echo "Releasing ${{ steps.version.outputs.next-version }} (${{ steps.version.outputs.bump }})"
```

Locally:

```bash
cd semver-judge && uv sync
uv run semver-judge --repo /path/to/repo              # changelog to stdout
uv run semver-judge --repo /path/to/repo --json       # decisions with probabilities
uv run semver-judge --repo /path/to/repo --offline    # no API key: prefixes only
```

## What's in the skeleton

| File | Role |
| --- | --- |
| `conventional.py` | Deterministic first pass over `type(scope)!:` and `BREAKING CHANGE:` |
| `judge.py` | Builds only the questions the message leaves open; `JevDecider` and `ScriptedDecider` |
| `policy.py` | Bump, next version, and the "could it change the answer?" review rule |
| `changelog.py` | Sections from judgments, lines from the authors' own subjects |
| `git.py` | Commits since a ref, with per-file change counts as extra state |
| `action.yml` | Composite GitHub Action wrapping the CLI |

## Open

1. Build the check-1 harness: replay each tag range of a repo, compare to the actual next tag.
2. Label ~30 unflagged breaking commits from public changelogs for check 3.
3. Send commits concurrently (`AsyncTypeSafeClient`); one request per commit today.
4. Try adding a trimmed diff to the state and measure whether it helps check 1 or only adds tokens.

Jev's limits apply: the state is the commit message and file list, and a message written to argue
for a smaller bump can move the answer. Keep `fail-on-review` on for releases that matter.
