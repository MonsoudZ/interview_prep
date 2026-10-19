import { esc, modeName } from "./ui.js";
import { createRequestScope } from "./request-scope.js";
import { sourceDiff } from "./source-diff.js";
import { previewDiagram } from "./design-model.js";

const rating = (value) => (value || "not_observed").replaceAll("_", " ");
export function renderSourceDiff(
  before,
  after,
  labels = { before: "Original", after: "Rework" },
) {
  const diff = sourceDiff(before, after);
  return `${diff.large ? '<p class="subtitle">Large section shown as a replacement. Display is bounded; full files remain in their workspaces.</p>' : ""}<div class="source-diff" role="region" aria-label="Source changes" tabindex="0"><div class="diff-labels"><span>${esc(labels.before)}</span><span>${esc(labels.after)}</span><span>− removed · + added</span></div>${diff.rows.map((row) => (row.kind === "omitted" ? `<div class="diff-omitted">… ${row.before} ${esc(labels.before.toLowerCase())} / ${row.after} ${esc(labels.after.toLowerCase())} lines omitted</div>` : `<div class="diff-line diff-${row.kind}"><span class="diff-number">${row.oldLine ?? ""}</span><span class="diff-number">${row.newLine ?? ""}</span><code>${row.kind === "added" ? "+" : row.kind === "removed" ? "−" : " "} ${esc(row.text.length > 2000 ? row.text.slice(0, 2000) + "… [line shortened]" : row.text)}</code></div>`)).join("")}</div>`;
}

export function renderSavedFeedback(context) {
  if (!context) return "";
  const review = context.self_review;
  const entries = Object.entries(review?.entries || {}).filter(
    ([, entry]) => entry.rating !== "not_observed",
  );
  return `<p class="subtitle">Feedback captured when this rework began; later edits to the original review do not replace it.</p>${entries.map(([id, entry]) => `<div class="rework-feedback"><strong>${esc(id.replaceAll("_", " "))} · ${esc(rating(entry.rating))}</strong><p>${esc(entry.notes)}</p>${entry.evidence ? `<small>Original source: ${esc(entry.evidence.path)}:${entry.evidence.start_line}–${entry.evidence.end_line}</small>` : ""}</div>`).join("")}${review?.reflection ? `<blockquote>${esc(review.reflection)}</blockquote>` : ""}${!entries.length && !review?.reflection ? "<p>No saved self-assessment was available when this rework began.</p>" : ""}${context.model_review ? `<details><summary>Earlier model feedback · advisory</summary><p>${esc(context.model_review.summary)}</p>${context.model_review.findings.map((finding) => `<p><strong>${esc(finding.title)}</strong><br>${esc(finding.recommendation)}</p>`).join("")}<small>${esc(context.model_review.model)} · original revision only</small></details>` : ""}<p class="subtitle">${context.prior_hints_revealed} hints had been revealed in the source attempt. Earlier work and feedback were available; this is revision practice.</p>`;
}

export async function openComparison(session, { api, signal, notice }) {
  const scope = createRequestScope(api),
    dialog = document.createElement("dialog");
  dialog.className = "comparison-dialog";
  dialog.setAttribute("aria-label", "Compare rework with original");
  dialog.innerHTML =
    '<h2>Saved changes</h2><p role="status">Loading comparison…</p><div id="comparison-content"></div><footer><button id="close-comparison">Close comparison</button></footer>';
  const close = () => dialog.close();
  dialog.querySelector("#close-comparison").onclick = close;
  signal?.addEventListener("abort", close, { once: true });
  dialog.addEventListener(
    "close",
    () => {
      scope.destroy();
      signal?.removeEventListener("abort", close);
      dialog.remove();
    },
    { once: true },
  );
  document.body.append(dialog);
  dialog.showModal();
  try {
    const result = await scope.request(
      `/api/sessions/${session.id}/rework_comparison`,
    );
    if (!scope.alive) return;
    dialog.querySelector('[role="status"]').textContent =
      `${result.changes.length} changed ${result.changes.length === 1 ? "file" : "files"} · ${result.unchanged_files} unchanged. ${result.submitted ? "Preserved submission" : "Saved draft"}.`;
    dialog.querySelector("#comparison-content").innerHTML =
      `<p class="subtitle">Original ${esc(result.source_revision.slice(0, 10))} → rework ${esc(result.revision.slice(0, 10))}</p><p><strong>Your goal:</strong> ${esc(result.goal)}</p>${result.before_design ? `<details><summary>Architecture before and after</summary><div class="diagram-comparison"><section><h3>Original</h3>${previewDiagram(result.before_design)}</section><section><h3>Rework</h3>${previewDiagram(result.after_design)}</section></div></details>` : ""}${result.changes.length ? `<label class="comparison-file-label">Changed file<select id="comparison-file">${result.changes.map((file, index) => `<option value="${index}">${esc(file.path)} · ${file.kind}</option>`).join("")}</select></label><div id="comparison-source"></div>` : '<p class="rework-empty">No saved source changes yet. Describe and test a concrete improvement before judging the result.</p>'}<details class="rework-ratings"><summary>Compare saved self-ratings</summary>${result.review_comparable ? `<table><thead><tr><th>Criterion</th><th>At rework start</th><th>Rework review</th></tr></thead><tbody>${result.criteria.map((item) => `<tr><th>${esc(item.title)}</th><td>${esc(rating(item.before))}</td><td>${esc(rating(item.after))}</td></tr>`).join("")}</tbody></table>` : "<p>A saved original review and a review of this submitted rework with the same rubric are needed for comparison. Missing ratings remain unobserved.</p>"}${result.current_reflection ? `<blockquote>${esc(result.current_reflection)}</blockquote>` : ""}</details><p class="subtitle">${esc(result.note)}</p>`;
    const picker = dialog.querySelector("#comparison-file");
    if (picker) {
      const render = () => {
        const file = result.changes[Number(picker.value)];
        dialog.querySelector("#comparison-source").innerHTML = renderSourceDiff(
          file.before,
          file.after,
        );
      };
      picker.onchange = render;
      render();
    }
  } catch (error) {
    if (scope.alive) {
      dialog.querySelector('[role="status"]').textContent =
        "Comparison could not be loaded.";
      notice(error.message);
    }
  }
}

export function mountRework(
  host,
  session,
  { api, signal, onOpen, notice, hasUnsavedReview, onLeave },
) {
  const scope = createRequestScope(api);
  let requestId = crypto.randomUUID(),
    busy = false;
  const abort = () => scope.destroy();
  signal?.addEventListener("abort", abort, { once: true });
  async function load() {
    const state = await scope.request(`/api/sessions/${session.id}/rework`);
    if (!scope.alive || !host.isConnected) return;
    host.innerHTML = `<h3>${session.revision_of_id ? "Next revision round" : "Rework this submission"}</h3><p>Start from this submitted source and work through a specific improvement. The original stays read-only.</p>${session.revision_of_id ? '<button type="button" id="review-compare">Compare with original</button>' : ""}${state.active ? `<p>${esc(modeName(state.active.mode))} rework already in progress.</p><button type="button" id="resume-rework" class="primary">Continue rework →</button>` : `<details class="rework-launch"><summary>Start a rework →</summary><form id="start-rework"><label>What will you improve?<textarea name="goal" rows="3" maxlength="1500" required placeholder="For example: handle malformed input without changing persisted data."></textarea></label><label>Practice mode<select name="mode"><option value="guided">Guided rework · no deadline</option><option value="assessment">Timed rework · ${session.duration_minutes} minutes</option></select></label><p class="subtitle">The same exercise version and saved source are used. Timed rework is practice with prior exposure.</p><button class="primary" type="submit">Open rework workspace →</button><p role="alert" id="rework-error" class="error"></p></form></details>`}${state.submitted.length ? `<details><summary>Submitted reworks · latest ${state.submitted.length}</summary>${state.submitted.map((item) => `<p><button type="button" class="quiet" data-open-rework="${esc(item.id)}">${esc(modeName(item.mode))} · ${new Date(item.submitted_at).toLocaleDateString()} →</button></p>`).join("")}</details>` : ""}`;
    function allowed() {
      if (hasUnsavedReview()) {
        notice(
          "Save your review before opening a rework so its feedback is included.",
        );
        return false;
      }
      return true;
    }
    async function navigate(id) {
      if (!allowed()) return;
      onLeave();
      await onOpen(id);
    }
    const resume = host.querySelector("#resume-rework");
    if (resume)
      resume.onclick = () =>
        navigate(state.active.id).catch((error) => notice(error.message));
    host
      .querySelectorAll("[data-open-rework]")
      .forEach(
        (button) =>
          (button.onclick = () =>
            navigate(button.dataset.openRework).catch((error) =>
              notice(error.message),
            )),
      );
    const compare = host.querySelector("#review-compare");
    if (compare)
      compare.onclick = () => openComparison(session, { api, signal, notice });
    const form = host.querySelector("#start-rework");
    if (form)
      form.onsubmit = async (event) => {
        event.preventDefault();
        if (busy || !allowed()) return;
        busy = true;
        const button = form.querySelector('[type="submit"]');
        button.disabled = true;
        try {
          const result = await scope.request(
            `/api/sessions/${session.id}/rework`,
            "POST",
            {
              client_request_id: requestId,
              expected_revision: session.submitted_revision,
              mode: form.elements.mode.value,
              goal: form.elements.goal.value,
            },
          );
          if (!scope.alive) return;
          if (result.rework_reused)
            notice(
              "Resuming the existing rework; a second attempt was not created.",
            );
          onLeave();
          await onOpen(result.id);
        } catch (error) {
          if (scope.alive) {
            form.querySelector("#rework-error").textContent = error.message;
            button.disabled = false;
          }
        } finally {
          busy = false;
        }
      };
  }
  host.innerHTML = '<p role="status">Loading revision practice…</p>';
  load().catch((error) => {
    if (scope.alive)
      host.innerHTML = `<p class="error" role="alert">${esc(error.message)}</p>`;
  });
  return {
    destroy() {
      scope.destroy();
      signal?.removeEventListener("abort", abort);
    },
  };
}
