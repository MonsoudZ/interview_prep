export const tracks = {
  rails: [
    "Rails engineering",
    "API implementation in a Rails repository.",
    "↗",
  ],
  ruby: ["Ruby challenges", "Algorithms and problem solving in Ruby.", "{ }"],
  system_design: [
    "System design",
    "Architecture, reliability, and trade-offs.",
    "◇",
  ],
};
export const esc = (value) =>
  String(value ?? "").replace(
    /[&<>"']/g,
    (char) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        char
      ],
  );
export const short = (value) => (value || "").slice(0, 10);
export function notice(message) {
  const node = document.querySelector("#notice");
  node.textContent = message;
  node.style.display = "block";
  clearTimeout(node.hide);
  node.hide = setTimeout(() => (node.style.display = "none"), 6500);
}
export function confirmSubmission(signal) {
  return new Promise((resolve) => {
    const dialog = document.createElement("dialog");
    dialog.innerHTML =
      '<form method="dialog"><h2>Ready to submit?</h2><p class="subtitle">Your latest saved revision will become read-only. You can add review notes after submitting.</p><button value="cancel">Keep working</button> <button class="primary" value="submit">Submit revision</button></form>';
    const cancel = () => dialog.close("cancel");
    document.body.append(dialog);
    signal?.addEventListener("abort", cancel, { once: true });
    dialog.addEventListener(
      "close",
      () => {
        signal?.removeEventListener("abort", cancel);
        const accepted = dialog.returnValue === "submit";
        dialog.remove();
        resolve(accepted);
      },
      { once: true },
    );
    dialog.showModal();
  });
}
const icons = {
  progress: '<path d="M4 20h17M5 16l5-6 4 3 6-9M15 4h5v5"/>',
  home: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
  library: '<path d="M4 5h6v15H4zM14 5h6v15h-6zM4 9h6M14 9h6"/>',
  history: '<path d="M3 11a9 9 0 1 1 3 8M3 4v7h7M12 7v5l3 2"/>',
  rails: '<path d="m8 5-6 7 6 7m8-14 6 7-6 7m-3-16-2 18"/>',
  ruby: '<path d="m5 4-4 7 11 10 11-10-4-7ZM1 11h22M5 4l7 17 7-17M5 4h14"/>',
  system_design:
    '<rect x="8" y="2" width="8" height="6" rx="1"/><rect x="1" y="16" width="8" height="6" rx="1"/><rect x="15" y="16" width="8" height="6" rx="1"/><path d="M12 8v4M5 16v-4h14v4"/>',
  arrow: '<path d="M5 12h14m-5-5 5 5-5 5"/>',
  check: '<path d="m5 12 4 4L19 6"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  play: '<path d="m8 4 12 8-12 8Z"/>',
};
export function icon(name) {
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${icons[name] || icons.arrow}</svg>`;
}
export function brand() {
  return '<div class="brand"><span>is<span class="brand-dot">.</span></span>interview studio</div>';
}
export function modeName(mode) {
  return mode === "assessment" ? "Timed assessment" : "Guided practice";
}
export function statusName(status) {
  return (
    {
      draft: "Not started",
      preparing: "Preparing",
      ready: "Ready to start",
      active: "In progress",
      submitted: "Submitted",
    }[status] || status
  );
}
export function renderBrief(text) {
  const inline = (text) => esc(text).replace(/`([^`]+)`/g, "<code>$1</code>");
  return text
    .replace(/^(#{1,3} [^\n]+)\n(?=\S)/gm, "$1\n\n")
    .split(/\n\s*\n/)
    .map((block) => {
      if (/^# /.test(block)) return "";
      if (/^#{2,3} /.test(block))
        return `<h4>${inline(block.replace(/^#+ /, ""))}</h4>`;
      if (block.split("\n").every((line) => /^[-*] /.test(line)))
        return `<ul>${block
          .split("\n")
          .map((line) => `<li>${inline(line.slice(2))}</li>`)
          .join("")}</ul>`;
      return `<p>${inline(block).replaceAll("\n", "<br>")}</p>`;
    })
    .join("");
}
