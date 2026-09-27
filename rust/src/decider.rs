//! The port between the matcher and whatever model makes the judgment.
//!
//! The matcher never talks to a model directly. It hands a [`Decider`] the state, the options (one
//! per branch, plus "none of these"), and any guard statements, and gets back a [`Decision`]. That
//! keeps the dispatch logic testable without a network and lets the model behind it be swapped.
//!
//! The port speaks in string labels, not your enum: that's the boundary where untyped model output
//! comes in, and the matcher is what turns it back into `B`.

use std::collections::HashMap;
use std::sync::Arc;

use serde_json::Value;

use crate::branch::{Branches, Criterion, guard_key, label_of};

/// Any error a decider can report.
pub type BoxError = Box<dyn std::error::Error + Send + Sync>;

/// One dispatch question, as the matcher asks it.
#[derive(Clone, Copy, Debug)]
pub struct Request<'a> {
    /// Text or JSON data to judge.
    pub state: &'a Value,
    /// The dispatch question, e.g. "What is the customer asking for?".
    pub instructions: &'a str,
    /// Label and description of every option, in order, ending with "none of these".
    pub options: &'a [(&'static str, Criterion)],
    /// Guard name and a statement that is either true or false of the state.
    pub guards: &'a [(String, String)],
}

/// Anything that can pick one option for a state and check guard statements alongside it.
pub trait Decider {
    /// Choose one of `request.options` and evaluate every guard in `request.guards`.
    fn decide(&self, request: &Request<'_>) -> Result<Decision, BoxError>;
}

impl<D: Decider + ?Sized> Decider for &D {
    fn decide(&self, request: &Request<'_>) -> Result<Decision, BoxError> {
        (**self).decide(request)
    }
}

impl<D: Decider + ?Sized> Decider for Box<D> {
    fn decide(&self, request: &Request<'_>) -> Result<Decision, BoxError> {
        (**self).decide(request)
    }
}

impl<D: Decider + ?Sized> Decider for Arc<D> {
    fn decide(&self, request: &Request<'_>) -> Result<Decision, BoxError> {
        (**self).decide(request)
    }
}

/// A model's answer to one dispatch question, plus its guard checks.
#[derive(Clone, Debug, PartialEq)]
pub struct Decision {
    /// Label of the most probable option.
    pub choice: String,
    /// How concentrated the distribution is (0-1), as reported by the model.
    pub confidence: f64,
    /// Probability of every option, keyed by label.
    pub probabilities: Vec<(String, f64)>,
    /// Probability (0-1) that each guard statement is true, keyed by guard name.
    pub guards: HashMap<String, f64>,
    /// The model version that answered, for audit logs.
    pub model: Option<String>,
}

impl Decision {
    /// A decision for `choice`, with probabilities defaulting to `{choice: confidence}`.
    pub fn new(choice: impl Into<String>, confidence: f64) -> Self {
        let choice = choice.into();
        Self {
            probabilities: vec![(choice.clone(), confidence)],
            choice,
            confidence,
            guards: HashMap::new(),
            model: None,
        }
    }

    /// Record the probability that `branch`'s guard holds.
    pub fn with_guard<B: Branches>(mut self, branch: B, probability: f64) -> Self {
        self.guards.insert(guard_key(branch.label()), probability);
        self
    }

    /// Replace the probability distribution. `None` stands for "none of these".
    pub fn with_probabilities<B: Branches>(
        mut self,
        probabilities: impl IntoIterator<Item = (Option<B>, f64)>,
    ) -> Self {
        self.probabilities =
            probabilities.into_iter().map(|(pick, p)| (label_of(pick).to_owned(), p)).collect();
        self
    }

    pub fn with_model(mut self, model: impl Into<String>) -> Self {
        self.model = Some(model.into());
        self
    }
}
