/* HTTP endpoint for the lesson runtime: POST /api/diagnose {gate, answer}.

   Meant to be mounted in js-animation-sandbox's serve.mjs so the API key
   stays on the server. It fails open: if the model is unreachable the
   learner still gets the gate's static WHY, as today. */

import { diagnose } from "./diagnose.mjs";

const MAX_BODY = 16 * 1024;
const MAX_ANSWER = 2000;

export function createDiagnoseHandler({ gates, decider, onRecord = () => {}, thresholds } = {}) {
  const byId = gates instanceof Map ? gates : new Map(gates.map((g) => [g.id, g]));

  return async function handle(req, res) {
    if (req.method !== "POST") return send(res, 405, { error: "POST only" });
    let body;
    try {
      body = JSON.parse(await readBody(req));
    } catch {
      return send(res, 400, { error: "body must be JSON {gate, answer}" });
    }
    const gate = byId.get(body?.gate);
    if (!gate) return send(res, 404, { error: `unknown gate ${JSON.stringify(body?.gate)}` });
    const answer = String(body.answer ?? "").slice(0, MAX_ANSWER);

    try {
      const record = await diagnose(gate, answer, { decider, thresholds });
      await onRecord(record);
      return send(res, 200, publicView(record));
    } catch (error) {
      return send(res, 200, { gate: gate.id, kind: "unavailable", reason: String(error.message ?? error) });
    }
  };
}

/* What the browser needs; probabilities stay server-side in the record. */
function publicView(r) {
  return { gate: r.gate, kind: r.kind, misconception: r.misconception ?? null, remedy: r.remedy ?? null, alsoHolds: r.alsoHolds };
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on("data", (c) => {
      size += c.length;
      if (size > MAX_BODY) {
        reject(new Error("body too large"));
        req.destroy();
      } else chunks.push(c);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

function send(res, status, payload) {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(payload));
}
