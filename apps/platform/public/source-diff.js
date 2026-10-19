// Bound the alignment work and rendered output independently of workspace size.
export function sourceDiff(before, after) {
  const a = before == null || before === "" ? [] : before.split("\n"),
    b = after == null || after === "" ? [] : after.split("\n");
  let prefix = 0,
    suffix = 0;
  while (prefix < a.length && prefix < b.length && a[prefix] === b[prefix])
    prefix++;
  while (
    suffix < a.length - prefix &&
    suffix < b.length - prefix &&
    a[a.length - suffix - 1] === b[b.length - suffix - 1]
  )
    suffix++;
  const n = a.length - prefix - suffix,
    m = b.length - prefix - suffix;
  const row = (kind, oldIndex, newIndex, text) => ({
    kind,
    oldLine: oldIndex == null ? null : oldIndex + 1,
    newLine: newIndex == null ? null : newIndex + 1,
    text,
  });
  const rows = [];
  if (prefix > 3)
    rows.push({ kind: "omitted", before: prefix - 3, after: prefix - 3 });
  for (let i = Math.max(0, prefix - 3); i < prefix; i++)
    rows.push(row("same", i, i, a[i]));
  let large = (n + 1) * (m + 1) > 250000 || n + m > 10000;
  if (large) {
    for (let i = 0; i < Math.min(n, 200); i++)
      rows.push(row("removed", prefix + i, null, a[prefix + i]));
    for (let j = 0; j < Math.min(m, 200); j++)
      rows.push(row("added", null, prefix + j, b[prefix + j]));
    if (n > 200 || m > 200)
      rows.push({
        kind: "omitted",
        before: Math.max(0, n - 200),
        after: Math.max(0, m - 200),
      });
  } else {
    const width = m + 1,
      matrix = new Uint32Array((n + 1) * width);
    for (let i = n - 1; i >= 0; i--)
      for (let j = m - 1; j >= 0; j--)
        matrix[i * width + j] =
          a[prefix + i] === b[prefix + j]
            ? 1 + matrix[(i + 1) * width + j + 1]
            : Math.max(matrix[(i + 1) * width + j], matrix[i * width + j + 1]);
    let i = 0,
      j = 0;
    const middle = [];
    while (i < n || j < m) {
      if (i < n && j < m && a[prefix + i] === b[prefix + j]) {
        middle.push(row("same", prefix + i, prefix + j, a[prefix + i]));
        i++;
        j++;
      } else if (
        j < m &&
        (i === n || matrix[i * width + j + 1] > matrix[(i + 1) * width + j])
      ) {
        middle.push(row("added", null, prefix + j, b[prefix + j]));
        j++;
      } else {
        middle.push(row("removed", prefix + i, null, a[prefix + i]));
        i++;
      }
    }
    if (middle.length > 600) {
      const omitted = middle.slice(300, -100);
      rows.push(
        ...middle.slice(0, 300),
        {
          kind: "omitted",
          before: omitted.filter((item) => item.kind !== "added").length,
          after: omitted.filter((item) => item.kind !== "removed").length,
        },
        ...middle.slice(-100),
      );
    } else rows.push(...middle);
  }
  for (let i = 0; i < Math.min(suffix, 3); i++)
    rows.push(
      row(
        "same",
        a.length - suffix + i,
        b.length - suffix + i,
        a[a.length - suffix + i],
      ),
    );
  if (suffix > 3)
    rows.push({ kind: "omitted", before: suffix - 3, after: suffix - 3 });
  return { rows, large, identical: before === after };
}
