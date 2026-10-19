import { esc, icon, modeName, renderBrief } from "./ui.js";
import { renderSavedFeedback } from "./rework.js";
export function workspaceMarkup(session) {
  const design = !!session.files["diagram.json"];
  return `<main class="workspace ${design ? "is-design" : ""}">
    <header class="workspace-head">
    <button id="back" class="quiet" aria-label="${session.mock_interview_id ? "Back to mock interview" : "Back to studio"}">← <span>${session.mock_interview_id ? "Interview" : "Studio"}</span>
    </button>
    <div class="workspace-identity">
    <strong>${esc(session.title)}</strong>
    <span>${modeName(session.mode)}${session.mock_interview_id ? " · mock interview stage" : ""}${session.revision_of_id ? " · rework" : ""}</span>
    </div>
    <span class="spacer">
    </span>
    <span class="save-state" id="save-state" role="status">Saved</span>
    <span class="timer" id="timer">Untimed</span>
    <button id="save" class="quiet">Save</button>
    <button id="run" class="primary" title="Run tests (⌘ / Ctrl + Enter)">${icon("play")}Run tests</button>
    <button id="submit">Submit</button>
    <button id="review-shortcut" class="primary" hidden>Review submission</button>
    </header>
    <div class="work-grid">
    <aside class="files">
    <h4>Files</h4>
    <div id="file-list">
    </div>
    <form class="new-file" id="new-file">
    <input aria-label="New Ruby file path" placeholder="app/models/event.rb">
    <button title="Add file" aria-label="Add Ruby file">+</button>
    </form>
    <p class="files-help">Autosave is on.<br>⌘ / Ctrl + S to save.</p>
    </aside>
    <div class="resize-handle resize-files" data-resize="files" role="separator" aria-label="Resize file explorer" aria-orientation="vertical" aria-valuemin="140" aria-valuemax="320" tabindex="0">
    </div>
    <section class="code-area" aria-label="${design ? "Design workspace" : "Code workspace"}">
    <div class="code-title">
    <span id="code-title">
    </span>
    <span class="spacer">
    </span>
    <span id="editor-position">
    </span>
    <button id="search-code" title="Find in ${design ? "notes" : "file"} (⌘ / Ctrl + F)">${design ? "Find in notes" : "Find"}</button>
    </div>
    <div id="code" class="code-editor">
    </div>
    <div class="resize-handle resize-output" data-resize="output" role="separator" aria-label="Resize test output" aria-orientation="horizontal" aria-valuemin="140" aria-valuemax="600" tabindex="0">
    </div>
    <section class="output" aria-label="Test results">
    <div class="output-toolbar">
    <h4 id="output-title">Test output</h4>
    <div role="group" aria-label="Output display">
    <button id="show-results" aria-pressed="true">Results</button>
    <button id="show-raw" aria-pressed="false">Raw output</button>
    </div>
    </div>
    <div id="test-summary" role="status">
    </div>
    <div id="test-details">
    <div class="result-message">Run tests to see results for your saved code.</div>
    </div>
    <pre id="output" hidden>${session.executable ? "Your test results will appear here.\nPrepare the environment, then run your saved code." : "Your writing saves automatically.\nExecution tools for this track are coming soon."}</pre>
    </section>
    </section>
    <div class="resize-handle resize-brief" data-resize="brief" role="separator" aria-label="Resize exercise brief" aria-orientation="vertical" aria-valuemin="260" aria-valuemax="520" tabindex="0">
    </div>
    <aside class="brief">
    <div class="workspace-tabs" role="tablist" aria-label="Session information">
    <button role="tab" id="tab-brief" aria-selected="true" aria-controls="panel-brief" data-panel="brief">Brief</button>
    <button role="tab" id="tab-support" aria-selected="false" aria-controls="panel-support" data-panel="support" tabindex="-1">Support</button>
    <button role="tab" id="tab-runs" aria-selected="false" aria-controls="panel-runs" data-panel="runs" tabindex="-1" ${design ? "hidden" : ""}>Runs</button>
    </div>
    <section class="brief-panel" id="panel-brief" role="tabpanel" aria-labelledby="tab-brief">
    <div class="eyebrow">Exercise · version ${session.exercise_version}</div>
    <h3>${esc(session.title)}</h3>
    ${session.revision_of_id ? `<section class="rework-context" aria-label="Rework context"><h4>Revision practice</h4><p><strong>Your goal:</strong> ${esc(session.revision_context.goal)}</p><p class="subtitle">Working from an earlier submission of the same exercise version.</p><button id="compare-rework">Compare saved changes</button><button id="open-original" class="quiet">Original submission →</button><details><summary>Feedback from the original</summary>${renderSavedFeedback(session.revision_context)}</details></section>` : ""}
    ${session.practice_focus ? `<section class="practice-focus" aria-label="Practice focus"><h4>Your practice focus</h4><strong>${esc(session.practice_focus.title)}</strong><p>${esc(session.practice_focus.practice)}</p><p class="subtitle">Based on your earlier self-assessment. Submit and review this attempt to reassess the gap.</p></section>` : ""}
    ${session.mock_interview_id ? `<section class="practice-focus"><h4>Part of a mock interview · ${session.duration_minutes} minutes</h4><p>The stage and overall deadlines keep running while you navigate. After submitting, use “Interview” at the top to continue to the next stage. The brief may include pacing suggestions for the standalone exercise.</p></section>` : ""}
    <div class="session-setup">
    <p id="session-state">
    </p>
    <p id="next-action">
    </p>
    <div class="setup-actions">
    <button id="prepare">Prepare environment</button>
    <button id="start" class="primary">Start session ${icon("arrow")}</button>
    </div>
    <p id="worker-state">
    </p>
    </div>
    <div class="brief-content">${renderBrief(session.brief)}</div>
    </section>
    <section class="brief-panel" id="panel-support" role="tabpanel" aria-labelledby="tab-support" hidden>
    </section>
    <section class="brief-panel" id="panel-runs" role="tabpanel" aria-labelledby="tab-runs" hidden>
    <h3>Run history</h3>
    <p class="subtitle">Select a run to inspect its output. Results belong to the code saved at that revision.</p>
    <div class="execution">
    <div id="executions">
    </div>
    </div>
    </section>
    </aside>
    </div>
    </main>`;
}
