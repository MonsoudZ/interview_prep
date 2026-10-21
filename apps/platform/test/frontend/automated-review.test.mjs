import test from "node:test";
import assert from "node:assert/strict";
import {
  renderAutomatedReport,
  renderReasoningMode,
  renderReviewGuidance,
} from "../../public/automated-review.js";
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

test("guidance sources are separate from submission citations and reject unsafe links", () => {
  assert.equal(renderReviewGuidance(null), "");
  const html = renderReviewGuidance({
    version: "v1",
    digest: "sha256:test",
    sources: [
      {
        company: "Google",
        title: "Review <script>",
        url: "https://google.github.io/eng-practices/",
        kind: "Engineering guidance",
        checked_on: "2026-10-21",
      },
      {
        company: "Apple",
        title: "Team description",
        url: "javascript:alert(1)",
        kind: "Not interview scoring",
        checked_on: "2026-10-21",
      },
    ],
  });
  assert.ok(html.includes('href="https://google.github.io/eng-practices/"'));
  assert.ok(html.includes("&lt;script&gt;"));
  assert.ok(!html.includes("javascript:"));
  assert.ok(html.includes("not company hiring scores"));
});

test("reasoning-mode provenance distinguishes a fallback answer from an unknown mode", () => {
  assert.equal(renderReasoningMode(undefined), "");
  assert.equal(renderReasoningMode({ input_tokens: 1 }), "");
  assert.ok(renderReasoningMode({ reasoning: 1 }).includes("Reasoning mode: on"));
  assert.ok(renderReasoningMode({ reasoning: 0 }).includes("budget ran out"));
});
