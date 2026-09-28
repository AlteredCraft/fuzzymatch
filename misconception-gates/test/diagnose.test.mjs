import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import {
  buildQuestions,
  choice,
  diagnose,
  heatmap,
  noul,
  score,
  ScriptedDecider,
  validateGate,
} from "../src/index.mjs";

const gate = JSON.parse(readFileSync(new URL("../examples/claude-md.gate.json", import.meta.url), "utf8"));

/** Scripted answers: a genuine attempt, a diagnosis, completeness, and optional per-misconception nouls. */
function answers({ attempt = 0.97, pick = "correct", confidence = 0.92, completeness = 2, holds = {} } = {}) {
  const out = { attempt: noul(attempt), diagnosis: choice(pick, confidence), completeness: score(completeness) };
  for (const m of gate.misconceptions) out[`holds__${m.key}`] = noul(holds[m.key] ?? 0.05);
  return { answers: out };
}

const run = (script, answer = "an answer", opts = {}) => diagnose(gate, answer, { decider: new ScriptedDecider(script), ...opts });

test("the example gate is valid", () => {
  assert.deepEqual(validateGate(gate), []);
});

test("one request carries attempt, diagnosis, completeness and a noul per misconception", () => {
  const q = buildQuestions(gate);
  assert.deepEqual(Object.keys(q).sort(), [
    "attempt",
    "completeness",
    "diagnosis",
    "holds__enforced_rule",
    "holds__lasting_memory",
    "holds__per_prompt",
    "holds__trains_model",
  ]);
  assert.deepEqual(Object.keys(q.diagnosis.criteria), [
    "correct",
    "trains_model",
    "per_prompt",
    "lasting_memory",
    "enforced_rule",
    "other",
  ]);
  assert.equal(q.completeness.criteria.length, 3);
});

test("the learner's answer and the question are the state", async () => {
  const decider = new ScriptedDecider(answers());
  await diagnose(gate, "It's loaded at startup", { decider });
  assert.deepEqual(decider.calls[0].state, { question: gate.q, learner_answer: "It's loaded at startup" });
});

test("a confident misconception points at its remedy beat", async () => {
  const r = await run(answers({ pick: "per_prompt", confidence: 0.88 }));
  assert.equal(r.kind, "misconception");
  assert.equal(r.misconception, "per_prompt");
  assert.equal(r.remedy, "beat-auto-load");
  assert.equal(r.review, false);
});

test("a second belief shows up in alsoHolds", async () => {
  const r = await run(answers({ pick: "correct", holds: { trains_model: 0.8, per_prompt: 0.3 } }));
  assert.equal(r.kind, "correct");
  assert.deepEqual(r.alsoHolds, ["trains_model"]);
});

test("the top pick is never repeated in alsoHolds", async () => {
  const r = await run(answers({ pick: "per_prompt", holds: { per_prompt: 0.99 } }));
  assert.deepEqual(r.alsoHolds, []);
});

test("a right but thin answer is partial", async () => {
  const r = await run(answers({ pick: "correct", completeness: 0.4 }));
  assert.equal(r.kind, "partial");
});

test("low confidence is unsure and queued for review", async () => {
  const r = await run(answers({ pick: "per_prompt", confidence: 0.55 }));
  assert.equal(r.kind, "unsure");
  assert.equal(r.review, true);
});

test("an idea the author didn't list is queued as unlisted", async () => {
  const r = await run(answers({ pick: "other" }));
  assert.equal(r.kind, "unlisted");
  assert.equal(r.review, true);
});

test("a non-attempt wins over everything else", async () => {
  const r = await run(answers({ attempt: 0.1, pick: "correct" }), "idk");
  assert.equal(r.kind, "no_attempt");
});

test("thresholds can be overridden per call", async () => {
  const r = await run(answers({ pick: "per_prompt", confidence: 0.55 }), "x", { thresholds: { diagnosis: 0.5 } });
  assert.equal(r.kind, "misconception");
});

test("an option the gate never offered is an error", async () => {
  await assert.rejects(run(answers({ pick: "made_up" })), /never offered/);
});

test("gate validation catches reserved, repeated and malformed keys", () => {
  const bad = {
    id: "g",
    q: "?",
    correct: "x",
    misconceptions: [
      { key: "other", label: "a" },
      { key: "dup", label: "b" },
      { key: "dup", label: "c" },
      { key: "Bad Key", label: "d" },
    ],
  };
  const problems = validateGate(bad).join("\n");
  assert.match(problems, /other is reserved/);
  assert.match(problems, /dup is repeated/);
  assert.match(problems, /must be snake_case/);
});

test("heatmap counts outcomes and collects the review queue", () => {
  const map = heatmap([
    { gate: "g", kind: "misconception", misconception: "per_prompt", alsoHolds: [], review: false },
    { gate: "g", kind: "misconception", misconception: "per_prompt", alsoHolds: ["trains_model"], review: false },
    { gate: "g", kind: "unlisted", top: "other", confidence: 0.9, answer: "servers", alsoHolds: [], review: true },
    { gate: "h", kind: "correct", alsoHolds: [], review: false },
  ]);
  const g = map.find((x) => x.gate === "g");
  assert.equal(g.total, 3);
  assert.deepEqual(g.counts, { "misconception:per_prompt": 2, unlisted: 1 });
  assert.deepEqual(g.alsoHolds, { trains_model: 1 });
  assert.deepEqual(g.review.map((r) => r.answer), ["servers"]);
});

test("every labelled eval answer uses a key the gate offers", () => {
  const keys = new Set(["correct", "other", "no_attempt", ...gate.misconceptions.map((m) => m.key)]);
  const rows = readFileSync(new URL("../eval/claude-md.answers.jsonl", import.meta.url), "utf8")
    .split("\n")
    .filter(Boolean)
    .map((l) => JSON.parse(l));
  assert.ok(rows.length >= 20);
  for (const r of rows) assert.ok(keys.has(r.label), `unknown label ${r.label}`);
});
