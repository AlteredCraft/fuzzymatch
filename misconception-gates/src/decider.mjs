/* The port to the model, and two adapters.

   A decider takes (state, questions) and resolves to { model, answers },
   where answers mirrors the System One wire format:
     noul:   { type: "noul", noul }
     choice: { type: "choice", choice, confidence, probabilities }
     score:  { type: "score", score, confidence, probabilities }

   JevDecider calls the TypeSafe REST API directly with fetch, keeping this
   package dependency-free like the sandbox. ScriptedDecider is for tests. */

export class JevDecider {
  constructor({
    apiKey = process.env.TYPESAFE_API_KEY,
    model = process.env.TYPESAFE_DEFAULT_MODEL ?? "jev-latest",
    baseUrl = process.env.TYPESAFE_BASE_URL ?? "https://api.typesafe.ai",
    timeoutMs = 5000,
    fetchImpl = globalThis.fetch,
  } = {}) {
    if (!apiKey) throw new Error("no API key: pass apiKey or set TYPESAFE_API_KEY");
    Object.assign(this, { apiKey, model, baseUrl: baseUrl.replace(/\/$/, ""), timeoutMs, fetchImpl });
  }

  async decide(state, questions) {
    const res = await this.fetchImpl(`${this.baseUrl}/v1/systemone`, {
      method: "POST",
      headers: { Authorization: `Bearer ${this.apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ state, model: this.model, questions }),
      signal: AbortSignal.timeout(this.timeoutMs),
    });
    if (!res.ok) {
      const body = (await res.text()).slice(0, 200);
      throw new Error(`System One request failed: HTTP ${res.status} ${body}`);
    }
    const data = await res.json();
    for (const name of Object.keys(questions)) {
      const answer = data.answers?.[name];
      if (!answer || answer.type !== questions[name].type) throw new Error(`response is missing answer ${name}`);
    }
    return { model: data.model, answers: data.answers };
  }
}

/** Returns scripted answers. `script` is { model?, answers } or (state, questions) => that. */
export class ScriptedDecider {
  constructor(script) {
    this.script = script;
    this.calls = [];
  }

  async decide(state, questions) {
    this.calls.push({ state, questions });
    const out = typeof this.script === "function" ? await this.script(state, questions) : this.script;
    return { model: "scripted", ...out };
  }
}

/* Answer builders for tests and fixtures. */
export const noul = (p) => ({ type: "noul", noul: p });
export const choice = (label, confidence = 0.95, probabilities = { [label]: confidence }) => ({
  type: "choice",
  choice: label,
  confidence,
  probabilities,
});
export const score = (value, confidence = 0.9) => ({ type: "score", score: value, confidence, probabilities: {} });
