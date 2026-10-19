import { renderBrief } from "../../public/ui.js";
import test from "node:test";
import assert from "node:assert/strict";
import {
  cleanPreferences,
  preferenceStore,
  shouldAutoPrepare,
  preparationRequestId,
} from "../../public/workspace-state.js";
import { parseFailures, renderTestResults } from "../../public/test-results.js";

test("a clean summary from a failed command is not presented as passing", () => {
  const host = { innerHTML: "", querySelectorAll: () => [] };
  const execution = {
    purpose: "tests",
    status: "execution_failed",
    revision: "abcdef0123456789",
    result: {
      output: "12 runs, 30 assertions, 0 failures, 0 errors, 0 skips\n",
    },
    reported_test_summary: {
      reported: true,
      tests: 12,
      assertions: 30,
      failures: 0,
      errors: 0,
      skipped: 0,
      passed: 12,
    },
  };
  renderTestResults(host, execution, { openFile() {} });
  assert.match(host.innerHTML, /Run did not finish cleanly/);
  assert.match(host.innerHTML, /runner status execution_failed/);
  assert.doesNotMatch(host.innerHTML, /All reported tests passed/);
  renderTestResults(
    host,
    { ...execution, status: "execution_completed" },
    { openFile() {} },
  );
  assert.match(host.innerHTML, /All reported tests passed/);
});

test("runner diagnostics preserve expected/actual values, source, and failure order", () => {
  const output = `Failure:\nEventsTest#test_creates [test/integration/events_test.rb:22]:\nExpected response to be a <201: created>, but was a <501: Not Implemented>\nResponse body: \n\nbin/rails test test/integration/events_test.rb:22\n\nF\n\nFailure:\nEventsTest#test_lists [test/integration/events_test.rb:73]:\nExpected: []\n  Actual: [1]\n\nFinished in 0.1s\n12 runs, 12 assertions, 2 failures, 0 errors, 0 skips`;
  const items = parseFailures(output);
  assert.equal(items.length, 2);
  assert.equal(items[0].expected, "201: created");
  assert.equal(items[0].actual, "501: Not Implemented");
  assert.ok(!items[0].message.endsWith("F"));
  assert.equal(items[0].path, "test/integration/events_test.rb");
  assert.equal(items[0].line, 22);
  assert.equal(items[1].expected, "[]");
  assert.equal(items[1].actual, "[1]");
  assert.ok(!items[1].message.includes("Finished in"));
});
test("truncated and error output retain diagnostics without inventing test results", () => {
  const items = parseFailures(
    "Error:\nEventsTest#test_lists:\nNameError: uninitialized constant Event\n    app/controllers/events_controller.rb:3",
  );
  assert.equal(items.length, 1);
  assert.equal(items[0].kind, "Error");
  assert.equal(items[0].expected, null);
  assert.equal(items[0].path, null);
  assert.equal(
    parseFailures("12 runs, 158 assertions, 0 failures, 0 errors, 0 skips")
      .length,
    0,
  );
  assert.equal(parseFailures("worker unavailable").length, 0);
});
test("untrusted output remains diagnostic data and ANSI sequences are removed", () => {
  const item = parseFailures(
    "\x1b[31mFailure:\nTest#test_x [test/x.rb:1]:\n<script>alert(1)</script>\x1b[0m",
  )[0];
  assert.equal(item.message, "<script>alert(1)</script>");
  assert.equal(item.line, 1);
});
test("workspace preferences contain UI metadata only and validate stored values", () => {
  const value = cleanPreferences({
    selected: "solution.rb",
    files: { "solution.rb": "private source" },
    positions: { "solution.rb": { anchor: 5, head: 9, top: 30 } },
    layout: { files: 999, brief: -1, output: "oops" },
    panel: "invented",
  });
  assert.equal(value.files, undefined);
  assert.equal(value.positions["solution.rb"].head, 9);
  assert.deepEqual(value.layout, { files: 320, brief: 260, output: 240 });
  assert.equal(value.panel, "brief");
});
test("unavailable or corrupt browser storage does not prevent opening a workspace", () => {
  const storage = {
    getItem() {
      throw Error("blocked");
    },
    setItem() {
      throw Error("blocked");
    },
  };
  const store = preferenceStore(storage, "account:session");
  assert.equal(store.read().selected, "");
  assert.doesNotThrow(() => store.write({}));
  assert.equal(
    preferenceStore({ getItem: () => "{bad" }, "x").read().layout.files,
    200,
  );
});
test("automatic preparation waits for a worker and avoids queued, completed, failed, changed, and submitted revisions", () => {
  const session = {
    executable: true,
    worker_available: true,
    status: "draft",
    revision: "v1",
    executions: [],
  };
  assert.equal(shouldAutoPrepare(session, "v1"), true);
  for (const change of [
    { worker_available: false },
    { executable: false },
    { status: "submitted" },
    { status: "ready" },
    { status: "active" },
    { revision: "v2" },
    { executions: [{ purpose: "tests", status: "queued", revision: "v1" }] },
    {
      executions: [
        { purpose: "prepare", status: "execution_failed", revision: "v1" },
      ],
    },
    {
      executions: [
        { purpose: "prepare", status: "execution_completed", revision: "v1" },
      ],
    },
  ])
    assert.equal(shouldAutoPrepare({ ...session, ...change }, "v1"), false);
});

test("opening the same source in multiple tabs shares a preparation idempotency key", async () => {
  const first = await preparationRequestId("session-1", "revision-1");
  assert.equal(first, await preparationRequestId("session-1", "revision-1"));
  assert.notEqual(first, await preparationRequestId("session-1", "revision-2"));
  assert.notEqual(first, await preparationRequestId("session-2", "revision-1"));
  assert.match(
    first,
    /^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
  );
});

test("standalone Ruby Minitest diagnostics retain numbered failures and errors", () => {
  const failures = parseFailures(
    "  1) Failure:\nVisibleIntervalsTest#test_empty_input [test/visible_test.rb:6]:\nExpected: []\n  Actual: nil\n\n  2) Error:\nAdditionalIntervalsTest#test_input_ownership:\nFrozenError: can't modify frozen Array\n\n12 runs, 12 assertions, 1 failures, 1 errors, 0 skips",
  );
  assert.equal(failures.length, 2);
  assert.equal(failures[0].expected, "[]");
  assert.equal(failures[0].actual, "nil");
  assert.equal(failures[0].path, "test/visible_test.rb");
  assert.equal(failures[1].kind, "Error");
  assert.ok(!failures[0].message.includes("2)"));
});

test("brief headings do not swallow their following paragraph and task text stays escaped", () => {
  const html = renderBrief(
    "# Title\n\n## Your workspace\nOnly solution.rb is editable.\n\n<script>unsafe</script>",
  );
  assert.ok(
    html.includes(
      "<h4>Your workspace</h4><p>Only solution.rb is editable.</p>",
    ),
  );
  assert.ok(html.includes("&lt;script&gt;unsafe&lt;/script&gt;"));
  assert.ok(!html.includes("<script>"));
});
