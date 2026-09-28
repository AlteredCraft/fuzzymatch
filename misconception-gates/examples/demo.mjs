/* Diagnose one answer against the example gate with the live API.

     TYPESAFE_API_KEY=sk-... node examples/demo.mjs "You have to @-mention it every time"
*/

import { readFile } from "node:fs/promises";
import { diagnose, JevDecider } from "../src/index.mjs";

const gate = JSON.parse(await readFile(new URL("./claude-md.gate.json", import.meta.url), "utf8"));
const answer = process.argv.slice(2).join(" ") || "Claude reads it at the start and it stays in context.";

const record = await diagnose(gate, answer, { decider: new JevDecider() });
console.log(JSON.stringify(record, null, 2));
