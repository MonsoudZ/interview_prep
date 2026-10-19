// A lifetime, not a session ID: reopening the same session creates a new owner.
export function createRequestScope(api) {
  const controller = new AbortController();
  let alive = true;
  function assertAlive() {
    if (!alive)
      throw new DOMException("This screen is no longer open", "AbortError");
  }
  return {
    get alive() {
      return alive;
    },
    get signal() {
      return controller.signal;
    },
    async request(path, method, body) {
      assertAlive();
      const result = await api(path, method, body, {
        signal: controller.signal,
      });
      // Transport cancellation is advisory; never apply a late reply even if it ignores abort.
      assertAlive();
      return result;
    },
    destroy() {
      alive = false;
      controller.abort();
    },
  };
}
