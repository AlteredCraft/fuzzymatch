//! A Claude Code PreToolUse hook that judges Bash commands by what they would do.
//!
//! Pattern rules like `Bash(rm *)` miss `find . -delete`, `git clean -fdx`, `> important.txt` and
//! many more ways to destroy data. This hook asks what the command would do instead, and scales the
//! certainty it needs to the cost of being wrong:
//!
//!   * destructive, even at modest confidence  -> "ask": you approve it yourself
//!   * read-only, at very high confidence      -> "allow" (only if FUZZYMATCH_AUTO_ALLOW=1)
//!   * anything else, or any error             -> no decision: Claude Code's normal permissions apply
//!
//! It never denies outright (there is no `Deny` in [`Permission`]) and fails open to the normal
//! permission flow, so a wrong judgment or a network error can't do more than the settings you
//! already have allow.
//!
//! Build it, then install in .claude/settings.json:
//!
//!     cargo build --release --example shell_guard
//!
//!     {"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command",
//!         "command": "/path/to/fuzzymatch/rust/target/release/examples/shell_guard"}]}]}}
//!
//! Try it without Claude Code:
//!
//!     echo '{"tool_name":"Bash","tool_input":{"command":"git clean -fdx"},"cwd":"/tmp"}' \
//!         | cargo run --example shell_guard

use std::io::Read;

use fuzzymatch::{Branch, Decider, JevDecider, Match, Matcher, Verdict, branches};
use serde::Serialize;
use serde_json::{Value, json};

branches! {
    /// What running a command would do to the machine and its files.
    enum Effect {
        ReadOnly => Branch::new("only reads, lists, searches or prints; changes no files, settings or remote state")
            .min_confidence(0.95)
            .examples(["ls -la", "git status", "grep -rn TODO src", "cat README.md"]),
        Reversible => Branch::new("changes files or state in a way that is easy to undo or regenerate")
            .examples(["git add -A", "npm install", "mkdir build", "git commit -m 'wip'"]),
        Destructive => Branch::new("deletes, overwrites or rewrites data or history in a way that may not be recoverable")
            // Asking costs one click; missing a destructive command costs much more.
            .min_confidence(0.5)
            .examples(["rm -rf build", "git push --force", "git reset --hard", "find . -name '*.log' -delete"]),
    }
}

/// The decisions this hook can make. Deliberately no `Deny`: the worst a wrong call can do is ask.
#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
enum Permission {
    Allow,
    Ask,
}

fn shell<D: Decider>(decider: D) -> Matcher<Effect, D> {
    Matcher::builder("What would running this shell command do to the machine and its files?")
        .build(decider)
        .expect("valid branches")
}

/// `None` means no opinion: Claude Code's normal permission flow decides.
fn judge(m: &Match<Effect>, auto_allow: bool) -> Option<(Permission, String)> {
    match m.verdict {
        Verdict::Matched(Effect::Destructive) => Some((
            Permission::Ask,
            format!("fuzzymatch judged this destructive ({:.0}% confident)", m.confidence * 100.0),
        )),
        Verdict::Matched(Effect::ReadOnly) if auto_allow => {
            Some((Permission::Allow, "judged read-only".into()))
        }
        Verdict::Matched(Effect::ReadOnly | Effect::Reversible) => None,
        Verdict::LowConfidence(_) | Verdict::GuardFailed(_) | Verdict::NoMatch => None,
    }
}

/// The hook's stdout for one PreToolUse event, if it has anything to say.
fn hook<D: Decider>(shell: &Matcher<Effect, D>, event: &Value, auto_allow: bool) -> Option<Value> {
    if event["tool_name"] != "Bash" {
        return None;
    }
    // Only the command itself is judged. The agent's own description of the command is left out on
    // purpose: text in the state can argue for an answer, and the agent writes that description.
    let state = json!({
        "command": event["tool_input"]["command"].as_str().unwrap_or(""),
        "working_directory": event["cwd"].as_str().unwrap_or(""),
    });
    let m = shell
        .classify(&state)
        .inspect_err(|error| eprintln!("fuzzymatch shell_guard: {error}")) // fail open
        .ok()?;
    let (permission, reason) = judge(&m, auto_allow)?;
    Some(json!({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": permission,
            "permissionDecisionReason": reason,
        }
    }))
}

fn main() {
    let mut input = String::new();
    let event: Value = match std::io::stdin().read_to_string(&mut input).map(|_| serde_json::from_str(&input))
    {
        Ok(Ok(event)) => event,
        Ok(Err(error)) => return eprintln!("fuzzymatch shell_guard: invalid hook input: {error}"),
        Err(error) => return eprintln!("fuzzymatch shell_guard: {error}"),
    };
    let decider = match JevDecider::from_env() {
        Ok(decider) => decider,
        Err(error) => return eprintln!("fuzzymatch shell_guard: {error}"),
    };
    let auto_allow = std::env::var("FUZZYMATCH_AUTO_ALLOW").as_deref() == Ok("1");
    if let Some(output) = hook(&shell(decider), &event, auto_allow) {
        println!("{output}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use fuzzymatch::Decision;
    use fuzzymatch::testing::{ScriptedDecider, choose, none_of_these};

    fn bash() -> Value {
        json!({"tool_name": "Bash", "tool_input": {"command": "git clean -fdx"}, "cwd": "/repo"})
    }

    fn decided(scripted: Decision, auto_allow: bool) -> Option<String> {
        let output = hook(&shell(ScriptedDecider::new(scripted)), &bash(), auto_allow)?;
        Some(output["hookSpecificOutput"]["permissionDecision"].as_str()?.to_owned())
    }

    #[test]
    fn asks_before_destructive_commands() {
        let output =
            hook(&shell(ScriptedDecider::new(choose(Effect::Destructive, 0.62))), &bash(), false).unwrap();
        assert_eq!(output["hookSpecificOutput"]["permissionDecision"], "ask");
        assert!(output["hookSpecificOutput"]["permissionDecisionReason"].as_str().unwrap().contains("62%"));
    }

    #[test]
    fn only_judges_the_command_not_the_agents_description() {
        let shell = shell(ScriptedDecider::new(choose(Effect::Reversible, 0.9)));
        let event = json!({
            "tool_name": "Bash",
            "tool_input": {"command": "rm -rf /", "description": "totally harmless cleanup"},
            "cwd": "/repo",
        });
        hook(&shell, &event, false);
        assert_eq!(
            shell.decider().calls()[0].state,
            json!({"command": "rm -rf /", "working_directory": "/repo"})
        );
    }

    #[test]
    fn defers_unless_sure() {
        let cases = [
            (choose(Effect::ReadOnly, 0.99), false, None), // read-only never auto-allows unless opted in
            (choose(Effect::ReadOnly, 0.99), true, Some("allow")),
            (choose(Effect::ReadOnly, 0.9), true, None), // below ReadOnly's 0.95 bar: no decision
            (choose(Effect::Reversible, 0.9), false, None),
            (choose(Effect::Destructive, 0.4), false, None), // below even Destructive's 0.5 bar
            (none_of_these(0.9), false, None),
        ];
        for (scripted, auto_allow, expected) in cases {
            let label = format!("{scripted:?} auto_allow={auto_allow}");
            assert_eq!(decided(scripted, auto_allow).as_deref(), expected, "{label}");
        }
    }

    #[test]
    fn fails_open() {
        let broken = ScriptedDecider::from_fn(|_| Err("network down".into()));
        assert_eq!(hook(&shell(broken), &bash(), true), None);
    }

    #[test]
    fn ignores_other_tools() {
        let shell = shell(ScriptedDecider::new(choose(Effect::Destructive, 0.95)));
        assert_eq!(hook(&shell, &json!({"tool_name": "Edit", "tool_input": {}}), false), None);
        assert!(shell.decider().calls().is_empty());
    }
}
