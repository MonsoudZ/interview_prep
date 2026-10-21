import { esc } from "./ui.js";
import { createRequestScope } from "./request-scope.js";
const words = (value) => String(value || "").replaceAll("_", " ");
const categories = {
  source_concern: "Source concern",
  design_concern: "Design concern",
  execution_observation: "Runner observation",
  refinement: "Optional refinement",
};
const errors = {
  model_unavailable: "The Studio model is unavailable.",
  context_too_large:
    "This submission exceeds the configured model context. Increase the Studio context setting or review it manually.",
  output_invalid:
    "The model response failed the review contract. No report was accepted.",
  inference_timeout: "The model did not finish within the review time limit.",
  worker_interrupted: "The review worker was interrupted.",
  worker_unavailable: "The Studio worker did not pick up this request.",
  model_changed:
    "The installed model changed during this review. Retry with a stable model version.",
};
const FOLLOW_UP_PREFIX = "follow-up/";
// Citations into follow-up/<criterion>.md quote the typed follow-up answer, not a submitted file.
export function citationLabel(path) {
  const value = String(path || "");
  return value.startsWith(FOLLOW_UP_PREFIX)
    ? `Follow-up answer · ${value.slice(FOLLOW_UP_PREFIX.length).replace(/\.md$/, "")}`
    : value;
}
export function renderCitations(items = []) {
  return items
    .map(
      (item) =>
        `<details class="ai-citation"><summary>${esc(citationLabel(item.path))}:${item.start_line}–${item.end_line}</summary><pre>${esc(item.excerpt)}</pre></details>`,
    )
    .join("");
}
export function renderReasoningMode(usage) {
  if (!usage || usage.reasoning === undefined || usage.reasoning === null)
    return "";
  return `<br>Reasoning mode: ${Number(usage.reasoning) === 1 ? "on" : "off (the reasoning budget ran out, so this review was produced without reasoning)"}`;
}
export function renderReviewGuidance(guidance) {
  if (!guidance?.sources?.length) return "";
  const sources = guidance.sources
    .map((source) => {
      let url = "";
      try {
        const parsed = new URL(source.url);
        if (
          parsed.protocol === "https:" &&
          !parsed.username &&
          !parsed.password
        )
          url = parsed.href;
      } catch {}
      const title = `${esc(source.company)}: ${esc(source.title)}`;
      return `<li>${url ? `<a href="${esc(url)}" target="_blank" rel="noopener noreferrer">${title}</a>` : title}<br>${esc(source.kind)} · checked ${esc(source.checked_on)}</li>`;
    })
    .join("");
  return `<details class="ai-criterion"><summary>Public preparation sources</summary><p>These sources inform coaching. Your exercise rubric determines ratings; these are not company hiring scores.</p><ul>${sources}</ul><p>Guidance: ${esc(guidance.version)}<br>Digest: <code>${esc(guidance.digest)}</code></p></details>`;
}
export function renderAutomatedReport(report, criteria) {
  const lookup = new Map(
    criteria.map((criterion) => [criterion.id, criterion]),
  );
  const findings = report.findings
    .map(
      (finding) =>
        `<article class="ai-finding"><p class="ai-finding-meta">${esc(finding.severity)} · ${esc(categories[finding.category] || finding.category)} · ${esc(finding.confidence)} confidence</p><h4>${esc(finding.title)}</h4><p>${esc(finding.observation)}</p><p><strong>Why it matters</strong> ${esc(finding.consequence)}</p><p><strong>Next change</strong> ${esc(finding.recommendation)}</p>${renderCitations(finding.evidence)}${finding.execution_ids.length ? `<p class="ai-finding-meta">Cited run IDs: ${finding.execution_ids.map(esc).join(", ")}</p>` : ""}</article>`,
    )
    .join("");
  return `<p class="ai-summary">${esc(report.summary)}</p><h3>Priority findings</h3>${findings || "<p>No findings were returned. That alone does not establish correctness.</p>"}
    ${report.strengths.length ? `<h3>Supported strengths</h3>${report.strengths.map((item) => `<p>${esc(item.statement)}</p>${renderCitations(item.evidence)}`).join("")}` : ""}
    <h3>Rubric observations</h3>${report.criteria.map((item) => `<details class="ai-criterion"><summary>${esc(lookup.get(item.id)?.title || item.id)} · ${esc(words(item.rating))}</summary><p>${esc(item.reasoning)}</p>${renderCitations(item.evidence)}</details>`).join("")}
    ${report.understanding_checks.length ? `<h3>Check your understanding</h3><ul>${report.understanding_checks.map((text) => `<li>${esc(text)}</li>`).join("")}</ul>` : ""}
    ${
      report.criteria.some((item) =>
        ["needs_development", "approaching_target"].includes(item.rating),
      )
        ? `<h3>Suggested drills</h3>${report.criteria
            .filter((item) =>
              ["needs_development", "approaching_target"].includes(item.rating),
            )
            .map(
              (item) =>
                `<p><strong>${esc(lookup.get(item.id)?.title || item.id)}</strong><br>${esc(lookup.get(item.id)?.practice || "")}</p>`,
            )
            .join("")}`
        : ""
    }
    <details class="ai-criterion"><summary>Review limitations</summary><ul>${report.limitations.map((text) => `<li>${esc(text)}</li>`).join("")}</ul><p>Source locations are checked against your submission. The model's reasoning may still be incorrect.</p></details>`;
}
export function mountAutomatedReview(host, session, criteria, { api, signal }) {
  if (session.track === "behavioral") {
    host.innerHTML =
      "<p>Review your submitted response below. No model judgment, audio assessment, or verification of personal experience is performed.</p>";
    return { destroy() {} };
  }
  const scope = createRequestScope(api);
  let state = null,
    timer = null,
    loading = false,
    generating = false,
    error = "";
  const abort = () => {
    scope.destroy();
    clearTimeout(timer);
  };
  signal?.addEventListener("abort", abort, { once: true });
  function render() {
    if (!scope.alive || !host.isConnected) return;
    const review = state?.review,
      pending = review && ["queued", "running"].includes(review.status);
    host.innerHTML = `<header><div><h2>Local model feedback</h2><p>Advisory feedback against the senior rubric. Your self-assessment stays separate.</p></div></header><div class="ai-status" role="status">${!state ? "Checking Studio connection…" : review?.status === "completed" ? "Review completed" : pending ? (review.status === "running" ? "Reviewing your submitted work…" : "Review queued for the Studio") : review?.status === "failed" ? errors[review.error_code] || "Review could not be completed." : state.available ? "Studio reviewer connected" : "Studio reviewer offline"}</div>
      ${!state?.available && !pending && review?.status !== "completed" ? "<p>Connect the review worker on your Mac Studio to generate feedback. Your saved work and self-review remain available.</p>" : ""}
      ${review?.status !== "completed" ? `<button type="button" id="generate-feedback" ${!state?.available || pending || generating ? "disabled" : ""}>${review?.status === "failed" ? "Retry review" : "Generate review"}</button>` : ""}
      <p class="error" role="alert">${esc(error)}</p>
      ${review?.status === "completed" ? `<p class="ai-provenance">${esc(review.model)} · submitted revision ${esc(review.revision.slice(0, 10))}. Review judgments are not a calibrated hiring score.</p>${renderAutomatedReport(review.report, criteria)}${renderReviewGuidance(review.guidance)}<details class="ai-criterion"><summary>Review provenance</summary><p>Model digest: <code>${esc(review.model_digest)}</code><br>Rubric: ${esc(review.content_version)}<br>Reviewer instructions: ${esc(review.prompt_version)}${renderReasoningMode(review.usage)}</p></details>` : ""}`;
    const button = host.querySelector("#generate-feedback");
    if (button)
      button.onclick = async () => {
        if (generating) return;
        generating = true;
        error = "";
        render();
        try {
          state = await scope.request(
            `/api/sessions/${session.id}/automated_review`,
            "POST",
            { client_request_id: crypto.randomUUID() },
          );
        } catch (problem) {
          if (scope.alive) error = problem.message;
        } finally {
          generating = false;
          render();
          schedule();
        }
      };
  }
  function schedule() {
    clearTimeout(timer);
    if (scope.alive && state?.review?.status !== "completed")
      timer = setTimeout(
        load,
        state?.review && ["queued", "running"].includes(state.review.status)
          ? 3000
          : 10000,
      );
  }
  async function load() {
    if (!scope.alive || loading || generating) return;
    loading = true;
    try {
      state = await scope.request(
        `/api/sessions/${session.id}/automated_review`,
      );
      error = "";
    } catch (problem) {
      if (scope.alive) error = problem.message;
    } finally {
      loading = false;
      render();
      schedule();
    }
  }
  render();
  load();
  return {
    destroy() {
      abort();
      signal?.removeEventListener("abort", abort);
    },
  };
}
