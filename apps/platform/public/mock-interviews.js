import { esc, brand } from "./ui.js";
import { createRequestScope } from "./request-scope.js";

export function mockStateKey({ server_time, ...state }) {
  return JSON.stringify(state);
}
export function mockReportText(mock) {
  const lines = [
    mock.title,
    `Interview: ${mock.id}`,
    `Status: ${mock.status} (${mock.completion_reason || "in progress"})`,
    `Started: ${mock.started_at || "not started"}`,
    `Overall deadline: ${mock.deadline_at || "not started"}`,
    "",
    mock.limitations,
  ];
  for (const stage of mock.stages) {
    lines.push(
      "",
      `${stage.position + 1}. ${stage.title} — ${stage.status}`,
      `Budget: ${stage.duration_seconds / 60} minutes`,
      `Started: ${stage.started_at || "not started"}`,
      `Stage deadline: ${stage.deadline_at || "not started"}`,
    );
    if (stage.evidence) {
      lines.push(
        `Session: ${stage.session_id}`,
        `Submitted revision: ${stage.evidence.revision}`,
      );
      for (const run of stage.evidence.reported_tests)
        lines.push(
          `Reported test run ${run.id}: ${run.status}; ${run.summary ? `${run.summary.passed}/${run.summary.tests} passing` : "no complete test summary"}`,
        );
      if (!stage.evidence.reported_tests.length)
        lines.push(
          stage.evidence.track === "system_design"
            ? "Design evidence: submitted architecture and notes; no automated correctness grade."
            : "No test run for this submitted revision.",
        );
      for (const criterion of stage.evidence.criteria || []) {
        const entry = stage.evidence.self_assessment[criterion.id];
        lines.push(
          `Self-assessment — ${criterion.title}: ${entry?.rating || "not_observed"}${entry?.notes ? `; ${entry.notes}` : ""}`,
        );
        if (entry?.evidence)
          lines.push(
            `Source: ${entry.evidence.path}:${entry.evidence.start_line}–${entry.evidence.end_line}`,
          );
      }
    }
    if (stage.transcript)
      for (const item of stage.transcript.transcript || []) {
        lines.push(
          "",
          item.prompt,
          `Source: ${item.source_session_id || stage.source_session_id} @ ${item.source_revision || stage.transcript.source_revision}`,
          `[${item.answer.status}] ${item.answer.text}`,
          `Self-check: ${stage.transcript.review_entries?.[item.id]?.rating || "not_observed"}`,
        );
      }
  }
  for (const step of mock.next_steps || [])
    lines.push(
      "",
      `Next practice — ${step.title}: ${step.practice} (${step.basis})`,
    );
  lines.push("", "Overall reflection", mock.reflection || "Not written.");
  return lines.join("\n");
}
function evidenceMarkup(stage) {
  const e = stage.evidence;
  if (!e) return "";
  const observed = Object.values(e.self_assessment).filter(
    (entry) => entry.rating !== "not_observed",
  ).length;
  const latest = e.reported_tests[0]?.summary;
  return `<details class="mock-evidence"><summary>${e.track === "system_design" ? "Architecture and notes" : latest ? `Runner reported ${latest.passed}/${latest.tests} passing` : "No submitted-revision test result"} · ${observed}/${e.criteria?.length || 0} criteria assessed</summary><p><strong>Submitted revision</strong> <code>${esc(e.revision.slice(0, 12))}</code></p>${e.reported_tests.length ? e.reported_tests.map((run) => `<p>Runner reported: ${esc(run.status)}${run.summary ? ` · ${run.summary.passed}/${run.summary.tests} passing` : " · no complete test summary"}</p>`).join("") : e.track === "system_design" ? "<p>Submitted architecture and notes. No automated correctness grade.</p>" : "<p>No test run for this submitted revision.</p>"}<h4>Self-assessment</h4>${(
    e.criteria || []
  )
    .map((c) => {
      const entry = e.self_assessment[c.id];
      return `<p>${esc(c.title)}: <strong>${esc((entry?.rating || "not_observed").replaceAll("_", " "))}</strong>${entry?.notes ? `<br>${esc(entry.notes)}` : ""}</p>`;
    })
    .join(
      "",
    )}<p>${e.model_reviews.length ? `${e.model_reviews.length} advisory model review(s) available in the submission.` : "No advisory model review for this submission."}</p></details>`;
}
export function renderMockInterview(mock) {
  const completed = mock.status === "completed";
  return `<header class="page-header"><div><div class="eyebrow">Mock interview</div><h1>${esc(mock.title)}</h1><p>${completed ? `${mock.archived_at ? "Archived · " : "Completed · "}${esc(mock.completion_reason.replaceAll("_", " "))}` : `${mock.duration_seconds / 60} minutes total · ${mock.started_at ? "The overall timer is running, including transitions." : "Prepare the first workspace. The overall timer starts with its Start session button."}`}</p></div><strong id="mock-clock" class="timer"></strong></header><ol class="mock-stages">${mock.stages.map((stage) => `<li class="mock-stage ${stage.status === "current" ? "current" : ""}"><div class="section-top"><div><span class="eyebrow">${stage.kind === "followup" ? "Follow-up discussion" : "Workspace"} · ${stage.duration_seconds / 60} min</span><h2>${esc(stage.title)}</h2><p>${esc(stage.status === "pending" ? "Locked" : stage.status === "unattempted" ? "Unattempted" : stage.status === "completed" ? "Finished" : stage.session_status === "active" || stage.followup_status === "active" ? "In progress" : "Ready to continue")}${stage.exercise_version ? ` · version ${stage.exercise_version}` : ""}</p></div>${stage.session_id || stage.followup_id ? `<button data-open-stage="${stage.position}">${stage.status === "current" ? "Open stage" : "View work"}</button>` : ""}</div>${completed ? evidenceMarkup(stage) : ""}${completed && stage.transcript ? `<p>Follow-ups: ${stage.transcript.transcript.filter((q) => q.answer.status === "answered").length}/${stage.transcript.question_count} answered. Partial, skipped, and unasked questions remain recorded in the transcript.</p>` : ""}</li>`).join("")}</ol>${completed ? `<section class="mock-review"><h2>Interview review</h2>${mock.next_steps?.length ? `<h3>Next practice</h3><ul>${mock.next_steps.map((step) => `<li><strong>${esc(step.title)}</strong> · ${esc(step.basis)}<p>${esc(step.practice)}</p></li>`).join("")}</ul>` : "<p>Save your stage self-assessments to build a focused next-practice plan.</p>"}<p>${esc(mock.limitations)}</p><p>Open each stage to inspect source, review criteria, references, or the follow-up transcript. Save stage self-assessments there, then refresh this review.</p><label for="mock-reflection">What would you change in the next interview?</label><textarea id="mock-reflection" maxlength="4000" rows="5">${esc(mock.reflection)}</textarea><div class="mock-actions"><button id="save-mock-reflection">Save reflection</button><button id="export-mock">Export interview review</button><button id="refresh-mock">Refresh evidence</button><button id="organize-mock" class="quiet">${mock.archived_at ? "Restore interview" : "Archive interview"}</button></div><p id="mock-save-state" role="status"></p></section>` : `<div class="mock-actions"><button id="advance-mock" class="primary" ${!(mock.stages[mock.stage_index]?.session_status === "submitted" || mock.stages[mock.stage_index]?.followup_status === "completed") ? "disabled" : ""}>${mock.stage_index === mock.stages.length - 1 ? "Complete interview" : "Continue to next stage"}</button><button id="finish-mock" class="quiet">Finish interview early</button></div><p class="subtitle">Submit the current workspace or finish its follow-up round before continuing. Unopened stages stay locked. Finishing early freezes saved work and records remaining stages as unattempted.</p>`}`;
}
export function mountMockInterviews({
  root,
  api: request,
  notice,
  onBack,
  onOpenSession,
  initialId,
}) {
  const scope = createRequestScope(request),
    api = scope.request;
  let mock = null,
    dirty = false,
    draft = "",
    pending = false,
    requestIds = new Map(),
    list = null,
    archivedView = false,
    offset = 0,
    polling = false,
    navigationEpoch = 0;
  function shell(content) {
    root.innerHTML = `<main class="mock-page"><div class="mock-top">${brand()}<button id="mock-back" class="quiet">← ${mock ? "Mock interviews" : "Practice"}</button></div><p id="mock-error" role="alert"></p><div id="mock-content">${content}</div></main>`;
    root.querySelector("#mock-back").onclick = async () => {
      if (dirty) {
        notice("Save your overall reflection before leaving this interview.");
        return;
      }
      if (mock) {
        mock = null;
        await loadList();
      } else onBack();
    };
  }
  function fail(error) {
    if (!scope.alive) return;
    const node = root.querySelector("#mock-error");
    if (node) node.textContent = error.message;
    notice(error.message);
  }
  function renderList() {
    window.history.replaceState(null, "", "#interviews");
    shell(
      `<header class="page-header"><div><h1>Mock interviews</h1><p>A complete timed loop with practical work, architecture, and questions about your submitted solutions.</p></div></header><section class="mock-plans">${list.plans.map((plan) => `<article class="mock-stage"><h2>${esc(plan.title)}</h2><p>${plan.duration_minutes} minutes · ${plan.stages.length} stages</p><ol>${plan.stages.map((stage) => `<li>${esc(stage.title)} · ${stage.duration_minutes} min</li>`).join("")}</ol><button data-plan="${esc(plan.key)}">Set up interview</button></article>`).join("")}</section><section><div class="section-top"><h2>${archivedView ? "Archived interviews" : "Saved interviews"}</h2><button id="toggle-mock-archives" class="quiet">${archivedView ? "Saved interviews" : "Archived interviews"}</button></div><p class="subtitle">Showing ${list.interviews.length} of ${list.total} interviews. Completed interviews can be archived together with their stages; reviews remain available.</p>${list.interviews.length ? list.interviews.map((item) => `<article class="history-row"><div><strong>${esc(item.title)}</strong><p>${item.archived_at ? "Archived" : item.status === "completed" ? "Completed" : item.status === "active" ? "In progress" : "Not started"} · ${new Date(item.created_at).toLocaleDateString()}</p></div><div class="session-row-actions"><button data-mock="${esc(item.id)}">${item.status === "completed" ? "Review" : "Continue"}</button>${item.status === "completed" ? `<button class="quiet" data-mock-archive="${esc(item.id)}" data-restore="${!!item.archived_at}">${item.archived_at ? "Restore" : "Archive"}</button>` : ""}</div></article>`).join("") : "<p>No interviews yet.</p>"}</section><p class="subtitle">Questions are scripted from the exercise rubrics. Follow-up review and source self-assessments stay separate from reported tests. Previous exposure to an exercise can affect how representative the timed practice feels.</p>`,
    );
    root.querySelector("#toggle-mock-archives").onclick = () => {
      archivedView = !archivedView;
      loadList();
    };
    root
      .querySelectorAll("[data-mock-archive]")
      .forEach(
        (button) =>
          (button.onclick = () =>
            organize(
              button.dataset.mockArchive,
              button.dataset.restore === "true",
            ).catch(fail)),
      );
    root.querySelectorAll("[data-plan]").forEach(
      (button) =>
        (button.onclick = async () => {
          if (pending) return;
          pending = true;
          root
            .querySelectorAll("[data-plan]")
            .forEach((b) => (b.disabled = true));
          try {
            mock = await api("/api/mock_interviews", "POST", {
              plan_key: button.dataset.plan,
              client_request_id:
                requestIds.get(button.dataset.plan) ||
                (() => {
                  const id = crypto.randomUUID();
                  requestIds.set(button.dataset.plan, id);
                  return id;
                })(),
            });
            requestIds.delete(button.dataset.plan);
            apply(mock);
          } catch (error) {
            fail(error);
          } finally {
            pending = false;
            root
              .querySelectorAll("[data-plan]")
              .forEach((b) => (b.disabled = false));
          }
        }),
    );
    root
      .querySelectorAll("[data-mock]")
      .forEach(
        (button) =>
          (button.onclick = () =>
            loadInterview(button.dataset.mock).catch(fail)),
      );
  }
  async function organize(id, restore) {
    if (pending) return;
    if (dirty) {
      notice("Save your reflection before archiving this interview.");
      return;
    }
    pending = true;
    try {
      await api(
        `/api/mock_interviews/${id}/${restore ? "restore" : "archive"}`,
        "POST",
      );
      mock = null;
      archivedView = false;
      await loadList();
      notice(
        restore
          ? "Interview and stages restored."
          : "Interview archived. Restore it from Archived interviews.",
      );
    } finally {
      pending = false;
    }
  }
  async function loadList() {
    const epoch = ++navigationEpoch;
    try {
      const result = await api(
        `/api/mock_interviews${archivedView ? "?archived=true" : ""}`,
      );
      if (!scope.alive || epoch !== navigationEpoch) return;
      list = result;
      if (scope.alive && epoch === navigationEpoch) renderList();
    } catch (error) {
      fail(error);
    }
  }
  function clock() {
    const node = root.querySelector("#mock-clock");
    if (!node || !mock) return;
    const seconds = mock.deadline_at
      ? Math.max(
          0,
          Math.ceil(
            (new Date(mock.deadline_at).getTime() - Date.now() - offset) / 1000,
          ),
        )
      : null;
    node.textContent =
      mock.status === "completed"
        ? "Completed"
        : seconds === null
          ? "Not started"
          : `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")} remaining overall`;
  }
  function apply(value) {
    mock = value;
    archivedView = !!mock.archived_at;
    offset = new Date(mock.server_time).getTime() - Date.now();
    window.history.replaceState(null, "", `#interview/${mock.id}`);
    shell(renderMockInterview(mock));
    clock();
    const organizeButton = root.querySelector("#organize-mock");
    if (organizeButton)
      organizeButton.onclick = () =>
        organize(mock.id, !!mock.archived_at).catch(fail);
    root.querySelectorAll("[data-open-stage]").forEach(
      (button) =>
        (button.onclick = () => {
          if (dirty) {
            notice("Save your overall reflection before opening a stage.");
            return;
          }
          const stage = mock.stages[Number(button.dataset.openStage)];
          onOpenSession(stage.session_id || stage.source_session_id, {
            followupRoundId: stage.followup_id,
            reviewOnOpen:
              mock.status === "completed" && stage.kind === "workspace",
          }).catch(fail);
        }),
    );
    for (const [selector, command] of [
      ["#advance-mock", "advance"],
      ["#finish-mock", "finish"],
    ]) {
      const button = root.querySelector(selector);
      if (button)
        button.onclick = () => {
          if (command === "finish") {
            const confirm = document.createElement("dialog");
            confirm.className = "setup-dialog";
            confirm.innerHTML =
              '<form method="dialog"><h2>Finish this interview?</h2><p>Saved work will be frozen. Unopened stages will be recorded as unattempted.</p><footer><button value="cancel">Keep practicing</button><button value="finish">Finish interview</button></footer></form>';
            document.body.append(confirm);
            confirm.showModal();
            confirm.addEventListener(
              "close",
              () => {
                const finish = confirm.returnValue === "finish";
                confirm.remove();
                if (scope.alive && finish) mutate(command).catch(fail);
              },
              { once: true },
            );
            scope.signal.addEventListener(
              "abort",
              () => {
                confirm.close();
                confirm.remove();
              },
              { once: true },
            );
          } else mutate(command).catch(fail);
        };
    }
    const textarea = root.querySelector("#mock-reflection");
    if (textarea) {
      if (dirty) textarea.value = draft;
      textarea.oninput = () => {
        draft = textarea.value;
        dirty = draft !== mock.reflection;
        root.querySelector("#mock-save-state").textContent = dirty
          ? "Unsaved reflection"
          : "Saved";
      };
      root.querySelector("#save-mock-reflection").onclick = () =>
        mutate("reflect", { reflection: textarea.value }).catch(fail);
      root.querySelector("#refresh-mock").onclick = () =>
        loadInterview(mock.id).catch(fail);
      root.querySelector("#export-mock").onclick = () => {
        const value = dirty
          ? {
              ...mock,
              reflection: `${draft}\n[Local reflection — not yet saved]`,
            }
          : mock;
        const url = URL.createObjectURL(
          new Blob([mockReportText(value)], {
            type: "text/plain;charset=utf-8",
          }),
        );
        const anchor = document.createElement("a");
        anchor.href = url;
        anchor.download = `interview-${mock.id}.txt`;
        anchor.click();
        setTimeout(() => URL.revokeObjectURL(url), 1000);
      };
    }
  }
  async function mutate(command, extra = {}) {
    if (pending) return;
    pending = true;
    const controls = [
      ...root.querySelectorAll("#mock-content button, #mock-content textarea"),
    ].map((node) => [node, node.disabled]);
    controls.forEach(([node]) => (node.disabled = true));
    const id = mock.id;
    try {
      const result = await api(`/api/mock_interviews/${id}`, "PATCH", {
        command,
        expected_version: mock.version,
        ...extra,
      });
      if (command === "reflect") {
        dirty = false;
        draft = "";
      }
      apply(result);
      if (command === "reflect")
        root.querySelector("#mock-save-state").textContent = "Reflection saved";
    } catch (error) {
      // Fetch the latest version while preserving the local reflection on conflicts.
      if (error.status === 409) await loadInterview(id);
      throw error;
    } finally {
      pending = false;
      controls.forEach(([node, disabled]) => {
        if (node.isConnected) node.disabled = disabled;
      });
    }
  }
  async function loadInterview(id) {
    const epoch = ++navigationEpoch;
    const value = await api(`/api/mock_interviews/${id}`);
    if (scope.alive && epoch === navigationEpoch) apply(value);
  }
  shell('<p role="status">Loading interviews…</p>');
  const ready = initialId ? loadInterview(initialId).catch(fail) : loadList();
  const timer = setInterval(clock, 1000);
  const poll = setInterval(async () => {
    if (!mock || mock.status === "completed" || pending || polling) return;
    polling = true;
    const previous = mock;
    try {
      const value = await api(`/api/mock_interviews/${mock.id}`);
      if (
        scope.alive &&
        mock === previous &&
        !pending &&
        mockStateKey(value) !== mockStateKey(previous)
      )
        apply(value);
    } catch (error) {
      fail(error);
    } finally {
      polling = false;
    }
  }, 5000);
  return {
    load: () => ready,
    get hasUnsavedChanges() {
      return dirty;
    },
    destroy() {
      scope.destroy();
      clearInterval(timer);
      clearInterval(poll);
    },
  };
}
