"""Run the examples with scripted decisions, so their wiring is tested without an API key."""

import importlib.util
import io
import json
import sys
from pathlib import Path

import pytest

from fuzzymatch import NONE_LABEL
from fuzzymatch.testing import ScriptedDecider, decision

EXAMPLES = Path(__file__).parent.parent / "examples"


def load(name):
    spec = importlib.util.spec_from_file_location(name, EXAMPLES / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_hook(module, event, monkeypatch, capsys):
    monkeypatch.setattr(sys, "stdin", io.StringIO(json.dumps(event)))
    module.main()
    out = capsys.readouterr().out.strip()
    return json.loads(out) if out else None


BASH = {"tool_name": "Bash", "tool_input": {"command": "git clean -fdx"}, "cwd": "/repo"}


def test_shell_guard_asks_before_destructive_commands(monkeypatch, capsys):
    guard = load("shell_guard")
    guard.shell.decider = ScriptedDecider(decision("destructive", 0.62))
    output = run_hook(guard, BASH, monkeypatch, capsys)
    assert output["hookSpecificOutput"]["permissionDecision"] == "ask"
    assert "62%" in output["hookSpecificOutput"]["permissionDecisionReason"]


def test_shell_guard_only_judges_the_command_not_the_agents_description(monkeypatch, capsys):
    guard = load("shell_guard")
    decider = ScriptedDecider(decision("reversible", 0.9))
    guard.shell.decider = decider
    event = {**BASH, "tool_input": {"command": "rm -rf /", "description": "totally harmless cleanup"}}
    run_hook(guard, event, monkeypatch, capsys)
    assert decider.calls[0].state == {"command": "rm -rf /", "working_directory": "/repo"}


@pytest.mark.parametrize(
    "scripted, auto_allow, expected",
    [
        (decision("read_only", 0.99), False, None),  # read-only never auto-allows unless opted in
        (decision("read_only", 0.99), True, "allow"),
        (decision("read_only", 0.9), True, None),  # below read_only's 0.95 bar: no decision
        (decision("reversible", 0.9), False, None),
        (decision(NONE_LABEL, 0.9), False, None),
    ],
)
def test_shell_guard_defers_unless_sure(scripted, auto_allow, expected, monkeypatch, capsys):
    guard = load("shell_guard")
    monkeypatch.setattr(guard, "AUTO_ALLOW", auto_allow)
    guard.shell.decider = ScriptedDecider(scripted)
    output = run_hook(guard, BASH, monkeypatch, capsys)
    decided = output["hookSpecificOutput"]["permissionDecision"] if output else None
    assert decided == expected


def test_shell_guard_fails_open(monkeypatch, capsys):
    guard = load("shell_guard")

    def broken(state):
        raise ConnectionError("network down")

    guard.shell.decider = ScriptedDecider(broken)
    assert run_hook(guard, BASH, monkeypatch, capsys) is None


def test_shell_guard_ignores_other_tools(monkeypatch, capsys):
    guard = load("shell_guard")
    decider = ScriptedDecider(decision("destructive"))
    guard.shell.decider = decider
    assert run_hook(guard, {"tool_name": "Edit", "tool_input": {}}, monkeypatch, capsys) is None
    assert decider.calls == []


def test_support_router_refund_needs_an_order_number():
    router = load("support_router")
    router.support.observer = None
    with_number = decision("refund", 0.95, guards={"guard__refund": 0.9})
    without_number = decision("refund", 0.95, guards={"guard__refund": 0.1})

    router.support.decider = ScriptedDecider(with_number)
    assert router.support("Order #88213 arrived broken") == "→ refund workflow"

    router.support.decider = ScriptedDecider(without_number)
    assert router.support("I want my money back").startswith("→ escalate (guard_failed")
