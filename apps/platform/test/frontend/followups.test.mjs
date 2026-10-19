import test from "node:test";
import assert from "node:assert/strict";
import {
  reconcileRound,
  renderFollowupReview,
  followupTranscript,
} from "../../public/followups.js";

test("polling preserves an unsaved answer and detects a competing tab instead of replacing it", () => {
  const previous = {
    version: 2,
    status: "active",
    question_index: 0,
    question: { id: "correctness" },
  };
  assert.deepEqual(
    reconcileRound(
      previous,
      { ...previous, current_draft: "old" },
      "new local text",
      true,
    ),
    { accept: false, conflict: false },
  );
  assert.deepEqual(
    reconcileRound(
      previous,
      { ...previous, version: 3, current_draft: "other tab" },
      "new local text",
      true,
    ),
    { accept: false, conflict: true },
  );
  const acknowledged = reconcileRound(
    previous,
    { ...previous, version: 3, current_draft: "new local text" },
    "new local text",
    true,
  );
  assert.equal(true, acknowledged.accept);
  assert.equal(false, acknowledged.dirty);
});
test("deadline completion keeps late local text outside the accepted transcript", () => {
  const previous = {
    version: 2,
    status: "active",
    question: { id: "correctness" },
  };
  const incoming = {
    version: 3,
    status: "completed",
    transcript: [
      { id: "correctness", answer: { text: "saved before deadline" } },
    ],
  };
  const result = reconcileRound(previous, incoming, "unsaved late text", true);
  assert.equal(true, result.accept);
  assert.equal("unsaved late text", result.lateDraft);
  assert.equal(
    null,
    reconcileRound(previous, incoming, "saved before deadline", true).lateDraft,
  );
});
test("a competing completed review preserves local self-check edits", () => {
  const previous = { status: "completed", version: 4 };
  assert.deepEqual(
    reconcileRound(previous, { ...previous, version: 5 }, "", false, true),
    { accept: false, conflict: true },
  );
});
const round = {
  title: "Ruby fixture",
  mode: "guided",
  source_revision: "abc",
  content_version: "fixture",
  question_count: 2,
  completion_reason: "finished_early",
  review_entries: {
    correctness: { rating: "needs_practice", note: "<script>bad()</script>" },
  },
  reflection: "<img src=x>",
  transcript: [
    {
      id: "correctness",
      title: "Correctness",
      kind: "criterion",
      prompt: "Explain the invariant.",
      target: "Show a counterexample.",
      practice: "Trace three inputs.",
      answer: { status: "answered", text: "<script>untrusted()</script>" },
    },
    {
      id: "extension",
      title: "Changed requirement",
      kind: "extension",
      prompt: "Now stream the input.",
      target: "Separate the changed assumptions.",
      practice: "Explain the change.",
      answer: { status: "unanswered", text: "" },
    },
  ],
};
test("rendered answers and self-checks remain text and unanswered questions never become successes", () => {
  const html = renderFollowupReview(round);
  assert.ok(!html.includes("<script>"));
  assert.ok(!html.includes("<img"));
  assert.ok(html.includes("&lt;script&gt;"));
  assert.ok(html.includes("1/2 answered"));
  assert.ok(html.includes("Unanswered"));
  assert.ok(html.includes("Practice from your self-checks"));
});
test("transcript export labels rehearsal, actual response states, and unsaved local text", () => {
  const output = followupTranscript(round, "late local answer");
  assert.ok(output.includes("SCRIPTED FOLLOW-UP PRACTICE"));
  assert.ok(output.includes("Response status: Unanswered"));
  assert.ok(
    output.includes(
      "UNSAVED LOCAL TEXT — NOT PART OF THE SAVED ROUND\nlate local answer",
    ),
  );
  assert.ok(output.includes("not a hiring score"));
});
