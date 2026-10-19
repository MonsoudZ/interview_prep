export function createApi(fetchImpl = fetch) {
  let csrf;
  async function api(path, method = "GET", body, { signal } = {}) {
    const response = await fetchImpl(path, {
      method,
      signal,
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrf || "",
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const result = await response
      .json()
      .catch(() => ({ error: "Unexpected server response" }));
    signal?.throwIfAborted();
    if (!response.ok) {
      const error = new Error(
        result.error || `Request failed (${response.status})`,
      );
      error.status = response.status;
      throw error;
    }
    if (result.csrf_token) csrf = result.csrf_token;
    return result;
  }

  return api;
}
