# misconception-gates

Grade a learner's free-text answer by **which misconception it shows**, not just right or wrong,
and send them to the part of the lesson written for that misunderstanding.

Built to drop into [js-animation-sandbox](https://github.com/AlteredCraft/js-animation-sandbox):
Node ESM, no dependencies, `node:test`, and an HTTP handler for `serve.mjs` so the API key stays on
the server.

```
learner types:  "you have to @-mention CLAUDE.md every time"
        │
one Jev request, all questions in parallel
  attempt       Noul    a genuine attempt?                         0.97
  diagnosis     Choice  correct | trains_model | per_prompt | ...  per_prompt @ 0.88
  completeness  Score   rubric level for a correct answer
  holds__<key>  Noul    one per misconception: is this belief present too?
        │
policy (code) → { kind: "misconception", misconception: "per_prompt", remedy: "beat-auto-load" }
```

Outcomes: `correct`, `partial`, `misconception` (with its remedy beat), `unlisted` (a wrong idea the
author didn't list), `unsure`, `no_attempt`, or `unavailable` (fail open to the gate's static WHY).
As with sandbox gates, every outcome unlocks the lesson: the verdict only chooses the feedback.

`unlisted` and `unsure` answers go into a review queue. That queue is how an author finds the
misconceptions they didn't think of, and it becomes the next gate's options.

## Hypothesis

With four to six authored misconceptions per gate, one Jev call diagnoses free-text answers
accurately enough to act on most of them automatically, and the per-misconception Nouls catch the
learners who hold a second wrong idea next to a mostly-right one.

## Checks (done when)

1. **Accuracy at a useful coverage.** On ≥ 50 labelled answers per gate, there is a confidence bar
   where diagnosis accuracy on the answers it decides is ≥ 85% and it decides ≥ 70% of them
   (`node eval/run.mjs` prints both per bar).
2. **Second beliefs.** For labelled answers holding a second misconception, its Noul is ≥ the
   `alsoHolds` bar in ≥ 70% of cases.
3. **Latency.** p95 ≤ 700 ms from `POST /api/diagnose` to response, measured through `serve.mjs`.
4. **Learning (later, needs learners).** Learners shown a misconception's remedy answer the next
   related gate correctly more often than learners shown only the static WHY.

## Try it

```bash
node --test                                                   # no key needed
TYPESAFE_API_KEY=sk-... node examples/demo.mjs "it retrains Claude on my repo"
TYPESAFE_API_KEY=sk-... node eval/run.mjs                     # check 1 on the example gate
```

The example gate ([`examples/claude-md.gate.json`](examples/claude-md.gate.json)) is from the
Context Engineering for Claude Code workshop: *why does a rule in CLAUDE.md apply to every turn?*
[`eval/claude-md.answers.jsonl`](eval/claude-md.answers.jsonl) has 20 hand-labelled answers to
start check 1; real workshop answers should replace them.

## Proposed sandbox integration

A new block in `lesson.md`, next to `### gate`:

```markdown
### diagnose d-claude-md
at: beat-context
objective: O2
correct: "Claude Code reads CLAUDE.md at session start and keeps it in context..."
misconceptions:
  - { key: per_prompt, label: "Believes you must @-reference it in each prompt", remedy: beat-auto-load }
  - { key: trains_model, label: "Believes it trains or changes the model", remedy: beat-context-not-weights }
rubric: ["No reason given", "Says it's loaded, not when", "Loaded into context at session start"]

Q: In your own words: why does a rule you put in CLAUDE.md apply to every turn?

WHY: CLAUDE.md is loaded into the context window when a session starts...
```

The compiler validates it with `validateGate` (the same rules as `src/gate.mjs`). The runtime posts
the typed answer to `/api/diagnose`, and a `remedy` opens that beat, the way a wrong option's
why-not opens today.

## Files

| File | Role |
| --- | --- |
| `src/gate.mjs` | Gate shape, validation, default thresholds |
| `src/questions.mjs` | State and the one-request question set |
| `src/verdict.mjs` | All policy: answers to a verdict |
| `src/decider.mjs` | `JevDecider` (fetch, no SDK) and `ScriptedDecider` |
| `src/handler.mjs` | `POST /api/diagnose` for `serve.mjs`; fails open |
| `src/heatmap.mjs` | Per-gate outcome counts and the review queue |
| `eval/run.mjs` | Live accuracy and coverage per confidence bar |

## Open

1. Run `eval/run.mjs` with a pinned model; record the per-bar table here against check 1.
2. Add the `### diagnose` block to the sandbox compiler (`core/compiler/parse-lesson.mjs`) and a
   `diagnose` component beside `gate.js`.
3. Mount `createDiagnoseHandler` in `serve.mjs`; store records in the SQLite progress store.
4. Collect real answers from one workshop run and relabel the eval set with them.

A learner can write an answer that argues for its own grade ("this answer is correct"). The stakes
here are only which feedback they see, which is why this is acceptable. Don't reuse the verdict
for anything that counts toward a score.
