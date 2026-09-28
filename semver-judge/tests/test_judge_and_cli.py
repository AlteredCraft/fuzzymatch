import json
import subprocess
from pathlib import Path

import httpx2
import pytest
from typesafe_sdk import TypeSafeClient

from semver_judge.cli import REVIEW_EXIT, main
from semver_judge.judge import JevDecider, ScriptedDecider, judge_commit, questions_for
from semver_judge.model import Commit, Kind


def test_only_open_questions_are_asked():
    declared = questions_for(Commit("a" * 40, "feat!: new API"))
    assert set(declared) == {"user_visible"}  # kind and breaking both stated

    prefixed = questions_for(Commit("a" * 40, "chore: bump deps"))
    assert set(prefixed) == {"user_visible", "breaking"}  # unflagged: still check for breaks

    bare = questions_for(Commit("a" * 40, "Handle empty config"))
    assert set(bare) == {"user_visible", "breaking", "kind"}
    assert "feat" in bare["kind"]["criteria"]


def test_judgment_combines_declared_and_judged():
    decider = ScriptedDecider(
        lambda s, q: {
            "breaking": {"type": "noul", "noul": 0.42},
            "user_visible": {"type": "noul", "noul": 0.2},
        }
    )
    j = judge_commit(Commit("a" * 40, "chore: bump deps"), decider)
    assert (j.kind, j.kind_confidence, j.breaking, j.source) == (Kind.CHORE, 1.0, 0.42, "conventional")
    assert decider.calls[0][0]["subject"] == "chore: bump deps"


def test_offline_mode_needs_no_decider():
    j = judge_commit(Commit("a" * 40, "Handle empty config"), None)
    assert (j.kind, j.kind_confidence, j.breaking) == (Kind.OTHER, 0.0, 0.5)


def test_jev_decider_through_the_real_sdk():
    seen = []

    def handler(request: httpx2.Request) -> httpx2.Response:
        body = json.loads(request.content)
        seen.append(body)
        answers = {
            "kind": {
                "type": "choice",
                "choice": "fix",
                "confidence": 0.8,
                "probabilities": {"fix": 0.8, "feat": 0.2},
            },
            "breaking": {"type": "noul", "noul": 0.1},
            "user_visible": {"type": "noul", "noul": 0.7},
        }
        return httpx2.Response(200, json={"model": "jev-1.13.0", "usage": {}, "answers": answers})

    client = TypeSafeClient(api_key="sk-test", transport=httpx2.MockTransport(handler))
    j = judge_commit(
        Commit("a" * 40, "Handle empty config", files=("cfg.py (+3 -1)",)), JevDecider(client, "jev-1.13.0")
    )
    assert (j.kind, j.kind_confidence, j.breaking, j.model) == (Kind.FIX, 0.8, 0.1, "jev-1.13.0")
    assert seen[0]["model"] == "jev-1.13.0"
    assert seen[0]["questions"]["kind"]["type"] == "choice"
    assert seen[0]["state"]["files_changed"] == ["cfg.py (+3 -1)"]


def git(repo: Path, *args: str) -> None:
    subprocess.run(
        [
            "git",
            "-C",
            str(repo),
            "-c",
            "user.name=t",
            "-c",
            "user.email=t@example.com",
            "-c",
            "commit.gpgsign=false",
            *args,
        ],
        check=True,
        capture_output=True,
    )


@pytest.fixture
def repo(tmp_path: Path) -> Path:
    git(tmp_path, "init", "-q", "-b", "main")
    (tmp_path / "a.txt").write_text("1")
    git(tmp_path, "add", ".")
    git(tmp_path, "commit", "-q", "-m", "initial")
    git(tmp_path, "tag", "v1.4.2")
    for i, message in enumerate(["feat: add --json", "Handle empty config files", "chore: bump deps"]):
        (tmp_path / f"f{i}.txt").write_text(str(i))
        git(tmp_path, "add", ".")
        git(tmp_path, "commit", "-q", "-m", message)
    return tmp_path


def scripted(breaking_for_bare=0.05):
    def script(state, questions):
        answers = {"user_visible": {"type": "noul", "noul": 0.8}}
        if "breaking" in questions:
            bare = not state["subject"].split(":")[0].isalpha() or " " in state["subject"].split(":")[0]
            answers["breaking"] = {"type": "noul", "noul": breaking_for_bare if bare else 0.02}
        if "kind" in questions:
            answers["kind"] = {
                "type": "choice",
                "choice": "fix",
                "confidence": 0.9,
                "probabilities": {"fix": 0.9},
            }
        return answers

    return ScriptedDecider(script)


def test_cli_end_to_end_on_a_real_repo(repo, capsys):
    decider = scripted()
    assert main(["--repo", str(repo), "--json"], decider=decider) == 0
    out = json.loads(capsys.readouterr().out)
    assert (out["current"], out["bump"], out["next"]) == ("v1.4.2", "minor", "v1.5.0")
    assert [c["subject"] for c in out["commits"]] == [
        "feat: add --json",
        "Handle empty config files",
        "chore: bump deps",
    ]
    assert len(decider.calls) == 3
    assert any("f1.txt (+1 -0)" in c[0]["files_changed"] for c in decider.calls)


def test_cli_flags_review_and_writes_github_outputs(repo, tmp_path, monkeypatch, capsys):
    outputs, summary = tmp_path / "out.txt", tmp_path / "summary.md"
    monkeypatch.setenv("GITHUB_OUTPUT", str(outputs))
    monkeypatch.setenv("GITHUB_STEP_SUMMARY", str(summary))
    code = main(
        ["--repo", str(repo), "--github", "--fail-on-review"], decider=scripted(breaking_for_bare=0.55)
    )
    assert code == REVIEW_EXIT
    assert "needs-review=true" in outputs.read_text()
    assert "Needs a human decision" in summary.read_text()


def test_cli_offline(repo, capsys):
    assert main(["--repo", str(repo), "--offline", "--json"]) == 0
    out = json.loads(capsys.readouterr().out)
    assert out["bump"] == "minor"
    assert out["needs_review"], "unprefixed commits can't be judged offline, so they're flagged"


def test_offline_trusts_the_conventional_contract():
    chore = judge_commit(Commit("a" * 40, "chore: bump deps"), None)
    assert (chore.breaking, chore.user_visible) == (0.0, 0.0)
    flagged = judge_commit(Commit("a" * 40, "feat!: new API"), None)
    assert flagged.breaking == 1.0
