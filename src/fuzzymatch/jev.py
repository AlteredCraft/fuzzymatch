"""The TypeSafe Jev adapter for the `Decider` port.

One request carries the dispatch question (a Choice over every branch plus "none of these") and every
guard (one Noul each). Jev answers them all in parallel, so guards add input tokens but not latency.
"""

from collections.abc import Mapping
from typing import Any

from typesafe_sdk import Choice, Noul, TypeSafeClient

from fuzzymatch.decider import Decision

DISPATCH_KEY = "branch"


class JevDecider:
    """Makes dispatch decisions with a TypeSafe System One model.

    Args:
        client: A configured `TypeSafeClient`. Defaults to one built from `TYPESAFE_API_KEY`.
        model: Model to use, e.g. a pinned `jev-...` version. Pin it if you tune thresholds, since a
            moving alias can shift confidence under you. `None` uses the client default.
    """

    def __init__(self, client: TypeSafeClient | None = None, *, model: str | None = None) -> None:
        self.client = client if client is not None else TypeSafeClient()
        self.model = model

    def decide(
        self,
        state: Any,
        *,
        instructions: str,
        options: Mapping[str, Any],
        guards: Mapping[str, str],
    ) -> Decision:
        if DISPATCH_KEY in guards:
            raise ValueError(f"guard name {DISPATCH_KEY!r} is reserved")
        questions: dict[str, Choice | Noul] = {
            DISPATCH_KEY: Choice(instructions=instructions, criteria=dict(options)),
        }
        for name, statement in guards.items():
            questions[name] = Noul(instructions=statement)

        response = self.client.system_one(state=state, questions=questions, model=self.model)

        answer = response.choices[DISPATCH_KEY]
        return Decision(
            choice=answer.choice,
            confidence=answer.confidence,
            probabilities=dict(answer.probabilities),
            guards={name: response.nouls[name].noul for name in guards},
            model=response.model,
        )
