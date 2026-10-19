// Runner text is untrusted evidence. Only render it as text, and never invent passing test names.
export function parseFailures(output = "") {
  const text = String(output).replace(/\x1b\[[0-9;]*m/g, "");
  // Some truncated outputs have no trailing suite summary; keep the last diagnostic too.
  const starts = [
    ...text.matchAll(/^\s*(?:\d+\)\s*)?(Failure|Error):\r?\n([^\n]+)\n/gm),
  ];
  return starts.slice(0, 100).map((match, index) => {
    let body = text.slice(
      match.index + match[0].length,
      starts[index + 1]?.index ?? text.length,
    );
    body = body
      .split(/^Finished in /m)[0]
      .replace(/^bin\/rails test .+$/gm, "")
      .replace(/\n[F.ES]+\s*$/, "")
      .trim();
    const header = match[2].trim(),
      location = header.match(/\[([^\]]+):(\d+)\]:?$/);
    const expected = body.match(
      /^Expected:\s*([\s\S]*?)\n\s*Actual:\s*([^\n]*(?:\n(?!\n|[A-Z][a-z]+:)[^\n]+)*)/m,
    );
    const response = body.match(
      /Expected response to be a <([^>]+)>.*?but was a <([^>]+)>/s,
    );
    return {
      kind: match[1],
      name: header.replace(/\s*\[[^\]]+\]:?$/, "").replace(/:$/, ""),
      path: location?.[1] || null,
      line: location ? Number(location[2]) : null,
      message: body.slice(0, 20_000),
      expected: expected?.[1]?.trim() ?? response?.[1] ?? null,
      actual: expected?.[2]?.trim() ?? response?.[2] ?? null,
    };
  });
}
const escape = (value) =>
  String(value ?? "").replace(
    /[&<>"']/g,
    (char) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        char
      ],
  );
export function renderTestResults(host, execution, { openFile }) {
  const output = execution.result?.output || "",
    failures = parseFailures(output);
  const summary = execution.reported_test_summary;
  const passed =
    Boolean(summary) &&
    execution.status === "execution_completed" &&
    !summary.failures &&
    !summary.errors &&
    !summary.skipped;
  if (execution.purpose === "prepare") {
    host.innerHTML = `<div class="result-message"><strong>${execution.status === "execution_completed" ? "Environment ready" : execution.status === "queued" ? "Preparation queued" : execution.status === "leased" ? "Preparing environment…" : "Preparation did not finish"}</strong><p>${execution.status === "execution_completed" ? "Preparation passed. Run tests to check your implementation." : "See raw output for details. The assessment timer has not been started by preparation."}</p></div>`;
  } else if (["queued", "leased"].includes(execution.status)) {
    host.innerHTML = `<div class="result-message"><strong>${execution.status === "queued" ? "Tests queued" : "Running tests…"}</strong><p>Results will appear when the worker returns this saved revision.</p></div>`;
  } else {
    host.innerHTML = `${failures.length ? `<div class="failure-list">${failures.map((failure, index) => `<details class="test-failure" ${index === 0 ? "open" : ""}><summary><span class="failure-kind">${escape(failure.kind)}</span><span>${escape(failure.name.replaceAll("_", " "))}</span></summary>${failure.path ? `<button class="source-link" type="button" data-diagnostic="${index}">${escape(failure.path)}:${failure.line}</button>` : ""}${failure.expected !== null ? `<div class="assertion-comparison"><div><span>Expected</span><pre>${escape(failure.expected)}</pre></div><div><span>Actual</span><pre>${escape(failure.actual)}</pre></div></div>` : ""}<pre class="failure-message">${escape(failure.message)}</pre></details>`).join("")}</div>` : `<div class="result-message"><strong>${passed ? "All reported tests passed" : summary ? "Run did not finish cleanly" : "No individual test diagnostics were found"}</strong><p>${summary ? `${summary.tests} tests · ${summary.assertions} assertions · ${summary.skipped} skipped${passed ? "" : ` · runner status ${escape(execution.status)} — reported counts are not a passing verdict`}` : "See raw output. An incomplete or unrecognized result is not a passing verdict."}</p></div>`}<p class="results-provenance">Parsed from runner output for revision ${escape(execution.revision.slice(0, 10))}. ${failures.length && summary && failures.length !== summary.failures + summary.errors ? "Some reported failures have no individual diagnostic. " : ""}Test counts are separate from submission review.</p>`;
    host.querySelectorAll("[data-diagnostic]").forEach(
      (button) =>
        (button.onclick = () => {
          const failure = failures[Number(button.dataset.diagnostic)];
          openFile(failure.path, failure.line);
        }),
    );
  }
}
