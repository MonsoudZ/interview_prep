import test from "node:test";
import assert from "node:assert/strict";
import {
  parseDiagram,
  serializeDiagram,
  designHistory,
  removeComponent,
  diagramBounds,
  exportDiagram,
  previewDiagram,
  exportNotes,
} from "../../public/design-model.js";
const node = (id, x = 0) => ({
  id,
  kind: "service",
  label: "Service " + id,
  detail: "Owns durable acceptance",
  x,
  y: 30,
});
const diagram = () => ({
  version: 1,
  nodes: [node("ingest"), node("queue", 280)],
  edges: [{ id: "flow", from: "ingest", to: "queue", label: "accepted event" }],
});
test("diagram validation rejects unsafe or ambiguous documents, not harmless label text", () => {
  assert.deepEqual(parseDiagram(serializeDiagram(diagram())), diagram());
  const mutations = [
    (d) => d.nodes.push({ ...d.nodes[0] }),
    (d) => (d.edges[0].to = "missing"),
    (d) => (d.edges[0].id = "ingest"),
    (d) => (d.edges[0].to = "ingest"),
    (d) => (d.nodes[0].x = Infinity),
    (d) => (d.nodes[0].x = -1),
    (d) => (d.nodes[0].kind = "script"),
    (d) => (d.nodes[0].html = "<script>"),
    (d) => (d.version = 2),
    (d) => (d.nodes[0].label = " "),
    (d) => d.edges.push({ ...d.edges[0] }),
  ];
  for (const mutate of mutations) {
    const doc = diagram();
    mutate(doc);
    assert.throws(() => parseDiagram(serializeDiagram(doc)));
  }
  const document = diagram();
  document.nodes[0].label = "<script>alert(1)</script>";
  assert.ok(parseDiagram(serializeDiagram(document)));
});
test("undo and redo preserve exact node and edge edits without retaining mutable aliases", () => {
  const changes = [],
    original = diagram(),
    history = designHistory(original, (d) => changes.push(d));
  original.nodes[0].x = 99;
  history.change((d) => {
    d.nodes[0].x = 500;
    removeComponent(d, "queue");
  });
  assert.equal(history.value.edges.length, 0);
  assert.equal(history.value.nodes[0].x, 500);
  history.undo();
  assert.deepEqual(history.value, diagram());
  history.redo();
  assert.equal(history.value.nodes.length, 1);
  history.undo();
  history.change((d) => (d.nodes[0].label = "New name"));
  assert.equal(history.canRedo, false);
  const exposed = history.value;
  exposed.nodes[0].x = 999;
  assert.equal(history.value.nodes[0].x, 0);
  assert.equal(changes.length, 5);
});
test("invalid changes leave history and the published document untouched", () => {
  const history = designHistory(diagram(), () =>
    assert.fail("invalid edit published"),
  );
  assert.throws(() => history.change((d) => (d.edges[0].to = "missing")));
  assert.deepEqual(history.value, diagram());
  assert.equal(history.canUndo, false);
});
test("exports preserve every notes section and escape SVG labels; review previews need no inline style or controls", () => {
  const document = diagram();
  document.nodes[0].label = '"<script> & API';
  document.edges[0].label = '<img onerror="x">';
  const svg = exportDiagram(document),
    preview = previewDiagram(document);
  assert.ok(svg.startsWith("<svg"));
  assert.ok(svg.includes("&lt;script&gt;"));
  assert.ok(!svg.includes("<script>"));
  assert.ok(!svg.includes("<img"));
  assert.ok(preview.includes("Submitted architecture diagram"));
  assert.ok(!preview.includes("<style>"));
  assert.ok(!preview.includes('role="button"'));
  assert.ok(!preview.includes("tabindex"));
  const markdown = exportNotes({
    "requirements.md": "# Required\nAck after durable write",
    "notes.md": "# Handoff",
  });
  assert.ok(markdown.includes("Ack after durable write"));
  assert.ok(markdown.includes("Reliability"));
  assert.ok(markdown.includes("# Handoff"));
  const bounds = diagramBounds(document);
  assert.ok(bounds.x <= 0);
  assert.ok(bounds.width >= 460);
});
