import test from "node:test";
import assert from "node:assert/strict";
import { renderProgress, renderExecution } from "../../public/progress.js";

function fixture() {
  const observation = {
    session_id: "submitted-fixture",
    submitted_at: "2026-10-18T12:00:00Z",
    mode: "assessment",
    rating: "needs_development",
    notes: '<img src=x onerror="alert(1)">',
    hints_revealed: 0,
  };
  const gap = {
    key: "ruby:fixture:correctness",
    track: "ruby",
    title: "Correctness",
    exercise: "Ruby fixture",
    exercise_version: 2,
    target_version: 2,
    content_version: "fixture-review-v2",
    practice: "Trace the invariant.",
    recurring: true,
    gap_count: 2,
    observation_count: 2,
    trend: "unchanged",
    latest: observation,
    observations: [observation],
    exercise_id: "exercise-fixture",
  };
  return {
    summary: {
      submitted: 2,
      self_reviews_started: 2,
      awaiting_review: 2,
      recurring_gaps: 1,
    },
    plan: [gap],
    skills: [gap],
    awaiting_review: [
      {
        id: "submitted-fixture",
        title: "Ruby fixture",
        track: "ruby",
        submitted_at: observation.submitted_at,
        mode: "assessment",
        observed: 1,
        total: 5,
      },
    ],
    recent_attempts: [
      {
        id: "submitted-fixture",
        title: "Ruby fixture",
        track: "ruby",
        submitted_at: observation.submitted_at,
        mode: "assessment",
        exercise_version: 2,
        observed: 1,
        total: 5,
        reflection: "<script>untrusted()</script>",
        hints_revealed: 0,
      },
    ],
    recent_limit: 20,
    method: "Self-assessments only.",
  };
}

test("progress preserves untrusted reflections and evidence notes as text", () => {
  const html = renderProgress(fixture());
  assert.ok(!html.includes("<img"));
  assert.ok(!html.includes("<script>"));
  assert.ok(html.includes("&lt;img"));
  assert.ok(html.includes("&lt;script&gt;"));
  assert.ok(html.includes("Timed assessment"));
  assert.ok(html.includes("2 of 2 self-ratings below target"));
  assert.ok(html.includes('data-practice-gap="ruby:fixture:correctness"'));
});

test("an existing focused attempt is resumed or reviewed before a duplicate is offered", () => {
  const progress = fixture();
  Object.assign(progress.plan[0], {
    next_session_id: "focused-fixture",
    next_session_status: "draft",
  });
  let html = renderProgress(progress);
  assert.ok(html.includes("Continue focused attempt"));
  assert.ok(!html.includes("data-practice-gap="));
  assert.ok(
    html.includes(
      'data-progress-session="focused-fixture" data-review="false"',
    ),
  );
  progress.plan[0].next_session_status = "submitted";
  html = renderProgress(progress);
  assert.ok(html.includes("Review newer attempt"));
  assert.ok(
    html.includes('data-progress-session="focused-fixture" data-review="true"'),
  );
});

test("track filters remove unrelated plans, ratings, and submitted work while totals stay labeled", () => {
  const html = renderProgress(fixture(), "system_design");
  assert.ok(!html.includes("Ruby fixture"));
  assert.ok(!html.includes("data-practice-gap="));
  assert.ok(html.includes("Totals cover all tracks"));
  assert.ok(html.includes("No observed self-ratings yet"));
});

test("missing or truncated execution evidence cannot become a passing conclusion", () => {
  const execution = {
    status: "execution_completed",
    summary: { passed: 12, tests: 12, failures: 0, errors: 0, skipped: 0 },
  };
  assert.match(renderExecution(execution), /^Runner reported 12\/12/);
  execution.output_truncated = true;
  assert.ok(!renderExecution(execution).includes("12/12"));
  assert.match(renderExecution(execution), /no passing conclusion/);
  assert.match(renderExecution(null), /No test run/);
});
