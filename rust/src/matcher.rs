//! Classify a state into one of your enum's variants, gated by calibrated confidence.

use std::fmt;
use std::time::{Duration, Instant};

use serde::Serialize;
use serde_json::Value;

use crate::branch::{Branch, Branches, Criterion, MAX_BRANCHES, NONE_LABEL, guard_key, label_of};
use crate::decider::{BoxError, Decider, Decision, Request};

/// Where a call landed. The data each variant carries is exactly what that outcome knows: there is
/// no branch to speak of when the model picked "none of these".
///
/// Match on it like any other enum. The compiler makes sure every branch and every way of *not*
/// matching is handled, so a miss can't be silently dropped.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[must_use]
pub enum Verdict<B> {
    /// `B` won with enough confidence, and its guard (if any) held.
    Matched(B),
    /// `B` ranked first, but the model was less sure than `B` requires.
    LowConfidence(B),
    /// `B` won confidently, but its `when` statement did not hold.
    GuardFailed(B),
    /// The model judged that none of the branches describe the state.
    NoMatch,
}

impl<B: Copy> Verdict<B> {
    /// The branch, only if it matched.
    pub fn matched(&self) -> Option<B> {
        match *self {
            Verdict::Matched(branch) => Some(branch),
            _ => None,
        }
    }

    /// The branch the model ranked first, whether or not it matched.
    pub fn top(&self) -> Option<B> {
        match *self {
            Verdict::Matched(branch) | Verdict::LowConfidence(branch) | Verdict::GuardFailed(branch) => {
                Some(branch)
            }
            Verdict::NoMatch => None,
        }
    }

    pub fn is_matched(&self) -> bool {
        matches!(self, Verdict::Matched(_))
    }

    /// The outcome's name, for logs: `matched`, `low_confidence`, `guard_failed` or `no_match`.
    pub fn as_str(&self) -> &'static str {
        match self {
            Verdict::Matched(_) => "matched",
            Verdict::LowConfidence(_) => "low_confidence",
            Verdict::GuardFailed(_) => "guard_failed",
            Verdict::NoMatch => "no_match",
        }
    }
}

impl<B: Copy> fmt::Display for Verdict<B> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// The full record of one dispatch decision.
#[derive(Clone, Debug, PartialEq)]
#[must_use]
pub struct Match<B> {
    pub verdict: Verdict<B>,
    pub confidence: f64,
    /// The confidence the top branch required.
    pub threshold: f64,
    /// Probability that the top branch's guard holds, if it has one.
    pub guard: Option<f64>,
    /// Probability of every option. `None` is "none of these".
    pub probabilities: Vec<(Option<B>, f64)>,
    pub model: Option<String>,
    pub latency: Duration,
}

impl<B: Branches> Match<B> {
    /// Options ordered from most to least probable. Useful when escalating an uncertain call.
    pub fn ranked(&self) -> Vec<(Option<B>, f64)> {
        let mut ranked = self.probabilities.clone();
        ranked.sort_by(|a, b| b.1.total_cmp(&a.1));
        ranked
    }

    /// The matched branch, or [`Unmatched`] carrying this record, so a miss can propagate with `?`.
    pub fn into_result(self) -> Result<B, Unmatched<B>> {
        match self.verdict {
            Verdict::Matched(branch) => Ok(branch),
            _ => Err(Unmatched(self)),
        }
    }
}

/// Nothing matched. Carries the full [`Match`] so the caller can see why.
#[derive(Clone, Debug, PartialEq, thiserror::Error)]
#[error(
    "no branch matched ({}; top={}, confidence={:.2}, threshold={:.2})",
    .0.verdict, label_of(.0.verdict.top()), .0.confidence, .0.threshold
)]
pub struct Unmatched<B: Branches>(pub Match<B>);

/// Why a call could not be decided at all (as opposed to deciding "no match").
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("state could not be serialized to JSON: {0}")]
    State(#[source] serde_json::Error),
    #[error("decider failed: {0}")]
    Decider(#[source] BoxError),
    #[error("decider returned an option that was never offered: {0:?}")]
    UnknownOption(String),
    #[error("decider did not evaluate the guard for {0:?}")]
    MissingGuard(&'static str),
    #[error("decider returned {name} = {value}, which is not a probability between 0 and 1")]
    InvalidProbability { name: String, value: f64 },
}

/// A matcher that can't be built. Checked once, in [`MatcherBuilder::build`].
#[derive(Clone, Debug, PartialEq, thiserror::Error)]
pub enum ConfigError {
    #[error("a matcher needs at least one branch")]
    NoBranches,
    #[error("a matcher supports at most {MAX_BRANCHES} branches, got {0}")]
    TooManyBranches(usize),
    #[error("label {0:?} must be an identifier")]
    InvalidLabel(&'static str),
    #[error("label {NONE_LABEL:?} is reserved")]
    ReservedLabel,
    #[error("a branch labelled {0:?} is already registered")]
    DuplicateLabel(&'static str),
    #[error("the description for {0:?} must not be empty")]
    EmptyDescription(&'static str),
    #[error("{name} must be between 0 and 1, got {value}")]
    Probability { name: String, value: f64 },
}

type Observer<B> = Box<dyn Fn(&Value, &Match<B>) + Send + Sync>;

struct Arm<B> {
    branch: B,
    label: &'static str,
    min_confidence: f64,
    guard_key: Option<String>,
}

/// A dispatch table keyed by natural-language descriptions, classifying into `B`.
///
/// Every branch description becomes an option of one Choice question and every guard a yes/no
/// question in the same request, so adding a branch costs a few input tokens rather than another
/// round trip.
pub struct Matcher<B: Branches, D> {
    instructions: String,
    decider: D,
    guard_threshold: f64,
    observer: Option<Observer<B>>,
    arms: Vec<Arm<B>>,
    options: Vec<(&'static str, Criterion)>,
    guards: Vec<(String, String)>,
    default_confidence: f64,
}

impl<B: Branches> Matcher<B, ()> {
    /// Start a matcher for `instructions`, the question the branches answer, e.g.
    /// "What is the user trying to do?".
    pub fn builder(instructions: impl Into<String>) -> MatcherBuilder<B> {
        MatcherBuilder {
            instructions: instructions.into(),
            min_confidence: 0.7,
            guard_threshold: 0.5,
            none_description: "None of the other options describe this.".to_owned(),
            observer: None,
        }
    }
}

impl<B: Branches, D: Decider> Matcher<B, D> {
    /// A matcher with default settings. See [`Matcher::builder`] for the rest.
    pub fn new(instructions: impl Into<String>, decider: D) -> Result<Self, ConfigError> {
        Matcher::builder(instructions).build(decider)
    }

    /// Decide which branch `state` belongs to. `state` can be a string or anything serializable
    /// to JSON (`{"subject": ..., "body": ...}`).
    pub fn classify<S: Serialize + ?Sized>(&self, state: &S) -> Result<Match<B>, Error> {
        let state = serde_json::to_value(state).map_err(Error::State)?;
        let request = Request {
            state: &state,
            instructions: &self.instructions,
            options: &self.options,
            guards: &self.guards,
        };

        let started = Instant::now();
        let decision = self.decider.decide(&request).map_err(Error::Decider)?;
        let latency = started.elapsed();

        let found = self.resolve(decision, latency)?;
        if let Some(observer) = &self.observer {
            observer(&state, &found);
        }
        Ok(found)
    }

    pub fn instructions(&self) -> &str {
        &self.instructions
    }

    pub fn decider(&self) -> &D {
        &self.decider
    }

    /// Parse a label from the decider back into an arm. `None` is "none of these".
    fn parse(&self, label: &str) -> Result<Option<&Arm<B>>, Error> {
        if label == NONE_LABEL {
            return Ok(None);
        }
        match self.arms.iter().find(|arm| arm.label == label) {
            Some(arm) => Ok(Some(arm)),
            None => Err(Error::UnknownOption(label.to_owned())),
        }
    }

    fn resolve(&self, decision: Decision, latency: Duration) -> Result<Match<B>, Error> {
        let probabilities = decision
            .probabilities
            .iter()
            .map(|(label, p)| Ok((self.parse(label)?.map(|arm| arm.branch), *p)))
            .collect::<Result<_, Error>>()?;

        // NaN compares false against every threshold, so an unchecked NaN would fall through to
        // `Matched`: a malformed answer must never be able to run a branch.
        let confidence = checked_probability("confidence", decision.confidence)?;
        let (verdict, threshold, guard) = match self.parse(&decision.choice)? {
            None => (Verdict::NoMatch, self.default_confidence, None),
            Some(arm) => {
                let guard = match &arm.guard_key {
                    Some(key) => {
                        let p = *decision.guards.get(key).ok_or(Error::MissingGuard(arm.label))?;
                        Some(checked_probability(key, p)?)
                    }
                    None => None,
                };
                let verdict = match guard {
                    _ if confidence < arm.min_confidence => Verdict::LowConfidence(arm.branch),
                    Some(p) if p < self.guard_threshold => Verdict::GuardFailed(arm.branch),
                    _ => Verdict::Matched(arm.branch),
                };
                (verdict, arm.min_confidence, guard)
            }
        };

        Ok(Match {
            verdict,
            confidence: decision.confidence,
            threshold,
            guard,
            probabilities,
            model: decision.model,
            latency,
        })
    }
}

impl<B: Branches, D> fmt::Debug for Matcher<B, D> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let labels: Vec<_> = self.arms.iter().map(|arm| arm.label).collect();
        f.debug_struct("Matcher")
            .field("instructions", &self.instructions)
            .field("branches", &labels)
            .finish()
    }
}

/// Settings for a [`Matcher`]. Everything is validated once, in [`build`](Self::build).
pub struct MatcherBuilder<B: Branches> {
    instructions: String,
    min_confidence: f64,
    guard_threshold: f64,
    none_description: String,
    observer: Option<Observer<B>>,
}

impl<B: Branches> MatcherBuilder<B> {
    /// Confidence a branch needs to match unless it sets its own. Default 0.7.
    pub fn min_confidence(mut self, confidence: f64) -> Self {
        self.min_confidence = confidence;
        self
    }

    /// Probability a `when` statement needs to count as true. Default 0.5.
    pub fn guard_threshold(mut self, threshold: f64) -> Self {
        self.guard_threshold = threshold;
        self
    }

    /// Description of the implicit "none of these" option.
    pub fn none_description(mut self, description: impl Into<String>) -> Self {
        self.none_description = description.into();
        self
    }

    /// Called with `(state, match)` after every decision, for logging and audit.
    pub fn observer(mut self, observer: impl Fn(&Value, &Match<B>) + Send + Sync + 'static) -> Self {
        self.observer = Some(Box::new(observer));
        self
    }

    /// Check every branch of `B` and the settings, and build the matcher.
    pub fn build<D: Decider>(self, decider: D) -> Result<Matcher<B, D>, ConfigError> {
        check_probability("min_confidence".to_owned(), self.min_confidence)?;
        check_probability("guard_threshold".to_owned(), self.guard_threshold)?;
        match B::ALL.len() {
            0 => return Err(ConfigError::NoBranches),
            n if n > MAX_BRANCHES => return Err(ConfigError::TooManyBranches(n)),
            _ => {}
        }

        let mut arms: Vec<Arm<B>> = Vec::with_capacity(B::ALL.len());
        let mut options = Vec::with_capacity(B::ALL.len() + 1);
        let mut guards = Vec::new();
        for &branch in B::ALL {
            let label = branch.label();
            let spec: Branch = branch.branch();
            if !is_identifier(label) {
                return Err(ConfigError::InvalidLabel(label));
            }
            if label == NONE_LABEL {
                return Err(ConfigError::ReservedLabel);
            }
            if arms.iter().any(|arm| arm.label == label) {
                return Err(ConfigError::DuplicateLabel(label));
            }
            if spec.description().trim().is_empty() {
                return Err(ConfigError::EmptyDescription(label));
            }
            if let Some(p) = spec.required_confidence() {
                check_probability(format!("min_confidence for {label}"), p)?;
            }
            if let Some(statement) = spec.guard() {
                guards.push((guard_key(label), statement.to_owned()));
            }
            options.push((label, spec.criterion()));
            arms.push(Arm {
                branch,
                label,
                min_confidence: spec.required_confidence().unwrap_or(self.min_confidence),
                guard_key: spec.guard().map(|_| guard_key(label)),
            });
        }
        options.push((NONE_LABEL, Criterion::Plain(self.none_description)));

        Ok(Matcher {
            instructions: self.instructions,
            decider,
            guard_threshold: self.guard_threshold,
            observer: self.observer,
            arms,
            options,
            guards,
            default_confidence: self.min_confidence,
        })
    }
}

fn checked_probability(name: &str, value: f64) -> Result<f64, Error> {
    if (0.0..=1.0).contains(&value) {
        Ok(value)
    } else {
        Err(Error::InvalidProbability { name: name.to_owned(), value })
    }
}

fn check_probability(name: String, value: f64) -> Result<(), ConfigError> {
    if (0.0..=1.0).contains(&value) { Ok(()) } else { Err(ConfigError::Probability { name, value }) }
}

fn is_identifier(label: &str) -> bool {
    let mut chars = label.chars();
    matches!(chars.next(), Some(c) if c.is_ascii_alphabetic() || c == '_')
        && chars.all(|c| c.is_ascii_alphanumeric() || c == '_')
}
