export const clamp = (value, min, max, fallback = min) =>
  Number.isFinite(Number(value))
    ? Math.max(min, Math.min(max, Number(value)))
    : fallback;
export function cleanPreferences(value = {}) {
  if (!value || typeof value !== "object" || Array.isArray(value)) value = {};
  const positions = {};
  for (const [path, item] of Object.entries(value.positions || {}).slice(
    0,
    100,
  )) {
    if (!item || typeof item !== "object") continue;
    positions[path] = {
      anchor: clamp(item.anchor, 0, 2_000_000),
      head: clamp(item.head, 0, 2_000_000),
      top: clamp(item.top, 0, 5_000_000),
      left: clamp(item.left, 0, 100_000),
    };
  }
  return {
    selected:
      typeof value.selected === "string" ? value.selected.slice(0, 200) : "",
    positions,
    layout: {
      files: clamp(value.layout?.files, 140, 320, 200),
      brief: clamp(value.layout?.brief, 260, 520, 350),
      output: clamp(value.layout?.output, 140, 600, 240),
    },
    panel: ["brief", "support", "runs"].includes(value.panel)
      ? value.panel
      : "brief",
  };
}
export function preferenceStore(storage, key) {
  return {
    read() {
      try {
        return cleanPreferences(JSON.parse(storage.getItem(key) || "{}"));
      } catch {
        return cleanPreferences();
      }
    },
    write(value) {
      try {
        storage.setItem(key, JSON.stringify(cleanPreferences(value)));
      } catch {
        /* The editor still works with browser storage unavailable. */
      }
    },
  };
}
export function shouldAutoPrepare(session, openingRevision) {
  return (
    session.executable &&
    session.worker_available &&
    session.status === "draft" &&
    session.revision === openingRevision &&
    !session.executions.some(
      (e) =>
        ["queued", "leased"].includes(e.status) ||
        (e.purpose === "prepare" && e.revision === session.revision),
    )
  );
}
// Cross-tab preparation retries for the same opening revision share the server's idempotency key.
export async function preparationRequestId(
  sessionId,
  revision,
  crypto = globalThis.crypto,
) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`prepare:${sessionId}:${revision}`),
  );
  const bytes = new Uint8Array(digest).slice(0, 16);
  bytes[6] = (bytes[6] & 15) | 80;
  bytes[8] = (bytes[8] & 63) | 128;
  const hex = [...bytes]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}
