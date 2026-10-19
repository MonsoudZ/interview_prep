import { EditorState, Compartment } from "@codemirror/state";
import { EditorView, keymap } from "@codemirror/view";
import { basicSetup } from "codemirror";
import { indentWithTab } from "@codemirror/commands";
import { StreamLanguage, indentUnit } from "@codemirror/language";
import { ruby } from "@codemirror/legacy-modes/mode/ruby";
import { yaml } from "@codemirror/legacy-modes/mode/yaml";
import { markdown } from "@codemirror/lang-markdown";
import { json } from "@codemirror/lang-json";
import { openSearchPanel } from "@codemirror/search";
import { oneDark } from "@codemirror/theme-one-dark";

// Retain undo history while switching files. Only cursor/scroll metadata leaves memory.
export function createEditor(parent, { onChange, onPosition, onSave, onRun }) {
  const language = new Compartment(),
    editable = new Compartment();
  const documents = new Map();
  let current = null,
    restoring = false;
  const chooseLanguage = (path) =>
    path.endsWith(".md")
      ? [markdown(), EditorView.lineWrapping]
      : path.endsWith(".json")
        ? json()
        : /\.ya?ml$/.test(path)
          ? StreamLanguage.define(yaml)
          : /\.rb$/.test(path) || path === "Gemfile"
            ? StreamLanguage.define(ruby)
            : [];
  const theme = EditorView.theme(
    {
      "&": { height: "100%", fontSize: "13px", backgroundColor: "#182323" },
      ".cm-scroller": {
        overflow: "auto",
        fontFamily: "ui-monospace,SFMono-Regular,Menlo,monospace",
        lineHeight: "1.8",
      },
      ".cm-content": { padding: "18px 0", caretColor: "#cfe6c7" },
      ".cm-line": { padding: "0 20px 0 8px" },
      ".cm-gutters": {
        backgroundColor: "#182323",
        color: "#657d70",
        border: "none",
        paddingRight: "8px",
      },
      ".cm-activeLine,.cm-activeLineGutter": { backgroundColor: "#24332e" },
      ".cm-panels": { backgroundColor: "#24332e", color: "#d6e4d7" },
      ".cm-search": { padding: "10px" },
      ".cm-textfield": {
        backgroundColor: "#172520",
        border: "1px solid #5a7364",
        color: "#e5eee1",
      },
      ".cm-button": {
        backgroundImage: "none",
        backgroundColor: "#344b3f",
        color: "#e5eee1",
        border: "1px solid #61765f",
      },
      "&.cm-focused": { outline: "none" },
      ".cm-selectionBackground": { backgroundColor: "#3c5546 !important" },
    },
    { dark: true },
  );
  const extensions = [
    basicSetup,
    oneDark,
    theme,
    EditorView.cspNonce.of(
      document.querySelector('meta[name="style-nonce"]')?.content || "",
    ),
    EditorView.contentAttributes.of({
      "aria-label": "Source editor",
      spellcheck: "false",
      tabindex: "0",
    }),
    indentUnit.of("  "),
    keymap.of([
      {
        key: "Mod-s",
        run: () => {
          onSave();
          return true;
        },
      },
      {
        key: "Mod-Enter",
        run: () => {
          onRun();
          return true;
        },
      },
      indentWithTab,
    ]),
    language.of([]),
    editable.of([EditorState.readOnly.of(false), EditorView.editable.of(true)]),
    EditorView.updateListener.of((update) => {
      if (restoring || !current) return;
      if (update.docChanged) onChange(current, update.state.doc.toString());
      if (update.selectionSet || update.docChanged || update.viewportChanged)
        onPosition(current, position());
    }),
    EditorView.domEventHandlers({
      scroll: () => {
        if (!restoring && current) onPosition(current, position());
      },
    }),
  ];
  const view = new EditorView({
    parent,
    state: EditorState.create({ extensions }),
  });
  function position() {
    const { anchor, head } = view.state.selection.main;
    return {
      anchor,
      head,
      top: view.scrollDOM.scrollTop,
      left: view.scrollDOM.scrollLeft,
    };
  }
  function remember() {
    if (current)
      documents.set(current, {
        state: view.state,
        scroll: view.scrollSnapshot(),
      });
  }
  return {
    open(path, text, readOnly, saved = {}) {
      if (current === path && view.state.doc.toString() === text) {
        this.setReadOnly(readOnly);
        return;
      }
      remember();
      restoring = true;
      current = path;
      const previous = documents.get(path);
      let state;
      if (previous && previous.state.doc.toString() === text) {
        view.setState(previous.state);
        view.dispatch({
          effects: [
            language.reconfigure(chooseLanguage(path)),
            editable.reconfigure([
              EditorState.readOnly.of(readOnly),
              EditorView.editable.of(!readOnly),
            ]),
            previous.scroll,
          ],
        });
      } else {
        // Start from the configured state; discard history only for a new/external document.
        const anchor = Math.min(
            Math.max(Number(saved.anchor) || 0, 0),
            text.length,
          ),
          head = Math.min(Math.max(Number(saved.head) || 0, 0), text.length);
        state = EditorState.create({
          doc: text,
          selection: { anchor, head },
          extensions,
        });
        view.setState(state);
        view.dispatch({
          effects: [
            language.reconfigure(chooseLanguage(path)),
            editable.reconfigure([
              EditorState.readOnly.of(readOnly),
              EditorView.editable.of(!readOnly),
            ]),
          ],
        });
        view.requestMeasure({
          read: () => null,
          write: () => {
            view.scrollDOM.scrollTop = Math.max(0, Number(saved.top) || 0);
            view.scrollDOM.scrollLeft = Math.max(0, Number(saved.left) || 0);
          },
        });
      }
      restoring = false;
    },
    setReadOnly(value) {
      if (view.state.readOnly !== value)
        view.dispatch({
          effects: editable.reconfigure([
            EditorState.readOnly.of(value),
            EditorView.editable.of(!value),
          ]),
        });
    },
    search() {
      openSearchPanel(view);
    },
    jump(line) {
      const at = view.state.doc.line(
        Math.min(Math.max(1, line), view.state.doc.lines),
      );
      view.dispatch({
        selection: { anchor: at.from },
        effects: EditorView.scrollIntoView(at.from, { y: "center" }),
      });
      view.focus();
    },
    position,
    focus() {
      view.focus();
    },
    destroy() {
      remember();
      view.destroy();
      documents.clear();
    },
  };
}
