import test from "node:test";
import assert from "node:assert/strict";
import { renderAutomatedReport } from "../../public/automated-review.js";
test("automated findings and source excerpts remain escaped and separate concerns from observations", () => {
  const report = {
    summary: "<script>bad</script>",
    findings: [
      {
        severity: "major",
        category: "source_concern",
        title: "Unsafe <img>",
        observation: "<b>claim</b>",
        consequence: "risk",
        recommendation: "check",
        confidence: "medium",
        evidence: [
          {
            path: "solution.rb",
            start_line: 1,
            end_line: 2,
            excerpt: "<script>alert(1)</script>",
          },
        ],
        execution_ids: [],
      },
    ],
    strengths: [],
    criteria: [
      {
        id: "correctness",
        rating: "needs_development",
        reasoning: "Explain & verify",
        evidence: [],
      },
    ],
    understanding_checks: ["Why < this?"],
    limitations: ["No transcript"],
  };
  const html = renderAutomatedReport(report, [
    {
      id: "correctness",
      title: "Correctness",
      practice: "Trace a counterexample",
    },
  ]);
  assert.ok(!html.includes("<script>"));
  assert.ok(!html.includes("<img>"));
  assert.ok(html.includes("&lt;script&gt;"));
  assert.ok(html.includes("Source concern"));
  assert.ok(html.includes("medium confidence"));
  assert.ok(html.includes("Trace a counterexample"));
  assert.ok(!html.includes("hiring pass"));
});
