import {
  tracks,
  esc,
  icon,
  brand,
  modeName,
  statusName,
  renderBrief,
} from "./ui.js";
import { createRequestScope } from "./request-scope.js";
import { renderProgress, renderProgressPeek } from "./progress.js";
export function createDashboard({
  root,
  api: request,
  account,
  onSession,
  onOpenSession,
  onSignedOut,
  notice: showNotice,
  initialPage = "home",
}) {
  const scope = createRequestScope(request),
    api = scope.request,
    dialogs = new Set();
  const notice = (message) => {
    if (scope.alive) showNotice(message);
  };
  let page = initialPage,
    filter = "all",
    catalog = [],
    history = [],
    progress = null,
    progressError = "",
    progressLoading = false;
  async function loadDashboard() {
    window.history.replaceState(
      null,
      "",
      location.pathname + (page === "progress" ? "#progress" : ""),
    );
    const [exercises, sessions, overview] = await Promise.all([
      api("/api/exercises"),
      api("/api/sessions"),
      api("/api/progress").catch((error) => {
        progressError = error.message;
        return null;
      }),
    ]);
    if (!scope.alive) return;
    catalog = exercises.exercises;
    history = sessions.sessions;
    progress = overview;
    renderDashboard();
  }
  function card(exercise) {
    return `<article class="exercise-row"><div class="exercise-name"><span class="exercise-track">${esc(tracks[exercise.track][0])}</span><h3>${esc(exercise.title)}</h3><p>${esc(exercise.summary || tracks[exercise.track][1])}</p><div class="exercise-level" title="${esc(exercise.difficulty_note)}">${esc(exercise.difficulty)}<span>${esc((exercise.skills || []).join(" · "))}</span></div></div><div class="exercise-format">${exercise.executable ? (exercise.track === "ruby" ? "Code + tests" : "Repository + tests") : exercise.track === "system_design" && exercise.version >= 2 ? "Canvas + notes" : "Writing only"}</div><span class="exercise-time">${exercise.duration_minutes} min</span><button data-exercise="${exercise.id}" aria-label="Open ${esc(exercise.title)}">Open ${icon("arrow")}</button></article>`;
  }
  function renderDashboard() {
    if (!scope.alive) return;
    const submitted = history.filter((s) => s.status === "submitted");
    const ongoing = history.filter((s) => s.status !== "submitted");
    const displayed =
      filter === "all" ? catalog : catalog.filter((e) => e.track === filter);
    const pageTitle =
      page === "home"
        ? "Practice"
        : page === "library"
          ? "Exercises"
          : page === "progress"
            ? "Progress"
            : "Sessions";
    const heading = `<header class="page-header"><div><h1>${pageTitle}</h1><p>${page === "home" ? "Rails, Ruby, and system design." : page === "library" ? "Choose an exercise, then practice with hints or a timer." : page === "progress" ? "A focused practice plan, grounded in your own reviews." : "Your saved attempts and submissions."}</p></div>${page === "home" ? `<span class="practice-summary">${ongoing.length} in progress<span>·</span>${submitted.length} submitted</span>` : page === "progress" ? `<button id="refresh-progress" class="quiet" ${progressLoading ? "disabled" : ""}>${progressLoading ? "Refreshing…" : "Refresh"}</button>` : ""}</header>`;
    const library = `<section class="exercise-section" aria-label="Practice exercises"><div class="section-top">${page === "home" ? "<h2>Exercises</h2>" : "<span></span>"}<span class="count-label">${displayed.length} available</span></div><div class="filter" role="group" aria-label="Filter exercises">${[
      ["all", "All"],
      ["rails", "Rails"],
      ["ruby", "Ruby"],
      ["system_design", "System design"],
    ]
      .map(
        ([key, label]) =>
          `<button data-filter="${key}" aria-pressed="${filter === key}" class="${filter === key ? "active" : ""}">${label}</button>`,
      )
      .join(
        "",
      )}</div><div class="exercise-list">${displayed.map(card).join("") || '<p class="empty">No exercises available in this track.</p>'}</div></section>`;
    const continueSection = ongoing.length
      ? `<section class="continue-section"><div class="section-top"><h2>Continue practicing</h2></div>${historyRows(ongoing.slice(0, 3))}</section>`
      : `<div class="first-practice"><p>No sessions in progress. Open an exercise below to get started.</p></div>`;
    const recentSection = submitted.length
      ? `<section class="recent-section"><div class="section-top"><h2>Recent submissions</h2><button class="quiet" id="view-history">All sessions ${icon("arrow")}</button></div>${historyRows(submitted.slice(0, 3))}</section>`
      : "";
    const content =
      page === "progress"
        ? progress
          ? renderProgress(progress, filter)
          : `<section class="progress-empty" role="alert"><h2>Progress could not be loaded</h2><p>${esc(progressError)}</p><button id="retry-progress">Try again</button></section>`
        : page === "history"
          ? historyRows(history)
          : `${page === "home" ? continueSection + renderProgressPeek(progress) : ""}${library}${page === "home" ? recentSection : ""}`;
    root.innerHTML = `<div class="shell"><aside class="sidebar">${brand()}<nav class="nav" aria-label="Main navigation">${[
      ["home", "Practice"],
      ["library", "Exercises"],
      ["history", "Sessions"],
      ["progress", "Progress"],
    ]
      .map(
        ([key, label]) =>
          `<button data-page="${key}" ${page === key ? 'aria-current="page"' : ""} class="${page === key ? "active" : ""}">${icon(key)}${label}</button>`,
      )
      .join(
        "",
      )}</nav><div class="profile"><span class="avatar">${esc(account.name.slice(0, 1).toUpperCase())}</span><div><strong>${esc(account.name)}</strong><span>Personal account</span></div><button class="quiet" id="logout" aria-label="Sign out" title="Sign out">↪</button></div></aside><main class="main">${heading}${content}</main></div>`;
    root.querySelectorAll("[data-page]").forEach(
      (button) =>
        (button.onclick = () => {
          page = button.dataset.page;
          filter = "all";
          window.history.replaceState(
            null,
            "",
            location.pathname + (page === "progress" ? "#progress" : ""),
          );
          renderDashboard();
          window.scrollTo(0, 0);
        }),
    );
    root.querySelectorAll("[data-filter]").forEach(
      (button) =>
        (button.onclick = () => {
          filter = button.dataset.filter;
          renderDashboard();
          root.querySelector(`[data-filter="${filter}"]`)?.focus();
        }),
    );
    root
      .querySelectorAll("[data-exercise]")
      .forEach(
        (button) => (button.onclick = () => openBrief(button.dataset.exercise)),
      );
    root
      .querySelectorAll("[data-session]")
      .forEach(
        (button) =>
          (button.onclick = () =>
            onOpenSession(button.dataset.session, { returnPage: page }).catch(
              (error) => notice(error.message),
            )),
      );
    root.querySelectorAll("[data-progress-session]").forEach((button) => {
      button.onclick = () =>
        onOpenSession(button.dataset.progressSession, {
          returnPage: "progress",
          reviewOnOpen: button.dataset.review === "true",
        }).catch((error) => notice(error.message));
    });
    root.querySelectorAll("[data-progress-followup]").forEach((button) => {
      button.onclick = () =>
        onOpenSession(button.dataset.followupSource, {
          returnPage: "progress",
          followupRoundId: button.dataset.progressFollowup,
        }).catch((error) => notice(error.message));
    });
    root.querySelectorAll("[data-practice-gap]").forEach((button) => {
      button.onclick = () => {
        const focus = progress?.plan.find(
          (item) => item.key === button.dataset.practiceGap,
        );
        if (focus) openBrief(focus.exercise_id, focus);
      };
    });
    for (const selector of ["#refresh-progress", "#retry-progress"]) {
      const button = root.querySelector(selector);
      if (button) button.onclick = refreshProgress;
    }
    document.querySelector("#view-history")?.addEventListener("click", () => {
      page = "history";
      renderDashboard();
      window.scrollTo(0, 0);
    });
    document.querySelector("#logout").onclick = async () => {
      try {
        await api("/api/logout", "DELETE");
        onSignedOut();
      } catch (error) {
        notice(error.message);
      }
    };
  }
  function historyRows(rows) {
    return rows.length
      ? `<div class="history">${rows.map((s) => `<div class="history-row"><div class="history-info"><strong>${esc(s.title)}</strong><p>${modeName(s.mode)}${s.revision_of_id ? " · rework" : ""}<span>·</span>${new Date(s.updated_at).toLocaleDateString(undefined, { month: "short", day: "numeric" })}</p></div><span class="session-badge status-${esc(s.status)}">${statusName(s.status)}</span><button class="quiet" data-session="${s.id}">${s.status === "submitted" ? "View" : "Continue"} ${icon("arrow")}</button></div>`).join("")}</div>`
      : `<div class="empty"><h3>No sessions yet</h3><p>Open an exercise to start your first attempt.</p><button data-page="library">Browse exercises</button></div>`;
  }
  async function refreshProgress() {
    if (progressLoading) return;
    progressLoading = true;
    renderDashboard();
    try {
      progress = await api("/api/progress");
      progressError = "";
    } catch (error) {
      progressError = error.message;
      notice(error.message);
    } finally {
      progressLoading = false;
      renderDashboard();
    }
  }
  function openBrief(id, focus = null) {
    const exercise = catalog.find((e) => e.id === id);
    if (!exercise) {
      notice(
        "This exercise changed. Refresh the page to load the current catalog.",
      );
      return;
    }
    const dialog = document.createElement("dialog");
    dialogs.add(dialog);
    dialog.className = "setup-dialog";
    dialog.setAttribute("aria-label", "Set up your practice session");
    dialog.innerHTML = `<form method="dialog"><div class="eyebrow">${esc(tracks[exercise.track][0])}</div><h2>${esc(exercise.title)}</h2><p class="subtitle">${esc(exercise.summary)}</p><div class="exercise-overview"><p><strong>Level</strong> ${esc(exercise.difficulty)} <small>Editorial level</small></p><p><strong>Available tools</strong> ${esc((exercise.tools || []).join(", "))}</p>${exercise.limitation ? `<p class="exercise-limitation">${esc(exercise.limitation)}</p>` : ""}</div><details class="preview-brief"><summary>Read the full task</summary><div class="brief-content">${renderBrief(exercise.brief || "")}</div></details><fieldset class="mode-options"><legend>Session mode</legend><label class="mode-option"><input type="radio" name="mode" value="guided" checked><span><strong>Guided practice</strong><small>No deadline. Work at your pace with progressive hints.</small></span></label><label class="mode-option"><input type="radio" name="mode" value="assessment"><span><strong>Timed assessment</strong><small>${exercise.duration_minutes} minutes. No hints. The timer keeps running if you disconnect.</small></span></label></fieldset><div class="setup-note">${icon("check")}<p>Read the full brief before starting the session.${exercise.executable ? " The environment prepares automatically when a worker is connected. The timer starts only when you choose Start session." : exercise.track === "system_design" && exercise.version >= 2 ? " Diagram and notes save together. The timer starts only when you choose Start session." : " This exercise includes a saved writing workspace."}</p></div><p class="error" id="brief-error" role="alert"></p><footer><button value="cancel">Cancel</button><button type="button" class="primary" id="create-session">Open workspace ${icon("arrow")}</button></footer></form>`;
    if (focus) {
      const focusNode = document.createElement("section");
      focusNode.className = "practice-focus";
      focusNode.innerHTML = `<h3>Your practice focus</h3><strong>${esc(focus.title)}</strong><p>${esc(focus.practice)}</p><p class="subtitle">The full exercise still applies. This focus comes from an earlier self-assessment.</p>`;
      dialog.querySelector(".exercise-overview").after(focusNode);
    }
    document.body.append(dialog);
    dialog.showModal();
    dialog.addEventListener("close", () => {
      dialogs.delete(dialog);
      dialog.remove();
    });
    dialog.querySelector("#create-session").onclick = async (event) => {
      event.target.disabled = true;
      try {
        const session = await api("/api/sessions", "POST", {
          exercise_id: id,
          mode: dialog.querySelector("[name=mode]:checked").value,
          ...(focus
            ? {
                focus: {
                  source_session_id: focus.latest.session_id,
                  criterion_id: focus.criterion_id,
                },
              }
            : {}),
        });
        if (!scope.alive) return;
        dialog.close();
        onSession(session, { returnPage: page });
      } catch (error) {
        if (!scope.alive) return;
        dialog.querySelector("#brief-error").textContent = error.message;
        event.target.disabled = false;
      }
    };
  }

  return {
    async load() {
      try {
        await loadDashboard();
      } catch (error) {
        if (scope.alive) throw error;
      }
    },
    destroy() {
      scope.destroy();
      for (const dialog of dialogs) dialog.close();
      dialogs.clear();
    },
  };
}
