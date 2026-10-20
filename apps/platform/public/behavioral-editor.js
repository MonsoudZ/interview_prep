export function createBehavioralEditor(
  parent,
  { onChange, onPosition, onSave },
) {
  parent.innerHTML =
    '<div class="behavioral-writing"><div class="behavioral-writing-tools"><span id="behavioral-word-count"></span><button id="behavioral-show-search" type="button">Find in response</button><button id="behavioral-export" type="button">Export text</button></div><div id="behavioral-search" hidden><label>Find text<input type="search" id="behavioral-find-text"></label><button id="behavioral-find-next">Find next</button></div><label id="behavioral-writing-label" for="behavioral-response">Your rehearsed answer</label><textarea id="behavioral-response" spellcheck="true" maxlength="200000"></textarea><details><summary>Source lines for review citations</summary><pre id="behavioral-source-lines"></pre></details></div>';
  const text = parent.querySelector("#behavioral-response");
  let current = null,
    locked = false;
  const position = () => ({
    anchor: text.selectionStart,
    head: text.selectionEnd,
    top: text.scrollTop,
    left: 0,
  });
  function counters() {
    parent.querySelector("#behavioral-word-count").textContent =
      `${wordCount(text.value)} words · typed rehearsal`;
    parent.querySelector("#behavioral-source-lines").textContent = text.value
      .split("\n")
      .map((line, i) => `${i + 1}  ${line}`)
      .join("\n");
  }
  function search() {
    parent.querySelector("#behavioral-search").hidden = false;
    parent.querySelector("#behavioral-find-text").focus();
  }
  text.oninput = () => {
    if (!locked) {
      counters();
      onChange(current, text.value);
      onPosition(current, position());
    }
  };
  text.onselect = () => current && onPosition(current, position());
  text.onscroll = () => current && onPosition(current, position());
  text.onkeydown = (event) => {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
      event.preventDefault();
      onSave();
    }
  };
  parent.querySelector("#behavioral-show-search").onclick = search;
  parent.querySelector("#behavioral-find-next").onclick = () => {
    const query = parent.querySelector("#behavioral-find-text").value;
    if (!query) return;
    const at = text.value
      .toLowerCase()
      .indexOf(query.toLowerCase(), text.selectionEnd);
    const found =
      at < 0 ? text.value.toLowerCase().indexOf(query.toLowerCase()) : at;
    if (found >= 0) {
      text.focus();
      text.setSelectionRange(found, found + query.length);
    }
  };
  parent.querySelector("#behavioral-export").onclick = () => {
    const url = URL.createObjectURL(
      new Blob([text.value], { type: "text/plain;charset=utf-8" }),
    );
    const a = document.createElement("a");
    a.href = url;
    a.download = current || "response.md";
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  };
  return {
    open(path, value, readOnly, saved = {}) {
      if (current !== path || text.value !== value) {
        current = path;
        text.value = value;
        text.setSelectionRange(
          Math.min(saved.anchor || 0, value.length),
          Math.min(saved.head || 0, value.length),
        );
        text.scrollTop = saved.top || 0;
      }
      locked = readOnly;
      text.readOnly = readOnly;
      parent.querySelector("#behavioral-writing-label").textContent =
        path === "answer.md"
          ? "Your rehearsed answer"
          : "Preparation notes · not the rehearsed answer";
      counters();
    },
    setReadOnly(value) {
      locked = value;
      text.readOnly = value;
    },
    position,
    search,
    focus() {
      text.focus();
    },
    jump(line) {
      const at =
        text.value
          .split("\n")
          .slice(0, Math.max(0, line - 1))
          .join("\n").length + (line > 1 ? 1 : 0);
      text.focus();
      text.setSelectionRange(at, at);
      text.scrollTop = Math.max(0, line - 3) * 26;
    },
    destroy() {
      parent.replaceChildren();
    },
  };
}
export const wordCount = (text) =>
  text.trim() ? text.trim().split(/\s+/u).length : 0;
