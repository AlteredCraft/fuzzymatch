import pytest

from fuzzymatch import NONE_LABEL, Match, Matcher, Outcome, Unmatched
from fuzzymatch.testing import ScriptedDecider, decision


def support_matcher(decider, **kwargs):
    support = Matcher("What is the customer asking for?", decider=decider, **kwargs)

    @support.on("customer wants their money back", min_confidence=0.9)
    def refund(message):
        return "refund"

    @support.on("customer asks where their order is")
    def order_status(message, match: Match):
        return ("order_status", match.confidence)

    return support


def test_runs_the_winning_handler():
    support = support_matcher(ScriptedDecider(decision("refund", 0.95)))
    assert support("I was charged twice") == "refund"


def test_passes_match_to_two_argument_handlers():
    support = support_matcher(ScriptedDecider(decision("order_status", 0.8)))
    assert support("where is my package?") == ("order_status", 0.8)


def test_sends_every_branch_plus_none_as_options():
    decider = ScriptedDecider(decision("refund"))
    support = support_matcher(decider)
    support("anything")

    [call] = decider.calls
    assert call.instructions == "What is the customer asking for?"
    assert call.options == {
        "refund": "customer wants their money back",
        "order_status": "customer asks where their order is",
        NONE_LABEL: "None of the other options describe this.",
    }
    assert call.guards == {}


def test_examples_and_not_for_become_structured_criteria():
    decider = ScriptedDecider(decision("cancel"))
    m = Matcher("?", decider=decider)

    @m.on("customer wants to cancel", examples=["kill my plan"], not_for="pausing the subscription")
    def cancel(s):
        return s

    m.match("x")
    assert decider.calls[0].options["cancel"] == {
        "description": "customer wants to cancel",
        "examples": ["kill my plan"],
        "not_for": "pausing the subscription",
    }


def test_none_of_these_falls_through_to_otherwise():
    support = support_matcher(ScriptedDecider(decision(NONE_LABEL, 0.97)))

    @support.otherwise
    def escalate(message, match):
        return match.outcome

    assert support("what's your favourite colour?") is Outcome.NO_MATCH


def test_per_branch_thresholds_are_risk_scaled():
    # 0.8 confidence clears the default (0.7) for order_status but not refund's 0.9.
    status = support_matcher(ScriptedDecider(decision("order_status", 0.8))).match("x")
    refund = support_matcher(ScriptedDecider(decision("refund", 0.8))).match("x")

    assert status.outcome is Outcome.MATCHED and status.threshold == 0.7
    assert refund.outcome is Outcome.LOW_CONFIDENCE and refund.threshold == 0.9
    assert refund.branch == "refund"  # the top pick is still reported, for escalation


def test_raises_unmatched_without_otherwise():
    support = support_matcher(ScriptedDecider(decision("refund", 0.5)))
    with pytest.raises(Unmatched) as err:
        support("hmm")
    assert err.value.match.outcome is Outcome.LOW_CONFIDENCE


def test_guards_are_asked_in_the_same_call_for_every_branch():
    decider = ScriptedDecider(decision("refund", 0.95, guards={"guard__refund": 0.9, "guard__vip": 0.1}))
    m = Matcher("?", decider=decider)

    @m.on("customer wants their money back", when="The message includes an order number")
    def refund(s):
        return "refund"

    @m.on("a VIP customer", when="The customer says they are a premium member")
    def vip(s):
        return "vip"

    assert m("refund order #123") == "refund"
    [call] = decider.calls
    assert call.guards == {
        "guard__refund": "The message includes an order number",
        "guard__vip": "The customer says they are a premium member",
    }


def test_failed_guard_falls_through():
    decider = ScriptedDecider(decision("refund", 0.95, guards={"guard__refund": 0.2}))
    m = Matcher("?", decider=decider)

    @m.on("customer wants their money back", when="The message includes an order number")
    def refund(s):
        return "refund"

    @m.otherwise
    def ask_for_order_number(s, match):
        return (match.outcome, match.guard)

    assert m("give me my money back") == (Outcome.GUARD_FAILED, 0.2)


def test_observer_sees_every_decision():
    seen = []
    support = support_matcher(ScriptedDecider(decision("refund")), observer=lambda s, m: seen.append((s, m)))
    support("charged twice")
    assert [(s, m.branch) for s, m in seen] == [("charged twice", "refund")]


def test_ranked_orders_by_probability():
    m = support_matcher(
        ScriptedDecider(
            decision("refund", 0.4, probabilities={"refund": 0.5, "order_status": 0.3, NONE_LABEL: 0.2})
        )
    ).match("x")
    assert [label for label, _ in m.ranked()] == ["refund", "order_status", NONE_LABEL]


def test_state_can_be_structured():
    decider = ScriptedDecider(decision("refund"))
    support = support_matcher(decider)
    support({"subject": "Duplicate charge", "body": "Charged twice"})
    assert decider.calls[0].state == {"subject": "Duplicate charge", "body": "Charged twice"}


@pytest.mark.parametrize(
    "register, message",
    [
        (lambda m: m.on("x", label=NONE_LABEL)(lambda s: s), "reserved"),
        (lambda m: m.on("x", label="not valid")(lambda s: s), "identifier"),
        (lambda m: m.on("   "), "empty"),
        (lambda m: m.on("x", min_confidence=1.5), "between 0 and 1"),
    ],
)
def test_rejects_bad_registrations(register, message):
    with pytest.raises(ValueError, match=message):
        register(Matcher("?", decider=ScriptedDecider(decision("a"))))


def test_rejects_duplicate_labels():
    m = Matcher("?", decider=ScriptedDecider(decision("a")))
    m.on("first", label="same")(lambda s: s)
    with pytest.raises(ValueError, match="already registered"):
        m.on("second", label="same")(lambda s: s)


def test_needs_at_least_one_branch():
    with pytest.raises(ValueError, match="at least one branch"):
        Matcher("?", decider=ScriptedDecider(decision("a"))).match("x")


def test_rejects_options_that_were_never_offered():
    support = support_matcher(ScriptedDecider(decision("made_up")))
    with pytest.raises(RuntimeError, match="never offered"):
        support.match("x")
