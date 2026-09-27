//! Route support messages by meaning, with risk-scaled confidence and a guard.
//!
//!     export TYPESAFE_API_KEY=sk-...
//!     cargo run --example support_router

use fuzzymatch::{Branch, Decider, JevDecider, Match, Matcher, Verdict, branches, label_of};

branches! {
    /// What the customer is asking for.
    enum Intent {
        /// Refunds move money: demand more certainty, and an order number, like
        /// `Refund if has_order_number =>`.
        Refund => Branch::new("customer wants their money back for a purchase")
            .min_confidence(0.9)
            .when("The message includes an order number")
            .not_for("asking about a charge they don't recognise (that's BillingQuestion)"),
        OrderStatus => Branch::new("customer asks where their order is or when it will arrive"),
        BillingQuestion => Branch::new("customer has a question about a charge, invoice or payment method"),
        ChurnRisk => Branch::new("customer says they will cancel or leave for a competitor").min_confidence(0.6),
    }
}

fn support<D: Decider>(decider: D) -> Matcher<Intent, D> {
    Matcher::builder("What is the customer asking for?").build(decider).expect("valid branches")
}

/// Add a variant to `Intent` and this stops compiling until you decide where it goes.
fn route(m: &Match<Intent>) -> String {
    match m.verdict {
        Verdict::Matched(Intent::Refund) => "→ refund workflow".into(),
        Verdict::Matched(Intent::OrderStatus) => "→ order lookup (no model needed)".into(),
        Verdict::Matched(Intent::BillingQuestion) => "→ billing queue".into(),
        Verdict::Matched(Intent::ChurnRisk) => "→ page the retention team".into(),
        Verdict::LowConfidence(_) | Verdict::GuardFailed(_) | Verdict::NoMatch => escalate(m),
    }
}

/// Anything uncertain, off-topic, or missing a guard goes to a stronger model or a human, with the
/// ranked options as a head start.
fn escalate(m: &Match<Intent>) -> String {
    let top: Vec<_> =
        m.ranked().iter().take(3).map(|&(pick, p)| format!("{} {:.0}%", label_of(pick), p * 100.0)).collect();
    format!("→ escalate ({}; {})", m.verdict, top.join(", "))
}

const MESSAGES: &[&str] = &[
    "Order #88213 arrived broken. I want a refund.",
    "I want my money back.", // refund without an order number: the guard fails
    "Where's my package? It's been two weeks.",
    "What is this $14.99 charge on my card?",
    "Honestly I'm about done with you people, your competitor is half the price.",
    "Do you have a recipe for banana bread?",
];

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let support = support(JevDecider::from_env()?);
    for message in MESSAGES {
        let m = support.classify(message)?;
        println!("{message}");
        println!(
            "  [{}] top={} confidence={:.2} (needs {:.2}) {}ms {}",
            m.verdict,
            label_of(m.verdict.top()),
            m.confidence,
            m.threshold,
            m.latency.as_millis(),
            m.model.as_deref().unwrap_or("-"),
        );
        println!("  {}", route(&m));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use fuzzymatch::testing::{ScriptedDecider, choose};

    fn reply(decision: fuzzymatch::Decision, message: &str) -> String {
        route(&support(ScriptedDecider::new(decision)).classify(message).unwrap())
    }

    #[test]
    fn refund_needs_an_order_number() {
        let with_number = choose(Intent::Refund, 0.95).with_guard(Intent::Refund, 0.9);
        let without_number = choose(Intent::Refund, 0.95).with_guard(Intent::Refund, 0.1);

        assert_eq!(reply(with_number, "Order #88213 arrived broken"), "→ refund workflow");
        assert!(reply(without_number, "I want my money back").starts_with("→ escalate (guard_failed"));
    }

    #[test]
    fn escalation_carries_the_ranked_options() {
        let unsure = choose(Intent::Refund, 0.6).with_guard(Intent::Refund, 0.9).with_probabilities([
            (Some(Intent::Refund), 0.6),
            (Some(Intent::BillingQuestion), 0.3),
            (None, 0.1),
        ]);
        assert_eq!(
            reply(unsure, "hmm"),
            "→ escalate (low_confidence; Refund 60%, BillingQuestion 30%, none_of_these 10%)"
        );
    }
}
