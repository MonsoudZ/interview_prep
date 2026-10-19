import { esc, tracks, modeName } from "./ui.js";

const rating = (value) => String(value || "not observed").replaceAll("_", " ");
const date = (value) =>
  value
    ? new Date(value).toLocaleDateString(undefined, {
        month: "short",
        day: "numeric",
        year: "numeric",
      })
    : "Date unavailable";
const inTrack = (items, filter) =>
  items.filter((item) => filter === "all" || item.track === filter);
const reviewButton = (id, text = "Review attempt") =>
  `<button class="quiet" data-progress-session="${esc(id)}" data-review="true">${esc(text)} →</button>`;

export function renderProgressPeek(progress) {
  if (!progress) return "";
  const first = progress.plan[0];
  return `<section class="progress-peek"><div><h2>${first ? "Your next practice focus" : "Your practice plan"}</h2><p>${first ? `<strong>${esc(first.title)}</strong> · ${esc(first.exercise)}` : progress.summary.awaiting_review ? `${progress.summary.awaiting_review} submitted attempts have criteria left to review.` : "Review a submitted attempt to choose a focused drill."}</p></div><button class="quiet" data-page="progress">View progress →</button></section>`;
}

function renderPlanItem(item, index) {
  const next = item.next_session_id
    ? `<button class="primary" data-progress-session="${esc(item.next_session_id)}" data-review="${item.next_session_status === "submitted"}">${item.next_session_status === "submitted" ? "Review newer attempt" : "Continue focused attempt"} →</button>`
    : item.exercise_id
      ? `<button class="primary" data-practice-gap="${esc(item.key)}">Practice this focus →</button>`
      : "";
  return `<article class="focus-item"><span class="focus-number" aria-hidden="true">${index + 1}</span><div class="focus-body"><p class="progress-meta">${esc(tracks[item.track]?.[0])} · ${esc(item.exercise)} · version ${item.exercise_version}</p><h3>${esc(item.title)}</h3><p>${esc(item.practice)}</p><p class="focus-reason">${item.recurring ? "Repeated gap" : "Latest self-reported gap"} · ${item.gap_count} of ${item.observation_count} self-ratings below target. Latest: ${esc(rating(item.latest.rating))}.</p>${item.target_version !== item.exercise_version ? `<p class="progress-meta">The next attempt uses exercise version ${item.target_version}. Its rubric may differ; earlier observations stay separate.</p>` : ""}<div class="progress-actions">${next}${reviewButton(item.latest.session_id, "View source review")}</div></div></article>`;
}

function renderSkill(item) {
  const trend = {
    first_observation: "First self-rating",
    higher: "Higher self-rating",
    lower: "Lower self-rating",
    unchanged: "Same self-rating",
  }[item.trend];
  return `<details class="progress-skill"><summary><span><strong>${esc(item.title)}</strong><small>${esc(item.exercise)} · ${esc(item.content_version)}</small></span><span class="skill-reading">${esc(rating(item.latest.rating))}<small>${esc(trend)}${item.historical ? " · earlier rubric" : ""}${item.recurring ? " · repeated gap" : ""}</small></span></summary><p class="progress-meta">${item.observation_count} observations, ordered by submission date. Guided and timed attempts are labeled individually.</p><ol class="rating-history">${item.observations.map((observation) => `<li><div><strong>${esc(rating(observation.rating))}</strong><span>${date(observation.submitted_at)} · ${modeName(observation.mode)} · ${observation.hints_revealed} hints revealed</span><p>${esc(observation.notes)}</p></div>${reviewButton(observation.session_id, "View evidence")}</li>`).join("")}</ol>${item.history_truncated ? "<p class='progress-meta'>Showing the eight most recent observations. Counts include the full history.</p>" : ""}</details>`;
}

export function renderExecution(execution) {
  if (!execution) return "No test run for the submitted revision";
  const summary = execution.summary;
  if (summary && !execution.output_truncated)
    return `Runner reported ${summary.passed}/${summary.tests} passing · ${summary.failures} failures · ${summary.errors} errors · ${summary.skipped} skips`;
  return execution.output_truncated
    ? "Runner output truncated; no passing conclusion"
    : `Test run: ${rating(execution.status)} · no complete test summary`;
}

function renderFollowupProgress(rounds, filter) {
  const visible = inTrack(rounds, filter);
  return `<section class="progress-section" aria-label="Follow-up practice"><div class="section-top"><h2>Follow-up rounds</h2><span class="count-label">Latest 10 across tracks</span></div><p class="progress-intro">Scripted questions with saved typed answers. Self-checks stay separate from starter-attempt ratings.</p>${visible.length ? visible.map((round) => `<div class="progress-review-row"><div><strong>${esc(round.title)}</strong><p>${round.mode === "assessment" ? "Timed" : "Guided"} · ${{ ready: "Not started", active: "In progress", completed: "Completed" }[round.status]} · ${round.answered}/${round.question_count} answered${round.self_reported_gaps ? ` · ${round.self_reported_gaps} marked for practice` : ""}</p></div><button class="quiet" data-progress-followup="${esc(round.id)}" data-followup-source="${esc(round.session_id)}">${round.status === "completed" ? "View round" : "Resume round"} →</button></div>`).join("") : '<p class="progress-empty">No rounds in this view. Open a submitted attempt’s review to practice follow-up questions.</p>'}</section>`;
}

export function renderProgress(progress, filter = "all") {
  const plan = inTrack(progress.plan, filter).slice(0, 3),
    waiting = inTrack(progress.awaiting_review, filter).slice(0, 10),
    skills = inTrack(progress.skills, filter),
    attempts = inTrack(progress.recent_attempts, filter),
    summary = progress.summary;
  return `<section aria-label="Practice totals" class="progress-totals">${[
    [summary.submitted, "Submitted attempts"],
    [summary.self_reviews_started, "With a self-rating"],
    [summary.awaiting_review, "Reviews unfinished"],
    [summary.recurring_gaps, "Repeated gaps"],
  ]
    .map(
      ([count, text]) =>
        `<div><strong>${count}</strong><span>${text}</span></div>`,
    )
    .join("")}</section>
    <p class="progress-method">Totals cover all tracks. Ratings below come from your self-assessments. Test results and model feedback do not establish mastery.</p>
    <div class="filter" role="group" aria-label="Filter progress">${[
      ["all", "All"],
      ["rails", "Rails"],
      ["ruby", "Ruby"],
      ["system_design", "System design"],
    ]
      .map(
        ([key, text]) =>
          `<button data-filter="${key}" aria-pressed="${key === filter}" class="${key === filter ? "active" : ""}">${text}</button>`,
      )
      .join("")}</div>
    <section class="progress-section" aria-label="Focused practice plan"><div class="section-top"><h2>Next practice</h2><span class="count-label">Up to three priorities</span></div><p class="progress-intro">Repeated gaps come first, then other areas you last rated below target. A new attempt stays open until you assess it.</p>${plan.length ? plan.map(renderPlanItem).join("") : `<div class="progress-empty"><h3>${skills.length ? "No current self-reported gaps" : "Your plan starts with a review"}</h3><p>${skills.length ? "Review any unassessed work before drawing conclusions. Meeting a self-assessed target is not a verified skill score." : "Submit an attempt and rate at least one criterion with evidence. Unobserved criteria stay unassessed."}</p>${waiting[0] ? reviewButton(waiting[0].id) : '<button data-page="library">Browse exercises →</button>'}</div>`}</section>
    <section class="progress-section" aria-label="Review queue"><div class="section-top"><h2>Finish a review</h2><span class="count-label">Newest unfinished reviews · up to 10</span></div>${waiting.length ? waiting.map((attempt) => `<div class="progress-review-row"><div><strong>${esc(attempt.title)}</strong><p>${date(attempt.submitted_at)} · ${modeName(attempt.mode)}${attempt.revision_of_id ? " · rework" : ""} · ${attempt.observed}/${attempt.total} criteria assessed</p></div>${reviewButton(attempt.id)}</div>`).join("") : '<p class="progress-empty">No unfinished reviews in this view.</p>'}</section>
    ${renderFollowupProgress(progress.followups || [], filter)}
    <section class="progress-section" aria-label="Criterion history"><div class="section-top"><h2>How your ratings changed</h2></div><p class="progress-intro">The same criterion is compared only within one exercise and rubric version. Updating an older review replaces its observation. Reworks stay in attempt history and do not change starter-attempt trends.</p>${skills.length ? skills.map(renderSkill).join("") : '<p class="progress-empty">No observed self-ratings yet. Blank and “not observed” entries do not count as evidence of progress.</p>'}</section>
    <section class="progress-section" aria-label="Recent submitted attempts"><div class="section-top"><h2>Recent attempts</h2><span class="count-label">Latest ${progress.recent_limit} across tracks</span></div>${attempts.length ? attempts.map((attempt) => `<details class="progress-attempt"><summary><span><strong>${esc(attempt.title)}</strong><small>${date(attempt.submitted_at)} · ${modeName(attempt.mode)}${attempt.revision_of_id ? " · rework" : ""} · version ${attempt.exercise_version}</small></span><span>${attempt.observed}/${attempt.total} assessed</span></summary><p>${attempt.track === "system_design" ? "System design is reviewed from the submitted diagram and reasoning." : esc(renderExecution(attempt.execution))}</p><p class="progress-meta">${attempt.hints_revealed} hints revealed. Runner output is reported evidence, separate from self-ratings.</p>${attempt.practice_focus ? `<p><strong>Practice focus:</strong> ${esc(attempt.practice_focus.title)}</p>` : ""}${attempt.reflection ? `<blockquote>${esc(attempt.reflection)}</blockquote>` : ""}${reviewButton(attempt.id, "Open submission review")}</details>`).join("") : '<p class="progress-empty">No submitted attempts in this view.</p>'}</section>
    <details class="progress-method-details"><summary>How this plan is built</summary><p>${esc(progress.method)}</p><p>A repeated gap means you rated the same criterion below target on two or more submissions and your latest observed rating is still below target. A higher self-rating updates the plan; it does not certify improvement. The review queue includes partial reviews and criteria left unobserved.</p></details>`;
}
