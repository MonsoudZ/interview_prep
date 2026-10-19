import test from "node:test";
import assert from "node:assert/strict";
import { sessionPolicy, editorReadOnly } from "../../public/session-policy.js";
const session = {
  status: "draft",
  mode: "assessment",
  track: "rails",
  executable: true,
  worker_available: true,
  revision: "v1",
  editable_paths: ["solution.rb"],
  executions: [],
};
const policy = (changes, context = {}) =>
  sessionPolicy(
    { ...session, ...changes },
    { openingRevision: "v1", ...context },
  );

test("assessment controls follow preparation, readiness, active work, and submission", () => {
  assert.equal(policy({}).buttons.start.disabled, true);
  assert.equal(
    policy({
      status: "preparing",
      executions: [{ purpose: "prepare", revision: "v1", status: "queued" }],
    }).buttons.prepare.hidden,
    true,
  );
  assert.equal(policy({ status: "ready" }).buttons.start.disabled, false);
  assert.equal(policy({ status: "active" }).buttons.submit.disabled, false);
  assert.equal(policy({ status: "active" }).buttons.start.hidden, true);
  const submitted = policy({ status: "submitted" });
  for (const action of ["save", "run", "submit", "start", "prepare"])
    assert.equal(submitted.buttons[action].hidden, true);
  assert.equal(submitted.buttons["review-shortcut"].hidden, false);
  assert.equal(submitted.newFileHidden, true);
});
test("writing and guided practice do not require a coding runner to start", () => {
  assert.equal(
    policy({ track: "ruby", executable: false, worker_available: false })
      .buttons.start.disabled,
    false,
  );
  assert.equal(policy({ mode: "guided" }).buttons.start.disabled, false);
  assert.equal(
    policy({ track: "system_design", executable: false }).buttons.run.hidden,
    true,
  );
});
test("busy controls and save conflicts remain disabled across polling renders", () => {
  const state = policy(
    { status: "active" },
    { busy: new Set(["run", "submit"]) },
  );
  assert.equal(state.buttons.run.disabled, true);
  assert.equal(state.buttons.submit.disabled, true);
  const conflict = policy({ status: "ready" }, { conflict: true });
  for (const action of ["run", "start", "save"])
    assert.equal(conflict.buttons[action].disabled, true);
});
test("changed source, offline workers, failed preparation, and waiting queues have distinct messages", () => {
  assert.match(
    policy({ worker_available: false }).nextAction,
    /worker connects/,
  );
  assert.match(policy({ revision: "v2" }).nextAction, /Code changed/);
  assert.match(
    policy({
      executions: [
        { purpose: "prepare", revision: "v1", status: "execution_failed" },
      ],
    }).nextAction,
    /needs attention/,
  );
  assert.match(
    policy({}, { autoPreparationAttempted: true }).nextAction,
    /could not be queued/,
  );
  assert.match(
    policy({
      executions: [{ purpose: "prepare", revision: "v1", status: "leased" }],
    }).nextAction,
    /Preparing the environment/,
  );
});
test("fixed exercise files, conflicts, and submitted work are read-only", () => {
  assert.equal(editorReadOnly(session, "solution.rb"), false);
  assert.equal(editorReadOnly(session, "test/fixed.rb"), true);
  assert.equal(editorReadOnly(session, "solution.rb", true), true);
  assert.equal(
    editorReadOnly({ ...session, status: "submitted" }, "solution.rb"),
    true,
  );
});
