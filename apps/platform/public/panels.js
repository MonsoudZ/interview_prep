import { clamp } from "./workspace-state.js";
export function mountPanels(workspace, layout, onChange) {
  const cleanups = [];
  function apply() {
    // Leave room for at least 280px of source and both resize handles.
    const available = workspace.clientWidth - 12;
    const files = clamp(
      layout.files,
      140,
      Math.min(320, Math.max(140, available - 540)),
      200,
    );
    const brief = clamp(
      layout.brief,
      260,
      Math.min(520, Math.max(260, available - files - 280)),
      350,
    );
    const output = clamp(
      layout.output,
      140,
      Math.max(140, Math.min(600, workspace.clientHeight - 250)),
      240,
    );
    workspace.style.setProperty("--files-width", `${files}px`);
    workspace.style.setProperty("--brief-width", `${brief}px`);
    workspace.style.setProperty("--output-height", `${output}px`);
    for (const handle of workspace.querySelectorAll("[data-resize]")) {
      const name = handle.dataset.resize;
      handle.setAttribute(
        "aria-valuenow",
        String(Math.round({ files, brief, output }[name])),
      );
    }
  }
  for (const handle of workspace.querySelectorAll("[data-resize]")) {
    const name = handle.dataset.resize,
      vertical = name === "output";
    function change(delta) {
      layout[name] = clamp(
        layout[name] + delta,
        name === "files" ? 140 : name === "brief" ? 260 : 140,
        name === "files" ? 320 : name === "brief" ? 520 : 600,
      );
      apply();
      onChange({ ...layout });
    }
    const onKey = (event) => {
      const direction = vertical
        ? { ArrowUp: 1, ArrowDown: -1 }
        : {
            ArrowLeft: name === "brief" ? 1 : -1,
            ArrowRight: name === "brief" ? -1 : 1,
          };
      if (event.key in direction) {
        event.preventDefault();
        change(direction[event.key] * (event.shiftKey ? 40 : 10));
      }
      if (event.key === "Home") {
        event.preventDefault();
        layout[name] = { files: 200, brief: 350, output: 240 }[name];
        apply();
        onChange({ ...layout });
      }
    };
    let stopDrag = () => {};
    const onPointer = (event) => {
      if (event.button !== 0) return;
      event.preventDefault();
      stopDrag();
      handle.focus();
      let last = vertical ? event.clientY : event.clientX;
      workspace.classList.add("resizing");
      const move = (event) => {
        const at = vertical ? event.clientY : event.clientX;
        change((at - last) * (name === "files" ? 1 : -1));
        last = at;
      };
      stopDrag = () => {
        window.removeEventListener("pointermove", move);
        window.removeEventListener("pointerup", stopDrag);
        window.removeEventListener("pointercancel", stopDrag);
        workspace.classList.remove("resizing");
      };
      window.addEventListener("pointermove", move);
      window.addEventListener("pointerup", stopDrag);
      window.addEventListener("pointercancel", stopDrag);
    };
    handle.addEventListener("pointerdown", onPointer);
    handle.addEventListener("keydown", onKey);
    cleanups.push(() => {
      stopDrag();
      handle.removeEventListener("pointerdown", onPointer);
      handle.removeEventListener("keydown", onKey);
    });
  }
  const observer = new ResizeObserver(apply);
  observer.observe(workspace);
  apply();
  return {
    destroy() {
      observer.disconnect();
      cleanups.forEach((fn) => fn());
    },
  };
}
