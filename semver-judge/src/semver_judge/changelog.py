"""Group commits into a changelog using the authors' own words.

No text is generated: each line is the commit subject (minus any Conventional
prefix) and its short SHA. The model only decides which section a line goes in.
"""

from semver_judge.conventional import parse
from semver_judge.model import Judgment, Kind
from semver_judge.policy import Release, Thresholds

SECTIONS = [
    ("Breaking changes", None),
    ("Features", Kind.FEAT),
    ("Fixes", Kind.FIX),
    ("Performance", Kind.PERF),
]


def render(release: Release, judgments: list[Judgment], t: Thresholds | None = None) -> str:
    t = t or Thresholds()
    lines = [f"## {release.next}", "", f"`{release.current}` → `{release.next}` ({release.bump} bump)", ""]
    used: set[str] = set()

    breaking = [j for j in judgments if j.breaking >= t.breaking_yes]
    for title, kind in SECTIONS:
        items = (
            breaking
            if kind is None
            else [j for j in judgments if j.kind is kind and j.commit.sha not in used]
        )
        if items:
            lines += [f"### {title}", ""] + [_line(j) for j in items] + [""]
            used.update(j.commit.sha for j in items)

    other_visible = [j for j in judgments if j.commit.sha not in used and j.user_visible >= 0.5]
    if other_visible:
        lines += ["### Other changes", ""] + [_line(j) for j in other_visible] + [""]
    internal = len(judgments) - len(used) - len(other_visible)
    if internal:
        lines += [f"_{internal} internal change{'s' if internal != 1 else ''} not listed._", ""]

    if release.needs_review:
        lines += ["### Needs a human decision", ""]
        lines += [
            f"- `{r.sha[:7]}` {r.subject} — {r.reason}; could mean a {r.could_be} bump"
            for r in release.needs_review
        ]
        lines.append("")
    return "\n".join(lines)


def _line(j: Judgment) -> str:
    return f"- {parse(j.commit.subject, j.commit.body).description} (`{j.commit.short}`)"
