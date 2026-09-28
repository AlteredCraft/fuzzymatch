/* Turn the model's answers into a verdict. All policy lives here, in code,
   so thresholds can change without touching a prompt.

   kinds:
     correct       right idea, complete enough
     partial       right idea, missing parts (rubric below `complete`)
     misconception a listed misconception, confidently -> jump to its remedy
     unlisted      a wrong idea the author didn't list -> queue for authoring
     unsure        confidence below the bar -> show the WHY, queue for review
     no_attempt    not a real attempt -> invite a retry

   Every kind still unlocks the lesson, as sandbox gates do: the verdict only
   chooses which feedback the learner sees. */

import { holdsKey } from "./questions.mjs";

export function verdictFrom(gate, answers, thresholds) {
  const attempt = answers.attempt?.noul;
  const diagnosis = answers.diagnosis;
  if (attempt === undefined || !diagnosis) throw new Error("answers are missing attempt or diagnosis");

  const base = {
    gate: gate.id,
    confidence: diagnosis.confidence,
    probabilities: diagnosis.probabilities,
    top: diagnosis.choice,
    attempt,
    completeness: answers.completeness?.score ?? null,
    alsoHolds: alsoHolds(gate, answers, diagnosis.choice, thresholds.alsoHolds),
  };

  if (attempt < thresholds.attempt) return { ...base, kind: "no_attempt", review: false };
  if (diagnosis.confidence < thresholds.diagnosis) return { ...base, kind: "unsure", review: true };

  if (diagnosis.choice === "correct") {
    const partial = base.completeness !== null && base.completeness < thresholds.complete;
    return { ...base, kind: partial ? "partial" : "correct", review: false };
  }
  if (diagnosis.choice === "other") return { ...base, kind: "unlisted", review: true };

  const m = gate.misconceptions.find((x) => x.key === diagnosis.choice);
  if (!m) throw new Error(`model chose an option the gate never offered: ${diagnosis.choice}`);
  return { ...base, kind: "misconception", misconception: m.key, remedy: m.remedy ?? null, review: false };
}

function alsoHolds(gate, answers, top, bar) {
  return gate.misconceptions
    .filter((m) => m.key !== top && (answers[holdsKey(m.key)]?.noul ?? 0) >= bar)
    .map((m) => m.key);
}
