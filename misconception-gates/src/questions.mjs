/* Build the single System One request for one learner answer.

   All questions run in parallel against the same state, so the extra
   per-misconception checks add input tokens, not latency:

     attempt      Noul    is this a genuine attempt at the question?
     diagnosis    Choice  correct | one misconception | other
     completeness Score   how complete a correct answer is (if the gate has a rubric)
     holds__<key> Noul    does the answer show this belief? (one per misconception)

   The Choice finds the main idea; the Nouls catch a second belief the
   learner holds alongside it, which a single Choice can't report. */

export function buildState(gate, answer) {
  return { question: gate.q, learner_answer: String(answer ?? "") };
}

export function buildQuestions(gate) {
  const criteria = { correct: gate.correct };
  for (const m of gate.misconceptions) criteria[m.key] = m.label;
  criteria.other = "A wrong or confused idea that none of the other options describe.";

  const questions = {
    attempt: {
      type: "noul",
      instructions:
        "The learner_answer is a genuine attempt to answer the question, not blank, 'I don't know', off-topic, or a joke.",
    },
    diagnosis: {
      type: "choice",
      instructions: "Which idea does the learner_answer express about the question?",
      criteria,
    },
  };

  if (gate.rubric) {
    questions.completeness = {
      type: "score",
      instructions: "How completely does the learner_answer explain the correct idea?",
      criteria: gate.rubric,
    };
  }

  for (const m of gate.misconceptions) {
    questions[holdsKey(m.key)] = {
      type: "noul",
      instructions: `The learner_answer shows this belief: ${m.label}`,
    };
  }
  return questions;
}

export const holdsKey = (key) => `holds__${key}`;
