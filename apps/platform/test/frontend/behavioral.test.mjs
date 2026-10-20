import test from "node:test";
import assert from "node:assert/strict";
import {
  filterStories,
  storyText,
  storyForm,
  storyLabels,
} from "../../public/stories.js";
import { workspaceMarkup } from "../../public/workspace-view.js";
import { wordCount } from "../../public/behavioral-editor.js";
import { editorReadOnly, sessionPolicy } from "../../public/session-policy.js";
const story = {
  id: "fixture",
  title: "<script>example</script>",
  topics: ["incidents"],
  sections: Object.fromEntries(
    Object.keys(storyLabels).map((key) => [key, "<b>Mentored colleague</b>"]),
  ),
  readiness: "draft",
};
test("story retrieval finds details and applies theme filters without mutating examples", () => {
  assert.equal(filterStories([story], "mentored", "incidents").length, 1);
  assert.equal(filterStories([story], "mentored", "ownership").length, 0);
  assert.equal(filterStories([story], "missing").length, 0);
  assert.equal(story.readiness, "draft");
});
test("story forms escape personal text and exports include every section and self-marked readiness", () => {
  const form = storyForm(story, []);
  assert.ok(form.includes("&lt;script&gt;"));
  assert.ok(!form.includes("<b>Mentored"));
  const text = storyText(story);
  for (const label of Object.values(storyLabels))
    assert.ok(text.includes(label));
  assert.ok(text.includes("Self-marked readiness: draft"));
  assert.equal(wordCount("  specific actions\n observable outcomes "), 4);
  assert.equal(wordCount(" \n"), 0);
});
test("behavioral assessments lock fresh responses before starting and need no worker", () => {
  const session = {
    track: "behavioral",
    status: "draft",
    mode: "assessment",
    executable: false,
    editable_paths: ["answer.md"],
    executions: [],
  };
  assert.equal(editorReadOnly(session, "answer.md"), true);
  assert.equal(
    editorReadOnly({ ...session, status: "active" }, "answer.md"),
    false,
  );
  assert.equal(
    editorReadOnly({ ...session, mode: "guided" }, "answer.md"),
    false,
  );
  assert.equal(sessionPolicy(session, {}).buttons.run.hidden, true);
  assert.equal(sessionPolicy(session, {}).buttons.start.disabled, false);
});

test("behavioral workspaces hide coding run history without hiding support", () => {
  const markup = workspaceMarkup({
    track: "behavioral",
    files: { "answer.md": "" },
    mode: "guided",
    title: "Ownership",
    brief: "Question",
    exercise_version: 1,
  });
  assert.match(markup, /data-panel="runs"[^>]*hidden/);
  assert.match(markup, /data-panel="support"[^>]*>Support/);
  assert.ok(markup.includes("Behavioral rehearsal"));
});
