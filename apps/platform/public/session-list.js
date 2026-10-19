import { esc, icon, modeName, statusName } from "./ui.js";
const pages = {
  home: "",
  library: "#exercises",
  history: "#sessions",
  progress: "#progress",
};
export const dashboardHash = (page) => pages[page] || "";
export const dashboardPage = (hash) =>
  Object.keys(pages).find((page) => pages[page] === hash) || "home";
export function filterSessions(
  rows,
  { status = "all", kind = "all", query = "" } = {},
) {
  const term = query.trim().toLowerCase();
  return rows.filter(
    (row) =>
      (status === "all" ||
        status === "archived" ||
        (status === "submitted"
          ? row.status === "submitted"
          : row.status !== "submitted")) &&
      (kind === "all" ||
        (kind === "mock"
          ? !!row.mock_interview_id
          : kind === "rework"
            ? !!row.revision_of_id
            : row.track === kind)) &&
      (!term ||
        `${row.title} ${row.track} ${modeName(row.mode)} ${row.revision_of_id ? "rework" : ""} ${row.mock_interview_id ? "mock interview" : ""}`
          .toLowerCase()
          .includes(term)),
  );
}
export function renderSessionRows(
  rows,
  { empty = "No sessions in this view.", organize = false } = {},
) {
  return rows.length
    ? `<div class="history">${rows.map((row) => `<article class="history-row"><div class="history-info"><strong>${esc(row.title)}</strong><p>${modeName(row.mode)}${row.revision_of_id ? " · rework" : ""}${row.mock_interview_id ? " · interview stage" : ""}<span>·</span>${new Date(row.submitted_at || row.updated_at).toLocaleDateString(undefined, { month: "short", day: "numeric" })}</p></div><span class="session-badge status-${esc(row.status)}">${row.archived_at ? "Archived" : statusName(row.status)}</span><div class="session-row-actions"><button class="quiet" data-session="${esc(row.id)}">${row.status === "submitted" ? "View" : "Continue"} ${icon("arrow")}</button>${row.mock_interview_id ? `<button class="quiet" data-open-interview="${row.mock_interview_id}">Interview</button>` : ""}${organize && row.status === "submitted" && !row.mock_interview_id ? `<button class="quiet" data-organize-session="${esc(row.id)}" data-restore="${!!row.archived_at}" aria-label="${row.archived_at ? "Restore" : "Archive"} ${esc(row.title)}">${row.archived_at ? "Restore" : "Archive"}</button>` : ""}</div></article>`).join("")}</div>`
    : `<p class="empty">${esc(empty)}</p>`;
}
