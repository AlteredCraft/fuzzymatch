/* One learner answer in, one verdict record out. */

import { assertGate, thresholdsFor } from "./gate.mjs";
import { buildQuestions, buildState } from "./questions.mjs";
import { verdictFrom } from "./verdict.mjs";

export async function diagnose(gate, answer, { decider, thresholds = {}, now = () => new Date() } = {}) {
  assertGate(gate);
  if (!decider) throw new Error("diagnose needs a decider");
  const started = performance.now();
  const { model, answers } = await decider.decide(buildState(gate, answer), buildQuestions(gate));
  const verdict = verdictFrom(gate, answers, thresholdsFor(gate, thresholds));
  return {
    ...verdict,
    answer: String(answer ?? ""),
    model,
    latencyMs: Math.round(performance.now() - started),
    at: now().toISOString(),
  };
}
