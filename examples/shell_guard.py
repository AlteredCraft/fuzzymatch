"""A Claude Code PreToolUse hook that judges Bash commands by what they would do.

Pattern rules like `Bash(rm *)` miss `find . -delete`, `git clean -fdx`, `> important.txt` and many
more ways to destroy data. This hook asks what the command would do instead, and scales the certainty
it needs to the cost of being wrong:

  * destructive, even at modest confidence  -> "ask": you approve it yourself
  * read-only, at very high confidence      -> "allow" (only if FUZZYMATCH_AUTO_ALLOW=1)
  * anything else, or any error             -> no decision: Claude Code's normal permissions apply

It never denies outright and fails open to the normal permission flow, so a wrong judgment or a
network error can't do more than the settings you already have allow.

Install in .claude/settings.json:

    {"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command",
        "command": "uv run --project /path/to/fuzzymatch /path/to/fuzzymatch/examples/shell_guard.py"}]}]}}

Try it without Claude Code:

    echo '{"tool_name":"Bash","tool_input":{"command":"git clean -fdx"},"cwd":"/tmp"}' \
        | uv run examples/shell_guard.py
"""

import json
import os
import sys

from fuzzymatch import Match, Matcher

AUTO_ALLOW = os.environ.get("FUZZYMATCH_AUTO_ALLOW") == "1"

shell = Matcher("What would running this shell command do to the machine and its files?")


@shell.on(
    "only reads, lists, searches or prints; changes no files, settings or remote state",
    min_confidence=0.95,
    examples=["ls -la", "git status", "grep -rn TODO src", "cat README.md"],
)
def read_only(state: dict) -> dict | None:
    return decision("allow", "judged read-only") if AUTO_ALLOW else None


@shell.on(
    "changes files or state in a way that is easy to undo or regenerate",
    examples=["git add -A", "npm install", "mkdir build", "git commit -m 'wip'"],
)
def reversible(state: dict) -> dict | None:
    return None


@shell.on(
    "deletes, overwrites or rewrites data or history in a way that may not be recoverable",
    min_confidence=0.5,  # asking costs one click; missing a destructive command costs much more
    examples=["rm -rf build", "git push --force", "git reset --hard", "find . -name '*.log' -delete"],
)
def destructive(state: dict, match: Match) -> dict:
    return decision("ask", f"fuzzymatch judged this destructive ({match.confidence:.0%} confident)")


@shell.otherwise
def unsure(state: dict) -> None:
    return None


def decision(permission: str, reason: str) -> dict:
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": permission,
            "permissionDecisionReason": reason,
        }
    }


def main() -> None:
    event = json.load(sys.stdin)
    if event.get("tool_name") != "Bash":
        return
    # Only the command itself is judged. The agent's own description of the command is left out on
    # purpose: text in the state can argue for an answer, and the agent writes that description.
    state = {
        "command": event.get("tool_input", {}).get("command", ""),
        "working_directory": event.get("cwd", ""),
    }
    try:
        output = shell(state)
    except Exception as error:  # fail open: normal permissions still apply
        print(f"fuzzymatch shell_guard: {error}", file=sys.stderr)
        return
    if output is not None:
        print(json.dumps(output))


if __name__ == "__main__":
    main()
