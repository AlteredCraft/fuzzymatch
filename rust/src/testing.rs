//! Test doubles, so dispatch logic can be tested without a network or an API key.

use std::sync::Mutex;

use serde_json::Value;

use crate::branch::{Branches, Criterion, NONE_LABEL};
use crate::decider::{BoxError, Decider, Decision, Request};

/// A decision for `branch` at `confidence`, from a model called "scripted".
pub fn choose<B: Branches>(branch: B, confidence: f64) -> Decision {
    Decision::new(branch.label(), confidence).with_model("scripted")
}

/// A decision for "none of these" at `confidence`.
pub fn none_of_these(confidence: f64) -> Decision {
    Decision::new(NONE_LABEL, confidence).with_model("scripted")
}

/// What the matcher asked the decider, recorded for assertions.
#[derive(Clone, Debug, PartialEq)]
pub struct Call {
    pub state: Value,
    pub instructions: String,
    pub options: Vec<(String, Criterion)>,
    pub guards: Vec<(String, String)>,
}

type Script = Box<dyn Fn(&Value) -> Result<Decision, BoxError> + Send + Sync>;

/// Returns decisions you script, and records every call.
///
/// ```
/// # use fuzzymatch::{Branch, branches};
/// # branches! { enum Intent { Refund => Branch::new("wants money back") } }
/// use fuzzymatch::testing::{ScriptedDecider, choose, none_of_these};
///
/// let decider = ScriptedDecider::from_fn(|state| {
///     Ok(match state.as_str() {
///         Some(text) if text.contains("charged") => choose(Intent::Refund, 0.95),
///         _ => none_of_these(0.9),
///     })
/// });
/// ```
pub struct ScriptedDecider {
    script: Script,
    calls: Mutex<Vec<Call>>,
}

impl ScriptedDecider {
    /// Return `decision` every time.
    pub fn new(decision: Decision) -> Self {
        Self::from_fn(move |_| Ok(decision.clone()))
    }

    /// Compute each decision (or an error) from the state.
    pub fn from_fn(script: impl Fn(&Value) -> Result<Decision, BoxError> + Send + Sync + 'static) -> Self {
        Self { script: Box::new(script), calls: Mutex::new(Vec::new()) }
    }

    /// Every call so far, oldest first.
    pub fn calls(&self) -> Vec<Call> {
        self.calls.lock().unwrap_or_else(|poisoned| poisoned.into_inner()).clone()
    }
}

impl Decider for ScriptedDecider {
    fn decide(&self, request: &Request<'_>) -> Result<Decision, BoxError> {
        let call = Call {
            state: request.state.clone(),
            instructions: request.instructions.to_owned(),
            options: request.options.iter().map(|(label, c)| ((*label).to_owned(), c.clone())).collect(),
            guards: request.guards.to_vec(),
        };
        self.calls.lock().unwrap_or_else(|poisoned| poisoned.into_inner()).push(call);
        (self.script)(request.state)
    }
}
