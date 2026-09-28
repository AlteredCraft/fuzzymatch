import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer } from "node:http";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { buildQuestions, buildState, choice, createDiagnoseHandler, JevDecider, noul, ScriptedDecider } from "../src/index.mjs";

const gate = JSON.parse(readFileSync(new URL("../examples/claude-md.gate.json", import.meta.url), "utf8"));

test("JevDecider sends the System One wire format with a bearer key", async () => {
  const seen = [];
  const fetchImpl = async (url, init) => {
    seen.push({ url, init });
    const answers = {};
    for (const [name, q] of Object.entries(JSON.parse(init.body).questions)) {
      answers[name] = q.type === "choice" ? choice("correct", 0.9) : q.type === "noul" ? noul(0.1) : { type: "score", score: 2, confidence: 0.8 };
    }
    return new Response(JSON.stringify({ model: "jev-1.13.0", usage: {}, answers }), { status: 200 });
  };
  const decider = new JevDecider({ apiKey: "sk-test", model: "jev-1.13.0", fetchImpl });
  const out = await decider.decide(buildState(gate, "hi"), buildQuestions(gate));

  const [{ url, init }] = seen;
  assert.equal(url, "https://api.typesafe.ai/v1/systemone");
  assert.equal(init.headers.Authorization, "Bearer sk-test");
  const body = JSON.parse(init.body);
  assert.equal(body.model, "jev-1.13.0");
  assert.deepEqual(body.state, { question: gate.q, learner_answer: "hi" });
  assert.equal(body.questions.diagnosis.type, "choice");
  assert.equal(out.model, "jev-1.13.0");
  assert.equal(out.answers.diagnosis.choice, "correct");
});

test("JevDecider surfaces HTTP errors and missing answers", async () => {
  const failing = new JevDecider({ apiKey: "k", fetchImpl: async () => new Response("nope", { status: 429 }) });
  await assert.rejects(failing.decide({}, { a: { type: "noul" } }), /HTTP 429/);

  const partial = new JevDecider({
    apiKey: "k",
    fetchImpl: async () => new Response(JSON.stringify({ model: "m", answers: {} }), { status: 200 }),
  });
  await assert.rejects(partial.decide({}, { a: { type: "noul" } }), /missing answer a/);
});

test("JevDecider refuses to start without a key", () => {
  assert.throws(() => new JevDecider({ apiKey: "" }), /no API key/);
});

async function serve(handler) {
  const server = createServer(handler).listen(0);
  await once(server, "listening");
  const url = `http://127.0.0.1:${server.address().port}/api/diagnose`;
  return { url, close: () => server.close() };
}

test("the handler returns a public verdict and records the full one", async () => {
  const script = { answers: { attempt: noul(0.9), diagnosis: choice("per_prompt", 0.9) } };
  const records = [];
  const { url, close } = await serve(
    createDiagnoseHandler({ gates: [{ ...gate, rubric: undefined }], decider: new ScriptedDecider(script), onRecord: (r) => records.push(r) }),
  );
  try {
    const res = await fetch(url, { method: "POST", body: JSON.stringify({ gate: gate.id, answer: "paste it each time" }) });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.deepEqual(body, { gate: gate.id, kind: "misconception", misconception: "per_prompt", remedy: "beat-auto-load", alsoHolds: [] });
    assert.equal(records.length, 1);
    assert.ok("probabilities" in records[0]);
  } finally {
    close();
  }
});

test("the handler fails open when the model is unavailable", async () => {
  const broken = new ScriptedDecider(() => {
    throw new Error("network down");
  });
  const { url, close } = await serve(createDiagnoseHandler({ gates: [gate], decider: broken }));
  try {
    const body = await (await fetch(url, { method: "POST", body: JSON.stringify({ gate: gate.id, answer: "x" }) })).json();
    assert.equal(body.kind, "unavailable");
  } finally {
    close();
  }
});

test("the handler rejects bad requests", async () => {
  const { url, close } = await serve(createDiagnoseHandler({ gates: [gate], decider: new ScriptedDecider({}) }));
  try {
    assert.equal((await fetch(url)).status, 405);
    assert.equal((await fetch(url, { method: "POST", body: "not json" })).status, 400);
    assert.equal((await fetch(url, { method: "POST", body: JSON.stringify({ gate: "nope" }) })).status, 404);
  } finally {
    close();
  }
});
