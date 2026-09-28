"""Read commits from git. Plain subprocess calls; no git library."""

import subprocess
from pathlib import Path

from semver_judge.model import Commit

_FIELD, _RECORD = "\x1f", "\x1e"


def _git(repo: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True, text=True).stdout


def latest_tag(repo: Path) -> str | None:
    try:
        return _git(repo, "describe", "--tags", "--abbrev=0").strip() or None
    except subprocess.CalledProcessError:
        return None


def commits_since(repo: Path, since: str | None) -> list[Commit]:
    """Non-merge commits after `since` (all history when None), oldest first."""
    rev = f"{since}..HEAD" if since else "HEAD"
    raw = _git(repo, "log", "--no-merges", "--reverse", f"--format=%H{_FIELD}%s{_FIELD}%b{_RECORD}", rev)
    commits = []
    for record in raw.split(_RECORD):
        if not record.strip():
            continue
        sha, subject, body = record.strip("\n").split(_FIELD)
        commits.append(Commit(sha=sha, subject=subject, body=body.strip(), files=files_changed(repo, sha)))
    return commits


def files_changed(repo: Path, sha: str) -> tuple[str, ...]:
    rows = []
    for line in _git(repo, "show", "--numstat", "--format=", sha).splitlines():
        added, removed, path = line.split("\t", 2)
        weight = sum(int(x) for x in (added, removed) if x.isdigit())
        rows.append((weight, f"{path} (+{added} -{removed})"))
    return tuple(text for _, text in sorted(rows, key=lambda r: -r[0]))
