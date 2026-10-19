import { createEditor } from "./editor.bundle.js?v=1";
import { createDesignEditor } from "./design-workspace.js";
import { renderTestResults } from "./test-results.js";
import {
  preferenceStore,
  shouldAutoPrepare,
  preparationRequestId,
} from "./workspace-state.js";
import { mountPanels } from "./panels.js";
import { mountPractice } from "./practice.js";
import { esc, short, statusName, confirmSubmission } from "./ui.js";
import { createRequestScope } from "./request-scope.js";
import { workspaceMarkup } from "./workspace-view.js";
import { sessionPolicy, editorReadOnly } from "./session-policy.js";
import { openComparison } from "./rework.js";
import { openFollowups } from "./followups.js";

export function mountWorkspace({
  root,
  session,
  account,
  api: request,
  notice: showNotice,
  onBack,
  reviewOnOpen = false,
  onOpenSession,
  followupRoundId,
}) {
  const scope = createRequestScope(request),
    api = scope.request;
  const notice = (message) => {
    if (scope.alive) showNotice(message);
  };
  let active = session,
    files = {},
    selected = "",
    dirty = false,
    saving = null,
    autosave,
    polling,
    serverOffset = 0,
    conflict = false;
  let practiceTools = null,
    selectedExecutionId = null,
    sourceEditor = null,
    panels = null,
    preferences = null,
    preferencesStore = null,
    preferenceTimer,
    openingRevision,
    autoPreparing = false,
    lastOutputKey = null,
    autoPreparationAttempted = false,
    pollingRequest = false,
    mutationEpoch = 0;
  const busy = new Set();
  let storage = null;
  try {
    storage = window.localStorage;
  } catch {}
  function persistPreferences() {
    if (preferencesStore && preferences) preferencesStore.write(preferences);
  }
  function rememberPosition(path, position) {
    if (!preferences) return;
    preferences.positions[path] = position;
    clearTimeout(preferenceTimer);
    preferenceTimer = setTimeout(persistPreferences, 250);
    const indicator = root.querySelector("#editor-position");
    if (indicator && path === selected) {
      const before = (files[path] || "").slice(0, position.head);
      indicator.textContent = `Ln ${before.split("\n").length}, Col ${before.length - before.lastIndexOf("\n")}`;
    }
  }
  function disposeWorkspace() {
    clearTimeout(preferenceTimer);
    if (sourceEditor && selected)
      rememberPosition(selected, sourceEditor.position());
    persistPreferences();
    sourceEditor?.destroy();
    panels?.destroy();
    sourceEditor = null;
    panels = null;
    preferences = null;
    preferencesStore = null;
    clearTimeout(preferenceTimer);
  }
  async function maybePrepare() {
    if (
      !active ||
      autoPreparing ||
      autoPreparationAttempted ||
      !shouldAutoPrepare(active, openingRevision)
    )
      return;
    autoPreparing = true;
    autoPreparationAttempted = true;
    try {
      await sessionAction("prepare", true);
    } finally {
      autoPreparing = false;
      renderSessionState();
    }
  }
  const hasDesignCanvas = !!session.files["diagram.json"];
  function mount() {
    active = session;
    openingRevision = session.revision;
    autoPreparationAttempted = false;
    lastOutputKey = null;
    files = { ...session.files };
    dirty = false;
    conflict = false;
    selectedExecutionId = null;
    selected = hasDesignCanvas
      ? "requirements.md"
      : session.track === "rails" &&
          files["app/controllers/events_controller.rb"] !== undefined
        ? "app/controllers/events_controller.rb"
        : session.editable_paths[0] || Object.keys(files)[0];
    preferencesStore = preferenceStore(
      storage,
      `interview.workspace.v1:${account.id}:${session.id}`,
    );
    preferences = preferencesStore.read();
    if (Object.hasOwn(files, preferences.selected))
      selected = preferences.selected;
    if (hasDesignCanvas && !selected.endsWith(".md"))
      selected = "requirements.md";
    preferences.selected = selected;
    window.history.replaceState(null, "", `#session/${session.id}`);
    serverOffset = new Date(session.server_time).getTime() - Date.now();
    root.innerHTML = workspaceMarkup(session);
    root.querySelector("#review-shortcut").onclick = () =>
      root.querySelector("#open-review")?.click();
    const tabs = [...root.querySelectorAll("[data-panel]")].filter(
      (tab) => !tab.hidden,
    );
    function activateTab(button) {
      if (!scope.alive) return;
      preferences.panel = button.dataset.panel;
      persistPreferences();
      tabs.forEach((tab) => {
        const chosen = tab === button;
        tab.setAttribute("aria-selected", String(chosen));
        tab.tabIndex = chosen ? 0 : -1;
        root.querySelector("#panel-" + tab.dataset.panel).hidden = !chosen;
      });
    }
    tabs.forEach((button, index) => {
      button.onclick = () => activateTab(button);
      button.onkeydown = (event) => {
        const next =
          event.key === "ArrowRight"
            ? (index + 1) % tabs.length
            : event.key === "ArrowLeft"
              ? (index + tabs.length - 1) % tabs.length
              : event.key === "Home"
                ? 0
                : event.key === "End"
                  ? tabs.length - 1
                  : null;
        if (next !== null) {
          event.preventDefault();
          activateTab(tabs[next]);
          tabs[next].focus();
        }
      };
    });
    const practiceHost = document.createElement("section");
    practiceHost.id = "practice-tools";
    root.querySelector("#panel-support").append(practiceHost);
    practiceTools = mountPractice(session, {
      api,
      notice,
      signal: scope.signal,
      onOpen: (id) => onOpenSession(id),
    });
    const comparisonButton = root.querySelector("#compare-rework");
    if (comparisonButton)
      comparisonButton.onclick = async () => {
        comparisonButton.disabled = true;
        try {
          await save();
          if (scope.alive)
            await openComparison(active, { api, signal: scope.signal, notice });
        } catch (error) {
          notice(error.message);
        } finally {
          if (scope.alive) comparisonButton.disabled = false;
        }
      };
    const originalButton = root.querySelector("#open-original");
    if (originalButton)
      originalButton.onclick = async () => {
        originalButton.disabled = true;
        try {
          await save();
          if (scope.alive) await onOpenSession(session.revision_of_id);
        } catch (error) {
          notice(error.message);
        } finally {
          if (scope.alive) originalButton.disabled = false;
        }
      };
    const editorOptions = {
      onChange(path, value) {
        if (!scope.alive) return;
        files[path] = value;
        if (!active.editable_paths.includes(path)) return;
        dirty = true;
        setSaveState("Unsaved changes");
        clearTimeout(autosave);
        autosave = setTimeout(
          () => save().catch((error) => notice(error.message)),
          800,
        );
      },
      onPosition: (path, position) => {
        if (scope.alive) rememberPosition(path, position);
      },
      onSave: () => save().catch((error) => notice(error.message)),
      onRun: () => {
        const button = root.querySelector("#run");
        if (button && !button.disabled && !button.hidden) sessionAction("run");
      },
    };
    sourceEditor = hasDesignCanvas
      ? createDesignEditor(root.querySelector("#code"), {
          ...editorOptions,
          files,
          notice,
          onSelect(path) {
            selected = path;
            renderCode();
          },
        })
      : createEditor(root.querySelector("#code"), editorOptions);
    panels = mountPanels(
      root.querySelector(".workspace"),
      preferences.layout,
      (layout) => {
        if (!scope.alive) return;
        preferences.layout = layout;
        persistPreferences();
      },
    );
    root.querySelector("#search-code").onclick = () => sourceEditor?.search();
    function setOutputView(raw) {
      if (!scope.alive) return;
      root.querySelector("#output").hidden = !raw;
      root.querySelector("#test-details").hidden = raw;
      root
        .querySelector("#show-results")
        .setAttribute("aria-pressed", String(!raw));
      root.querySelector("#show-raw").setAttribute("aria-pressed", String(raw));
    }
    root.querySelector("#show-results").onclick = () => setOutputView(false);
    root.querySelector("#show-raw").onclick = () => setOutputView(true);
    renderFiles();
    renderCode();
    renderSessionState();
    const restoredTab = tabs.find(
      (tab) => tab.dataset.panel === preferences.panel,
    );
    if (restoredTab) activateTab(restoredTab);
    root.onkeydown = (event) => {
      if (event.defaultPrevented) return;
      if (!(event.metaKey || event.ctrlKey)) return;
      if (event.key.toLowerCase() === "s") {
        event.preventDefault();
        save().catch((error) => notice(error.message));
      }
      if (
        event.key === "Enter" &&
        !root.querySelector("#run").disabled &&
        !root.querySelector("#run").hidden
      ) {
        event.preventDefault();
        sessionAction("run");
      }
    };
    root.querySelector("#save").onclick = () =>
      save().catch((error) => notice(error.message));
    root.querySelector("#back").onclick = async () => {
      try {
        await save();
        if (scope.alive) await onBack();
      } catch (error) {
        notice(error.message);
      }
    };
    root.querySelector("#new-file").onsubmit = (event) => {
      if (!scope.alive) return;
      event.preventDefault();
      const input = event.target.querySelector("input");
      const path = input.value.trim();
      if (!/^app\/(?:[A-Za-z0-9_-]+\/)*[A-Za-z0-9_-]+\.rb$/.test(path))
        return notice("Use a Ruby file path inside app/.");
      if (files[path] !== undefined) return notice("That file already exists.");
      files[path] = "";
      active.editable_paths.push(path);
      dirty = true;
      selected = path;
      input.value = "";
      renderFiles();
      renderCode();
      setSaveState("Unsaved changes");
      clearTimeout(autosave);
      autosave = setTimeout(
        () => save().catch((error) => notice(error.message)),
        800,
      );
    };
    for (const action of ["prepare", "start", "submit", "run"])
      root.querySelector("#" + action).onclick = () => sessionAction(action);
    polling = setInterval(pollSession, 2500);
    maybePrepare();
  }
  function renderFiles() {
    if (!scope.alive) return;
    const exerciseOpen =
      root.querySelector("#exercise-files")?.open ||
      !active.editable_paths.includes(selected);
    const fileButton = (path) =>
      `<button class="file ${path === selected ? "selected" : ""}" data-file="${esc(path)}" aria-pressed="${path === selected}" title="${esc(path)}"><span class="file-symbol">${path.endsWith(".rb") ? "rb" : "≡"}</span><span class="file-name">${esc(path.split("/").at(-1))}<small>${esc(path.split("/").slice(0, -1).join("/") || "repository")}</small></span></button>`;
    const paths = Object.keys(files).sort();
    root.querySelector("#file-list").innerHTML =
      `<div class="file-group-label">Solution</div>${paths
        .filter((path) => active.editable_paths.includes(path))
        .map(fileButton)
        .join(
          "",
        )}<details id="exercise-files" ${exerciseOpen ? "open" : ""}><summary>Exercise files <span>read-only</span></summary>${paths
        .filter((path) => !active.editable_paths.includes(path))
        .map(fileButton)
        .join("")}</details>`;
    root.querySelectorAll("[data-file]").forEach(
      (button) =>
        (button.onclick = () => {
          selected = button.dataset.file;
          preferences.selected = selected;
          persistPreferences();
          renderFiles();
          renderCode();
        }),
    );
  }
  function renderCode() {
    if (!scope.alive) return;
    root.querySelector("#code-title").textContent =
      (hasDesignCanvas ? "Architecture & design notes" : selected) +
      (active.editable_paths.includes(selected)
        ? ""
        : " · read-only exercise file");
    preferences.selected = selected;
    persistPreferences();
    sourceEditor.open(
      selected,
      files[selected] || "",
      editorReadOnly(active, selected, conflict),
      preferences.positions[selected],
    );
    rememberPosition(selected, sourceEditor.position());
  }
  function setSaveState(text) {
    if (!scope.alive) return;
    const node = root.querySelector("#save-state");
    if (node) node.textContent = text;
  }
  async function save() {
    if (!scope.alive) return;
    clearTimeout(autosave);
    if (conflict)
      throw new Error(
        "A save conflict needs attention. Copy your unsaved code before reopening the session.",
      );
    if (saving) {
      await saving;
      if (dirty) return save();
      return;
    }
    if (!dirty || active.status === "submitted") return;
    const edits = Object.fromEntries(
      active.editable_paths.map((path) => [path, files[path]]),
    );
    dirty = false;
    mutationEpoch++;
    setSaveState("Saving…");
    saving = api(`/api/sessions/${active.id}/snapshot`, "PUT", {
      files: edits,
      expected_revision: active.revision,
    })
      .then((result) => {
        active = {
          ...result,
          editable_paths: [
            ...new Set([...result.editable_paths, ...active.editable_paths]),
          ],
        };
        setSaveState(dirty ? "Unsaved changes" : "Saved");
        renderSessionState();
      })
      .catch((error) => {
        dirty = true;
        if (error.status === 409) conflict = true;
        setSaveState("Save failed — work kept in this tab");
        throw error;
      });
    try {
      await saving;
    } finally {
      saving = null;
    }
    if (dirty && !conflict) return save();
  }
  async function sessionAction(action, automatic = false) {
    if (!scope.alive || busy.has(action)) return;
    busy.add(action);
    mutationEpoch++;
    renderSessionState();
    try {
      await save();
      if (action === "submit" && !(await confirmSubmission(scope.signal)))
        return;
      const path = action === "run" ? "execute" : action;
      const id = active.id;
      const revision = active.revision;
      const requestId = automatic
        ? await preparationRequestId(id, revision)
        : crypto.randomUUID();
      if (active?.id !== id) return;
      const result = await api(`/api/sessions/${id}/${path}`, "POST", {
        expected_revision: revision,
        client_request_id: requestId,
      });
      if (active?.id !== id) return;
      active = result;
      if (["run", "prepare"].includes(action)) selectedExecutionId = null;
      renderSessionState();
      renderCode();
      if (["run", "prepare"].includes(action) && !automatic)
        notice(
          active.worker_available
            ? "Execution queued."
            : "Queued. Waiting for a connected execution worker.",
        );
      if (action === "submit")
        notice(
          "Submission saved. Open Review submission to reflect and plan your next practice.",
        );
    } catch (error) {
      notice(error.message);
    } finally {
      busy.delete(action);
      renderSessionState();
    }
  }
  function renderSessionState() {
    if (!scope.alive || !active || !root.querySelector("#session-state"))
      return;
    const policy = sessionPolicy(active, {
      openingRevision,
      autoPreparing,
      autoPreparationAttempted,
      busy,
      conflict,
    });
    practiceTools?.update(active);
    root.querySelector("#session-state").innerHTML =
      `<span class="session-badge status-${esc(active.status)}">${statusName(active.status)}</span><code>${short(active.revision)}</code>`;
    root.querySelector("#next-action").textContent = policy.nextAction;
    root.querySelector("#worker-state").textContent = policy.workerState;
    for (const [action, control] of Object.entries(policy.buttons)) {
      const button = root.querySelector("#" + action);
      button.hidden = control.hidden;
      button.disabled = control.disabled;
      if (control.label) button.textContent = control.label;
    }
    root.querySelector(".files-help").innerHTML = policy.submitted
      ? "Submitted snapshot.<br>Preserved as read-only."
      : "Autosave is on.<br>⌘ / Ctrl + S to save.";
    if (policy.submitted && !dirty) setSaveState("Read-only submission");
    root.querySelector("#new-file").hidden = policy.newFileHidden;
    const executions = root.querySelector("#executions");
    executions.innerHTML = active.executions.length
      ? active.executions
          .map(
            (e, index) =>
              `<button data-execution="${index}">${esc(e.purpose)} · ${esc(executionLabel(e))}<br>revision ${short(e.revision)}${e.reported_test_summary ? `<br>Reported: ${e.reported_test_summary.passed}/${e.reported_test_summary.tests} passing` : ""}</button>`,
          )
          .join("")
      : '<div class="run-empty">No runs yet.<br>Prepare the environment or run your tests to see results here.</div>';
    executions.querySelectorAll("[data-execution]").forEach(
      (button) =>
        (button.onclick = () => {
          const execution = active.executions[Number(button.dataset.execution)];
          selectedExecutionId = execution.id;
          showOutput(execution);
        }),
    );
    const selectedExecution =
      active.executions.find(
        (execution) => execution.id === selectedExecutionId,
      ) || active.executions[0];
    if (selectedExecution) showOutput(selectedExecution);
    updateTimer();
  }
  function executionLabel(execution) {
    return (
      {
        queued: "Queued",
        leased: "Starting / running",
        execution_completed: "Finished",
        execution_failed: "Command failed",
        timed_out: "Time limit reached",
        output_limit: "Output limit reached",
        infrastructure_error: "Runner unavailable",
      }[execution.status] || execution.status
    );
  }
  function showOutput(execution) {
    if (!scope.alive) return;
    const stale = execution.revision !== active.revision;
    root.querySelector("#output-title").textContent =
      `${execution.purpose.toUpperCase()} · ${executionLabel(execution).toUpperCase()} · ${short(execution.revision)}${stale ? " · EARLIER REVISION" : ""}`;
    const summary = execution.reported_test_summary;
    root.querySelector("#test-summary").dataset.tone =
      summary && (summary.failures || summary.errors) ? "failure" : "neutral";
    root.querySelector("#test-summary").textContent = summary
      ? `Runner reported ${summary.passed}/${summary.tests} passing · ${summary.failures} failures · ${summary.errors} errors · ${summary.skipped} skipped${stale ? " · Earlier saved code" : ""}`
      : execution.status === "queued"
        ? "Waiting in the execution queue."
        : execution.status === "leased"
          ? "The worker is preparing or running this saved revision."
          : execution.purpose === "prepare" &&
              execution.status === "execution_completed"
            ? "Environment preparation finished. Run tests to check your solution."
            : "No complete test-count summary was reported.";
    root.querySelector("#output").textContent =
      execution.result?.output ||
      (execution.status === "queued"
        ? "Your code is saved. Execution will begin when a worker is available."
        : execution.status === "leased"
          ? "Waiting for the worker’s result…"
          : "No output was returned.");
    const key = `${execution.id}:${execution.status}`;
    if (key !== lastOutputKey) {
      lastOutputKey = key;
      renderTestResults(root.querySelector("#test-details"), execution, {
        openFile(path, line) {
          if (!scope.alive) return;
          if (!Object.hasOwn(files, path))
            return notice(
              "That diagnostic does not reference an available workspace file.",
            );
          selected = path;
          renderFiles();
          renderCode();
          sourceEditor.jump(line);
        },
      });
    }
  }
  async function pollSession() {
    if (!scope.alive || !active || pollingRequest || saving || busy.size)
      return;
    pollingRequest = true;
    const epoch = mutationEpoch;
    try {
      const id = active.id;
      const result = await api(`/api/sessions/${id}`);
      if (active?.id !== id || epoch !== mutationEpoch) return;
      if (result.revision !== active.revision && !saving) {
        conflict = true;
        setSaveState("Newer revision exists — reopen before editing");
        sourceEditor?.setReadOnly(true);
      }
      for (const key of [
        "status",
        "deadline_at",
        "submitted_at",
        "submitted_revision",
        "executions",
        "worker_available",
      ])
        active[key] = result[key];
      serverOffset = new Date(result.server_time).getTime() - Date.now();
      renderSessionState();
      maybePrepare();
      if (active.status === "submitted") {
        sourceEditor?.setReadOnly(true);
        if (dirty) setSaveState("Late edits kept in this tab; not submitted");
      }
    } catch (error) {
      setSaveState("Connection interrupted — keep this tab open");
    } finally {
      pollingRequest = false;
    }
  }
  function updateTimer() {
    const timer = root.querySelector("#timer");
    if (!scope.alive || !timer || !active) return;
    if (active.status === "submitted") {
      timer.textContent = "Submitted";
      return;
    }
    if (!active.deadline_at) {
      timer.textContent =
        active.mode === "assessment" ? "Not started" : "Untimed";
      return;
    }
    const seconds = Math.max(
      0,
      Math.ceil(
        (new Date(active.deadline_at).getTime() - Date.now() - serverOffset) /
          1000,
      ),
    );
    timer.textContent =
      active.status === "submitted"
        ? "Submitted"
        : `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
  }

  mount();
  if (followupRoundId && session.status === "submitted")
    openFollowups(session, {
      api,
      signal: scope.signal,
      notice,
      initialRoundId: followupRoundId,
    });
  if (reviewOnOpen && session.status === "submitted") practiceTools.review();
  const timer = setInterval(updateTimer, 1000);
  return {
    get hasUnsavedChanges() {
      return dirty || !!saving;
    },
    persist() {
      if (sourceEditor && selected)
        rememberPosition(selected, sourceEditor.position());
      persistPreferences();
    },
    destroy() {
      scope.destroy();
      clearInterval(timer);
      clearInterval(polling);
      clearTimeout(autosave);
      disposeWorkspace();
      practiceTools?.destroy?.();
      root.onkeydown = null;
    },
  };
}
