use std::sync::{Arc, Mutex};

use fuzzymatch::testing::{ScriptedDecider, choose, none_of_these};
use fuzzymatch::{
    Branch, Branches, ConfigError, Criterion, Decision, Error, Matcher, NONE_LABEL, Verdict, branches,
};
use serde_json::json;

branches! {
    enum Intent {
        Refund => Branch::new("customer wants their money back").min_confidence(0.9),
        OrderStatus => Branch::new("customer asks where their order is"),
    }
}

fn support(decision: Decision) -> Matcher<Intent, ScriptedDecider> {
    Matcher::new("What is the customer asking for?", ScriptedDecider::new(decision)).unwrap()
}

#[test]
fn matches_the_winning_branch() {
    let m = support(choose(Intent::Refund, 0.95)).classify("I was charged twice").unwrap();
    assert_eq!(m.verdict, Verdict::Matched(Intent::Refund));
    assert_eq!(m.clone().into_result(), Ok(Intent::Refund));
    assert_eq!(m.confidence, 0.95);
    assert_eq!(m.model.as_deref(), Some("scripted"));
}

#[test]
fn sends_every_branch_plus_none_as_options() {
    let support = support(choose(Intent::Refund, 0.95));
    let _ = support.classify("anything").unwrap();

    let [call] = support.decider().calls().try_into().unwrap();
    assert_eq!(call.instructions, "What is the customer asking for?");
    assert_eq!(
        call.options,
        [
            ("Refund".to_owned(), Criterion::from("customer wants their money back")),
            ("OrderStatus".to_owned(), Criterion::from("customer asks where their order is")),
            (NONE_LABEL.to_owned(), Criterion::from("None of the other options describe this.")),
        ]
    );
    assert!(call.guards.is_empty());
}

#[test]
fn examples_and_not_for_become_structured_criteria() {
    branches! {
        enum Plan {
            Cancel => Branch::new("customer wants to cancel").examples(["kill my plan"]).not_for("pausing the subscription"),
        }
    }
    let m = Matcher::<Plan, _>::new("?", ScriptedDecider::new(choose(Plan::Cancel, 0.9))).unwrap();
    let _ = m.classify("x").unwrap();
    let options = &m.decider().calls()[0].options;
    assert_eq!(
        serde_json::to_value(&options[0].1).unwrap(),
        json!({"description": "customer wants to cancel", "examples": ["kill my plan"], "not_for": "pausing the subscription"})
    );
}

#[test]
fn none_of_these_is_no_match() {
    let m = support(none_of_these(0.97)).classify("what's your favourite colour?").unwrap();
    assert_eq!(m.verdict, Verdict::NoMatch);
    assert_eq!(m.verdict.top(), None);
}

#[test]
fn per_branch_thresholds_are_risk_scaled() {
    // 0.8 confidence clears the default (0.7) for OrderStatus but not Refund's 0.9.
    let status = support(choose(Intent::OrderStatus, 0.8)).classify("x").unwrap();
    let refund = support(choose(Intent::Refund, 0.8)).classify("x").unwrap();

    assert_eq!((status.verdict, status.threshold), (Verdict::Matched(Intent::OrderStatus), 0.7));
    assert_eq!((refund.verdict, refund.threshold), (Verdict::LowConfidence(Intent::Refund), 0.9));
    assert_eq!(refund.verdict.top(), Some(Intent::Refund)); // the top pick is still reported, for escalation
    assert_eq!(refund.verdict.matched(), None);
}

#[test]
fn builder_sets_the_default_threshold() {
    let m = Matcher::builder("?")
        .min_confidence(0.85)
        .build(ScriptedDecider::new(choose(Intent::OrderStatus, 0.8)))
        .unwrap()
        .classify("x")
        .unwrap();
    assert_eq!((m.verdict, m.threshold), (Verdict::LowConfidence(Intent::OrderStatus), 0.85));
}

#[test]
fn into_result_carries_the_miss() {
    let unmatched = support(choose(Intent::Refund, 0.5)).classify("hmm").unwrap().into_result().unwrap_err();
    assert_eq!(unmatched.0.verdict, Verdict::LowConfidence(Intent::Refund));
    assert_eq!(
        unmatched.to_string(),
        "no branch matched (low_confidence; top=Refund, confidence=0.50, threshold=0.90)"
    );
}

branches! {
    enum Guarded {
        Refund => Branch::new("customer wants their money back").when("The message includes an order number"),
        Vip => Branch::new("a VIP customer").when("The customer says they are a premium member"),
    }
}

#[test]
fn guards_are_asked_in_the_same_call_for_every_branch() {
    let decision =
        choose(Guarded::Refund, 0.95).with_guard(Guarded::Refund, 0.9).with_guard(Guarded::Vip, 0.1);
    let m = Matcher::new("?", ScriptedDecider::new(decision)).unwrap();

    assert_eq!(m.classify("refund order #123").unwrap().verdict, Verdict::Matched(Guarded::Refund));
    let [call] = m.decider().calls().try_into().unwrap();
    assert_eq!(
        call.guards,
        [
            ("guard__Refund".to_owned(), "The message includes an order number".to_owned()),
            ("guard__Vip".to_owned(), "The customer says they are a premium member".to_owned()),
        ]
    );
}

#[test]
fn failed_guard_does_not_match() {
    let decision =
        choose(Guarded::Refund, 0.95).with_guard(Guarded::Refund, 0.2).with_guard(Guarded::Vip, 0.9);
    let m =
        Matcher::new("?", ScriptedDecider::new(decision)).unwrap().classify("give me my money back").unwrap();
    assert_eq!((m.verdict, m.guard), (Verdict::GuardFailed(Guarded::Refund), Some(0.2)));
}

#[test]
fn low_confidence_wins_over_a_failed_guard() {
    let decision =
        choose(Guarded::Refund, 0.3).with_guard(Guarded::Refund, 0.2).with_guard(Guarded::Vip, 0.9);
    let m = Matcher::new("?", ScriptedDecider::new(decision)).unwrap().classify("x").unwrap();
    assert_eq!(m.verdict, Verdict::LowConfidence(Guarded::Refund));
}

#[test]
fn missing_guard_is_an_error() {
    let m = Matcher::<Guarded, _>::new("?", ScriptedDecider::new(choose(Guarded::Refund, 0.95))).unwrap();
    assert!(matches!(m.classify("x"), Err(Error::MissingGuard("Refund"))));
}

#[test]
fn rejects_confidence_that_is_not_a_probability() {
    // NaN compares false against every threshold, so it must not slip through as a match.
    for confidence in [f64::NAN, 1.5, -0.1] {
        let result = support(choose(Intent::Refund, confidence)).classify("x");
        assert!(
            matches!(result, Err(Error::InvalidProbability { ref name, .. }) if name == "confidence"),
            "{confidence}: {result:?}"
        );
    }
}

#[test]
fn rejects_guard_probabilities_that_are_not_probabilities() {
    for p in [f64::NAN, 1.5, -0.1] {
        let decision =
            choose(Guarded::Refund, 0.95).with_guard(Guarded::Refund, p).with_guard(Guarded::Vip, 0.9);
        let result = Matcher::<Guarded, _>::new("?", ScriptedDecider::new(decision)).unwrap().classify("x");
        assert!(
            matches!(result, Err(Error::InvalidProbability { ref name, .. }) if name == "guard__Refund"),
            "{p}: {result:?}"
        );
    }
}

#[test]
fn observer_sees_every_decision() {
    let seen = Arc::new(Mutex::new(Vec::new()));
    let log = Arc::clone(&seen);
    let support = Matcher::builder("?")
        .observer(move |state, m| log.lock().unwrap().push((state.clone(), m.verdict)))
        .build(ScriptedDecider::new(choose(Intent::Refund, 0.95)))
        .unwrap();
    let _ = support.classify("charged twice").unwrap();
    assert_eq!(*seen.lock().unwrap(), [(json!("charged twice"), Verdict::Matched(Intent::Refund))]);
}

#[test]
fn ranked_orders_by_probability() {
    let decision = choose(Intent::Refund, 0.4).with_probabilities([
        (None, 0.2),
        (Some(Intent::Refund), 0.5),
        (Some(Intent::OrderStatus), 0.3),
    ]);
    let m = support(decision).classify("x").unwrap();
    let order: Vec<_> = m.ranked().into_iter().map(|(pick, _)| pick).collect();
    assert_eq!(order, [Some(Intent::Refund), Some(Intent::OrderStatus), None]);
}

#[test]
fn state_can_be_structured() {
    let support = support(choose(Intent::Refund, 0.95));
    let state = json!({"subject": "Duplicate charge", "body": "Charged twice"});
    let _ = support.classify(&state).unwrap();
    assert_eq!(support.decider().calls()[0].state, state);
}

#[test]
fn state_can_be_any_serializable_type() {
    #[derive(serde::Serialize)]
    struct Ticket<'a> {
        subject: &'a str,
    }
    let support = support(choose(Intent::Refund, 0.95));
    let _ = support.classify(&Ticket { subject: "Duplicate charge" }).unwrap();
    assert_eq!(support.decider().calls()[0].state, json!({"subject": "Duplicate charge"}));
}

#[test]
fn rejects_options_that_were_never_offered() {
    let m = support(Decision::new("made_up", 0.9));
    assert!(matches!(m.classify("x"), Err(Error::UnknownOption(label)) if label == "made_up"));
}

#[test]
fn rejects_probabilities_for_options_that_were_never_offered() {
    let mut decision = choose(Intent::Refund, 0.95);
    decision.probabilities.push(("made_up".to_owned(), 0.01));
    assert!(matches!(support(decision).classify("x"), Err(Error::UnknownOption(_))));
}

#[test]
fn decider_errors_propagate() {
    let m = Matcher::<Intent, _>::new("?", ScriptedDecider::from_fn(|_| Err("network down".into()))).unwrap();
    assert!(matches!(m.classify("x"), Err(Error::Decider(e)) if e.to_string() == "network down"));
}

// -- configuration ---------------------------------------------------------------------------
// `branches!` can't produce most of these (labels are variant names, and it needs at least one
// variant), so they use hand-written impls.

macro_rules! hand_written {
    ($name:ident, [$($label:literal => $description:expr),*]) => {
        #[derive(Clone, Copy, Debug, PartialEq, Eq)]
        struct $name(usize);

        const LABELS: &[&str] = &[$($label),*];

        impl Branches for $name {
            const ALL: &'static [Self] = &{
                let mut all = [$name(0); LABELS.len()];
                let mut i = 0;
                while i < all.len() {
                    all[i] = $name(i);
                    i += 1;
                }
                all
            };
            fn label(self) -> &'static str {
                LABELS[self.0]
            }
            fn branch(self) -> Branch {
                let descriptions: Vec<Branch> = vec![$($description),*];
                descriptions[self.0].clone()
            }
        }
    };
}

fn build<B: Branches>() -> Result<Matcher<B, ScriptedDecider>, ConfigError> {
    Matcher::new("?", ScriptedDecider::new(none_of_these(0.9)))
}

#[test]
fn rejects_the_reserved_label() {
    hand_written!(Reserved, ["none_of_these" => Branch::new("x")]);
    assert_eq!(build::<Reserved>().unwrap_err(), ConfigError::ReservedLabel);
}

#[test]
fn rejects_labels_that_are_not_identifiers() {
    hand_written!(Spaced, ["not valid" => Branch::new("x")]);
    assert_eq!(build::<Spaced>().unwrap_err(), ConfigError::InvalidLabel("not valid"));
}

#[test]
fn rejects_duplicate_labels() {
    hand_written!(Twice, ["same" => Branch::new("first"), "same" => Branch::new("second")]);
    assert_eq!(build::<Twice>().unwrap_err(), ConfigError::DuplicateLabel("same"));
}

#[test]
fn rejects_empty_descriptions() {
    hand_written!(Blank, ["blank" => Branch::new("   ")]);
    assert_eq!(build::<Blank>().unwrap_err(), ConfigError::EmptyDescription("blank"));
}

#[test]
fn needs_at_least_one_branch() {
    hand_written!(Empty, []);
    assert_eq!(build::<Empty>().unwrap_err(), ConfigError::NoBranches);
}

#[test]
fn rejects_confidence_outside_zero_to_one() {
    hand_written!(Sure, ["sure" => Branch::new("x").min_confidence(1.5)]);
    assert!(matches!(build::<Sure>(), Err(ConfigError::Probability { value: 1.5, .. })));

    let decider = ScriptedDecider::new(none_of_these(0.9));
    let error = Matcher::<Intent, ()>::builder("?").guard_threshold(f64::NAN).build(decider).unwrap_err();
    assert!(matches!(error, ConfigError::Probability { ref name, .. } if name == "guard_threshold"));
}
