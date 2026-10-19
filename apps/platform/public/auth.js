import { brand } from "./ui.js";
import { createRequestScope } from "./request-scope.js";
export function mountAuth({
  root,
  api: request,
  registrationAllowed,
  onSignedIn,
}) {
  const scope = createRequestScope(request),
    api = scope.request;
  function authForm(register = false) {
    if (!scope.alive) return;
    root.innerHTML = `<main class="auth"><section class="auth-story">${brand()}<h1>Interview practice.</h1><p>Rails repositories, Ruby problems, and system design exercises. Your code, notes, and previous attempts in one place.</p></section><section class="auth-panel"><form id="auth"><h2>${register ? "Create an account" : "Sign in"}</h2><p class="subtitle">${register ? "Your sessions and code belong to your account." : "Pick up where you left off."}</p>${register ? '<label>Your name<input name="name" autocomplete="name" required maxlength="100"></label>' : ""}<label>Email<input name="email" type="email" autocomplete="email" required></label><label>Password<input name="password" type="password" autocomplete="${register ? "new-password" : "current-password"}" required ${register ? 'minlength="12" maxlength="72"' : ""}></label>${register ? '<p class="subtitle">Use at least 12 characters.</p>' : ""}<p id="auth-error" class="error" role="alert"></p><button class="primary" type="submit">${register ? "Create account" : "Sign in"} →</button>${registrationAllowed ? `<p class="auth-switch">${register ? "Already have an account?" : "New here?"} <button type="button" class="quiet" id="switch-auth">${register ? "Sign in" : "Create account"}</button></p>` : ""}</form></section></main>`;
    document
      .querySelector("#switch-auth")
      ?.addEventListener("click", () => authForm(!register));
    document
      .querySelector("#auth")
      .addEventListener("submit", async (event) => {
        event.preventDefault();
        const button = event.target.querySelector("[type=submit]");
        button.disabled = true;
        try {
          const data = Object.fromEntries(new FormData(event.target));
          const result = await api(
            register ? "/api/register" : "/api/login",
            "POST",
            data,
          );
          if (scope.alive) await onSignedIn(result.account);
        } catch (error) {
          if (!scope.alive) return;
          document.querySelector("#auth-error").textContent = error.message;
          button.disabled = false;
        }
      });
  }

  authForm();
  return {
    destroy() {
      scope.destroy();
    },
  };
}
