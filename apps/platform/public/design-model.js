import { esc } from "./ui.js";
export const NOTE_SECTIONS = [
  ["requirements.md", "Requirements"],
  ["capacity.md", "Capacity"],
  ["api-data.md", "APIs & data"],
  ["reliability.md", "Reliability"],
  ["tradeoffs.md", "Tradeoffs"],
  ["notes.md", "Handoff"],
];
export const KINDS = [
  "client",
  "service",
  "database",
  "queue",
  "cache",
  "external",
];
const exact = (item, keys) =>
  item &&
  typeof item === "object" &&
  !Array.isArray(item) &&
  Object.keys(item).sort().join() === [...keys].sort().join();
const id = (value) =>
  typeof value === "string" && /^[A-Za-z0-9_-]{1,64}$/.test(value);
const string = (value, size) =>
  typeof value === "string" && [...value].length <= size;
export function parseDiagram(text) {
  const document = JSON.parse(text);
  if (
    !exact(document, ["version", "nodes", "edges"]) ||
    document.version !== 1 ||
    !Array.isArray(document.nodes) ||
    !Array.isArray(document.edges) ||
    document.nodes.length > 50 ||
    document.edges.length > 100
  )
    throw Error("Invalid architecture document");
  for (const node of document.nodes) {
    if (
      !exact(node, ["id", "kind", "label", "detail", "x", "y"]) ||
      !id(node.id) ||
      !KINDS.includes(node.kind) ||
      !string(node.label, 80) ||
      !node.label.trim() ||
      !string(node.detail, 1000) ||
      ![node.x, node.y].every((n) => Number.isFinite(n) && n >= 0 && n <= 4000)
    )
      throw Error("Invalid architecture component");
  }
  const nodes = new Set(document.nodes.map((node) => node.id));
  if (nodes.size !== document.nodes.length)
    throw Error("Duplicate component identity");
  for (const edge of document.edges) {
    if (
      !exact(edge, ["id", "from", "to", "label"]) ||
      !id(edge.id) ||
      nodes.has(edge.id) ||
      !string(edge.label, 120) ||
      !nodes.has(edge.from) ||
      !nodes.has(edge.to) ||
      edge.from === edge.to
    )
      throw Error("Invalid architecture connection");
  }
  if (
    new Set(document.edges.map((edge) => edge.id)).size !==
    document.edges.length
  )
    throw Error("Duplicate connection identity");
  return document;
}
export const serializeDiagram = (document) =>
  JSON.stringify(document, null, 2) + "\n";
const copy = (value) => JSON.parse(JSON.stringify(value));
export function designHistory(initial, onChange) {
  let document = copy(initial),
    past = [],
    future = [];
  const publish = () => onChange(copy(document));
  return {
    get value() {
      return copy(document);
    },
    get canUndo() {
      return past.length > 0;
    },
    get canRedo() {
      return future.length > 0;
    },
    change(update) {
      const next = copy(document);
      update(next);
      parseDiagram(serializeDiagram(next));
      if (JSON.stringify(document) === JSON.stringify(next)) return;
      past.push(document);
      past = past.slice(-100);
      future = [];
      document = next;
      publish();
    },
    undo() {
      if (!past.length) return;
      future.push(document);
      document = past.pop();
      publish();
    },
    redo() {
      if (!future.length) return;
      past.push(document);
      document = future.pop();
      publish();
    },
  };
}
export function removeComponent(document, id) {
  document.nodes = document.nodes.filter((node) => node.id !== id);
  document.edges = document.edges.filter(
    (edge) => edge.from !== id && edge.to !== id,
  );
}
export function diagramBounds(document) {
  if (!document.nodes.length) return { x: 0, y: 0, width: 1000, height: 650 };
  const left = Math.min(...document.nodes.map((n) => n.x)) - 50,
    top = Math.min(...document.nodes.map((n) => n.y)) - 65;
  return {
    x: left,
    y: top,
    width: Math.max(
      400,
      Math.max(...document.nodes.map((n) => n.x + 180)) - left + 50,
    ),
    height: Math.max(
      280,
      Math.max(...document.nodes.map((n) => n.y + 84)) - top + 65,
    ),
  };
}
export function diagramContents(document, selected = null) {
  const marker =
    '<defs><marker id="design-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 Z" fill="#718579"/></marker></defs>';
  const nodes = new Map(document.nodes.map((node) => [node.id, node]));
  const edges = document.edges
    .map((edge) => {
      const a = nodes.get(edge.from),
        b = nodes.get(edge.to);
      const dx = b.x - a.x,
        dy = b.y - a.y;
      const distance = Math.max(Math.abs(dx) / 90, Math.abs(dy) / 42, 1);
      const sx = a.x + 90 + dx / distance,
        sy = a.y + 42 + dy / distance;
      const ex = b.x + 90 - dx / distance,
        ey = b.y + 42 - dy / distance;
      return `<g class="design-edge ${selected === edge.id ? "selected" : ""}" data-edge="${esc(edge.id)}" role="button" tabindex="0" aria-label="Connection: ${esc(a.label)} to ${esc(b.label)}${edge.label ? ", " + esc(edge.label) : ""}"><path class="edge-hit" d="M${sx} ${sy} L${ex} ${ey}"/><path class="edge-line" marker-end="url(#design-arrow)" d="M${sx} ${sy} L${ex} ${ey}"/><text x="${(sx + ex) / 2}" y="${(sy + ey) / 2 - 9}" text-anchor="middle">${esc(edge.label)}</text></g>`;
    })
    .join("");
  const components = document.nodes
    .map(
      (node) =>
        `<g class="design-node kind-${node.kind} ${selected === node.id ? "selected" : ""}" data-node="${esc(node.id)}" transform="translate(${node.x},${node.y})" tabindex="0" role="button" aria-label="${esc(node.kind)}: ${esc(node.label)}"><rect width="180" height="84" rx="${node.kind === "database" || node.kind === "cache" ? 18 : 7}"/><text class="node-kind" x="14" y="23">${esc(node.kind.toUpperCase())}</text><text class="node-label" x="14" y="47">${esc([...node.label].slice(0, 21).join(""))}${[...node.label].length > 21 ? "…" : ""}</text><text class="node-detail" x="14" y="68">${esc([...node.detail.replaceAll("\n", " ")].slice(0, 27).join(""))}</text><title>${esc(node.label)}${node.detail ? ": " + esc(node.detail) : ""}</title></g>`,
    )
    .join("");
  return marker + edges + components;
}
export function previewDiagram(document) {
  parseDiagram(serializeDiagram(document));
  const bounds = diagramBounds(document);
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${bounds.x} ${bounds.y} ${bounds.width} ${bounds.height}" role="img" aria-label="Submitted architecture diagram">${diagramContents(
    document,
  )
    .replace(/ tabindex="0"/g, "")
    .replace(/ role="button"/g, "")}</svg>`;
}
export function exportDiagram(document) {
  parseDiagram(serializeDiagram(document));
  const bounds = diagramBounds(document);
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${bounds.x} ${bounds.y} ${bounds.width} ${bounds.height}" width="${bounds.width}" height="${bounds.height}" role="img" aria-label="Architecture diagram"><style>text{font-family:system-ui,sans-serif;fill:#203a2c;font-size:12px}.node-kind{font-size:10px;fill:#617869}.node-label{font-size:14px;font-weight:600}.node-detail{font-size:10px;fill:#617869}.design-node rect{fill:#f5f8f3;stroke:#9eafa1;stroke-width:1.5}.edge-line{fill:none;stroke:#718579;stroke-width:1.5}.edge-hit{fill:none;stroke:transparent;stroke-width:14}.design-edge text{paint-order:stroke;stroke:white;stroke-width:5px;stroke-linejoin:round}</style>${diagramContents(document)}</svg>`;
}
export function exportNotes(files) {
  return NOTE_SECTIONS.map(
    ([path, title]) => `<!-- ${title}: ${path} -->\n${files[path] || ""}`,
  ).join("\n\n---\n\n");
}
