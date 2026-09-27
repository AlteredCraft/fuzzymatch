"""Exercise JevDecider through the real TypeSafe SDK, with only the HTTP layer mocked.

This checks that the questions we build are valid SDK objects, that the request body has the wire
shape, and that a response in the documented shape parses back into a Decision.
"""

import json

import httpx2
import pytest
from typesafe_sdk import TypeSafeClient

from fuzzymatch import NONE_LABEL, Matcher, Outcome
from fuzzymatch.jev import DISPATCH_KEY, JevDecider


def mocked_client(answers, captured):
    def handler(request: httpx2.Request) -> httpx2.Response:
        captured.append(json.loads(request.content))
        body = {"model": "jev-1.13.0", "usage": {"input_tokens": 120, "output_tokens": 0}, "answers": answers}
        return httpx2.Response(200, json=body)

    return TypeSafeClient(api_key="sk-test", transport=httpx2.MockTransport(handler))


def test_request_carries_one_choice_and_a_noul_per_guard():
    captured = []
    answers = {
        DISPATCH_KEY: {
            "type": "choice",
            "choice": "refund",
            "confidence": 0.91,
            "probabilities": {"refund": 0.93, "order_status": 0.04, NONE_LABEL: 0.03},
        },
        "guard__refund": {"type": "noul", "noul": 0.88},
    }
    decider = JevDecider(mocked_client(answers, captured), model="jev-1.13.0")

    result = decider.decide(
        "I was charged twice for order #4411",
        instructions="What is the customer asking for?",
        options={"refund": "wants money back", "order_status": "where is my order", NONE_LABEL: "none"},
        guards={"guard__refund": "The message includes an order number"},
    )

    [body] = captured
    assert body["state"] == "I was charged twice for order #4411"
    assert body["model"] == "jev-1.13.0"
    assert body["questions"][DISPATCH_KEY] == {
        "type": "choice",
        "instructions": "What is the customer asking for?",
        "criteria": {"refund": "wants money back", "order_status": "where is my order", NONE_LABEL: "none"},
    }
    assert body["questions"]["guard__refund"] == {
        "type": "noul",
        "instructions": "The message includes an order number",
    }

    assert result.choice == "refund"
    assert result.confidence == 0.91
    assert result.probabilities[NONE_LABEL] == 0.03
    assert result.guards == {"guard__refund": 0.88}
    assert result.model == "jev-1.13.0"


def test_matcher_end_to_end_over_mocked_http():
    captured = []
    answers = {
        DISPATCH_KEY: {
            "type": "choice",
            "choice": "destructive",
            "confidence": 0.97,
            "probabilities": {"read_only": 0.01, "destructive": 0.98, NONE_LABEL: 0.01},
        }
    }
    shell = Matcher(
        "What would running this command do?", decider=JevDecider(mocked_client(answers, captured))
    )

    @shell.on("only reads or lists things; changes nothing", min_confidence=0.9)
    def read_only(cmd):
        return "run"

    @shell.on("deletes or overwrites data in a way that cannot be undone", min_confidence=0.3)
    def destructive(cmd):
        return "block"

    match = shell.match("rm -rf ./build && git push --force")
    assert match.outcome is Outcome.MATCHED
    assert shell("rm -rf ./build && git push --force") == "block"
    assert captured[0]["model"] == "jev-latest"  # SDK default when no model is pinned
    assert "guard__" not in json.dumps(captured[0]["questions"])


def test_default_decider_needs_an_api_key(monkeypatch):
    monkeypatch.delenv("TYPESAFE_API_KEY", raising=False)
    m = Matcher("?")  # building and registering never needs a key...

    @m.on("anything")
    def anything(s):
        return s

    with pytest.raises(Exception, match="(?i)api key"):  # ...only the first decision does
        m.match("x")
