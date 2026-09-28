"""semver-judge: decide the next version from the commits since the last tag.

  semver-judge                      judge commits since the latest tag
  semver-judge --since v1.2.0       ...since a specific ref
  semver-judge --offline            Conventional Commits only, no model calls
  semver-judge --json               machine-readable output
  semver-judge --github             also write GITHUB_OUTPUT / GITHUB_STEP_SUMMARY

Exit code: 0, or 3 with --fail-on-review when a commit needs a human decision.
"""

import argparse
import json
import os
import sys
from dataclasses import asdict
from pathlib import Path

from semver_judge import changelog, git
from semver_judge.judge import Decider, JevDecider, judge_commit
from semver_judge.policy import Thresholds, decide_release

REVIEW_EXIT = 3


def main(argv: list[str] | None = None, decider: Decider | None = None) -> int:
    p = argparse.ArgumentParser(prog="semver-judge", description=__doc__.splitlines()[0])
    p.add_argument("--repo", type=Path, default=Path.cwd())
    p.add_argument("--since", default="", help="ref to compare from (default: latest tag)")
    p.add_argument("--current", default="", help="current version (default: the --since tag, else 0.0.0)")
    p.add_argument("--model", default=None, help="pin a model version, e.g. jev-1.13.0")
    p.add_argument("--offline", action="store_true", help="no model: Conventional Commits prefixes only")
    p.add_argument("--json", action="store_true")
    p.add_argument("--github", action="store_true", help="write GitHub Actions outputs and step summary")
    p.add_argument("--fail-on-review", action="store_true")
    args = p.parse_args(argv)

    since = args.since or git.latest_tag(args.repo)
    current = args.current or since or "0.0.0"
    commits = git.commits_since(args.repo, since)

    if not args.offline and decider is None:
        decider = JevDecider(model=args.model)
    judgments = [judge_commit(c, None if args.offline else decider) for c in commits]

    thresholds = Thresholds()
    release = decide_release(current, judgments, thresholds)
    notes = changelog.render(release, judgments, thresholds)

    if args.json:
        payload = {
            "current": release.current,
            "bump": str(release.bump),
            "next": release.next,
            "needs_review": [asdict(r) | {"could_be": str(r.could_be)} for r in release.needs_review],
            "commits": [
                {
                    "sha": j.commit.sha,
                    "subject": j.commit.subject,
                    "kind": str(j.kind),
                    "kind_confidence": j.kind_confidence,
                    "breaking": j.breaking,
                    "user_visible": j.user_visible,
                    "source": j.source,
                    "model": j.model,
                }
                for j in judgments
            ],
        }
        print(json.dumps(payload, indent=2))
    else:
        print(notes)

    if args.github:
        _github_outputs(release, notes)
    return REVIEW_EXIT if args.fail_on_review and release.needs_review else 0


def _github_outputs(release, notes: str) -> None:
    if path := os.environ.get("GITHUB_OUTPUT"):
        with open(path, "a") as f:
            f.write(f"bump={release.bump}\nnext-version={release.next}\n")
            f.write(f"needs-review={'true' if release.needs_review else 'false'}\n")
    if path := os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(path, "a") as f:
            f.write(notes + "\n")


if __name__ == "__main__":
    sys.exit(main())
