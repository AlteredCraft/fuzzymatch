"""The port between the matcher and whatever model makes the judgment.

The matcher never talks to a model directly. It hands a `Decider` the state, the options (one per
branch, plus "none of these"), and any guard statements, and gets back a `Decision`. That keeps the
dispatch logic testable without a network and lets the model behind it be swapped.
"""

from collections.abc import Mapping
from dataclasses import dataclass, field
from typing import Any, Protocol


@dataclass(frozen=True)
class Decision:
    """A model's answer to one dispatch question, plus its guard checks."""

    choice: str
    """Label of the most probable option."""
    confidence: float
    """How concentrated the distribution is (0-1), as reported by the model."""
    probabilities: Mapping[str, float]
    """Probability of every option, keyed by label."""
    guards: Mapping[str, float] = field(default_factory=dict)
    """Probability (0-1) that each guard statement is true, keyed by guard name."""
    model: str | None = None
    """The model version that answered, for audit logs."""


class Decider(Protocol):
    """Anything that can pick one option for a state and check guard statements alongside it."""

    def decide(
        self,
        state: Any,
        *,
        instructions: str,
        options: Mapping[str, Any],
        guards: Mapping[str, str],
    ) -> Decision:
        """Choose one of `options` for `state` and evaluate every guard statement.

        Args:
            state: Text or JSON-compatible data to judge.
            instructions: The dispatch question, e.g. "What is the customer asking for?".
            options: Label -> description (a string, or a JSON object for richer criteria).
            guards: Guard name -> a statement that is either true or false of the state.
        """
        ...
