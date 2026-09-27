# fuzzymatch (Rust)

**Pattern matching on meaning, checked by the compiler.** A Rust port of the Python
[`fuzzymatch`](../README.md): classify a value by what it *means* into your own enum, with a
calibrated confidence gating whether a branch matches, then dispatch with an ordinary `match`.

```rust
use fuzzymatch::{Branch, JevDecider, Matcher, Verdict, branches};

branches! {
    enum Intent {
        Refund => Branch::new("customer wants their money back")
            .min_confidence(0.9)
            .when("The message includes an order number"),
        OrderStatus => Branch::new("customer asks where their order is"),
    }
}

let support = Matcher::<Intent, _>::new("What is the customer asking for?", JevDecider::from_env()?)?;

let m = support.classify("Order #88213 arrived broken. I want a refund.")?;
match m.verdict {
    Verdict::Matched(Intent::Refund) => refund(),
    Verdict::Matched(Intent::OrderStatus) => look_up_order(),
    Verdict::LowConfidence(Intent::Refund) => ask_a_person_to_confirm_refund(&m),
    Verdict::GuardFailed(Intent::Refund) => ask_for_order_number(),
    Verdict::LowConfidence(_) | Verdict::GuardFailed(_) | Verdict::NoMatch => escalate(&m),
}
```

> **Status: proof of concept**, like the Python version. The wire format is tested over real HTTP
> against a local stand-in for the API, not against the live TypeSafe API.

## What Rust's enums and `match` buy you

The Python library had to rebuild a small `match` statement at runtime: decorators register
handlers, `@otherwise` is the `case _`, and `Unmatched` is raised if you forgot it. In Rust the
branches are variants of your own enum, and the language's `match` does the dispatching, so that
machinery either moves into the type system or disappears.

| Python                                                  | Rust                                                                     |
| ------------------------------------------------------- | ------------------------------------------------------------------------ |
| `@matcher.on(...)` registers a handler under a string   | `branches!` declares an enum variant with its `Branch`                   |
| `@matcher.otherwise`, else `Unmatched` at runtime       | the non-`Matched` arms of your `match`, required by the compiler         |
| `Outcome` plus `branch: str \| None`, `guard: float \| None` | `Verdict<B>`: `NoMatch` carries no branch, the rest carry a `B`     |
| one `otherwise` for every kind of miss                  | match on them separately: `LowConfidence(Refund)` ≠ `GuardFailed(Refund)` |
| `match.ranked()` → `[(str, float)]`                     | `ranked()` → `[(Option<B>, f64)]`, `None` is "none of these"             |
| handler arity sniffed with `inspect.signature`          | gone: there are no handlers, just your code in each arm                  |
| label, reserved-name, duplicate checks at decoration    | checked once in `build()`; `branches!` makes most of them impossible     |
| option criterion is `str \| dict`                        | `Criterion::Plain` / `Criterion::Detailed`                               |
| Jev answers told apart by `isinstance`                  | `#[serde(tag = "type")] enum Answer { Choice, Noul, Other }`             |

Concretely:

- **Exhaustiveness is the fallback check.** Leave out `NoMatch` or a variant's `Matched` arm and it
  doesn't compile (`error[E0004]`). Add a variant to the enum and every `match` on it lights up until
  you decide where it goes. The Python version could only find out at runtime, on the input that
  hit the gap.
- **Illegal states are unrepresentable.** A verdict of `NoMatch` has no branch to read; a matched
  `B` is always one of your variants, because labels coming back from the model are parsed into `B`
  (an unknown label is `Error::UnknownOption`, not a string that flows onward).
- **Guards compose.** `when(...)` is the model-evaluated guard; Rust's own `if` guards still work on
  top: `Verdict::Matched(Effect::ReadOnly) if auto_allow => allow()`.
- **A miss can be an error when you want one.** `m.into_result()?` turns anything but `Matched` into
  `Unmatched<B>`, carrying the full record, for code that would rather propagate than branch.
- **Enums constrain your side too.** The shell guard's decision type is `enum Permission { Allow, Ask }`.
  There is no `Deny`, so "this hook never blocks outright" is a guarantee, not a comment.
- **Adding a branch is still one line.** Descriptions live next to the variant in `branches!`, and
  the generated `branch()` is an exhaustive `match self`, so no variant can ship without one.

## How it works

Same design as the Python library: every variant's description becomes an option of one Choice
question (plus `none_of_these`), each `when` guard becomes a Noul question in the same request,
and Jev answers them all in one call. A call resolves to one `Verdict`:

| Verdict            | When                                                          |
| ------------------ | ------------------------------------------------------------- |
| `Matched(b)`       | `b` ranks first, clears its `min_confidence`, and its guard holds |
| `LowConfidence(b)` | `b` ranks first but is below its `min_confidence`             |
| `GuardFailed(b)`   | `b` is confident but its `when` statement is false            |
| `NoMatch`          | the model picks "none of these"                               |

`Match<B>` carries the verdict alongside the confidence, the threshold it needed, the guard
probability, every option's probability, the model version and latency. `Matcher::builder` sets
the default `min_confidence` (0.7), `guard_threshold` (0.5), the "none of these" description, and
an `observer` called after every decision for logging. State is anything `Serialize`: a `&str`,
`serde_json::Value`, or your own struct.

### Branch options

```rust
Destructive => Branch::new("deletes or overwrites data in a way that may not be recoverable")
    .min_confidence(0.5)                                   // certainty this branch needs
    .when("The command targets files outside the project") // model-evaluated guard
    .examples(["rm -rf build", "git push --force"])        // to separate similar branches
    .not_for("commands that only move files"),             // what belongs to a neighbour
```

Labels sent to the model are the variant names (`Refund`, `OrderStatus`). You can implement the
`Branches` trait by hand instead of using the macro, e.g. to choose your own labels.

## Examples

- [`examples/support_router.rs`](examples/support_router.rs): support triage with thresholds scaled
  to risk, a guard (refunds need an order number), and escalation that carries the ranked options.
- [`examples/shell_guard.rs`](examples/shell_guard.rs): the **Claude Code PreToolUse hook** that
  judges Bash commands by what they'd do. It asks before destructive commands, never denies, and
  falls back to Claude Code's normal permission flow on any error. As a compiled binary it starts
  in milliseconds, which matters for a hook that runs before every command.

```bash
export TYPESAFE_API_KEY=sk-...
cargo run --example support_router
echo '{"tool_name":"Bash","tool_input":{"command":"git clean -fdx"},"cwd":"/tmp"}' | cargo run --example shell_guard
```

## Testing without a network

The matcher depends on the small `Decider` trait, and `JevDecider` is one implementation. Tests use
`ScriptedDecider`, which also records every call:

```rust
use fuzzymatch::testing::{ScriptedDecider, choose};

let decider = ScriptedDecider::new(choose(Intent::Refund, 0.95).with_guard(Intent::Refund, 0.9));
let support = Matcher::<Intent, _>::new("What is the customer asking for?", decider)?;
assert_eq!(support.classify("Order #1 arrived broken")?.verdict, Verdict::Matched(Intent::Refund));
assert_eq!(support.decider().calls().len(), 1);
```

Build with `default-features = false` to drop the Jev adapter (and its HTTP client) and bring your
own decider.

```bash
cargo test
```

## Limits

Everything in the Python version's [Limits](../README.md#limits) applies: pin the model before
tuning thresholds, Jev's own limits, and up to 254 branches. In addition:

- The Jev adapter talks to the HTTP API directly (there's no official Rust SDK), without the Python
  SDK's automatic retries.
- Blocking only for now (`ureq`); an async `Decider` is a natural next step.
- Branch enums must be fieldless: the model picks a variant, it doesn't fill in data.
