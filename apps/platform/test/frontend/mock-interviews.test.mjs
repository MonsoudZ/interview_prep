import test from "node:test";
import assert from "node:assert/strict";
import {
  renderMockInterview,
  mockReportText,
  mockStateKey,
} from "../../public/mock-interviews.js";
const fixture = (overrides = {}) => ({
  id: "mock-fixture",
  title: "Synthetic interview <script>",
  status: "active",
  stage_index: 0,
  started_at: null,
  deadline_at: null,
  duration_seconds: 5340,
  limitations: "Reported evidence is not a hiring score.",
  reflection: "",
  next_steps: [],
  stages: [
    {
      position: 0,
      kind: "workspace",
      title: "Repair & debug",
      duration_seconds: 2400,
      status: "current",
      session_id: "first",
      session_status: "active",
      exercise_version: 1,
    },
    {
      position: 1,
      kind: "workspace",
      title: "Design",
      duration_seconds: 2100,
      status: "pending",
    },
    {
      position: 2,
      kind: "followup",
      title: "Questions",
      duration_seconds: 840,
      status: "pending",
    },
  ],
  ...overrides,
});
test("unsubmitted stages cannot advance and future stages have no open button", () => {
  const html = renderMockInterview(fixture());
  assert.match(html, /id="advance-mock"[^>]*disabled/);
  assert.match(html, /data-open-stage="0"/);
  assert.doesNotMatch(html, /data-open-stage="1"|data-open-stage="2"/);
  assert.match(html, /Synthetic interview &lt;script&gt;/);
  assert.doesNotMatch(html, /<script>/);
});
test("stage submission offers advance while final completion is separate", () => {
  const value = fixture();
  value.stages[0].session_status = "submitted";
  assert.doesNotMatch(
    renderMockInterview(value),
    /id="advance-mock"[^>]*disabled/,
  );
  value.stage_index = 2;
  value.stages[2].followup_status = "completed";
  assert.match(renderMockInterview(value), /Complete interview/);
});
test("completed review separates unobserved ratings missing runs and source evidence", () => {
  const value = fixture({
    status: "completed",
    completion_reason: "finished_early",
  });
  value.stages[0].evidence = {
    revision: "a".repeat(64),
    reported_tests: [],
    self_assessment: {},
    criteria: [{ id: "atomicity", title: "Atomicity" }],
    model_reviews: [],
  };
  const html = renderMockInterview(value);
  assert.match(html, /No test run for this submitted revision/);
  assert.match(html, /not observed/);
  assert.match(html, /No advisory model review/);
  assert.doesNotMatch(html, /id="advance-mock"/);
});
test("export preserves per-source provenance partial states and focused drills", () => {
  const value = fixture({
    status: "completed",
    completion_reason: "all_stages",
    reflection: "Synthetic reflection",
    next_steps: [
      {
        title: "Atomicity",
        practice: "Inject a failure",
        basis: "Self-assessment",
      },
    ],
  });
  value.stages[2].transcript = {
    source_revision: "design-revision",
    question_count: 1,
    review_entries: {},
    transcript: [
      {
        id: "q",
        prompt: "Why lock?",
        source_session_id: "coding-session",
        source_revision: "coding-revision",
        answer: { status: "partial", text: "Synthetic partial answer" },
      },
    ],
  };
  const text = mockReportText(value);
  assert.match(text, /coding-session @ coding-revision/);
  assert.match(text, /\[partial\] Synthetic partial answer/);
  assert.match(text, /Next practice — Atomicity: Inject a failure/);
  assert.match(text, /Synthetic reflection/);
  assert.match(text, /not a hiring score/);
});

test("clock-only polling leaves the screen identity stable while changed stages refresh", () => {
  const a = fixture({ server_time: "2026-10-18T12:00:00Z" });
  const b = { ...a, server_time: "2026-10-18T12:00:05Z" };
  assert.equal(mockStateKey(a), mockStateKey(b));
  assert.notEqual(mockStateKey(a), mockStateKey({ ...b, stage_index: 1 }));
});

test("mock stage source and test controls wait for the stage clock", async () => {
  const { editorReadOnly, sessionPolicy } =
    await import("../../public/session-policy.js");
  const value = {
    mock_interview_id: "mock",
    status: "ready",
    mode: "assessment",
    executable: true,
    track: "rails",
    editable_paths: ["app/models/example.rb"],
    executions: [],
    revision: "source",
    worker_available: true,
  };
  assert.equal(editorReadOnly(value, "app/models/example.rb"), true);
  assert.equal(sessionPolicy(value).buttons.run.disabled, true);
  assert.equal(sessionPolicy(value).newFileHidden, true);
  const active = { ...value, status: "active" };
  assert.equal(editorReadOnly(active, "app/models/example.rb"), false);
  assert.equal(sessionPolicy(active).buttons.run.disabled, false);
});
