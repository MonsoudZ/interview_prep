import test from "node:test";
import assert from "node:assert/strict";
import { sourceDiff } from "../../public/source-diff.js";
import { renderSourceDiff, renderSavedFeedback } from "../../public/rework.js";

test("line alignment preserves exact source locations for additions removals and repeated lines", () => {
  const cases = [
    ["a\nb\na\nc\n", "a\na\nx\nc\n"],
    [null, "new\n"],
    ["old\n", null],
    ["line", "line\n"],
    ["a\r\nb", "a\nb"],
    ["same\n".repeat(20) + "old\n", "same\n".repeat(20) + "new\n"],
  ];
  for (const [before, after] of cases) {
    const a = before ? before.split("\n") : [],
      b = after ? after.split("\n") : [];
    const { rows } = sourceDiff(before, after);
    let oldCount = 0,
      newCount = 0;
    for (const row of rows) {
      if (row.kind === "omitted") {
        oldCount += row.before;
        newCount += row.after;
        continue;
      }
      if (row.oldLine != null) {
        assert.equal(a[row.oldLine - 1], row.text);
        oldCount++;
      }
      if (row.newLine != null) {
        assert.equal(b[row.newLine - 1], row.text);
        newCount++;
      }
      if (row.kind === "same")
        assert.equal(a[row.oldLine - 1], b[row.newLine - 1]);
    }
    assert.equal(a.length, oldCount);
    assert.equal(b.length, newCount);
  }
});

test("large adversarial replacements use bounded output without pretending omitted lines were unchanged", () => {
  const diff = sourceDiff("old\n".repeat(100000), "new\n".repeat(100000));
  assert.ok(diff.large);
  assert.ok(diff.rows.length <= 410);
  assert.ok(
    diff.rows.some(
      (row) => row.kind === "omitted" && row.before > 0 && row.after > 0,
    ),
  );
  assert.ok(!diff.rows.some((row) => row.kind === "same" && row.text !== ""));
});

test("large near-identical files retain the actual change and collapse unchanged context", () => {
  const common = "unchanged\n".repeat(100000);
  const result = sourceDiff(common + "old\n", common + "new\n");
  assert.ok(!result.large);
  assert.ok(result.rows.length < 12);
  assert.ok(
    result.rows.some(
      (row) =>
        row.kind === "removed" && row.oldLine === 100001 && row.text === "old",
    ),
  );
  assert.ok(
    result.rows.some(
      (row) =>
        row.kind === "added" && row.newLine === 100001 && row.text === "new",
    ),
  );
});

test("diffs and captured feedback escape untrusted source without losing trailing-newline changes", () => {
  const html = renderSourceDiff(
    "<script>old()</script>",
    "<img src=x onerror=bad()>\n",
  );
  assert.ok(!html.includes("<script>"));
  assert.ok(!html.includes("<img"));
  assert.ok(html.includes("&lt;img"));
  assert.ok(html.includes("diff-added"));
  assert.ok(html.includes("diff-removed"));
  const feedback = renderSavedFeedback({
    prior_hints_revealed: 1,
    self_review: {
      entries: {
        correctness: {
          rating: "needs_development",
          notes: "<script>bad()</script>",
        },
      },
      reflection: "<img src=x>",
    },
  });
  assert.ok(!feedback.includes("<script>"));
  assert.ok(!feedback.includes("<img"));
  assert.ok(feedback.includes("Feedback captured when this rework began"));
});
