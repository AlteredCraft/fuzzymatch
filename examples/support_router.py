"""Route support messages by meaning, with risk-scaled confidence and a guard.

export TYPESAFE_API_KEY=sk-...
uv run examples/support_router.py
"""

from fuzzymatch import Match, Matcher

support = Matcher(
    "What is the customer asking for?",
    observer=lambda message, m: print(
        f"  [{m.outcome}] top={m.branch} confidence={m.confidence:.2f} "
        f"(needs {m.threshold:.2f}) {m.latency_ms:.0f}ms {m.model}"
    ),
)


@support.on(
    "customer wants their money back for a purchase",
    min_confidence=0.9,  # refunds move money: demand more certainty
    when="The message includes an order number",  # like `case refund if has_order_number`
    not_for="asking about a charge they don't recognise (that's billing_question)",
)
def refund(message: str) -> str:
    return "→ refund workflow"


@support.on("customer asks where their order is or when it will arrive")
def order_status(message: str) -> str:
    return "→ order lookup (no model needed)"


@support.on("customer has a question about a charge, invoice or payment method")
def billing_question(message: str) -> str:
    return "→ billing queue"


@support.on("customer says they will cancel or leave for a competitor", min_confidence=0.6)
def churn_risk(message: str) -> str:
    return "→ page the retention team"


@support.otherwise
def escalate(message: str, match: Match) -> str:
    # Anything uncertain, off-topic, or missing a guard goes to a stronger model or a human,
    # with the ranked options as a head start.
    top = ", ".join(f"{label} {p:.0%}" for label, p in match.ranked()[:3])
    return f"→ escalate ({match.outcome}; {top})"


MESSAGES = [
    "Order #88213 arrived broken. I want a refund.",
    "I want my money back.",  # refund without an order number: the guard fails
    "Where's my package? It's been two weeks.",
    "What is this $14.99 charge on my card?",
    "Honestly I'm about done with you people, your competitor is half the price.",
    "Do you have a recipe for banana bread?",
]

if __name__ == "__main__":
    for message in MESSAGES:
        print(message)
        print(" ", support(message))
