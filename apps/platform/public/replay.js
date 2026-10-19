// Replays the owner's own saved revisions. It shows what changed between saves and
// when tests ran or hints were revealed; it does not score, time, or judge the attempt.
import { esc } from "./ui.js";
import { createRequestScope } from "./request-scope.js";
import { renderSourceDiff } from "./rework.js";

export function formatOffset(seconds) {
  const total = Math.max(0, Math.round(Number(seconds) || 0));
  const hours = Math.floor(total / 3600),
    minutes = Math.floor((total % 3600) / 60),
    rest = total % 60;
  const pad = (value) => String(value).padStart(2, "0");
  return hours
    ? `+${hours}:${pad(minutes)}:${pad(rest)}`
    : `+${pad(minutes)}:${pad(rest)}`;
}

export function describeStep(step, index, total) {
  const parts = [
    index === 0 ? "Opening revision" : `Save ${index + 1} of ${total}`,
    formatOffset(step.offset_seconds),
    step.changed_paths.length
      ? `${step.changed_paths.length} ${step.changed_paths.length === 1 ? "file" : "files"} changed`
      : "no source changes",
  ];
  if (step.submitted) parts.push("submitted revision");
  return parts.join(" · ");
}

export function describeEvents(step) {
  const events = step.executions.map((run) => {
    if (run.purpose === "prepare")
      return `Prepared · ${run.status.replaceAll("_", " ")}`;
    const summary = run.summary;
    return summary
      ? `Tests · runner reported ${summary.passed}/${summary.tests} passing`
      : `Tests · ${run.status.replaceAll("_", " ")} · no complete summary`;
  });
  for (const position of step.hints)
    events.push(`Hint ${position + 1} revealed`);
  return events;
}

export async function openReplay(session, { api, signal, notice }) {
  const scope = createRequestScope(api),
    dialog = document.createElement("dialog");
  dialog.className = "comparison-dialog replay-dialog";
  dialog.setAttribute("aria-label", "Replay this attempt");
  dialog.innerHTML =
    '<h2>Replay attempt</h2><p role="status">Loading saved revisions…</p><div id="replay-content"></div><footer><button id="close-replay">Close replay</button></footer>';
  const close = () => dialog.close();
  dialog.querySelector("#close-replay").onclick = close;
  signal?.addEventListener("abort", close, { once: true });
  dialog.addEventListener(
    "close",
    () => {
      scope.destroy();
      signal?.removeEventListener("abort", close);
      dialog.remove();
    },
    { once: true },
  );
  document.body.append(dialog);
  dialog.showModal();
  const diffs = new Map();
  let steps = [],
    index = 0;
  const status = dialog.querySelector('[role="status"]'),
    content = dialog.querySelector("#replay-content");
  async function changesFor(revision) {
    if (!diffs.has(revision))
      diffs.set(
        revision,
        scope
          .request(
            `/api/sessions/${session.id}/timeline?revision=${encodeURIComponent(revision)}`,
          )
          .then((result) => result.changes),
      );
    return diffs.get(revision);
  }
  async function show() {
    if (!scope.alive) return;
    const step = steps[index];
    status.textContent = describeStep(step, index, steps.length);
    dialog.querySelector("#replay-position").value = String(index);
    dialog.querySelector("#replay-prev").disabled = index === 0;
    dialog.querySelector("#replay-next").disabled = index === steps.length - 1;
    const events = describeEvents(step);
    dialog.querySelector("#replay-events").innerHTML = events.length
      ? events.map((text) => `<span>${esc(text)}</span>`).join("")
      : "<span>No runs or hints at this save</span>";
    const source = dialog.querySelector("#replay-source");
    if (!step.changed_paths.length) {
      source.innerHTML =
        '<p class="subtitle">This save matches the previous revision for every file.</p>';
      return;
    }
    source.innerHTML = '<p class="subtitle">Loading changes…</p>';
    try {
      const changes = await changesFor(step.revision);
      if (!scope.alive || steps[index] !== step) return;
      source.innerHTML = `<label class="comparison-file-label">Changed file<select id="replay-file">${changes.map((file, position) => `<option value="${position}">${esc(file.path)} · ${esc(file.kind)}</option>`).join("")}</select></label><div id="replay-diff"></div>`;
      const picker = source.querySelector("#replay-file");
      const render = () => {
        const file = changes[Number(picker.value)];
        source.querySelector("#replay-diff").innerHTML = renderSourceDiff(
          file.before,
          file.after,
          { before: "Previous save", after: "This save" },
        );
      };
      picker.onchange = render;
      render();
    } catch (error) {
      if (scope.alive) {
        source.innerHTML =
          '<p class="subtitle">Changes could not be loaded.</p>';
        notice(error.message);
      }
    }
  }
  try {
    const result = await scope.request(`/api/sessions/${session.id}/timeline`);
    if (!scope.alive) return;
    steps = result.steps;
    index = Math.max(
      0,
      steps.findIndex((step) => step.submitted),
    );
    content.innerHTML = `<p class="subtitle">${steps.length} saved ${steps.length === 1 ? "revision" : "revisions"}. Step through them to see how the attempt took shape.</p><div class="replay-controls"><button type="button" id="replay-prev">◀ Earlier</button><input type="range" id="replay-position" min="0" max="${steps.length - 1}" step="1" aria-label="Saved revision"><button type="button" id="replay-next">Later ▶</button></div><div class="replay-events" id="replay-events"></div><div id="replay-source"></div><p class="subtitle">${esc(result.note)}</p>`;
    dialog.querySelector("#replay-prev").onclick = () => {
      index = Math.max(0, index - 1);
      show();
    };
    dialog.querySelector("#replay-next").onclick = () => {
      index = Math.min(steps.length - 1, index + 1);
      show();
    };
    dialog.querySelector("#replay-position").oninput = (event) => {
      index = Number(event.target.value);
      show();
    };
    await show();
  } catch (error) {
    if (scope.alive) {
      status.textContent = "Replay could not be loaded.";
      notice(error.message);
    }
  }
}
