# System One experiments

Experiments with **System One models**, starting with TypeSafe's
[Jev](https://typesafe.ai/blog/introducing-system-one-models-and-jev): models that don't write text
but answer typed questions (a Choice, a Score, a yes/no probability) about some state, in
milliseconds, with calibrated confidence.

[Open Jev](https://huggingface.co/openjev) is an open-weights model served through the same
`/v1/systemone` API, so it can run on your own machine without a key. godot-jev runs against either
and compares them; the other experiments call TypeSafe's API only so far.

Each directory is a standalone experiment with its own stack, a hypothesis, the checks that would
confirm it, and tests that run without an API key. They were picked from areas that
[awesome-jev](https://github.com/yibie/awesome-jev) had no entries for as of 2026-09-27.

| Experiment | The idea | Stack | Status |
| --- | --- | --- | --- |
| [misconception-gates](misconception-gates/) | Grade a learner's free-text answer by *which misconception* it shows, and jump to the lesson section that fixes it | Node, no dependencies (drops into js-animation-sandbox) | Skeleton |
| [godot-jev](godot-jev/) | A Godot 4 add-on for Jev, and a text adventure whose parser understands anything but can only choose moves the author wrote | Godot 4.7, GDScript | Live: TypeSafe Jev and Open Jev |
| [semver-judge](semver-judge/) | Decide the next version from the commits since the last tag, flagging only the uncertain commits that could change the answer | Python, GitHub Action | Skeleton |

**Skeleton** means the design is in code and tested against scripted model answers, but nothing
has been run against the live API yet. Each README's first Open item is that run. **Live** means
runs against the named models are recorded, with dates, under the README's Checks.

## Shared shape

Every experiment is built the same way, because it keeps the model replaceable and the tests honest:

- **A decider port.** Code asks `decide(state, questions)` and gets typed answers back. One adapter
  calls Jev; a scripted one drives the tests. No unit test calls the network.
- **Policy in code.** Thresholds, arithmetic, dates and counting stay in ordinary code. The model
  only makes the judgments, so a policy change is a code change, not a prompt rewrite.
- **Ask only what's open.** Deterministic rules go first (a Conventional Commit prefix, the moves
  possible in a room); the model answers what they leave undecided.
- **Confidence decides the path.** Act, ask, or escalate by how sure the model is, with the bar set
  by the cost of being wrong.
- **Fail safe.** If the model is unreachable, each experiment falls back to what it did before
  (a gate's static explanation, an authored "not possible" line, Conventional Commits only).

## Running them

```bash
export TYPESAFE_API_KEY=sk-...          # only for live runs; tests never need it
export TYPESAFE_DEFAULT_MODEL=jev-1.13.0  # pin before comparing results

cd misconception-gates && node --test && node eval/run.mjs
cd godot-jev && godot --headless --path . --import && godot --headless --path . --script res://tests/run_tests.gd
cd semver-judge && uv sync && uv run pytest && uv run semver-judge --repo /path/to/repo
```

godot-jev can use a local Open Jev server instead (`JEV_BACKEND=openjev`), and
`eval/compare_backends.gd` asks both the same questions; see its README.

## Limits that apply to all of them

Jev takes text only, reads instructions literally, can't count or compare dates, and text inside
the state can argue for an answer. Where the state comes from someone with a reason to game it
(a learner, a commit author, a player), keep the stakes of any automatic action low or keep a
human in the loop.

## History

This repository started as `fuzzymatch`, a Python library for dispatching on meaning, plus a Rust
port. That code is on the [`archive/fuzzymatch`](../../tree/archive/fuzzymatch) branch.
