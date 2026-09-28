"""The data that flows through semver-judge."""

from dataclasses import dataclass, field
from enum import IntEnum, StrEnum


class Kind(StrEnum):
    FEAT = "feat"
    FIX = "fix"
    PERF = "perf"
    REFACTOR = "refactor"
    DOCS = "docs"
    TEST = "test"
    BUILD = "build"
    CI = "ci"
    CHORE = "chore"
    REVERT = "revert"
    OTHER = "other"


class Bump(IntEnum):
    NONE = 0
    PATCH = 1
    MINOR = 2
    MAJOR = 3

    def __str__(self) -> str:
        return self.name.lower()


# What each kind of change does to the version on its own (breaking changes override).
KIND_BUMP: dict[Kind, Bump] = {
    Kind.FEAT: Bump.MINOR,
    Kind.FIX: Bump.PATCH,
    Kind.PERF: Bump.PATCH,
    Kind.REVERT: Bump.PATCH,
}


@dataclass(frozen=True)
class Commit:
    sha: str
    subject: str
    body: str = ""
    files: tuple[str, ...] = ()
    """`path (+added -removed)` lines, most-changed first."""

    @property
    def short(self) -> str:
        return self.sha[:7]


@dataclass(frozen=True)
class Judgment:
    """What we concluded about one commit, and how sure we are."""

    commit: Commit
    kind: Kind
    kind_confidence: float
    kind_probabilities: dict[str, float] = field(default_factory=dict)
    breaking: float = 0.0
    """Probability the change breaks existing users (1.0 when the author flagged it)."""
    user_visible: float = 0.5
    source: str = "model"
    """"conventional" when the commit message said so, "model" when Jev judged it."""
    model: str | None = None
