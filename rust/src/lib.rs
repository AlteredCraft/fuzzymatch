//! Pattern matching on meaning.
//!
//! Declare the branches as variants of your own enum, each with a plain-language description.
//! A [`Matcher`] asks a model which one a state belongs to and hands back a [`Verdict`], and you
//! dispatch on it with an ordinary `match`:
//!
//! ```
//! use fuzzymatch::{Branch, Matcher, Verdict, branches};
//! # use fuzzymatch::testing::{ScriptedDecider, choose};
//!
//! branches! {
//!     enum Intent {
//!         Refund => Branch::new("customer wants their money back")
//!             .min_confidence(0.9)
//!             .when("The message includes an order number"),
//!         OrderStatus => Branch::new("customer asks where their order is"),
//!     }
//! }
//!
//! # fn main() -> Result<(), Box<dyn std::error::Error>> {
//! # let decider = ScriptedDecider::new(choose(Intent::Refund, 0.95).with_guard(Intent::Refund, 0.9));
//! let support = Matcher::<Intent, _>::new("What is the customer asking for?", decider)?;
//!
//! let m = support.classify("Order #88213 arrived broken. I want a refund.")?;
//! let reply = match m.verdict {
//!     Verdict::Matched(Intent::Refund) => "refund workflow",
//!     Verdict::Matched(Intent::OrderStatus) => "order lookup",
//!     Verdict::LowConfidence(Intent::Refund) => "ask a person to confirm the refund",
//!     Verdict::GuardFailed(Intent::Refund) => "ask for the order number",
//!     Verdict::LowConfidence(_) | Verdict::GuardFailed(_) | Verdict::NoMatch => "escalate",
//! };
//! assert_eq!(reply, "refund workflow");
//! # Ok(())
//! # }
//! ```
//!
//! The `match` is checked for exhaustiveness like any other, so forgetting a branch, or forgetting
//! to handle the ways a call can *fail* to match, doesn't compile:
//!
//! ```compile_fail,E0004
//! # use fuzzymatch::{Branch, Verdict, branches};
//! # branches! { enum Intent { Refund => Branch::new("a"), OrderStatus => Branch::new("b") } }
//! fn route(verdict: Verdict<Intent>) -> &'static str {
//!     match verdict {
//!         Verdict::Matched(Intent::Refund) => "refund workflow",
//!         Verdict::Matched(Intent::OrderStatus) => "order lookup",
//!         // error[E0004]: `Verdict::LowConfidence(_)`, `Verdict::GuardFailed(_)` and
//!         // `Verdict::NoMatch` not covered
//!     }
//! }
//! ```
//!
//! All branch descriptions become the options of one Choice question and every guard a yes/no
//! question in the same request, so adding a branch costs a few input tokens rather than another
//! round trip. The model's calibrated confidence decides whether the top branch matches, and each
//! branch can demand its own confidence, so risky branches need more certainty than harmless ones.

mod branch;
mod decider;
#[cfg(feature = "jev")]
pub mod jev;
mod matcher;
pub mod testing;

pub use branch::{Branch, Branches, Criterion, MAX_BRANCHES, NONE_LABEL, label_of};
pub use decider::{BoxError, Decider, Decision, Request};
#[cfg(feature = "jev")]
pub use jev::JevDecider;
pub use matcher::{ConfigError, Error, Match, Matcher, MatcherBuilder, Unmatched, Verdict};
