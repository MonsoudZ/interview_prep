import test from "node:test";
import assert from "node:assert/strict";
import { createRequestScope } from "../../public/request-scope.js";
import { createApi } from "../../public/api.js";
const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
};

test("a closed screen aborts transport and rejects late replies even when transport ignores cancellation", async () => {
  const pending = deferred();
  let signal;
  const scope = createRequestScope((path, method, body, options) => {
    signal = options.signal;
    return pending.promise;
  });
  const reply = scope.request("/api/sessions/same-id");
  scope.destroy();
  assert.equal(signal.aborted, true);
  pending.resolve({ revision: "old" });
  await assert.rejects(reply, { name: "AbortError" });
  await assert.rejects(scope.request("/api/sessions/same-id"), {
    name: "AbortError",
  });
});
test("reopening the same session has independent ownership of saves, polling, and preparation", async () => {
  for (const operation of ["snapshot", "poll", "prepare"]) {
    const pending = deferred(),
      applied = [];
    const old = createRequestScope(() => pending.promise);
    const reply = old
      .request(`/same-session/${operation}`)
      .then((value) => applied.push(value))
      .catch((error) => assert.equal(error.name, "AbortError"));
    old.destroy();
    const current = createRequestScope(async () => ({ revision: "current" }));
    applied.push(await current.request(`/same-session/${operation}`));
    pending.resolve({ revision: "stale" });
    await reply;
    assert.deepEqual(applied, [{ revision: "current" }]);
    current.destroy();
  }
});
test("the API adapter keeps CSRF and same-origin credentials while forwarding cancellation", async () => {
  const calls = [];
  const api = createApi(async (path, options) => {
    calls.push({ path, options });
    return { ok: true, json: async () => ({ csrf_token: "rotated" }) };
  });
  await api("/api/bootstrap");
  const controller = new AbortController();
  await api(
    "/api/sessions",
    "POST",
    { mode: "guided" },
    { signal: controller.signal },
  );
  assert.equal(calls[1].options.headers["X-CSRF-Token"], "rotated");
  assert.equal(calls[1].options.credentials, "same-origin");
  assert.equal(calls[1].options.signal, controller.signal);
  assert.equal(calls[1].options.body, '{"mode":"guided"}');
});
test("API errors retain status codes needed for optimistic conflicts", async () => {
  const api = createApi(async () => ({
    ok: false,
    status: 409,
    json: async () => ({ error: "A newer save exists" }),
  }));
  await assert.rejects(
    api("/snapshot", "PUT", {}),
    (error) => error.status === 409 && /newer save/.test(error.message),
  );
});

test("an aborted response cannot replace the current CSRF token", async () => {
  const old = deferred(),
    calls = [];
  const api = createApi(async (path, options) => {
    calls.push(options);
    if (path === "/old") return old.promise;
    return { ok: true, json: async () => ({ csrf_token: "current-token" }) };
  });
  const controller = new AbortController();
  const pending = api("/old", "GET", undefined, { signal: controller.signal });
  await api("/current");
  controller.abort();
  old.resolve({ ok: true, json: async () => ({ csrf_token: "stale-token" }) });
  await assert.rejects(pending, { name: "AbortError" });
  await api("/write", "POST", {});
  assert.equal(calls.at(-1).headers["X-CSRF-Token"], "current-token");
});
