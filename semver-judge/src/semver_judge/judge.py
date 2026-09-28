"""Judge each commit: one System One request per commit.

Each request asks, in parallel, only what the commit message didn't already say:

  kind          Choice  what kind of change (skipped when a Conventional prefix declares it)
  breaking      Noul    would this break existing users? (skipped when flagged with ! / footer)
  user_visible  Noul    would users notice it? (decides changelog placement)
"""

from collections.abc import Callable, Mapping
from typing import Any, Protocol

from semver_judge.conventional import parse
from semver_judge.model import Commit, Judgment, Kind

KIND_CRITERIA: dict[str, str] = {
    "feat": "Adds a new capability, option, command or API that users can use.",
    "fix": "Corrects wrong behaviour users could hit.",
    "perf": "Makes existing behaviour faster or lighter without changing what it does.",
    "refactor": "Restructures code without changing behaviour.",
    "docs": "Documentation, comments or README only.",
    "test": "Tests only.",
    "build": "Packaging, dependencies or the build system.",
    "ci": "Continuous integration configuration.",
    "chore": "Maintenance with no effect on behaviour: formatting, renames in private code, tooling.",
    "revert": "Undoes an earlier commit.",
    "other": "None of the above.",
}

BREAKING = (
    "This change would break existing users or callers: it removes or renames something public, "
    "changes a default or an output format they rely on, or drops support for a platform or version."
)
USER_VISIBLE = "People using this software would notice this change."

# Declared kinds that are internal by definition, so offline mode leaves them out of the changelog.
INTERNAL = {Kind.REFACTOR, Kind.DOCS, Kind.TEST, Kind.BUILD, Kind.CI, Kind.CHORE}


class Decider(Protocol):
    def decide(self, state: Mapping[str, Any], questions: Mapping[str, Mapping[str, Any]]) -> dict[str, Any]:
        """Return {"model": str, "answers": {name: wire-format answer dict}}."""
        ...


def state_for(commit: Commit) -> dict[str, Any]:
    return {"subject": commit.subject, "body": commit.body[:4000], "files_changed": list(commit.files[:50])}


def questions_for(commit: Commit) -> dict[str, dict[str, Any]]:
    declared = parse(commit.subject, commit.body)
    questions: dict[str, dict[str, Any]] = {"user_visible": {"type": "noul", "instructions": USER_VISIBLE}}
    if declared.kind is None:
        questions["kind"] = {
            "type": "choice",
            "instructions": "What kind of change is this commit?",
            "criteria": KIND_CRITERIA,
        }
    if not declared.breaking:
        questions["breaking"] = {"type": "noul", "instructions": BREAKING}
    return questions


def judge_commit(commit: Commit, decider: Decider | None) -> Judgment:
    """Combine what the message declares with what the model judges.

    With no decider (offline mode) the Conventional Commits contract is taken
    at its word: a prefix without `!` is not breaking. Commits with no prefix
    become `other` at zero confidence and P(breaking)=0.5, which policy
    flags for review when they could raise the bump.
    """
    declared = parse(commit.subject, commit.body)
    if decider is None:
        if declared.kind is None:
            breaking = 1.0 if declared.breaking else 0.5
        else:
            breaking = 1.0 if declared.breaking else 0.0
        return Judgment(
            commit=commit,
            kind=declared.kind or Kind.OTHER,
            kind_confidence=1.0 if declared.kind else 0.0,
            breaking=breaking,
            user_visible=0.0 if declared.kind in INTERNAL else 0.5,
            source="conventional" if declared.kind else "none",
        )

    out = decider.decide(state_for(commit), questions_for(commit))
    answers = out["answers"]
    if declared.kind is None:
        kind_answer = answers["kind"]
        kind, confidence = Kind(kind_answer["choice"]), kind_answer["confidence"]
        probabilities = dict(kind_answer.get("probabilities", {}))
    else:
        kind, confidence, probabilities = declared.kind, 1.0, {declared.kind.value: 1.0}
    return Judgment(
        commit=commit,
        kind=kind,
        kind_confidence=confidence,
        kind_probabilities=probabilities,
        breaking=1.0 if declared.breaking else answers["breaking"]["noul"],
        user_visible=answers["user_visible"]["noul"],
        source="conventional" if declared.kind else "model",
        model=out.get("model"),
    )


class JevDecider:
    """Adapter over the TypeSafe SDK. Pin `model` before tuning thresholds."""

    def __init__(self, client: Any = None, model: str | None = None) -> None:
        if client is None:
            from typesafe_sdk import TypeSafeClient

            client = TypeSafeClient()
        self.client, self.model = client, model

    def decide(self, state: Mapping[str, Any], questions: Mapping[str, Mapping[str, Any]]) -> dict[str, Any]:
        response = self.client.system_one(state=dict(state), questions=dict(questions), model=self.model)
        return {
            "model": response.model,
            "answers": {name: answer.model_dump() for name, answer in response.answers.items()},
        }


class ScriptedDecider:
    """Test double: `script(state, questions)` returns the answers dict."""

    def __init__(self, script: Callable[[Mapping[str, Any], Mapping[str, Any]], dict[str, Any]]) -> None:
        self.script = script
        self.calls: list[tuple[Mapping[str, Any], Mapping[str, Any]]] = []

    def decide(self, state: Mapping[str, Any], questions: Mapping[str, Mapping[str, Any]]) -> dict[str, Any]:
        self.calls.append((state, questions))
        return {"model": "scripted", "answers": self.script(state, questions)}
