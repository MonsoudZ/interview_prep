import { createEditor } from "./editor.bundle.js?v=1";
import { esc } from "./ui.js";
import {
  NOTE_SECTIONS,
  KINDS,
  parseDiagram,
  serializeDiagram,
  designHistory,
  removeComponent,
  diagramBounds,
  diagramContents,
  exportDiagram,
  exportNotes,
} from "./design-model.js";

export function createDesignEditor(
  parent,
  { files, onChange, onPosition, onSave, onSelect, notice },
) {
  const controller = new AbortController();
  let readOnly = false,
    selected = null,
    current = "requirements.md",
    dragging = null,
    view;
  const initial = parseDiagram(files["diagram.json"]);
  view = diagramBounds(initial);
  parent.innerHTML = `<div class="design-layout"><section class="design-board" aria-label="Architecture workspace">
    <div class="design-toolbar"><label>Component<select id="component-kind" aria-label="Component">${KINDS.map((kind) => `<option>${kind}</option>`).join("")}</select></label><button id="add-component">Add component</button><span class="spacer"></span><button id="design-undo" title="Undo diagram change">Undo</button><button id="design-redo" title="Redo diagram change">Redo</button></div>
    <div class="design-canvas-wrap"><svg id="design-canvas" tabindex="0" role="group" aria-label="Architecture canvas"></svg><p id="diagram-empty">Start with one component.<br>Add a service, queue, database, or client, then connect the flow.</p><div class="canvas-view"><button id="zoom-out" aria-label="Zoom out">−</button><button id="fit-diagram">Fit</button><button id="zoom-in" aria-label="Zoom in">+</button></div></div>
    <div class="design-inspector"><div id="component-inspector"></div><form id="connect-components"><h4>Data flow</h4><div class="connection-fields"><label>From<select id="connection-from" aria-label="From"></select></label><label>To<select id="connection-to" aria-label="To"></select></label></div><label>Connection label<input id="connection-label" maxlength="120" placeholder="e.g. append accepted event"></label><button type="submit">Connect components</button></form><div id="connection-list"></div></div>
    <div class="design-footer"><span id="diagram-status" role="status"></span><label>Export<select id="design-export" aria-label="Export"><option value="">Choose format…</option><option value="svg">Architecture SVG</option><option value="json">Diagram JSON</option><option value="md">All notes Markdown</option></select></label></div>
    </section><section class="design-notes" aria-label="Design notes"><div class="design-notes-head"><label>Notes section<select id="notes-section" aria-label="Notes section">${NOTE_SECTIONS.map(([path, title]) => `<option value="${path}">${title}</option>`).join("")}</select></label><span id="notes-status">Autosaves with architecture</span></div><div id="design-notes-editor"></div></section></div>`;
  const $ = (selector) => parent.querySelector(selector);
  const canvas = $("#design-canvas");
  const history = designHistory(initial, (document) => {
    onChange("diagram.json", serializeDiagram(document));
    draw();
    updateControls();
  });
  const notes = createEditor($("#design-notes-editor"), {
    onChange,
    onPosition,
    onSave,
    onRun() {},
  });
  function draw(document = history.value) {
    canvas.setAttribute(
      "viewBox",
      `${view.x} ${view.y} ${view.width} ${view.height}`,
    );
    canvas.innerHTML = diagramContents(document, selected);
    $("#diagram-empty").hidden = document.nodes.length > 0;
    $("#diagram-status").textContent =
      `${document.nodes.length}/50 components · ${document.edges.length}/100 connections${readOnly ? " · read-only" : ""}`;
  }
  function updateControls() {
    $("#design-undo").disabled = readOnly || !history.canUndo;
    $("#design-redo").disabled = readOnly || !history.canRedo;
    $("#add-component").disabled = readOnly || history.value.nodes.length >= 50;
    $("#component-kind").disabled = readOnly;
    $("#connect-components")
      .querySelectorAll("input,select,button")
      .forEach(
        (control) =>
          (control.disabled =
            readOnly ||
            history.value.nodes.length < 2 ||
            history.value.edges.length >= 100),
      );
    $("#component-inspector")
      .querySelectorAll("input,textarea,button")
      .forEach((control) => (control.disabled = readOnly));
    $("#notes-status").textContent = readOnly
      ? "Preserved submission / read-only"
      : "Autosaves with architecture";
  }
  function connectionOptions() {
    const nodes = history.value.nodes;
    for (const name of ["from", "to"]) {
      const select = $(`#connection-${name}`),
        previous = select.value;
      select.innerHTML = nodes
        .map(
          (node) =>
            `<option value="${esc(node.id)}">${esc(node.label)}</option>`,
        )
        .join("");
      if (nodes.some((node) => node.id === previous)) select.value = previous;
      else if (name === "to" && nodes.length > 1) select.value = nodes[1].id;
    }
    $("#connection-list").innerHTML = history.value.edges.length
      ? `<p class="connection-list-title">Connections</p>${history.value.edges.map((edge) => `<button type="button" data-select-edge="${esc(edge.id)}">${esc(nodes.find((n) => n.id === edge.from).label)} → ${esc(nodes.find((n) => n.id === edge.to).label)}${edge.label ? ": " + esc(edge.label) : ""}</button>`).join("")}`
      : "";
  }
  function inspect() {
    const document = history.value,
      node = document.nodes.find((n) => n.id === selected),
      edge = document.edges.find((e) => e.id === selected);
    const host = $("#component-inspector");
    if (node) {
      host.innerHTML = `<h4>Selected ${esc(node.kind)}</h4><label>Name<input id="node-name" maxlength="80" value="${esc(node.label)}"></label><label>Responsibility<textarea id="node-detail" maxlength="1000" rows="2" placeholder="What does this component own?">${esc(node.detail)}</textarea></label><p class="diagram-help">Drag to move. Arrow keys move a focused component; Shift moves farther.</p><button id="delete-component" type="button">Remove component</button>`;
      $("#node-name").oninput = (event) => {
        const name = event.target.value;
        if (readOnly || !name.trim()) return;
        history.change(
          (doc) => (doc.nodes.find((n) => n.id === selected).label = name),
        );
        connectionOptions();
      };
      $("#node-name").onblur = () => {
        const field = $("#node-name");
        if (field)
          field.value =
            history.value.nodes.find((n) => n.id === selected)?.label || "";
      };
      $("#node-detail").oninput = (event) => {
        if (!readOnly)
          history.change(
            (doc) =>
              (doc.nodes.find((n) => n.id === selected).detail =
                event.target.value),
          );
      };
      $("#delete-component").onclick = () => {
        if (readOnly) return;
        history.change((doc) => removeComponent(doc, selected));
        selected = null;
        refresh();
      };
    } else if (edge) {
      host.innerHTML = `<h4>Selected connection</h4><label>Label<input id="edge-label" maxlength="120" value="${esc(edge.label)}"></label><button id="delete-connection" type="button">Remove connection</button>`;
      $("#edge-label").oninput = (event) => {
        if (!readOnly) {
          history.change(
            (doc) =>
              (doc.edges.find((e) => e.id === selected).label =
                event.target.value),
          );
          connectionOptions();
        }
      };
      $("#delete-connection").onclick = () => {
        if (!readOnly) {
          history.change(
            (doc) => (doc.edges = doc.edges.filter((e) => e.id !== selected)),
          );
          selected = null;
          refresh();
        }
      };
    } else
      host.innerHTML =
        '<p class="diagram-help">Select a component or connection to explain its role. A drawing should make the data flow clear; record guarantees and tradeoffs in the notes.</p>';
    updateControls();
  }
  function refresh() {
    draw();
    inspect();
    connectionOptions();
    updateControls();
  }
  function choose(id) {
    selected = id;
    refresh();
  }
  function point(event) {
    const transform = canvas.getScreenCTM();
    if (!transform) return { x: 0, y: 0 };
    return new DOMPoint(event.clientX, event.clientY).matrixTransform(
      transform.inverse(),
    );
  }
  function focusSelection() {
    if (controller.signal.aborted) return;
    const target =
      selected &&
      canvas.querySelector(
        `[data-node="${selected}"],[data-edge="${selected}"]`,
      );
    (target || canvas).focus({ preventScroll: true });
  }
  function endDrag(cancel = false) {
    if (!dragging) return;
    const drag = dragging;
    dragging = null;
    if (drag.kind === "pan") {
      if (cancel) view = drag.view;
      draw();
      focusSelection();
      return;
    }
    if (!cancel && !readOnly)
      history.change((doc) => {
        const node = doc.nodes.find((n) => n.id === drag.id);
        if (node) {
          node.x = drag.x;
          node.y = drag.y;
        }
      });
    draw();
    focusSelection();
  }
  canvas.addEventListener(
    "pointerdown",
    (event) => {
      if (event.button !== 0) return;
      const element = event.target.closest("[data-node],[data-edge]");
      if (!element) {
        choose(null);
        canvas.focus({ preventScroll: true });
        event.preventDefault();
        const inverse = canvas.getScreenCTM()?.inverse();
        if (inverse)
          dragging = {
            kind: "pan",
            inverse,
            origin: point(event),
            view: { ...view },
          };
        return;
      }
      const id = element.dataset.node || element.dataset.edge;
      choose(id);
      canvas.querySelector(`[data-node="${id}"],[data-edge="${id}"]`)?.focus();
      if (!element.dataset.node || readOnly) return;
      event.preventDefault();
      const node = history.value.nodes.find((n) => n.id === id),
        origin = point(event);
      dragging = {
        id,
        origin,
        initialX: node.x,
        initialY: node.y,
        x: node.x,
        y: node.y,
      };
    },
    { signal: controller.signal },
  );
  canvas.addEventListener(
    "click",
    (event) => {
      // Keyboard/screen-reader activation has no pointer coordinates.
      if (event.detail === 0) {
        const node = event.target.closest("[data-node],[data-edge]");
        if (node) {
          choose(node.dataset.node || node.dataset.edge);
          focusSelection();
        }
      }
    },
    { signal: controller.signal },
  );
  window.addEventListener(
    "pointermove",
    (event) => {
      if (!dragging) return;
      if (dragging.kind === "pan") {
        const at = new DOMPoint(event.clientX, event.clientY).matrixTransform(
          dragging.inverse,
        );
        view = {
          ...dragging.view,
          x: dragging.view.x - (at.x - dragging.origin.x),
          y: dragging.view.y - (at.y - dragging.origin.y),
        };
        draw();
        return;
      }
      if (readOnly) return;
      const at = point(event);
      dragging.x = Math.max(
        0,
        Math.min(4000, dragging.initialX + at.x - dragging.origin.x),
      );
      dragging.y = Math.max(
        0,
        Math.min(4000, dragging.initialY + at.y - dragging.origin.y),
      );
      const preview = history.value,
        node = preview.nodes.find((n) => n.id === dragging.id);
      node.x = dragging.x;
      node.y = dragging.y;
      draw(preview);
    },
    { signal: controller.signal },
  );
  window.addEventListener("pointerup", () => endDrag(), {
    signal: controller.signal,
  });
  window.addEventListener("pointercancel", () => endDrag(true), {
    signal: controller.signal,
  });
  canvas.addEventListener(
    "keydown",
    (event) => {
      const node = event.target.closest("[data-node]"),
        edge = event.target.closest("[data-edge]");
      if (event.key === "Escape") {
        endDrag(true);
        choose(null);
        return;
      }
      if (event.key === "Enter" || event.key === " ") {
        if (node || edge) {
          event.preventDefault();
          choose((node || edge).dataset[node ? "node" : "edge"]);
        }
        return;
      }
      const delta = {
        ArrowLeft: [-1, 0],
        ArrowRight: [1, 0],
        ArrowUp: [0, -1],
        ArrowDown: [0, 1],
      }[event.key];
      if (!readOnly && node && delta) {
        event.preventDefault();
        selected = node.dataset.node;
        history.change((doc) => {
          const item = doc.nodes.find((n) => n.id === selected),
            step = event.shiftKey ? 40 : 10;
          item.x = Math.max(0, Math.min(4000, item.x + delta[0] * step));
          item.y = Math.max(0, Math.min(4000, item.y + delta[1] * step));
        });
        canvas.querySelector(`[data-node="${selected}"]`)?.focus();
      }
    },
    { signal: controller.signal },
  );
  parent.addEventListener(
    "keydown",
    (event) => {
      if (
        event.defaultPrevented ||
        event.target.closest(".design-notes") ||
        event.target.matches("input,textarea,select")
      )
        return;
      if (
        (event.ctrlKey || event.metaKey) &&
        event.key.toLowerCase() === "z" &&
        !readOnly
      ) {
        event.preventDefault();
        endDrag(true);
        event.shiftKey ? history.redo() : history.undo();
        refresh();
      }
    },
    { signal: controller.signal },
  );
  $("#add-component").onclick = () => {
    if (readOnly || history.value.nodes.length >= 50) return;
    const kind = $("#component-kind").value,
      count = history.value.nodes.length,
      id = crypto.randomUUID();
    history.change((doc) =>
      doc.nodes.push({
        id,
        kind,
        label: kind[0].toUpperCase() + kind.slice(1) + " " + (count + 1),
        detail: "",
        x: 60 + (count % 3) * 280,
        y: 80 + Math.floor(count / 3) * 160,
      }),
    );
    selected = id;
    view = diagramBounds(history.value);
    refresh();
    $("#node-name").focus();
    $("#node-name").select();
  };
  $("#connect-components").onsubmit = (event) => {
    event.preventDefault();
    if (readOnly || history.value.edges.length >= 100) return;
    const from = $("#connection-from").value,
      to = $("#connection-to").value;
    if (!from || !to || from === to)
      return notice("Choose two different components to connect.");
    history.change((doc) =>
      doc.edges.push({
        id: crypto.randomUUID(),
        from,
        to,
        label: $("#connection-label").value,
      }),
    );
    $("#connection-label").value = "";
    refresh();
  };
  $("#connection-list").onclick = (event) => {
    const button = event.target.closest("[data-select-edge]");
    if (button) choose(button.dataset.selectEdge);
  };
  $("#design-undo").onclick = () => {
    if (!readOnly) {
      endDrag(true);
      history.undo();
      refresh();
    }
  };
  $("#design-redo").onclick = () => {
    if (!readOnly) {
      endDrag(true);
      history.redo();
      refresh();
    }
  };
  function zoom(factor) {
    const width = Math.max(250, Math.min(6000, view.width * factor)),
      height = (view.height * width) / view.width;
    view = {
      x: view.x + (view.width - width) / 2,
      y: view.y + (view.height - height) / 2,
      width,
      height,
    };
    draw();
  }
  $("#zoom-out").onclick = () => zoom(1.3);
  $("#zoom-in").onclick = () => zoom(1 / 1.3);
  $("#fit-diagram").onclick = () => {
    view = diagramBounds(history.value);
    draw();
  };
  $("#notes-section").onchange = (event) => onSelect(event.target.value);
  $("#design-export").onchange = (event) => {
    const format = event.target.value;
    if (!format) return;
    const content =
      format === "svg"
        ? exportDiagram(history.value)
        : format === "json"
          ? serializeDiagram(history.value)
          : exportNotes(files);
    const blob = new Blob([content], {
      type:
        format === "svg"
          ? "image/svg+xml"
          : format === "json"
            ? "application/json"
            : "text/markdown",
    });
    const url = URL.createObjectURL(blob),
      link = document.createElement("a");
    link.href = url;
    link.download = `interview-design.${format}`;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    event.target.value = "";
  };
  refresh();
  return {
    open(path, value, locked, position) {
      current = NOTE_SECTIONS.some(([file]) => file === path)
        ? path
        : "requirements.md";
      $("#notes-section").value = current;
      this.setReadOnly(locked);
      notes.open(current, files[current] || value || "", readOnly, position);
    },
    setReadOnly(locked) {
      if (locked === readOnly) return;
      if (locked && dragging) endDrag(true);
      readOnly = locked;
      notes.setReadOnly(locked);
      draw();
      updateControls();
    },
    position: () => notes.position(),
    search: () => notes.search(),
    jump: (line) => notes.jump(line),
    destroy() {
      controller.abort();
      endDrag(true);
      notes.destroy();
      parent.replaceChildren();
    },
  };
}
