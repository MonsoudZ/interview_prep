import { esc } from "./ui.js";
import { createRequestScope } from "./request-scope.js";

const modeName = (mode) =>
  mode === "assessment" ? "Timed follow-up" : "Guided follow-up";
const statusName = (status) =>
  ({
    answered: "Answered",
    skipped: "Skipped",
    partial: "Partial answer",
    unanswered: "Unanswered",
  })[status] || status;

export function reconcileRound(
  previous,
  incoming,
  draft,
  dirty,
  reviewDirty = false,
) {
  if (reviewDirty && incoming.version !== previous.version)
    return { accept: false, conflict: true };
  if (dirty && incoming.status === "completed") {
    const saved = incoming.transcript?.find(
      (item) => item.id === previous?.question?.id,
    )?.answer?.text;
    return {
      accept: true,
      dirty: false,
      draft: "",
      lateDraft: saved === draft ? null : draft,
      conflict: false,
    };
  }
  if (dirty) {
    if (incoming.version === previous.version)
      return { accept: false, conflict: false };
    if (
      incoming.status === "active" &&
      incoming.question_index === previous.question_index &&
      incoming.current_draft === draft
    )
      return { accept: true, dirty: false, draft, conflict: false };
    return { accept: false, conflict: true };
  }
  return {
    accept: true,
    dirty: false,
    draft: incoming.current_draft || "",
    conflict: false,
  };
}

export function followupTranscript(round, lateDraft = null) {
  const lines = [
    "INTERVIEW STUDIO — SCRIPTED FOLLOW-UP PRACTICE",
    round.title,
    `Source revision: ${round.source_revision}`,
    `Question set: ${round.content_version}`,
    `${modeName(round.mode)}; published questions and prior work were available.`,
    `Started: ${round.started_at || "Not started"}`,
    `Completed: ${round.completed_at || "Not completed"}`,
    `Completion reason: ${round.completion_reason || "In progress"}`,
    "Self-checks are personal observations, not a hiring score.",
    "",
  ];
  for (const [index, item] of (round.transcript || []).entries()) {
    const review = round.review_entries?.[item.id];
    lines.push(
      `${index + 1}. ${item.title} (${item.kind})`,
      item.prompt,
      ...(item.source_session_id
        ? [`Source: ${item.source_session_id} @ ${item.source_revision}`]
        : []),
      `Response status: ${statusName(item.answer.status)}`,
      item.answer.text || "[No saved answer]",
      "Review focus:",
      item.target,
      `Practice: ${item.practice}`,
      `Self-check: ${review?.rating || "not_observed"}`,
      review?.note || "",
      "",
    );
  }
  lines.push("Reflection:", round.reflection || "[Not recorded]");
  if (lateDraft)
    lines.push(
      "",
      "UNSAVED LOCAL TEXT — NOT PART OF THE SAVED ROUND",
      lateDraft,
    );
  return lines.join("\n");
}

export function renderFollowupReview(round) {
  const explained = Object.values(round.review_entries || {}).filter(
    (entry) => entry.rating === "needs_practice",
  );
  return `<p class="followup-result">${round.transcript.filter((item) => item.answer.status === "answered").length}/${round.question_count} answered. ${["deadline", "interview_deadline"].includes(round.completion_reason) ? "Time expired." : ["finished_early", "interview_finished"].includes(round.completion_reason) ? "Finished early; remaining questions are unasked." : "All questions reached."}</p><p class="subtitle">Your typed answers are preserved. Review focuses are prompts for reflection, not model judgments or an answer key. These self-checks stay separate from submission-review progress.</p><form id="followup-review">${round.transcript
    .map((item, index) => {
      const entry = round.review_entries?.[item.id] || {
        rating: "not_observed",
        note: "",
      };
      return `<details class="followup-response" ${index === 0 ? "open" : ""}><summary>${index + 1}. ${esc(item.title)} · ${esc(statusName(item.answer.status))}</summary><p>${esc(item.prompt)}</p>${item.kind === "extension" ? '<p class="subtitle">Extension to the original task.</p>' : ""}<div class="followup-answer">${esc(item.answer.text || "No saved answer.")}</div><h4>Review focus</h4><p>${esc(item.target)}</p><p class="subtitle">Practice: ${esc(item.practice)}</p><label>Your self-check<select name="${esc(item.id)}-rating"><option value="not_observed" ${entry.rating === "not_observed" ? "selected" : ""}>Not reviewed</option><option value="needs_practice" ${entry.rating === "needs_practice" ? "selected" : ""}>Needs practice</option><option value="explained" ${entry.rating === "explained" ? "selected" : ""}>Explained in my answer</option></select></label><label>Reason for this self-check<textarea name="${esc(item.id)}-note" rows="2" maxlength="2000">${esc(entry.note)}</textarea></label></details>`;
    })
    .join(
      "",
    )}<label>Reflection: what will you explain differently next time?<textarea name="reflection" rows="3" maxlength="4000">${esc(round.reflection || "")}</textarea></label><button type="submit">Save self-checks</button></form>${
    explained.length
      ? `<section class="followup-drills"><h3>Practice from your self-checks</h3>${round.transcript
          .filter(
            (item) =>
              round.review_entries?.[item.id]?.rating === "needs_practice",
          )
          .map(
            (item) =>
              `<p><strong>${esc(item.title)}</strong><br>${esc(item.practice)}</p>`,
          )
          .join("")}</section>`
      : ""
  }`;
}

export function openFollowups(
  session,
  { api, signal, notice, initialRoundId = null },
) {
  const scope = createRequestScope(api),
    dialog = document.createElement("dialog");
  dialog.className = "followup-dialog";
  dialog.setAttribute("aria-label", "Follow-up interview practice");
  dialog.tabIndex = -1;
  dialog.innerHTML =
    '<header><h2>Follow-up practice</h2><p class="subtitle">Scripted senior questions · typed responses</p><div id="followup-timer" role="timer" aria-live="off"></div></header><p id="followup-save" role="status"></p><p id="followup-error" role="alert" class="error"></p><button id="reload-followup" hidden>Reload saved round (discard local edits)</button><div id="followup-body"></div><footer><button type="button" id="followup-discard" class="quiet" hidden>Close without saving local edits</button><button type="button" id="followup-close">Save and close</button></footer>';
  const body = dialog.querySelector("#followup-body"),
    errorNode = dialog.querySelector("#followup-error"),
    saveNode = dialog.querySelector("#followup-save");
  let state = null,
    draft = "",
    dirty = false,
    reviewDirty = false,
    lateDraft = null,
    conflict = false,
    busy = false,
    saving = null,
    saveTimer = null,
    pollTimer = null,
    viewEpoch = 0,
    serverOffset = 0;
  const base = `/api/sessions/${session.id}/followups`;
  let requestId = crypto.randomUUID();
  const sessionHash = `#session/${session.id}`;
  function controls() {
    if (!scope.alive) return;
    const locked = busy || !!saving;
    body.querySelectorAll("button,input,select,textarea").forEach((node) => {
      const text = node.tagName === "TEXTAREA";
      node.disabled =
        (node.id === "followup-mode" && !!state?.mock_interview_id) ||
        busy ||
        (!!saving && !text) ||
        (conflict && !text && node.id !== "followup-export");
      if (conflict && text) node.readOnly = true;
    });
    dialog.querySelector("#reload-followup").hidden = !conflict;
    dialog.querySelector("#followup-close").disabled = locked;
    dialog.querySelector("#followup-discard").hidden = !(
      dirty ||
      reviewDirty ||
      lateDraft ||
      conflict
    );
    saveNode.textContent = conflict
      ? "Another tab changed this round. Local text is kept here."
      : saving
        ? "Saving…"
        : dirty || reviewDirty
          ? "Unsaved changes"
          : state?.status === "active"
            ? draft
              ? "Answer saved"
              : "Autosave ready"
            : "";
  }
  function clock() {
    if (!scope.alive) return;
    let text = "";
    if (state?.status === "active") {
      if (state.deadline_at) {
        const remaining = Math.max(
          0,
          Math.ceil(
            (new Date(state.deadline_at).getTime() -
              Date.now() -
              serverOffset) /
              1000,
          ),
        );
        text = `Time left ${Math.floor(remaining / 60)}:${String(remaining % 60).padStart(2, "0")}`;
      } else text = "Untimed follow-up";
    }
    dialog.querySelector("#followup-timer").textContent = text;
  }
  function adopt(remote) {
    state = remote;
    draft = remote.current_draft || "";
    dirty = false;
    conflict = false;
    serverOffset = new Date(remote.server_time).getTime() - Date.now();
    window.history.replaceState(
      null,
      "",
      location.pathname + sessionHash + `/followup/${remote.id}`,
    );
  }
  function schedule() {
    clearTimeout(pollTimer);
    if (scope.alive && state?.status === "active")
      pollTimer = setTimeout(poll, 5000);
  }
  async function poll() {
    if (!scope.alive || !state || busy || saving) {
      schedule();
      return;
    }
    const epoch = viewEpoch,
      previous = state;
    try {
      const remote = await scope.request(`/api/followups/${previous.id}`);
      if (epoch !== viewEpoch || state !== previous) return;
      serverOffset = new Date(remote.server_time).getTime() - Date.now();
      const merged = reconcileRound(
        previous,
        remote,
        draft,
        dirty,
        reviewDirty,
      );
      if (merged.accept) {
        const changed =
          remote.version !== previous.version ||
          remote.status !== previous.status;
        adopt(remote);
        draft = merged.draft;
        lateDraft = merged.lateDraft || lateDraft;
        if (changed) render();
      } else if (merged.conflict) {
        conflict = true;
        controls();
      }
    } catch (error) {
      if (scope.alive) errorNode.textContent = error.message;
    } finally {
      schedule();
      clock();
    }
  }
  async function failure(error) {
    if (!scope.alive) return;
    errorNode.textContent = error.message;
    if (error.status === 409) {
      conflict = true;
      await poll();
    }
    controls();
  }
  async function save() {
    clearTimeout(saveTimer);
    if (saving) {
      await saving;
      if (dirty) return save();
      return;
    }
    if (!dirty || state?.status !== "active") return;
    if (conflict)
      throw new Error(
        "Copy your local answer before reloading the saved round.",
      );
    const text = draft,
      round = state;
    saving = scope
      .request(`/api/followups/${round.id}`, "PATCH", {
        command: "save",
        expected_version: round.version,
        question_index: round.question_index,
        answer: text,
      })
      .then((remote) => {
        const changedAgain = draft !== text;
        if (remote.status === "completed") {
          if (changedAgain) lateDraft = draft;
          adopt(remote);
          render();
        } else {
          state = remote;
          dirty = changedAgain;
          serverOffset = new Date(remote.server_time).getTime() - Date.now();
        }
      })
      .finally(() => {
        saving = null;
        controls();
      });
    controls();
    await saving;
    if (dirty && state?.status === "active") return save();
  }
  async function command(kind, extra = {}) {
    if (busy || saving || conflict) return;
    busy = true;
    controls();
    errorNode.textContent = "";
    try {
      await save();
      if (state.status === "completed" && kind !== "review") return;
      const remote = await scope.request(
        `/api/followups/${state.id}`,
        "PATCH",
        {
          command: kind,
          expected_version: state.version,
          question_index: state.question_index,
          answer: draft,
          ...extra,
        },
      );
      adopt(remote);
      reviewDirty = false;
      render();
    } catch (error) {
      busy = false;
      await failure(error);
    } finally {
      busy = false;
      controls();
      schedule();
    }
  }
  async function saveReview() {
    const form = body.querySelector("#followup-review");
    if (!form || !reviewDirty) return;
    const entries = Object.fromEntries(
      state.transcript.map((item) => [
        item.id,
        {
          rating: form.elements[`${item.id}-rating`].value,
          note: form.elements[`${item.id}-note`].value,
        },
      ]),
    );
    await command("review", {
      review_entries: entries,
      reflection: form.elements.reflection.value,
    });
    if (reviewDirty)
      throw new Error(
        errorNode.textContent || "Your self-checks have not been saved.",
      );
  }
  async function leave(action) {
    if (busy || saving) return;
    try {
      await save();
      await saveReview();
      if (conflict)
        throw new Error(
          "Copy local edits or explicitly discard them before leaving.",
        );
      if (lateDraft)
        throw new Error(
          "Unsaved local text is outside the completed round. Copy or export it, then choose Close without saving local edits.",
        );
      action();
    } catch (error) {
      await failure(error);
    }
  }
  async function loadList() {
    requestId = crypto.randomUUID();
    window.history.replaceState(null, "", location.pathname + sessionHash);
    const epoch = ++viewEpoch;
    clearTimeout(pollTimer);
    state = null;
    draft = "";
    dirty = false;
    reviewDirty = false;
    lateDraft = null;
    conflict = false;
    errorNode.textContent = "";
    body.innerHTML = '<p role="status">Loading follow-up rounds…</p>';
    controls();
    clock();
    try {
      const listing = await scope.request(base);
      if (epoch !== viewEpoch) return;
      body.innerHTML = `<p>Practice explaining this submission under follow-up questioning. Prompts come from its published senior rubric, followed by ${session.track === "behavioral" ? "a reflection and transfer question" : "one changed-requirement scenario"}.</p><p class="subtitle">${listing.question_count} questions · ${listing.duration_seconds / 60} minutes in timed mode. Published prompts and prior work are available; this is rehearsal. No model or voice recording is connected.</p>${listing.active ? `<button class="primary" id="resume-followup">${listing.active.status === "ready" ? "Continue setup" : "Resume follow-up round"}</button>` : '<button class="primary" id="prepare-followup">Prepare follow-up round</button>'}${listing.completed.length ? `<h3>Completed rounds</h3>${listing.completed.map((round) => `<p><button class="quiet" data-followup="${esc(round.id)}">${modeName(round.mode)} · ${new Date(round.completed_at).toLocaleString()} →</button></p>`).join("")}` : ""}`;
      const resume = body.querySelector("#resume-followup");
      if (resume) resume.onclick = () => loadRound(listing.active.id);
      body
        .querySelectorAll("[data-followup]")
        .forEach(
          (button) =>
            (button.onclick = () => loadRound(button.dataset.followup)),
        );
      const prepare = body.querySelector("#prepare-followup");
      if (prepare)
        prepare.onclick = async () => {
          prepare.disabled = true;
          try {
            const remote = await scope.request(base, "POST", {
              client_request_id: requestId,
              mode: "guided",
            });
            if (epoch !== viewEpoch) return;
            adopt(remote);
            render();
            schedule();
          } catch (error) {
            if (scope.alive) {
              prepare.disabled = false;
              await failure(error);
            }
          }
        };
    } catch (error) {
      await failure(error);
    }
  }
  async function loadRound(id) {
    const epoch = ++viewEpoch;
    body.innerHTML = '<p role="status">Loading saved round…</p>';
    errorNode.textContent = "";
    try {
      const remote = await scope.request(`/api/followups/${id}`);
      if (epoch !== viewEpoch) return;
      if (remote.session_id !== session.id)
        throw new Error(
          "This follow-up belongs to another submission. Open it from Progress.",
        );
      adopt(remote);
      reviewDirty = false;
      lateDraft = null;
      render();
      schedule();
    } catch (error) {
      await failure(error);
    }
  }
  function render() {
    if (!scope.alive || !state) return;
    body.innerHTML = `<button type="button" class="quiet" id="all-followups">← All rounds</button><p class="followup-provenance">${esc(state.title)} · ${modeName(state.mode)} · ${state.mock_interview_id ? `${state.source_submissions.length} submitted workspaces · captured revisions` : `source ${esc(state.source_revision.slice(0, 10))}`}</p>${state.source_is_rework ? '<p class="subtitle">This round follows a rework, with prior source and feedback available.</p>' : ""}`;
    if (state.status === "ready") {
      body.innerHTML += `<h3>Ready for follow-ups</h3><p>${state.question_count} questions. The timed budget is ${state.duration_seconds / 60} minutes for the whole round; closing the window will not pause it.</p><label>Practice mode<select id="followup-mode" ${state.mock_interview_id ? "disabled" : ""}><option value="guided" ${state.mode === "guided" ? "selected" : ""}>Guided · no deadline</option><option value="assessment" ${state.mode === "assessment" ? "selected" : ""}>Timed follow-up</option></select></label><button id="start-followup" class="primary">Start follow-up round</button>`;
      body.querySelector("#start-followup").onclick = () =>
        command("start", { mode: body.querySelector("#followup-mode").value });
    } else if (state.status === "active") {
      body.innerHTML += `<p class="followup-position">Question ${state.question_index + 1} of ${state.question_count}${state.question.kind === "extension" ? " · extension" : ""}</p><h3>${esc(state.question.title)}</h3><p class="followup-prompt">${esc(state.question.prompt)}</p><form id="followup-answer-form"><label>Your answer<textarea id="followup-answer" maxlength="8000" rows="10" placeholder="Explain your decisions, a concrete example, and the limits of what you verified.">${esc(draft)}</textarea></label><p class="subtitle">Autosave is on. Next locks this answer. Review guidance appears after the round ends.</p><div class="followup-actions"><button type="submit" class="primary">${state.question_index + 1 === state.question_count ? "Save final answer" : "Next question"}</button><button type="button" id="skip-followup">Skip question</button><button type="button" id="finish-followup" class="quiet">Finish round now</button></div><p class="subtitle">Finishing early locks the round, keeps this answer as partial, and leaves remaining questions unasked.</p></form>`;
      body.querySelector("#followup-answer").oninput = (event) => {
        draft = event.target.value;
        dirty = draft !== state.current_draft;
        clearTimeout(saveTimer);
        saveTimer = setTimeout(() => {
          if (!busy) save().catch(failure);
        }, 800);
        controls();
      };
      body.querySelector("#followup-answer-form").onsubmit = (event) => {
        event.preventDefault();
        command("next");
      };
      body.querySelector("#skip-followup").onclick = () => command("skip");
      body.querySelector("#finish-followup").onclick = () => command("finish");
    } else {
      body.innerHTML += `${lateDraft ? `<section class="followup-local"><h3>Unsaved local answer</h3><p>This text was not accepted before the round ended. Copy or export it before closing.</p><textarea readonly rows="4" aria-label="Unsaved local answer">${esc(lateDraft)}</textarea></section>` : ""}<button type="button" id="followup-export">Download transcript</button>${renderFollowupReview(state)}`;
      const form = body.querySelector("#followup-review");
      form.oninput = () => {
        reviewDirty = true;
        controls();
      };
      form.onsubmit = (event) => {
        event.preventDefault();
        saveReview().catch(failure);
      };
      body.querySelector("#followup-export").onclick = () => {
        const url = URL.createObjectURL(
          new Blob([followupTranscript(state, lateDraft)], {
            type: "text/plain;charset=utf-8",
          }),
        );
        const link = document.createElement("a");
        link.href = url;
        link.download = `follow-up-${state.id}.txt`;
        document.body.append(link);
        link.click();
        link.remove();
        setTimeout(() => URL.revokeObjectURL(url), 1000);
      };
    }
    body.querySelector("#all-followups").onclick = () => leave(loadList);
    controls();
    clock();
  }
  const close = () => leave(() => dialog.close());
  dialog.querySelector("#followup-close").onclick = close;
  dialog.querySelector("#followup-discard").onclick = () => dialog.close();
  dialog.querySelector("#reload-followup").onclick = () => {
    dirty = false;
    reviewDirty = false;
    lateDraft = null;
    conflict = false;
    loadRound(state.id);
  };
  const guard = (event) => {
    if (dirty || saving || reviewDirty || lateDraft) {
      event.preventDefault();
      event.returnValue = "";
    }
  };
  const abort = () => dialog.close();
  signal?.addEventListener("abort", abort, { once: true });
  window.addEventListener("beforeunload", guard);
  dialog.addEventListener("cancel", (event) => {
    event.preventDefault();
    close();
  });
  const ticker = setInterval(clock, 1000);
  dialog.addEventListener(
    "close",
    () => {
      scope.destroy();
      if (location.hash.startsWith(sessionHash + "/followup/"))
        window.history.replaceState(null, "", location.pathname + sessionHash);
      clearInterval(ticker);
      clearTimeout(saveTimer);
      clearTimeout(pollTimer);
      signal?.removeEventListener("abort", abort);
      window.removeEventListener("beforeunload", guard);
      dialog.remove();
    },
    { once: true },
  );
  document.body.append(dialog);
  dialog.showModal();
  dialog.focus();
  if (initialRoundId) loadRound(initialRoundId);
  else loadList();
}
