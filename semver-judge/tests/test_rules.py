import pytest

from semver_judge.changelog import render
from semver_judge.conventional import parse
from semver_judge.model import Bump, Commit, Judgment, Kind
from semver_judge.policy import decide_release, next_version


@pytest.mark.parametrize(
    "subject, body, kind, breaking, description",
    [
        ("feat(cli): add --dry-run", "", Kind.FEAT, False, "add --dry-run"),
        ("fix!: stop swallowing errors", "", Kind.FIX, True, "stop swallowing errors"),
        ("refactor: split module", "BREAKING CHANGE: import path moved", Kind.REFACTOR, True, "split module"),
        ("Feature: nicer output", "", Kind.FEAT, False, "nicer output"),
        ("Handle empty config files", "", None, False, "Handle empty config files"),
        ("wip: something", "", None, False, "wip: something"),
        ('Revert "feat: add probe"', "", Kind.REVERT, False, 'Revert "feat: add probe"'),
    ],
)
def test_conventional_prefixes(subject, body, kind, breaking, description):
    parsed = parse(subject, body)
    assert (parsed.kind, parsed.breaking, parsed.description) == (kind, breaking, description)


@pytest.mark.parametrize(
    "current, bump, expected",
    [
        ("1.4.2", Bump.PATCH, "1.4.3"),
        ("v1.4.2", Bump.MINOR, "v1.5.0"),
        ("1.4.2", Bump.MAJOR, "2.0.0"),
        ("0.3.1", Bump.MAJOR, "0.4.0"),  # 0.x: breaking bumps minor
        ("1.4.2", Bump.NONE, "1.4.2"),
    ],
)
def test_next_version(current, bump, expected):
    assert next_version(current, bump) == expected


def test_next_version_rejects_non_semver():
    with pytest.raises(ValueError):
        next_version("release-7", Bump.PATCH)


def j(subject, kind, conf=0.95, breaking=0.05, probs=None, visible=0.9, sha=None):
    commit = Commit(sha=sha or f"{abs(hash(subject)):040x}"[:40], subject=subject)
    return Judgment(commit, kind, conf, probs or {kind.value: conf}, breaking, visible)


def test_highest_bump_wins():
    release = decide_release(
        "1.0.0", [j("fix: a", Kind.FIX), j("feat: b", Kind.FEAT), j("docs: c", Kind.DOCS)]
    )
    assert (release.bump, release.next, release.needs_review) == (Bump.MINOR, "1.1.0", [])


def test_confident_breaking_is_major():
    release = decide_release("1.0.0", [j("Rename the config key", Kind.REFACTOR, breaking=0.91)])
    assert release.bump is Bump.MAJOR


def test_uncertain_breaking_is_reviewed_only_when_it_would_raise_the_bump():
    maybe = j("Change default timeout", Kind.FIX, breaking=0.5)
    reviewed = decide_release("1.0.0", [maybe])
    assert reviewed.bump is Bump.PATCH
    assert [r.could_be for r in reviewed.needs_review] == [Bump.MAJOR]

    already_major = decide_release("1.0.0", [maybe, j("drop py3.9", Kind.BUILD, breaking=0.95)])
    assert already_major.needs_review == []


def test_unclear_kind_is_reviewed_if_a_plausible_kind_bumps_higher():
    unclear = j("Handle empty config", Kind.FIX, conf=0.5, probs={"fix": 0.5, "feat": 0.35, "chore": 0.15})
    release = decide_release("1.0.0", [unclear])
    assert release.bump is Bump.PATCH
    assert release.needs_review[0].could_be is Bump.MINOR

    harmless = j("Tidy things", Kind.CHORE, conf=0.5, probs={"chore": 0.5, "refactor": 0.4, "docs": 0.1})
    assert decide_release("1.0.0", [harmless]).needs_review == []


def test_changelog_uses_subjects_verbatim_and_groups_by_section():
    judgments = [
        j("feat(cli)!: drop --legacy", Kind.FEAT, breaking=1.0, sha="a" * 40),
        j("feat: add --json", Kind.FEAT, sha="b" * 40),
        j("Handle empty config files", Kind.FIX, sha="c" * 40),
        j("chore: bump deps", Kind.CHORE, visible=0.1, sha="d" * 40),
        j("Change default timeout", Kind.FIX, breaking=0.5, sha="e" * 40),
    ]
    release = decide_release("1.4.2", judgments)
    notes = render(release, judgments)
    assert "## 2.0.0" in notes
    assert "### Breaking changes\n\n- drop --legacy (`aaaaaaa`)" in notes
    assert "### Features\n\n- add --json (`bbbbbbb`)" in notes  # the breaking feat isn't listed twice
    assert "- Handle empty config files (`ccccccc`)" in notes
    assert "_1 internal change not listed._" in notes
    assert "Needs a human decision" not in notes  # already major: the uncertain one can't raise it


def test_on_zero_x_a_possible_break_that_cannot_change_the_version_is_not_reviewed():
    # 0.4.1 with a feat is already 0.5.0; a "major" on 0.x is also 0.5.0, so nothing to decide.
    judgments = [j("feat: a", Kind.FEAT), j("Change default timeout", Kind.FIX, breaking=0.5)]
    release = decide_release("0.4.1", judgments)
    assert (release.next, release.needs_review) == ("0.5.0", [])

    # ...but it still matters on 1.x
    assert decide_release("1.4.1", judgments).needs_review
