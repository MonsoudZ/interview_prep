import { mountAutomatedReview } from "./automated-review.js";
import { previewDiagram } from "./design-model.js";
import { mountRework } from "./rework.js";
import { openFollowups } from "./followups.js";
import { esc } from "./ui.js";
const label = (value) => value.replaceAll("_", " ");

export function mountPractice(session, { api, notice, signal, onOpen }) {
  const host = document.querySelector("#practice-tools");
  host.innerHTML =
    '<h4>Hints and review</h4><p class="subtitle" id="support-status">Loading practice support…</p><div id="hints"></div><button id="next-hint">Reveal next hint</button><button id="open-review">Review submission →</button>';
  let current = session,
    support = null;
  const hintButton = host.querySelector("#next-hint"),
    reviewButton = host.querySelector("#open-review");
  const followupButton = document.createElement("button");
  followupButton.textContent = "Practice follow-up questions";
  followupButton.id = "open-followups";
  followupButton.onclick = () =>
    openFollowups(current, { api, notice, signal });
  host.append(followupButton);
  followupButton.hidden = current.status !== "submitted";
  reviewButton.disabled = current.status !== "submitted";
  function render() {
    if (!host.isConnected) return;
    reviewButton.disabled = current.status !== "submitted";
    followupButton.hidden = current.status !== "submitted";
    hintButton.disabled =
      !support?.can_reveal || current.status === "submitted";
    hintButton.hidden = current.mode !== "guided" || !support?.available;
    host.querySelector("#support-status").textContent =
      current.mode === "assessment"
        ? "Hints are disabled in assessments. Review opens after submission."
        : support?.available
          ? `${support.hints.length} of ${support.total_hints} hints revealed. Hints are recorded with this attempt. Submission review opens after you submit.`
          : "Practice support is unavailable for this version.";
    host.querySelector("#hints").innerHTML = (support?.hints || [])
      .map(
        (hint) =>
          `<details class="hint"><summary>${esc(hint.title)}</summary><pre>${esc(hint.body)}</pre></details>`,
      )
      .join("");
  }
  async function load() {
    support = await api(`/api/sessions/${session.id}/practice`);
    render();
  }
  hintButton.onclick = async () => {
    hintButton.disabled = true;
    try {
      support = await api(`/api/sessions/${session.id}/hint`, "POST", {
        expected_position: support.hints.length,
      });
      render();
      host.querySelector(".hint:last-child")?.setAttribute("open", "");
    } catch (error) {
      notice(error.message);
      await load().catch(() => {});
    }
  };
  reviewButton.onclick = async () => {
    reviewButton.disabled = true;
    try {
      await openReview(
        current,
        await api(`/api/sessions/${session.id}/review`),
        { api, notice, signal, onOpen },
      );
    } catch (error) {
      notice(error.message);
    } finally {
      if (host.isConnected)
        reviewButton.disabled = current.status !== "submitted";
    }
  };
  load().catch((error) => {
    if (host.isConnected)
      host.querySelector("#support-status").textContent = error.message;
  });
  return {
    review() {
      reviewButton.click();
    },
    update(value) {
      current = value;
      reviewButton.disabled = current.status !== "submitted";
      followupButton.hidden = current.status !== "submitted";
      hintButton.disabled =
        !support?.can_reveal || current.status === "submitted";
    },
  };
}

async function openReview(session, review, { api, notice, signal, onOpen }) {
  const dialog = document.createElement("dialog");
  dialog.className = "review-dialog";
  dialog.setAttribute("aria-label", "Submission review");
  dialog.tabIndex = -1;
  let version = review.version,
    dirty = false;
  const evidenceOptions =
    '<option value="">No source reference</option>' +
    review.evidence_files
      .map((path) => `<option value="${esc(path)}">${esc(path)}</option>`)
      .join("");
  dialog.innerHTML = `<form id="review-form"><div class="eyebrow">SUBMISSION REVIEW · ${esc(review.content_version)}</div><h2>Review submission</h2><p class="subtitle">Self-assessment against senior-level criteria. These ratings are yours; they are not an AI review or a hiring verdict. Anchor each observed rating to your submitted work.</p><p class="review-revision">Submitted revision <code>${esc(review.revision)}</code></p><details class="review-evidence"><summary>${session.track === "system_design" ? "Practice context & assistance" : "Execution evidence & assistance"}</summary><p>${review.assistance.length} hints revealed during this attempt.</p>${review.assistance.map((hint) => `<p>${esc(hint.title)}</p>`).join("")}${review.executions.length ? review.executions.map((execution) => `<p>Tests · ${esc(execution.status)}</p><pre>${esc(execution.result?.output || "No completed output. This is not a test result.")}</pre>`).join("") : session.track === "system_design" ? "<p>Design reasoning is reviewed from the submitted diagram and notes. Test counts do not evaluate this work.</p>" : "<p>No test execution evidence exists for the submitted revision. Do not infer that the solution passes.</p>"}</details>${review.design ? `<details class="review-evidence submitted-diagram"><summary>Submitted architecture · preserved revision</summary><p>The diagram supports your explanation; component presence alone does not demonstrate a guarantee.</p>${previewDiagram(review.design)}</details>` : ""}<div class="review-criteria">${review.criteria
    .map((criterion) => {
      const entry = review.entries[criterion.id] || {
        rating: "not_observed",
        notes: "",
      };
      return `<fieldset data-criterion="${esc(criterion.id)}"><legend>${esc(criterion.title)}</legend><p>${esc(criterion.target)}</p><p class="review-probe">Consider: ${esc(criterion.probe)}</p><label>Your assessment<select name="${esc(criterion.id)}-rating">${review.ratings.map((rating) => `<option value="${esc(rating)}" ${entry.rating === rating ? "selected" : ""}>${esc(label(rating))}</option>`).join("")}</select></label><label>Evidence and reasoning<textarea name="${esc(criterion.id)}-notes" maxlength="2000" rows="3" placeholder="Explain what the submitted work demonstrates, or what remains unverified.">${esc(entry.notes)}</textarea></label><div class="evidence-fields"><label>Submitted file<select name="${esc(criterion.id)}-path">${evidenceOptions}</select></label><label>From line<input name="${esc(criterion.id)}-start" type="number" min="1" value="${entry.evidence?.start_line || 1}"></label><label>To line<input name="${esc(criterion.id)}-end" type="number" min="1" value="${entry.evidence?.end_line || 1}"></label><button type="button" data-preview="${esc(criterion.id)}">Show lines</button></div><pre class="source-reference" id="preview-${esc(criterion.id)}"></pre></fieldset>`;
    })
    .join(
      "",
    )}</div><label class="reflection-label">Reflection: what slowed you down, and what will you try differently?<textarea name="reflection" maxlength="4000" rows="4">${esc(review.reflection)}</textarea></label><section class="review-next"><h3>Your next practice</h3><div id="next-steps"></div><details><summary>Senior follow-up · extension</summary><p>${esc(review.follow_up)}</p></details></section>${review.reference_available ? '<details class="review-evidence" id="reference-solution"><summary>Compare a reference implementation</summary><p>Review your own work first. This is one tested approach, not the only acceptable design.</p><button type="button" id="load-reference">Show reference files</button><div id="reference-files"></div></details>' : ""}<p id="review-error" class="error" role="alert"></p><footer><span id="review-save-status" role="status">${review.updated_at ? "Previously saved" : "Not saved yet"}</span><button type="button" id="discard-review">Close without saving</button><button class="primary" type="submit">Save review</button></footer></form>`;
  const automatedHost = document.createElement("section");
  automatedHost.className = "automated-review";
  const reviewHeader = document.createElement("header");
  for (const selector of [".eyebrow", "h2", ".review-revision"])
    reviewHeader.append(dialog.querySelector(selector));
  dialog.prepend(automatedHost);
  dialog.prepend(reviewHeader);
  const followupButton = document.createElement("button");
  followupButton.type = "button";
  followupButton.textContent = "Practice follow-up questions";
  followupButton.onclick = () =>
    openFollowups(session, { api, notice, signal });
  reviewHeader.append(followupButton);
  const reworkHost = document.createElement("section");
  reworkHost.className = "rework-panel";
  reviewHeader.after(reworkHost);
  document.body.append(dialog);
  const rework = mountRework(reworkHost, session, {
    api,
    signal,
    onOpen,
    notice,
    hasUnsavedReview: () => dirty,
    onLeave: () => dialog.close(),
  });
  const automated = mountAutomatedReview(
    automatedHost,
    session,
    review.criteria,
    { api, signal },
  );
  const cancel = () => dialog.close();
  signal?.addEventListener("abort", cancel, { once: true });
  const form = dialog.querySelector("form");
  const referenceButton = dialog.querySelector("#load-reference");
  if (referenceButton)
    referenceButton.onclick = async () => {
      referenceButton.disabled = true;
      try {
        const reference = await api(`/api/sessions/${session.id}/reference`);
        if (!dialog.isConnected || signal?.aborted) return;
        dialog.querySelector("#reference-files").innerHTML = Object.entries(
          reference.files,
        )
          .map(
            ([path, source]) =>
              `<details><summary>${esc(path)}</summary><pre>${esc(source)}</pre></details>`,
          )
          .join("");
        referenceButton.hidden = true;
      } catch (error) {
        if (dialog.isConnected && !signal?.aborted) {
          notice(error.message);
          referenceButton.disabled = false;
        }
      }
    };
  for (const criterion of review.criteria) {
    form.elements[`${criterion.id}-path`].value =
      review.entries[criterion.id]?.evidence?.path || "";
  }
  function preview(id) {
    const path = form.elements[`${id}-path`].value;
    const first = Number(form.elements[`${id}-start`].value),
      last = Number(form.elements[`${id}-end`].value);
    const source = session.files[path];
    const lines = source?.split("\n");
    if (lines?.at(-1) === "") lines.pop();
    const output = dialog.querySelector(`#preview-${id}`);
    if (
      !lines ||
      !Number.isInteger(first) ||
      !Number.isInteger(last) ||
      first < 1 ||
      last < first ||
      last > lines.length ||
      last - first >= 20
    ) {
      output.textContent =
        "Choose an existing submitted file and a range of 1–20 lines.";
      return;
    }
    output.textContent =
      `${path} · submitted ${review.revision.slice(0, 10)}\n` +
      lines
        .slice(first - 1, last)
        .map((line, index) => `${first + index}  ${line}`)
        .join("\n");
  }
  function nextSteps(value) {
    dialog.querySelector("#next-steps").innerHTML = value.next_steps.length
      ? value.next_steps
          .map(
            (step) =>
              `<p><strong>${esc(step.title)}</strong><br>${esc(step.practice)}</p>`,
          )
          .join("")
      : "<p>Save ratings to build a practice plan from the areas you identify as needing work. Unobserved criteria remain open; they do not count as demonstrated skills.</p>";
  }
  nextSteps(review);
  dialog
    .querySelectorAll("[data-preview]")
    .forEach(
      (button) => (button.onclick = () => preview(button.dataset.preview)),
    );
  for (const criterion of review.criteria)
    if (review.entries[criterion.id]?.evidence) preview(criterion.id);
  const guardUnload = (event) => {
    if (dirty) {
      event.preventDefault();
      event.returnValue = "";
    }
  };
  window.addEventListener("beforeunload", guardUnload);
  form.oninput = () => {
    dirty = true;
    dialog.querySelector("#review-save-status").textContent =
      "Unsaved review changes";
  };
  dialog.querySelector("#discard-review").onclick = () => dialog.close();
  dialog.addEventListener("cancel", (event) => {
    if (dirty) {
      event.preventDefault();
      notice("Save the review or choose Close without saving.");
    }
  });
  form.onsubmit = async (event) => {
    event.preventDefault();
    const button = form.querySelector("[type=submit]");
    button.disabled = true;
    const errorNode = dialog.querySelector("#review-error");
    errorNode.textContent = "";
    const entries = Object.fromEntries(
      review.criteria.map((criterion) => {
        const id = criterion.id,
          path = form.elements[`${id}-path`].value;
        return [
          id,
          {
            rating: form.elements[`${id}-rating`].value,
            notes: form.elements[`${id}-notes`].value,
            evidence: path
              ? {
                  path,
                  start_line: Number(form.elements[`${id}-start`].value),
                  end_line: Number(form.elements[`${id}-end`].value),
                }
              : null,
          },
        ];
      }),
    );
    // Keep the draft intact while saving; editing resumes once the response is known.
    const controls = [...form.elements];
    controls.forEach((control) => (control.disabled = true));
    try {
      const saved = await api(`/api/sessions/${session.id}/review`, "PUT", {
        expected_version: version,
        entries,
        reflection: form.elements.reflection.value,
      });
      version = saved.version;
      dirty = false;
      nextSteps(saved);
      dialog.querySelector("#review-save-status").textContent = "Review saved";
    } catch (error) {
      errorNode.textContent = error.message;
    } finally {
      controls.forEach((control) => (control.disabled = false));
      button.disabled = false;
    }
  };
  dialog.addEventListener(
    "close",
    () => {
      automated.destroy();
      rework.destroy();
      window.removeEventListener("beforeunload", guardUnload);
      signal?.removeEventListener("abort", cancel);
      dialog.remove();
    },
    { once: true },
  );
  dialog.showModal();
  dialog.focus({ preventScroll: true });
  dialog.scrollTop = 0;
}
