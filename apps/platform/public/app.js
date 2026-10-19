import { createApi } from "./api.js";
import { mountAuth } from "./auth.js";
import { createDashboard } from "./dashboard.js";
import { mountWorkspace } from "./workspace.js";
import { createRequestScope } from "./request-scope.js";
import { mountMockInterviews } from "./mock-interviews.js";
import { dashboardPage } from "./session-list.js";
import { notice } from "./ui.js";

const root = document.querySelector("#app"),
  transport = createApi();
let account,
  registrationAllowed,
  screen = null,
  navigation = null;
// A 401 while signed in means the server session expired: return to sign-in once
// instead of letting every screen keep polling and reporting a connection problem.
async function api(...args) {
  try {
    return await transport(...args);
  } catch (error) {
    if (error.status === 401 && account) {
      account = null;
      showAuth();
      notice("Your sign-in expired. Sign in again to continue.");
    }
    throw error;
  }
}
function replaceScreen(factory, { fallback = true } = {}) {
  navigation?.destroy();
  navigation = null;
  screen?.destroy();
  root.onkeydown = null;
  try {
    screen = factory();
  } catch (error) {
    // Never keep a destroyed screen as the current one; it would answer unload
    // guards and openSession checks for a page that no longer exists.
    screen = null;
    notice(error.message);
    if (fallback && account) showDashboard().catch(() => {});
    else if (fallback) showAuth();
    else
      root.innerHTML =
        '<div class="loading">This screen could not open. Reload to try again.</div>';
    throw error;
  }
}
function showAuth() {
  replaceScreen(
    () =>
      mountAuth({
        root,
        api,
        registrationAllowed,
        onSignedIn: async (value) => {
          account = value;
          await showDashboard();
        },
      }),
    { fallback: false },
  );
}
async function showDashboard(initialPage = dashboardPage(location.hash)) {
  replaceScreen(
    () =>
      createDashboard({
        root,
        api,
        account,
        initialPage,
        notice,
        onSession: showWorkspace,
        onMocks: (id) => showMocks(id),
        onOpenSession: openSession,
        onSignedOut: () => {
          account = null;
          showAuth();
        },
      }),
    { fallback: false },
  );
  const dashboard = screen;
  try {
    await dashboard.load();
  } catch (error) {
    if (screen !== dashboard) return;
    root.innerHTML =
      '<main class="loading"><p>Your sessions could not be loaded.</p><button id="retry-dashboard">Try again</button></main>';
    notice(error.message);
    root.querySelector("#retry-dashboard").onclick = () => showDashboard();
  }
}
function showWorkspace(session, options = {}) {
  replaceScreen(() =>
    mountWorkspace({
      root,
      session,
      account,
      api,
      notice,
      onBack: () =>
        session.mock_interview_id
          ? showMocks(session.mock_interview_id)
          : showDashboard(options.returnPage || "home"),
      reviewOnOpen: options.reviewOnOpen,
      followupRoundId: options.followupRoundId,
      onOpenSession: (id, extra = {}) =>
        openSession(id, { returnPage: options.returnPage || "home", ...extra }),
    }),
  );
}
async function showMocks(id) {
  replaceScreen(() =>
    mountMockInterviews({
      root,
      api,
      notice,
      initialId: id,
      onBack: () => showDashboard(),
      onOpenSession: openSession,
    }),
  );
  await screen.load();
}
async function openSession(id, options = {}) {
  navigation?.destroy();
  const scope = (navigation = createRequestScope(api));
  try {
    const session = await scope.request(`/api/sessions/${id}`);
    if (scope.alive) showWorkspace(session, options);
  } catch (error) {
    if (scope.alive) {
      notice(error.message);
      if (!screen) await showDashboard();
    }
  }
}
window.addEventListener("pagehide", () => screen?.persist?.());
window.addEventListener("beforeunload", (event) => {
  if (screen?.hasUnsavedChanges) {
    event.preventDefault();
    event.returnValue = "";
  }
});
try {
  const boot = await transport("/api/bootstrap");
  account = boot.account;
  registrationAllowed = boot.registration_allowed;
  if (account) {
    const match = location.hash.match(
      /^#session\/([0-9a-f-]{36})(?:\/followup\/([0-9a-f-]{36}))?$/,
    );
    const mockMatch = location.hash.match(/^#interview\/([0-9a-f-]{36})$/);
    if (mockMatch) await showMocks(mockMatch[1]);
    else if (location.hash === "#interviews") await showMocks();
    else if (match) await openSession(match[1], { followupRoundId: match[2] });
    else await showDashboard();
  } else showAuth();
} catch (error) {
  root.innerHTML =
    '<div class="loading">The studio could not connect. Reload to try again.</div>';
  notice(error.message);
}
