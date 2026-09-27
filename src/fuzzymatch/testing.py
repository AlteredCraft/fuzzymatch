"""Test doubles, so dispatch logic can be tested without a network or an API key."""

from collections.abc import Callable, Mapping
from dataclasses import dataclass
from typing import Any

from fuzzymatch.decider import Decision


def decision(
    choice: str,
    confidence: float = 0.95,
    *,
    probabilities: Mapping[str, float] | None = None,
    guards: Mapping[str, float] | None = None,
    model: str | None = "scripted",
) -> Decision:
    """Build a `Decision`. Probabilities default to `{choice: confidence}`."""
    return Decision(
        choice=choice,
        confidence=confidence,
        probabilities=dict(probabilities) if probabilities is not None else {choice: confidence},
        guards=dict(guards or {}),
        model=model,
    )


@dataclass(frozen=True)
class Call:
    """What the matcher asked the decider, recorded for assertions."""

    state: Any
    instructions: str
    options: Mapping[str, Any]
    guards: Mapping[str, str]


class ScriptedDecider:
    """Returns decisions you script, and records every call.

    Pass either a single `Decision` (returned every time) or a function from state to `Decision`.

        decider = ScriptedDecider(lambda state: decision("refund") if "charged" in state
                                  else decision("none_of_these"))
    """

    def __init__(self, script: Decision | Callable[[Any], Decision]) -> None:
        self._script = script
        self.calls: list[Call] = []

    def decide(
        self,
        state: Any,
        *,
        instructions: str,
        options: Mapping[str, Any],
        guards: Mapping[str, str],
    ) -> Decision:
        self.calls.append(Call(state, instructions, dict(options), dict(guards)))
        return self._script(state) if callable(self._script) else self._script
