/* A diagnose gate: a free-text question plus the misconceptions an author
   expects to see in the answers.

   {
     id: "d-claude-md",
     objective: "O2",                       // optional, mirrors sandbox gates
     q: "In your own words ...",            // the question the learner answers
     correct: "What a correct answer says",  // one description of the target idea
     misconceptions: [
       { key: "per_prompt", label: "Believes ...", remedy: "beat-id" },  // remedy: optional beat to jump to
     ],
     rubric: ["level 0", "level 1", "level 2"],  // optional: completeness of a correct answer
     why: "The explanation every learner sees after answering",
     thresholds: { diagnosis: 0.7, attempt: 0.5, alsoHolds: 0.6 },  // optional overrides
   }

   Keys become option labels sent to the model, so they are short identifiers.
   The reserved keys below are added by the question builder. */

export const RESERVED = Object.freeze(["correct", "other", "no_attempt"]);
export const MAX_MISCONCEPTIONS = 250; // a Choice takes up to 255 options; a few are reserved

export const DEFAULT_THRESHOLDS = Object.freeze({
  attempt: 0.5, // P(genuine attempt) below this: treat as no attempt
  diagnosis: 0.7, // Choice confidence needed to act on the diagnosis
  alsoHolds: 0.6, // P(answer shows a second misconception) needed to report it
  complete: 1, // completeness score (0-based level) at or above which a correct answer counts as complete
});

const KEY = /^[a-z][a-z0-9_]*$/;

export function validateGate(gate) {
  const problems = [];
  if (!gate || typeof gate !== "object") return ["gate must be an object"];
  if (!gate.id) problems.push("id is required");
  if (!gate.q) problems.push("q (the question) is required");
  if (!gate.correct) problems.push("correct (what a right answer says) is required");
  const ms = gate.misconceptions ?? [];
  if (!Array.isArray(ms) || ms.length === 0) problems.push("list at least one misconception");
  if (ms.length > MAX_MISCONCEPTIONS) problems.push(`at most ${MAX_MISCONCEPTIONS} misconceptions`);
  const seen = new Set();
  for (const m of Array.isArray(ms) ? ms : []) {
    if (!KEY.test(m?.key ?? "")) problems.push(`misconception key ${JSON.stringify(m?.key)} must be snake_case`);
    else if (RESERVED.includes(m.key)) problems.push(`misconception key ${m.key} is reserved`);
    else if (seen.has(m.key)) problems.push(`misconception key ${m.key} is repeated`);
    seen.add(m?.key);
    if (!m?.label) problems.push(`misconception ${m?.key} needs a label`);
  }
  if (gate.rubric !== undefined && (!Array.isArray(gate.rubric) || gate.rubric.length < 2 || gate.rubric.length > 10)) {
    problems.push("rubric must list 2 to 10 levels");
  }
  return problems;
}

export function assertGate(gate) {
  const problems = validateGate(gate);
  if (problems.length) throw new Error(`invalid gate ${gate?.id ?? "?"}: ${problems.join("; ")}`);
  return gate;
}

export function thresholdsFor(gate, overrides = {}) {
  return { ...DEFAULT_THRESHOLDS, ...(gate.thresholds ?? {}), ...overrides };
}
