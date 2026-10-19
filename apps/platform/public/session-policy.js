const pending = (execution) => ["queued", "leased"].includes(execution.status);

export function editorReadOnly(session, path, conflict = false) {
  return (
    conflict ||
    session.status === "submitted" ||
    !session.editable_paths.includes(path)
  );
}

// Presentation rules only. Rails remains the authority for every transition.
export function sessionPolicy(
  session,
  {
    openingRevision,
    autoPreparing = false,
    autoPreparationAttempted = false,
    busy = new Set(),
    conflict = false,
  } = {},
) {
  const submitted = session.status === "submitted";
  const beforeStart = ["draft", "ready"].includes(session.status);
  const preparation = session.executions.find(
    (execution) =>
      execution.purpose === "prepare" &&
      execution.revision === session.revision,
  );
  const preparing = preparation && pending(preparation);
  function nextAction() {
    if (submitted)
      return "This submission is read-only. Open the review to add notes.";
    if (session.status === "active")
      return session.track === "system_design"
        ? "Develop the architecture and reasoning. Submit when finished."
        : "Run tests as you work. Submit when finished.";
    if (session.status === "ready")
      return "Environment ready. Start the session when you’re ready to work.";
    if (!session.executable)
      return session.track === "system_design"
        ? "Read the brief, then start your design session."
        : "Read the brief, then start your writing session.";
    if (preparing)
      return session.worker_available
        ? "Preparing the environment. Read the brief while it starts."
        : "Preparation queued. Waiting for a worker to connect.";
    if (!session.worker_available)
      return "Read the brief. Preparation will start when a worker connects.";
    if (session.revision !== openingRevision)
      return "Code changed since preparation. Prepare this revision before starting.";
    if (preparation)
      return "Preparation needs attention. Check Runs, then retry.";
    if (autoPreparationAttempted && !autoPreparing)
      return "Preparation could not be queued. Retry when ready.";
    return "Preparing your coding environment…";
  }
  const buttons = {
    prepare: {
      hidden:
        !session.executable ||
        session.status === "active" ||
        submitted ||
        session.status === "ready" ||
        !!preparing ||
        autoPreparing,
      disabled: !session.executable || !beforeStart,
      label: preparation ? "Retry preparation" : "Prepare environment",
    },
    start: {
      hidden: session.status === "active" || submitted,
      disabled:
        !beforeStart ||
        (session.mode === "assessment" &&
          session.executable &&
          session.status !== "ready"),
    },
    run: {
      hidden: !session.executable || submitted,
      disabled:
        !session.executable || submitted || session.executions.some(pending),
    },
    save: { hidden: submitted, disabled: submitted },
    submit: { hidden: submitted, disabled: session.status !== "active" },
    "review-shortcut": { hidden: !submitted, disabled: false },
  };
  for (const [action, control] of Object.entries(buttons)) {
    control.disabled ||=
      busy.has(action) ||
      (conflict &&
        ["prepare", "start", "run", "save", "submit"].includes(action));
  }
  return {
    submitted,
    buttons,
    nextAction: nextAction(),
    workerState: session.executable
      ? session.worker_available
        ? "Worker connected"
        : "Worker offline · Test runs will wait in the queue."
      : "Writing workspace · Execution and AI tools upcoming",
    newFileHidden: submitted || session.track !== "rails",
  };
}
