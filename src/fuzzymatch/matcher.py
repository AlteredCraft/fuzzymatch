"""Dispatch on meaning.

A `Matcher` is a dispatch table whose keys are descriptions instead of patterns:

    support = Matcher("What is the customer asking for?")

    @support.on("customer wants their money back", min_confidence=0.85)
    def refund(message): ...

    @support.otherwise
    def escalate(message, match): ...

    support("I was charged twice for the same order")

All branch descriptions become the options of one Choice question, so adding a branch costs a few
input tokens rather than another round trip. The model's calibrated confidence decides whether the
winning branch runs or the call falls through to `otherwise`, and each branch can demand its own
confidence, so risky handlers need more certainty than harmless ones.
"""

import inspect
import re
import time
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from enum import StrEnum
from typing import Any

from fuzzymatch.decider import Decider, Decision

NONE_LABEL = "none_of_these"
MAX_BRANCHES = 254  # Jev Choice questions take up to 255 options; one is reserved for NONE_LABEL.
_LABEL = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

Handler = Callable[..., Any]


class Outcome(StrEnum):
    """Why a call went where it went."""

    MATCHED = "matched"
    """A branch won with enough confidence and its guard (if any) held."""
    LOW_CONFIDENCE = "low_confidence"
    """A branch won, but the model was less sure than that branch requires."""
    GUARD_FAILED = "guard_failed"
    """A branch won confidently, but its `when=` statement did not hold."""
    NO_MATCH = "no_match"
    """The model judged that none of the branches describe the state."""


@dataclass(frozen=True)
class Match:
    """The full record of one dispatch decision. Handlers can take it as a second argument."""

    outcome: Outcome
    branch: str | None
    """Label of the branch the model ranked first, or None if it chose "none of these"."""
    confidence: float
    threshold: float
    """The confidence the winning branch required."""
    probabilities: Mapping[str, float]
    guard: float | None
    """Probability that the winning branch's guard holds, if it has one."""
    model: str | None
    latency_ms: float

    @property
    def matched(self) -> bool:
        return self.outcome is Outcome.MATCHED

    def ranked(self) -> list[tuple[str, float]]:
        """Options ordered from most to least probable. Useful when escalating an uncertain call."""
        return sorted(self.probabilities.items(), key=lambda item: item[1], reverse=True)


class Unmatched(LookupError):
    """Raised when nothing matched and no `otherwise` handler was registered."""

    def __init__(self, match: Match) -> None:
        super().__init__(
            f"no branch matched ({match.outcome}; top={match.branch!r}, "
            f"confidence={match.confidence:.2f}, threshold={match.threshold:.2f})"
        )
        self.match = match


@dataclass(frozen=True)
class Branch:
    label: str
    description: str
    handler: Handler
    min_confidence: float | None
    when: str | None
    examples: tuple[str, ...]
    not_for: str | None

    def criterion(self) -> str | dict[str, Any]:
        """The option description sent to the model.

        A plain string by default. When examples or a `not_for` boundary are given, an object, which
        TypeSafe recommends when neighbouring options keep getting confused.
        """
        if not self.examples and not self.not_for:
            return self.description
        criterion: dict[str, Any] = {"description": self.description}
        if self.examples:
            criterion["examples"] = list(self.examples)
        if self.not_for:
            criterion["not_for"] = self.not_for
        return criterion


class Matcher:
    """A dispatch table keyed by natural-language descriptions.

    Args:
        instructions: The question the branches answer, e.g. "What is the user trying to do?".
        decider: What makes the judgment. Defaults to `JevDecider()`, created on first use so that
            building a matcher never needs an API key.
        min_confidence: Confidence a branch needs to run unless it sets its own.
        guard_threshold: Probability a `when=` statement needs to count as true.
        none_description: Description of the implicit "none of these" option.
        observer: Called with `(state, match)` after every decision, for logging and audit.
    """

    def __init__(
        self,
        instructions: str,
        *,
        decider: Decider | None = None,
        min_confidence: float = 0.7,
        guard_threshold: float = 0.5,
        none_description: str = "None of the other options describe this.",
        observer: Callable[[Any, Match], None] | None = None,
    ) -> None:
        _check_probability("min_confidence", min_confidence)
        _check_probability("guard_threshold", guard_threshold)
        self.instructions = instructions
        self.min_confidence = min_confidence
        self.guard_threshold = guard_threshold
        self.none_description = none_description
        self.observer = observer
        self._decider = decider
        self._branches: dict[str, Branch] = {}
        self._otherwise: Handler | None = None

    # -- registration -------------------------------------------------------------------------

    def on(
        self,
        description: str,
        *,
        min_confidence: float | None = None,
        when: str | None = None,
        examples: Sequence[str] = (),
        not_for: str | None = None,
        label: str | None = None,
    ) -> Callable[[Handler], Handler]:
        """Register the decorated function as the handler for states that fit `description`.

        Args:
            description: What a state that belongs here looks like, in plain language.
            min_confidence: Confidence needed to run this handler. Set it high for handlers that do
                something hard to undo.
            when: An extra statement that must also be true, like a guard on a `case` clause
                (`case x if cond`). Evaluated in the same request as the choice.
            examples: Example inputs, to separate this branch from similar ones.
            not_for: What belongs to a neighbouring branch instead.
            label: Option label sent to the model. Defaults to the function name.
        """
        if not description.strip():
            raise ValueError("description must not be empty")
        if min_confidence is not None:
            _check_probability("min_confidence", min_confidence)

        def register(handler: Handler) -> Handler:
            name = label or handler.__name__
            if not _LABEL.match(name):
                raise ValueError(f"label {name!r} must be a Python identifier")
            if name == NONE_LABEL:
                raise ValueError(f"label {NONE_LABEL!r} is reserved")
            if name in self._branches:
                raise ValueError(f"a branch labelled {name!r} is already registered")
            if len(self._branches) >= MAX_BRANCHES:
                raise ValueError(f"a matcher supports at most {MAX_BRANCHES} branches")
            self._branches[name] = Branch(
                label=name,
                description=description,
                handler=handler,
                min_confidence=min_confidence,
                when=when,
                examples=tuple(examples),
                not_for=not_for,
            )
            return handler

        return register

    def otherwise(self, handler: Handler) -> Handler:
        """Register the fallback, run on no match, low confidence, or a failed guard."""
        self._otherwise = handler
        return handler

    @property
    def branches(self) -> tuple[Branch, ...]:
        return tuple(self._branches.values())

    @property
    def decider(self) -> Decider:
        """The decider in use, created on first access if none was given."""
        return self._get_decider()

    @decider.setter
    def decider(self, decider: Decider) -> None:
        """Swap the decider, e.g. a pinned model in production or a `ScriptedDecider` in tests."""
        self._decider = decider

    # -- dispatch -----------------------------------------------------------------------------

    def match(self, state: Any) -> Match:
        """Decide which branch `state` belongs to, without running any handler."""
        if not self._branches:
            raise ValueError("register at least one branch with @matcher.on(...) before matching")

        options: dict[str, Any] = {b.label: b.criterion() for b in self._branches.values()}
        options[NONE_LABEL] = self.none_description
        guards = {_guard_key(b.label): b.when for b in self._branches.values() if b.when}

        started = time.perf_counter()
        decision = self._get_decider().decide(
            state, instructions=self.instructions, options=options, guards=guards
        )
        latency_ms = (time.perf_counter() - started) * 1000

        match = self._resolve(decision, latency_ms)
        if self.observer is not None:
            self.observer(state, match)
        return match

    def __call__(self, state: Any) -> Any:
        """Run the handler `state` belongs to and return its result."""
        match = self.match(state)
        if match.matched:
            assert match.branch is not None
            return _invoke(self._branches[match.branch].handler, state, match)
        if self._otherwise is not None:
            return _invoke(self._otherwise, state, match)
        raise Unmatched(match)

    # -- internals ----------------------------------------------------------------------------

    def _resolve(self, decision: Decision, latency_ms: float) -> Match:
        def result(outcome: Outcome, branch: str | None, threshold: float, guard: float | None) -> Match:
            return Match(
                outcome=outcome,
                branch=branch,
                confidence=decision.confidence,
                threshold=threshold,
                probabilities=dict(decision.probabilities),
                guard=guard,
                model=decision.model,
                latency_ms=latency_ms,
            )

        if decision.choice == NONE_LABEL:
            return result(Outcome.NO_MATCH, None, self.min_confidence, None)
        branch = self._branches.get(decision.choice)
        if branch is None:
            raise RuntimeError(f"decider returned an option that was never offered: {decision.choice!r}")

        threshold = self.min_confidence if branch.min_confidence is None else branch.min_confidence
        guard = decision.guards.get(_guard_key(branch.label)) if branch.when else None
        if branch.when and guard is None:
            raise RuntimeError(f"decider did not evaluate the guard for {branch.label!r}")

        if decision.confidence < threshold:
            return result(Outcome.LOW_CONFIDENCE, branch.label, threshold, guard)
        if guard is not None and guard < self.guard_threshold:
            return result(Outcome.GUARD_FAILED, branch.label, threshold, guard)
        return result(Outcome.MATCHED, branch.label, threshold, guard)

    def _get_decider(self) -> Decider:
        if self._decider is None:
            from fuzzymatch.jev import JevDecider  # deferred: needs TYPESAFE_API_KEY at construction

            self._decider = JevDecider()
        return self._decider

    def __repr__(self) -> str:
        labels = ", ".join(self._branches)
        return f"Matcher({self.instructions!r}, branches=[{labels}])"


def _guard_key(label: str) -> str:
    return f"guard__{label}"


def _check_probability(name: str, value: float) -> None:
    if not 0.0 <= value <= 1.0:
        raise ValueError(f"{name} must be between 0 and 1, got {value}")


def _invoke(handler: Handler, state: Any, match: Match) -> Any:
    """Call `handler(state, match)`, or `handler(state)` if it only takes one argument."""
    try:
        inspect.signature(handler).bind(state, match)
    except TypeError:
        return handler(state)
    except ValueError:  # no signature available (some builtins); assume the full form
        pass
    return handler(state, match)
