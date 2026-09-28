/* The hypothesis test: against hand-labelled answers, how accurate is the
   diagnosis at each confidence bar, and how many answers does each bar
   decide automatically (coverage)? Needs TYPESAFE_API_KEY.

     node eval/run.mjs [gate.json] [answers.jsonl]

   A bar is useful when accuracy on the covered answers is high enough to
   act on and coverage is high enough to matter. Pin TYPESAFE_DEFAULT_MODEL
   before comparing runs. */

import { readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { buildQuestions, buildState, holdsKey } from "../src/questions.mjs";
import { JevDecider } from "../src/decider.mjs";

const here = (p) => fileURLToPath(new URL(p, import.meta.url));
const [gatePath = here("../examples/claude-md.gate.json"), answersPath = here("./claude-md.answers.jsonl")] =
  process.argv.slice(2);
const BARS = [0, 0.5, 0.6, 0.7, 0.8, 0.9];

const gate = JSON.parse(await readFile(gatePath, "utf8"));
const rows = (await readFile(answersPath, "utf8")).split("\n").filter(Boolean).map((l) => JSON.parse(l));

let decider;
try {
  decider = new JevDecider();
} catch (e) {
  console.error(`${e.message}. This script calls the live API; unit tests don't need a key.`);
  process.exit(2);
}

const results = [];
for (const row of rows) {
  const { model, answers } = await decider.decide(buildState(gate, row.answer), buildQuestions(gate));
  const predicted = answers.attempt.noul < 0.5 ? "no_attempt" : answers.diagnosis.choice;
  const holds = Object.fromEntries(gate.misconceptions.map((m) => [m.key, answers[holdsKey(m.key)].noul]));
  results.push({ ...row, predicted, confidence: answers.diagnosis.confidence, attempt: answers.attempt.noul, holds, model });
}

console.log(`model ${results[0]?.model}  gate ${gate.id}  n=${results.length}\n`);
console.log("bar   coverage  accuracy(covered)");
for (const bar of BARS) {
  const covered = results.filter((r) => r.predicted === "no_attempt" || r.confidence >= bar);
  const right = covered.filter((r) => r.predicted === r.label).length;
  const acc = covered.length ? right / covered.length : NaN;
  console.log(`${bar.toFixed(1)}   ${pct(covered.length / results.length)}      ${pct(acc)}`);
}
const mixed = results.filter((r) => r.alsoHolds?.length);
if (mixed.length) {
  console.log("\nsecond beliefs (P that each expected alsoHolds belief is present):");
  for (const r of mixed) {
    console.log(`  ${r.alsoHolds.map((k) => `${k}=${r.holds[k].toFixed(2)}`).join(" ")}  ${r.answer}`);
  }
}

console.log("\nmisses:");
for (const r of results.filter((r) => r.predicted !== r.label)) {
  console.log(`  [${r.label} -> ${r.predicted} @${r.confidence.toFixed(2)}] ${r.answer}`);
}

const out = here(`./results-${new Date().toISOString().replace(/[:.]/g, "-")}.json`);
await writeFile(out, JSON.stringify({ gate: gate.id, results }, null, 2));
console.log(`\nwrote ${out}`);

function pct(x) {
  return Number.isNaN(x) ? "  -  " : `${(x * 100).toFixed(0).padStart(3)}%`;
}
