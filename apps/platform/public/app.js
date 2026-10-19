import { createApi } from "./api.js";
import { mountAuth } from "./auth.js";
import { createDashboard } from "./dashboard.js";
import { mountWorkspace } from "./workspace.js";
import { createRequestScope } from "./request-scope.js";
import { notice } from "./ui.js";

const root = document.querySelector("#app"),
  api = createApi();
let account,
  registrationAllowed,
  screen = null,
  navigation = null;
function replaceScreen(factory) {
  navigation?.destroy();
  navigation = null;
  screen?.destroy();
  root.onkeydown = null;
  try {
    screen = factory();
  } catch (error) {
    notice(error.message);
    throw error;
  }
}
function showAuth() {
  replaceScreen(() =>
    mountAuth({
      root,
      api,
      registrationAllowed,
      onSignedIn: async (value) => {
        account = value;
        await showDashboard();
      },
    }),
  );
}
async function showDashboard(
  initialPage = location.hash === "#progress" ? "progress" : "home",
) {
  replaceScreen(() =>
    createDashboard({
      root,
      api,
      account,
      initialPage,
      notice,
      onSession: showWorkspace,
      onOpenSession: openSession,
      onSignedOut: () => {
        account = null;
        showAuth();
      },
    }),
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
      onBack: () => showDashboard(options.returnPage || "home"),
      reviewOnOpen: options.reviewOnOpen,
      followupRoundId: options.followupRoundId,
      onOpenSession: (id, extra = {}) =>
        openSession(id, { returnPage: options.returnPage || "home", ...extra }),
    }),
  );
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
  const boot = await api("/api/bootstrap");
  account = boot.account;
  registrationAllowed = boot.registration_allowed;
  if (account) {
    const match = location.hash.match(
      /^#session\/([0-9a-f-]{36})(?:\/followup\/([0-9a-f-]{36}))?$/,
    );
    if (match) await openSession(match[1], { followupRoundId: match[2] });
    else await showDashboard();
  } else showAuth();
} catch (error) {
  root.innerHTML =
    '<div class="loading">The studio could not connect. Reload to try again.</div>';
  notice(error.message);
}
