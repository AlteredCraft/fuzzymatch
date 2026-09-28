/* Aggregate verdict records into what an author needs to see:
   per gate, how many learners landed on each outcome, plus the answers
   queued for review (unsure and unlisted), which are where new
   misconceptions come from. */

export function heatmap(records) {
  const gates = new Map();
  for (const r of records) {
    const g = gates.get(r.gate) ?? { gate: r.gate, total: 0, counts: {}, alsoHolds: {}, review: [] };
    g.total += 1;
    const bucket = r.kind === "misconception" ? `misconception:${r.misconception}` : r.kind;
    g.counts[bucket] = (g.counts[bucket] ?? 0) + 1;
    for (const k of r.alsoHolds ?? []) g.alsoHolds[k] = (g.alsoHolds[k] ?? 0) + 1;
    if (r.review) g.review.push({ kind: r.kind, top: r.top, confidence: r.confidence, answer: r.answer });
    gates.set(r.gate, g);
  }
  return [...gates.values()];
}
