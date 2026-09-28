"""The deterministic first pass: read Conventional Commits prefixes when they're there.

Code handles what code can: `feat(api)!: ...` is a feature and breaking, no model
needed. The model is only asked about what the message doesn't state, most
importantly whether an *unflagged* commit breaks users anyway.
"""

import re
from dataclasses import dataclass

from semver_judge.model import Kind

_PREFIX = re.compile(r"^(?P<type>[a-zA-Z]+)(?:\([^)]*\))?(?P<bang>!)?:\s*(?P<rest>.+)$")
_FOOTER = re.compile(r"^BREAKING[ -]CHANGE:", re.MULTILINE)
_ALIASES = {"feature": Kind.FEAT, "bugfix": Kind.FIX, "doc": Kind.DOCS, "tests": Kind.TEST}


@dataclass(frozen=True)
class Parsed:
    kind: Kind | None
    """The declared kind, or None when the message has no recognised prefix."""
    breaking: bool
    """True only when the author flagged it (`!` or a BREAKING CHANGE footer)."""
    description: str
    """The subject without its prefix, for the changelog."""


def parse(subject: str, body: str = "") -> Parsed:
    flagged = bool(_FOOTER.search(body))
    if subject.startswith('Revert "'):  # git's own revert subject
        return Parsed(kind=Kind.REVERT, breaking=flagged, description=subject.strip())
    m = _PREFIX.match(subject.strip())
    if not m:
        return Parsed(kind=None, breaking=flagged, description=subject.strip())
    raw = m["type"].lower()
    kind = _ALIASES.get(raw) or (Kind(raw) if raw in Kind._value2member_map_ else None)
    if kind is None:
        return Parsed(kind=None, breaking=flagged, description=subject.strip())
    return Parsed(kind=kind, breaking=flagged or bool(m["bang"]), description=m["rest"].strip())
