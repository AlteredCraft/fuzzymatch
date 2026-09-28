# Working in this repo

- Each top-level directory is an independent experiment. Work inside one at a time; don't share code
  between them.
- Every experiment's README has **Hypothesis**, **Checks** and **Open**. Take the first Open item.
  When a check gets evidence, record it in that README with the date and the commit or PR.
- Tests first. Unit tests use the scripted decider and never call the network or need
  `TYPESAFE_API_KEY`. Live runs belong in `eval/` scripts and write their results to files.
- Keep thresholds and arithmetic in code, never in question text. Pin the model version for any
  run whose numbers you record.
- Loosening a check, or changing what an experiment is trying to show, needs the user.

Commands per experiment:

| Experiment | Test | Lint |
| --- | --- | --- |
| misconception-gates | `node --test` | — |
| godot-jev | `godot --headless --path . --import` then `godot --headless --path . --script res://tests/run_tests.gd` | — |
| semver-judge | `uv run pytest` | `uv run ruff check . && uv run ruff format --check .` |
