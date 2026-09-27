# fuzzymatch

**Pattern matching on meaning.** Dispatch to handlers by a plain-language description instead of a
pattern, and let a calibrated confidence decide whether a branch runs or the call falls through.

```python
from fuzzymatch import Matcher

support = Matcher("What is the customer asking for?")

@support.on("customer wants their money back", min_confidence=0.9, when="The message includes an order number")
def refund(message): ...

@support.on("customer asks where their order is")
def order_status(message): ...

@support.otherwise
def escalate(message, match):  # no match, not sure enough, or the guard failed
    ...

support("Order #88213 arrived broken. I want a refund.")
```

A Python `match` statement dispatches on the *shape* of a value. `fuzzymatch` dispatches on what the
value *means*, and it keeps what makes `match` trustworthy: a fixed set of arms, guards, and a
`case _` fallback.

There is also a [Rust port](rust/README.md), where the branches are variants of your own enum and
the compiler checks that every outcome is handled.

> **Status: proof of concept.** The request and response mapping is tested through the real TypeSafe
> SDK with only the HTTP layer mocked, but it has not yet been run against the live API. See
> [Limits](#limits).

## Why this is built on Jev

[Jev](https://typesafe.ai/blog/introducing-system-one-models-and-jev) is TypeSafe's "System One" model.
It doesn't generate text: it answers typed questions about some state and returns probabilities. That
is exactly what a dispatch table needs:

- **One call, whatever the number of branches.** Every branch description becomes an option of a single
  Choice question, and each `when=` guard becomes a Noul question in the same request. Jev evaluates
  them in parallel, so a tenth branch or guard costs a few input tokens, not another round trip.
  TypeSafe quotes 70-500 ms end to end, at $0.042 per million input tokens with free output.
- **It can't pick an arm that doesn't exist.** The answer is always one of the options you registered
  (or "none of these"). There's nothing to parse and no hallucinated label.
- **Confidence is part of the answer.** Jev is trained to report calibrated confidence, so a branch
  can demand as much certainty as its side effects warrant.

## How it works

```
state ──► Choice: one option per branch + "none_of_these"  ─┐
          Noul:   one per `when=` guard                     ├─► one Jev request ─► Match ─► handler
                                                           ─┘                            └─► otherwise
```

A call resolves to one of four outcomes, recorded on the `Match`:

| Outcome          | When                                                           | Runs        |
| ---------------- | -------------------------------------------------------------- | ----------- |
| `matched`        | the top branch clears its `min_confidence` and its guard holds | the branch  |
| `low_confidence` | the top branch is below its `min_confidence`                   | `otherwise` |
| `guard_failed`   | the top branch is confident but its `when=` statement is false | `otherwise` |
| `no_match`       | the model picks "none of these"                                | `otherwise` |

With no `otherwise` handler, anything but `matched` raises `Unmatched`, so a miss is never silent.

### Branch options

```python
@matcher.on(
    "deletes or overwrites data in a way that may not be recoverable",  # what belongs here
    min_confidence=0.5,              # certainty this branch needs (default: the matcher's 0.7)
    when="The command targets files outside the project",  # guard, like `case x if cond`
    examples=["rm -rf build", "git push --force"],        # to separate similar branches
    not_for="commands that only move files",              # what belongs to a neighbour instead
    label="destructive",             # option label sent to the model (default: function name)
)
def destructive(state, match): ...
```

**Set thresholds by what a wrong call would cost.** A handler that moves money or deletes data should
need high confidence to run automatically. A handler that only asks a person to look can accept less.
The shell guard example uses both.

Handlers take `(state)` or `(state, match)`. The `Match` carries the outcome, confidence, the full
probability distribution (`match.ranked()`), the guard probability, the model version and latency.
That's what an `otherwise` handler needs to escalate an uncertain call to a stronger model or a
person. Pass `observer=` to log every decision for audit or threshold tuning.

State can be a string or JSON-compatible data (`{"subject": ..., "body": ...}`).

## Examples

- [`examples/support_router.py`](examples/support_router.py): support triage with thresholds scaled to
  risk, a guard (refunds need an order number), and escalation that carries the ranked options.
- [`examples/shell_guard.py`](examples/shell_guard.py): a **Claude Code PreToolUse hook** that judges
  Bash commands by what they'd do rather than by pattern. It catches `find . -delete`,
  `git clean -fdx` and the rest of the ways `Bash(rm *)` rules miss. It asks before destructive
  commands, never denies outright, and falls back to Claude Code's normal permission flow on any error.

```bash
export TYPESAFE_API_KEY=sk-...
uv run examples/support_router.py
echo '{"tool_name":"Bash","tool_input":{"command":"git clean -fdx"},"cwd":"/tmp"}' | uv run examples/shell_guard.py
```

## Install

```bash
uv add git+https://github.com/AlteredCraft/fuzzymatch
```

Requires Python 3.11+ and a TypeSafe API key in `TYPESAFE_API_KEY`. Jev is in early access.

## Testing without a network

The matcher never calls a model directly. It depends on a small `Decider` port, and `JevDecider` is
one adapter. Tests swap in a `ScriptedDecider`:

```python
from fuzzymatch.testing import ScriptedDecider, decision

support.decider = ScriptedDecider(decision("refund", confidence=0.95, guards={"guard__refund": 0.9}))
assert support("Order #1 arrived broken") == ...
```

The same port lets you pin a model version in production (`JevDecider(model="jev-...")`), or put an
LLM, or an open System One model, behind the same interface.

```bash
uv run pytest
```

## Limits

- **Not yet run against the live API.** The adapter is checked against the real SDK's request
  building and response validation, not a real model's answers.
- **Pin the model before tuning thresholds.** The SDK default is `jev-latest`, which can change
  without notice and shift confidence along with it.
- **Jev's own limits apply.** It takes text only (no images), reads instructions literally, can't count
  or compare dates, and text in the state can argue for an answer. Don't put text an adversary
  controls in the state of a high-stakes matcher. The shell guard deliberately leaves out the agent's
  own description of the command for this reason.
- Up to 254 branches per matcher (Jev takes 255 options; one is reserved for "none of these").
- Synchronous only for now.

## Ideas for next steps

- `async` matchers on `AsyncTypeSafeClient`
- an `escalate_to=` decider, so uncertain calls go to a frontier model automatically
- a small tool that replays observer logs to suggest per-branch thresholds
- nested matchers for hierarchical routing, and a TypeScript port (a [Rust port](rust/README.md) exists)

## License

MIT
