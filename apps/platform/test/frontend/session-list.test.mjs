import test from "node:test";
import assert from "node:assert/strict";
import {
  filterSessions,
  renderSessionRows,
  dashboardHash,
  dashboardPage,
} from "../../public/session-list.js";
const rows = [
  {
    id: "rails",
    title: "Rails API <script>",
    track: "rails",
    mode: "guided",
    status: "submitted",
    updated_at: "2026-10-18T12:00:00Z",
  },
  {
    id: "ruby",
    title: "Intervals",
    track: "ruby",
    mode: "assessment",
    status: "active",
    revision_of_id: "source",
    updated_at: "2026-10-18T12:00:00Z",
  },
  {
    id: "design",
    title: "Webhooks",
    track: "system_design",
    mode: "assessment",
    status: "submitted",
    mock_interview_id: "mock",
    updated_at: "2026-10-18T12:00:00Z",
  },
];
test("session filters combine status practice type and case-insensitive search", () => {
  assert.deepEqual(
    filterSessions(rows, { status: "ongoing" }).map((x) => x.id),
    ["ruby"],
  );
  assert.deepEqual(
    filterSessions(rows, { kind: "mock", query: " WEBHOOKS " }).map(
      (x) => x.id,
    ),
    ["design"],
  );
  assert.deepEqual(
    filterSessions(rows, { status: "submitted", kind: "ruby" }),
    [],
  );
  assert.deepEqual(
    filterSessions(rows, { kind: "rework" }).map((x) => x.id),
    ["ruby"],
  );
});
test("session row controls archive only complete standalone work and preserve escaped labels", () => {
  const html = renderSessionRows(rows, { organize: true });
  assert.match(html, /data-organize-session="rails"/);
  assert.doesNotMatch(
    html,
    /data-organize-session="ruby"|data-organize-session="design"/,
  );
  assert.match(html, /&lt;script&gt;/);
  assert.doesNotMatch(html, /<script>/);
  const archived = renderSessionRows(
    [{ ...rows[0], archived_at: "2026-10-18T12:00:00Z" }],
    { organize: true },
  );
  assert.match(archived, /Restore/);
  assert.match(archived, /Archived/);
});
test("dashboard hashes preserve sessions and exercise pages across reloads", () => {
  for (const page of ["home", "history", "library", "progress"])
    assert.equal(dashboardPage(dashboardHash(page)), page);
  assert.equal(dashboardPage("#unknown"), "home");
});
test("design status describes available tools without a placeholder promise", async () => {
  const { sessionPolicy } = await import("../../public/session-policy.js");
  const result = sessionPolicy({
    track: "system_design",
    status: "active",
    mode: "guided",
    executable: false,
    executions: [],
    editable_paths: [],
  });
  assert.match(result.workerState, /Architecture and notes/);
  assert.doesNotMatch(result.workerState, /upcoming|coming soon/);
});

test("a prepared timed session cannot start while its runner is offline", async () => {
  const { sessionPolicy } = await import("../../public/session-policy.js");
  const value = {
    status: "ready",
    mode: "assessment",
    track: "rails",
    executable: true,
    worker_available: false,
    executions: [],
    editable_paths: [],
  };
  assert.equal(sessionPolicy(value).buttons.start.disabled, true);
  assert.match(sessionPolicy(value).nextAction, /Reconnect the worker/);
  assert.equal(
    sessionPolicy({ ...value, mode: "guided" }).buttons.start.disabled,
    false,
  );
});
