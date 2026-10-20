import { esc, brand } from "./ui.js";
import { createRequestScope } from "./request-scope.js";
export const storyLabels = {
  situation: "Situation and stakes",
  task: "Your responsibility",
  actions: "Your specific actions",
  results: "Outcomes and evidence",
  reflection: "Reflection and learning",
  short_version: "Two-minute opening",
};
export function filterStories(stories, query = "", topic = "all") {
  const term = query.trim().toLowerCase();
  return stories.filter(
    (story) =>
      (topic === "all" || story.topics.includes(topic)) &&
      (!term ||
        `${story.title} ${story.topics.join(" ")} ${Object.values(story.sections || {}).join(" ")}`
          .toLowerCase()
          .includes(term)),
  );
}
export function storyText(story) {
  return [
    `# ${story.title}`,
    `Topics: ${story.topics.join(", ")}`,
    `Self-marked readiness: ${story.readiness}`,
    ...Object.entries(storyLabels).flatMap(([key, label]) => [
      `\n## ${label}`,
      story.sections[key] || "",
    ]),
  ].join("\n\n");
}
export function storyForm(story, exercises) {
  return `<div class="section-top"><div><h2>${esc(story.title)}</h2><p class="subtitle">${story.archived_at ? "Archived example · restore to edit" : "Your experience, in your own words"}</p></div><button id="archive-story">${story.archived_at ? "Restore" : "Archive"}</button></div><form id="story-form"><label>Example title<input name="title" maxlength="120" required value="${esc(story.title)}"></label><fieldset><legend>Useful for</legend>${["ownership", "incidents", "conflict", "mentoring", "tradeoffs"].map((topic) => `<label class="story-topic"><input type="checkbox" name="topic" value="${topic}" ${story.topics.includes(topic) ? "checked" : ""}>${esc(topic)}</label>`).join("")}</fieldset>${Object.entries(
    storyLabels,
  )
    .map(
      ([key, label]) =>
        `<label>${label}<textarea name="${key}" rows="${key === "actions" ? 5 : 3}" maxlength="6000">${esc(story.sections[key] || "")}</textarea></label>`,
    )
    .join(
      "",
    )}<label>Readiness<select name="readiness"><option value="draft" ${story.readiness === "draft" ? "selected" : ""}>Still developing</option><option value="ready" ${story.readiness === "ready" ? "selected" : ""}>Ready to rehearse · my assessment</option></select></label><div class="story-actions"><button type="submit" class="primary" id="save-story">Save example</button><button type="button" id="export-story">Export text</button></div></form><section class="story-rehearse"><h3>Rehearse this example</h3><p>Guided rehearsal captures this saved version. Later story edits won’t change the rehearsal. Timed attempts in Exercises start fresh.</p><label>Question<select id="story-question">${exercises.map((exercise) => `<option value="${exercise.id}" ${exercise.topic === story.topics[0] ? "selected" : ""}>${esc(exercise.title)}</option>`).join("")}</select></label><button id="rehearse-story" class="primary" ${story.archived_at ? "disabled" : ""}>Open guided rehearsal</button></section>`;
}
export function mountStories({
  root,
  api: request,
  notice,
  onBack,
  onOpenSession,
  initialId,
}) {
  const scope = createRequestScope(request),
    api = scope.request;
  let bank = null,
    current = null,
    draft = null,
    dirty = false,
    conflict = false,
    saving = null,
    saveTimer,
    archived = false,
    query = "",
    topic = "all",
    pending = false,
    requestId = crypto.randomUUID(),
    navigation = 0;
  function fail(error) {
    if (scope.alive) {
      const el = root.querySelector("#story-error");
      if (el) el.textContent = error.message;
      notice(error.message);
    }
  }
  function shell() {
    root.innerHTML = `<main class="stories-page"><div class="mock-top">${brand()}<button id="stories-back" class="quiet">← Practice</button></div><header class="page-header"><div><h1>Your story bank</h1><p>Keep specific examples ready for ownership, incidents, disagreement, mentoring, and tradeoffs.</p></div><button id="new-story" class="primary">New example</button></header><p class="subtitle">Use real events and credit collaborators. Observable outcomes are enough when exact metrics aren’t available. Leave confidential details out.</p><p id="story-error" role="alert" class="error"></p><p id="story-save-state" role="status"></p><div class="story-layout"><aside><label>Find an example<input id="story-search" type="search" value="${esc(query)}"></label><label>Theme<select id="story-topic-filter"><option value="all">All themes</option>${bank.topics.map((item) => `<option value="${item}" ${topic === item ? "selected" : ""}>${item}</option>`).join("")}</select></label><button id="story-archives" class="quiet">${archived ? "Current examples" : "Archived examples"}</button><div id="story-list"></div></aside><section id="story-editor"><p>Choose an example or create one. Drafts are welcome; you don’t need a polished story to start.</p></section></div></main>`;
    root.querySelector("#stories-back").onclick = async () => {
      try {
        await save();
        if (scope.alive) onBack();
      } catch (error) {
        fail(error);
      }
    };
    root.querySelector("#new-story").onclick = async () => {
      if (pending) return;
      ++navigation;
      pending = true;
      try {
        await save();
        const value = await api("/api/stories", "POST", {
          client_request_id: requestId,
          story: {
            title: "Untitled example",
            topics: ["ownership"],
            sections: Object.fromEntries(
              Object.keys(storyLabels).map((key) => [key, ""]),
            ),
            readiness: "draft",
          },
        });
        requestId = crypto.randomUUID();
        if (archived) {
          archived = false;
          current = null;
          await load();
        } else bank.stories.unshift(value);
        open(value);
      } catch (error) {
        fail(error);
      } finally {
        pending = false;
      }
    };
    root.querySelector("#story-search").oninput = (event) => {
      query = event.target.value;
      renderList();
    };
    root.querySelector("#story-topic-filter").onchange = (event) => {
      topic = event.target.value;
      renderList();
    };
    root.querySelector("#story-archives").onclick = async () => {
      if (pending) return;
      pending = true;
      ++navigation;
      try {
        await save();
        archived = !archived;
        current = null;
        draft = null;
        await load();
      } catch (error) {
        fail(error);
      } finally {
        pending = false;
      }
    };
    renderList();
    if (current) renderEditor();
  }
  function renderList() {
    const host = root.querySelector("#story-list");
    if (!host) return;
    const visible = filterStories(bank.stories, query, topic);
    host.innerHTML = visible.length
      ? visible
          .map(
            (story) =>
              `<button class="story-list-item ${current?.id === story.id ? "selected" : ""}" data-story="${story.id}" aria-pressed="${current?.id === story.id}"><strong>${esc(story.title)}</strong><span>${esc(story.topics.join(" · "))}</span><small>${story.readiness === "ready" ? "Ready to rehearse" : "Still developing"}</small></button>`,
          )
          .join("")
      : "<p>No examples match this view.</p>";
    host.querySelectorAll("[data-story]").forEach(
      (button) =>
        (button.onclick = async () => {
          if (pending) return;
          const epoch = ++navigation;
          try {
            await save();
            const value = await api(`/api/stories/${button.dataset.story}`);
            if (scope.alive && epoch === navigation) open(value);
          } catch (error) {
            fail(error);
          }
        }),
    );
  }
  function open(story) {
    rehearsalRequest = null;
    const errorNode = root.querySelector("#story-error");
    if (errorNode) errorNode.textContent = "";
    current = story;
    draft = {
      title: story.title,
      topics: [...story.topics],
      sections: { ...story.sections },
      readiness: story.readiness,
    };
    dirty = false;
    conflict = false;
    window.history.replaceState(null, "", `#stories/${story.id}`);
    renderEditor();
    renderList();
    status("Saved");
  }
  function status(text) {
    const el = root.querySelector("#story-save-state");
    if (el) el.textContent = text;
  }
  function renderEditor() {
    const host = root.querySelector("#story-editor");
    host.innerHTML = storyForm(current, bank.exercises);
    const form = host.querySelector("#story-form");
    if (current.archived_at)
      form
        .querySelectorAll("input,textarea,select,button:not(#export-story)")
        .forEach((el) => (el.disabled = true));
    form.oninput = () => {
      draft = {
        title: form.elements.title.value,
        topics: [...form.querySelectorAll("[name=topic]:checked")].map(
          (el) => el.value,
        ),
        sections: Object.fromEntries(
          Object.keys(storyLabels).map((key) => [
            key,
            form.elements[key].value,
          ]),
        ),
        readiness: form.elements.readiness.value,
      };
      dirty = true;
      status("Unsaved changes");
      clearTimeout(saveTimer);
      saveTimer = setTimeout(() => save().catch(fail), 1000);
    };
    form.onsubmit = (event) => {
      event.preventDefault();
      save().catch(fail);
    };
    host.querySelector("#archive-story").onclick = async () => {
      if (pending) return;
      ++navigation;
      pending = true;
      try {
        await save();
        const value = await api(`/api/stories/${current.id}`, "PATCH", {
          command: current.archived_at ? "restore" : "archive",
          expected_version: current.version,
        });
        bank.stories = bank.stories.filter((item) => item.id !== value.id);
        if (!!value.archived_at === archived) bank.stories.unshift(value);
        open(value);
      } catch (error) {
        fail(error);
      } finally {
        pending = false;
      }
    };
    host.querySelector("#export-story").onclick = () => {
      const url = URL.createObjectURL(
        new Blob([storyText({ ...current, ...draft })], {
          type: "text/plain;charset=utf-8",
        }),
      );
      const link = document.createElement("a");
      link.href = url;
      link.download = `story-${current.id}.txt`;
      link.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    };
    host.querySelector("#rehearse-story").onclick = async () => {
      if (pending) return;
      ++navigation;
      pending = true;
      const button = host.querySelector("#rehearse-story");
      button.disabled = true;
      try {
        await save();
        const value = await api(`/api/stories/${current.id}/rehearse`, "POST", {
          exercise_id: host.querySelector("#story-question").value,
          expected_version: current.version,
          client_request_id: rehearsalId(),
        });
        if (scope.alive) await onOpenSession(value.id, { returnStories: true });
      } catch (error) {
        fail(error);
      } finally {
        pending = false;
        if (scope.alive) button.disabled = false;
      }
    };
  }
  let rehearsalRequest = null;
  function rehearsalId() {
    return (rehearsalRequest ||= crypto.randomUUID());
  }
  async function save() {
    clearTimeout(saveTimer);
    if (saving) {
      await saving;
      if (dirty) return save();
      return;
    }
    if (!dirty) return;
    if (conflict)
      throw new Error(
        "Your text is kept here. Copy or export it before reloading the changed story.",
      );
    const previous = current,
      text = JSON.stringify(draft),
      content = JSON.parse(text);
    status("Saving…");
    saving = api(`/api/stories/${previous.id}`, "PATCH", {
      command: "save",
      expected_version: previous.version,
      story: content,
    })
      .then((remote) => {
        current = remote;
        dirty = JSON.stringify(draft) !== text;
        const i = bank.stories.findIndex((item) => item.id === remote.id);
        if (i >= 0) bank.stories[i] = remote;
        rehearsalRequest = null;
        const errorNode = root.querySelector("#story-error");
        if (errorNode) errorNode.textContent = "";
        status(dirty ? "Unsaved changes" : "Saved");
        const heading = root.querySelector("#story-editor h2");
        if (heading) heading.textContent = remote.title;
        renderList();
      })
      .catch((error) => {
        if (error.status === 409) {
          conflict = true;
          const host = root.querySelector("#story-editor");
          if (host && !host.querySelector("#reload-story")) {
            const button = document.createElement("button");
            button.id = "reload-story";
            button.textContent = "Reload saved example";
            button.onclick = async () => {
              if (
                !window.confirm(
                  "Discard the text on this page and load the saved example? Export first if you want to keep your changes.",
                )
              )
                return;
              try {
                const value = await api(`/api/stories/${current.id}`);
                if (scope.alive) open(value);
              } catch (error) {
                fail(error);
              }
            };
            host.prepend(button);
          }
        }
        status(
          "Save failed · text kept in this page. Export it before reloading.",
        );
        throw error;
      })
      .finally(() => {
        saving = null;
      });
    await saving;
    if (dirty) return save();
  }
  async function load() {
    const epoch = ++navigation;
    const value = await api(`/api/stories${archived ? "?archived=true" : ""}`);
    if (!scope.alive || epoch !== navigation) return;
    bank = value;
    window.history.replaceState(
      null,
      "",
      current ? `#stories/${current.id}` : "#stories",
    );
    shell();
  }
  const ready = (async () => {
    await load();
    if (initialId && scope.alive) {
      const epoch = navigation;
      const value = await api(`/api/stories/${initialId}`);
      if (scope.alive && epoch === navigation) open(value);
    }
  })().catch(fail);
  return {
    load: () => ready,
    get hasUnsavedChanges() {
      return dirty || !!saving;
    },
    destroy() {
      clearTimeout(saveTimer);
      scope.destroy();
    },
  };
}
