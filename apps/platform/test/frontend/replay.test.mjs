import test from "node:test";
import assert from "node:assert/strict";
import {
  formatOffset,
  describeStep,
  describeEvents,
} from "../../public/replay.js";

test("offsets read as elapsed time since the opening revision", () => {
  assert.equal(formatOffset(0), "+00:00");
  assert.equal(formatOffset(65), "+01:05");
  assert.equal(formatOffset(3725), "+1:02:05");
  assert.equal(formatOffset(-4), "+00:00");
  assert.equal(formatOffset("oops"), "+00:00");
});

test("step descriptions name position, time, change count and submission", () => {
  const step = {
    offset_seconds: 130,
    changed_paths: ["a.rb"],
    submitted: true,
    executions: [],
    hints: [],
  };
  assert.equal(
    describeStep(step, 2, 5),
    "Save 3 of 5 · +02:10 · 1 file changed · submitted revision",
  );
  assert.equal(
    describeStep(
      { ...step, changed_paths: [], submitted: false, offset_seconds: 0 },
      0,
      5,
    ),
    "Opening revision · +00:00 · no source changes",
  );
});

test("events report runner counts only when a complete summary exists", () => {
  const step = {
    executions: [
      {
        purpose: "tests",
        status: "execution_failed",
        summary: { passed: 7, tests: 12 },
      },
      { purpose: "tests", status: "timed_out", summary: null },
      { purpose: "prepare", status: "execution_completed", summary: null },
    ],
    hints: [0, 2],
  };
  assert.deepEqual(describeEvents(step), [
    "Tests · runner reported 7/12 passing",
    "Tests · timed out · no complete summary",
    "Prepared · execution completed",
    "Hint 1 revealed",
    "Hint 3 revealed",
  ]);
});
