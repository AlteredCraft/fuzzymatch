"""From judgments to a release decision. All arithmetic and thresholds live here.

The rule for review is "only when it could change the answer": an uncertain
commit is flagged if resolving it the other way would raise the bump.
"""

import re
from dataclasses import dataclass, field

from semver_judge.model import KIND_BUMP, Bump, Judgment, Kind


@dataclass(frozen=True)
class Thresholds:
    breaking_yes: float = 0.8
    """P(breaking) at or above this counts as breaking."""
    breaking_no: float = 0.3
    """P(breaking) below this counts as not breaking; between the two needs review."""
    kind: float = 0.7
    """Kind confidence needed to trust the kind outright."""
    plausible: float = 0.2
    """An alternative kind this probable is considered when checking if review matters."""


@dataclass(frozen=True)
class Review:
    sha: str
    subject: str
    reason: str
    could_be: Bump


@dataclass(frozen=True)
class Release:
    current: str
    bump: Bump
    next: str
    needs_review: list[Review] = field(default_factory=list)


def commit_bump(j: Judgment, t: Thresholds) -> Bump:
    if j.breaking >= t.breaking_yes:
        return Bump.MAJOR
    return KIND_BUMP.get(j.kind, Bump.NONE)


def worst_case(j: Judgment, t: Thresholds) -> tuple[Bump, str | None]:
    """The highest bump this commit could plausibly mean, and why it's uncertain."""
    if t.breaking_no <= j.breaking < t.breaking_yes:
        return Bump.MAJOR, f"may be breaking (P={j.breaking:.2f})"
    if j.kind_confidence < t.kind:
        plausible = [
            Kind(k)
            for k, p in j.kind_probabilities.items()
            if p >= t.plausible and k in Kind._value2member_map_
        ]
        highest = max((KIND_BUMP.get(k, Bump.NONE) for k in plausible), default=Bump.MINOR)
        return highest, f"kind unclear ({j.kind} at {j.kind_confidence:.2f})"
    return commit_bump(j, t), None


def decide_release(
    current: str, judgments: list[Judgment], t: Thresholds | None = None, *, zero_major_is_minor: bool = True
) -> Release:
    t = t or Thresholds()
    bump = max((commit_bump(j, t) for j in judgments), default=Bump.NONE)
    chosen = next_version(current, bump, zero_major_is_minor)
    reviews = []
    for j in judgments:
        could_be, reason = worst_case(j, t)
        # Review only if resolving this commit the other way would change the version
        # (on 0.x a "major" is a minor, so it may not).
        if reason and could_be > bump and next_version(current, could_be, zero_major_is_minor) != chosen:
            reviews.append(Review(j.commit.sha, j.commit.subject, reason, could_be))
    return Release(current, bump, chosen, reviews)


_VERSION = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)")


def next_version(current: str, bump: Bump, zero_major_is_minor: bool = True) -> str:
    m = _VERSION.match(current)
    if not m:
        raise ValueError(f"not a semantic version: {current!r}")
    prefix = "v" if current.startswith("v") else ""
    major, minor, patch = (int(x) for x in m.groups())
    if major == 0 and zero_major_is_minor and bump is Bump.MAJOR:
        bump = Bump.MINOR  # 0.x: breaking changes bump the minor version
    if bump is Bump.MAJOR:
        major, minor, patch = major + 1, 0, 0
    elif bump is Bump.MINOR:
        minor, patch = minor + 1, 0
    elif bump is Bump.PATCH:
        patch += 1
    return f"{prefix}{major}.{minor}.{patch}"
