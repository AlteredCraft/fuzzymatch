//! The TypeSafe Jev adapter for the [`Decider`] port.
//!
//! One request carries the dispatch question (a Choice over every branch plus "none of these") and
//! every guard (one Noul each). Jev answers them all in parallel, so guards add input tokens but not
//! latency. There is no official Rust SDK, so this speaks the documented wire format directly.

use std::collections::HashMap;
use std::time::Duration;

use indexmap::IndexMap;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::branch::Criterion;
use crate::decider::{BoxError, Decider, Decision, Request};

/// Name of the dispatch question in the request. Guards can't use it.
pub const DISPATCH_KEY: &str = "branch";

pub const API_KEY_ENV: &str = "TYPESAFE_API_KEY";
pub const BASE_URL_ENV: &str = "TYPESAFE_BASE_URL";
pub const DEFAULT_MODEL_ENV: &str = "TYPESAFE_DEFAULT_MODEL";
pub const DEFAULT_BASE_URL: &str = "https://api.typesafe.ai";
pub const DEFAULT_MODEL: &str = "jev-latest";
const SYSTEM_ONE_PATH: &str = "/v1/systemone";
const DEFAULT_TIMEOUT: Duration = Duration::from_secs(10);

/// What went wrong talking to Jev.
#[derive(Debug, thiserror::Error)]
pub enum JevError {
    #[error("no API key was provided; pass one or set the {API_KEY_ENV} environment variable")]
    MissingApiKey,
    #[error("API key must contain only printable ASCII characters without whitespace")]
    InvalidApiKey,
    #[error("guard name {DISPATCH_KEY:?} is reserved")]
    ReservedGuardName,
    #[error("request to TypeSafe failed: {0}")]
    Http(#[from] ureq::Error),
    #[error("TypeSafe returned HTTP {status}: {body}")]
    Status { status: u16, body: String },
    #[error("TypeSafe response was not valid: {0}")]
    Decode(#[source] serde_json::Error),
    #[error("TypeSafe response has no answer for {0:?}")]
    MissingAnswer(String),
    #[error("TypeSafe answered {name:?} with a {found} answer, expected {expected}")]
    WrongAnswerType { name: String, expected: &'static str, found: &'static str },
}

/// Makes dispatch decisions with a TypeSafe System One model.
///
/// Pin the model with [`model`](Self::model) if you tune thresholds, since a moving alias like
/// `jev-latest` can shift confidence under you.
#[derive(Clone)]
pub struct JevDecider {
    agent: ureq::Agent,
    api_key: String,
    base_url: String,
    model: String,
}

impl JevDecider {
    /// A decider configured from `TYPESAFE_API_KEY`, and optionally `TYPESAFE_BASE_URL` and
    /// `TYPESAFE_DEFAULT_MODEL`.
    pub fn from_env() -> Result<Self, JevError> {
        Self::from_lookup(|name| std::env::var(name).ok())
    }

    fn from_lookup(lookup: impl Fn(&str) -> Option<String>) -> Result<Self, JevError> {
        let env = |name| lookup(name).map(|v| v.trim().to_owned()).filter(|v| !v.is_empty());
        let mut decider = Self::new(env(API_KEY_ENV).ok_or(JevError::MissingApiKey)?)?;
        if let Some(url) = env(BASE_URL_ENV) {
            decider = decider.base_url(url);
        }
        if let Some(model) = env(DEFAULT_MODEL_ENV) {
            decider = decider.model(model);
        }
        Ok(decider)
    }

    /// A decider with an explicit API key.
    pub fn new(api_key: impl Into<String>) -> Result<Self, JevError> {
        let api_key = api_key.into().trim().to_owned();
        if api_key.is_empty() {
            return Err(JevError::MissingApiKey);
        }
        if !api_key.chars().all(|c| c.is_ascii_graphic()) {
            return Err(JevError::InvalidApiKey);
        }
        let config = ureq::Agent::config_builder()
            .timeout_global(Some(DEFAULT_TIMEOUT))
            .http_status_as_error(false)
            .build();
        Ok(Self {
            agent: config.into(),
            api_key,
            base_url: DEFAULT_BASE_URL.to_owned(),
            model: DEFAULT_MODEL.to_owned(),
        })
    }

    /// Use a specific model, e.g. a pinned `jev-...` version.
    pub fn model(mut self, model: impl Into<String>) -> Self {
        self.model = model.into();
        self
    }

    /// The API root. Defaults to `https://api.typesafe.ai`.
    pub fn base_url(mut self, url: impl Into<String>) -> Self {
        self.base_url = url.into().trim_end_matches('/').to_owned();
        self
    }

    /// Use your own HTTP agent, e.g. for a proxy or a different timeout.
    pub fn agent(mut self, agent: ureq::Agent) -> Self {
        self.agent = agent;
        self
    }

    fn system_one(&self, request: &Request<'_>) -> Result<Decision, JevError> {
        if request.guards.iter().any(|(name, _)| name == DISPATCH_KEY) {
            return Err(JevError::ReservedGuardName);
        }
        let body = request_body(request, &self.model);

        let mut response = self
            .agent
            .post(format!("{}{SYSTEM_ONE_PATH}", self.base_url))
            .header("Authorization", format!("Bearer {}", self.api_key))
            .header("Accept", "application/json")
            .header("User-Agent", concat!("fuzzymatch-rust/", env!("CARGO_PKG_VERSION")))
            .send_json(&body)
            .map_err(|error| match error {
                ureq::Error::StatusCode(status) => JevError::Status { status, body: String::new() },
                other => JevError::Http(other),
            })?;
        let status = response.status().as_u16();
        let text = response.body_mut().read_to_string()?;
        if !(200..300).contains(&status) {
            return Err(JevError::Status { status, body: text.chars().take(200).collect() });
        }
        parse_response(&text, request.guards)
    }
}

impl Decider for JevDecider {
    fn decide(&self, request: &Request<'_>) -> Result<Decision, BoxError> {
        Ok(self.system_one(request)?)
    }
}

impl std::fmt::Debug for JevDecider {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // The API key is left out on purpose.
        f.debug_struct("JevDecider").field("base_url", &self.base_url).field("model", &self.model).finish()
    }
}

// -- wire format ------------------------------------------------------------------------------

#[derive(Serialize)]
struct Body<'a> {
    state: &'a Value,
    model: &'a str,
    questions: IndexMap<&'a str, Question<'a>>,
}

#[derive(Serialize)]
#[serde(tag = "type", rename_all = "lowercase")]
enum Question<'a> {
    Choice { instructions: &'a str, criteria: IndexMap<&'a str, &'a Criterion> },
    Noul { instructions: &'a str },
}

#[derive(Deserialize)]
struct Response {
    model: String,
    #[serde(default)]
    answers: HashMap<String, Answer>,
}

#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "lowercase")]
enum Answer {
    Choice {
        choice: String,
        confidence: f64,
        probabilities: IndexMap<String, f64>,
    },
    Noul {
        noul: f64,
    },
    /// Score answers, and any type added after this was written.
    #[serde(other)]
    Other,
}

impl Answer {
    fn kind(&self) -> &'static str {
        match self {
            Answer::Choice { .. } => "choice",
            Answer::Noul { .. } => "noul",
            Answer::Other => "unrecognised",
        }
    }
}

fn request_body<'a>(request: &'a Request<'_>, model: &'a str) -> Body<'a> {
    let criteria = request.options.iter().map(|(label, criterion)| (*label, criterion)).collect();
    let mut questions = IndexMap::new();
    questions.insert(DISPATCH_KEY, Question::Choice { instructions: request.instructions, criteria });
    for (name, statement) in request.guards {
        questions.insert(name.as_str(), Question::Noul { instructions: statement });
    }
    Body { state: request.state, model, questions }
}

fn parse_response(text: &str, guards: &[(String, String)]) -> Result<Decision, JevError> {
    let mut response: Response = serde_json::from_str(text).map_err(JevError::Decode)?;
    let mut take =
        |name: &str| response.answers.remove(name).ok_or_else(|| JevError::MissingAnswer(name.to_owned()));
    let wrong = |name: &str, expected, found: &Answer| JevError::WrongAnswerType {
        name: name.to_owned(),
        expected,
        found: found.kind(),
    };

    let (choice, confidence, probabilities) = match take(DISPATCH_KEY)? {
        Answer::Choice { choice, confidence, probabilities } => (choice, confidence, probabilities),
        other => return Err(wrong(DISPATCH_KEY, "choice", &other)),
    };
    let guards = guards
        .iter()
        .map(|(name, _)| match take(name)? {
            Answer::Noul { noul } => Ok((name.clone(), noul)),
            other => Err(wrong(name, "noul", &other)),
        })
        .collect::<Result<_, _>>()?;

    Ok(Decision {
        choice,
        confidence,
        probabilities: probabilities.into_iter().collect(),
        guards,
        model: Some(response.model),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lookup(vars: &[(&str, &str)]) -> impl Fn(&str) -> Option<String> {
        let vars: HashMap<String, String> =
            vars.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect();
        move |name| vars.get(name).cloned()
    }

    #[test]
    fn needs_an_api_key() {
        assert!(matches!(JevDecider::from_lookup(lookup(&[])), Err(JevError::MissingApiKey)));
        assert!(matches!(
            JevDecider::from_lookup(lookup(&[(API_KEY_ENV, "  ")])),
            Err(JevError::MissingApiKey)
        ));
        assert!(matches!(JevDecider::new("sk bad"), Err(JevError::InvalidApiKey)));
    }

    #[test]
    fn reads_base_url_and_model_from_the_environment() {
        let decider = JevDecider::from_lookup(lookup(&[
            (API_KEY_ENV, " sk-test "),
            (BASE_URL_ENV, "http://localhost:9/"),
            (DEFAULT_MODEL_ENV, "jev-1.13.0"),
        ]))
        .unwrap();
        assert_eq!(decider.api_key, "sk-test");
        assert_eq!(decider.base_url, "http://localhost:9");
        assert_eq!(decider.model, "jev-1.13.0");
        assert!(!format!("{decider:?}").contains("sk-test"));
    }

    #[test]
    fn defaults_to_the_moving_alias() {
        let decider = JevDecider::from_lookup(lookup(&[(API_KEY_ENV, "sk-test")])).unwrap();
        assert_eq!(decider.model, DEFAULT_MODEL);
        assert_eq!(decider.base_url, DEFAULT_BASE_URL);
    }

    #[test]
    fn ignores_answer_types_it_does_not_model() {
        let text = r#"{"model": "jev", "answers": {
            "branch": {"type": "choice", "choice": "a", "confidence": 0.9, "probabilities": {"a": 0.9}},
            "extra": {"type": "score", "score": 3, "legend": {}, "probabilities": {}}
        }}"#;
        assert_eq!(parse_response(text, &[]).unwrap().choice, "a");
    }

    #[test]
    fn rejects_a_guard_answered_with_the_wrong_type() {
        let text = r#"{"model": "jev", "answers": {
            "branch": {"type": "choice", "choice": "a", "confidence": 0.9, "probabilities": {"a": 0.9}},
            "guard__a": {"type": "choice", "choice": "a", "confidence": 0.9, "probabilities": {}}
        }}"#;
        let guards = [("guard__a".to_owned(), "It is raining".to_owned())];
        let error = parse_response(text, &guards).unwrap_err();
        assert!(matches!(error, JevError::WrongAnswerType { expected: "noul", found: "choice", .. }));
    }

    #[test]
    fn reports_a_missing_guard_answer() {
        let text = r#"{"model": "jev", "answers": {
            "branch": {"type": "choice", "choice": "a", "confidence": 0.9, "probabilities": {"a": 0.9}}
        }}"#;
        let guards = [("guard__a".to_owned(), "It is raining".to_owned())];
        assert!(
            matches!(parse_response(text, &guards), Err(JevError::MissingAnswer(name)) if name == "guard__a")
        );
    }
}
