import { build } from "esbuild";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
const root = path.resolve(import.meta.dirname, "..");
const result = await build({
  absWorkingDir: root,
  entryPoints: ["frontend/editor.js"],
  bundle: true,
  format: "esm",
  minify: true,
  metafile: true,
  outfile: "public/editor.bundle.js",
  banner: { js: "/*! Third-party license notices: /editor-licenses.txt */" },
});
const packages = new Set();
for (const input of Object.keys(result.metafile.inputs)) {
  const match = input.match(/^node_modules\/((?:@[^/]+\/)?[^/]+)\//);
  if (match) packages.add(match[1]);
}
const notices = [];
for (const name of [...packages].sort()) {
  const directory = path.join(root, "node_modules", name);
  const metadata = JSON.parse(
    await readFile(path.join(directory, "package.json"), "utf8"),
  );
  let license;
  for (const filename of ["LICENSE", "LICENSE.txt", "LICENSE.md", "license"]) {
    try {
      license = await readFile(path.join(directory, filename), "utf8");
      break;
    } catch {}
  }
  if (!license) throw Error(`Missing license notice for ${name}`);
  notices.push(`${name} ${metadata.version}\n${license}`);
}
await writeFile(
  path.join(root, "public/editor-licenses.txt"),
  notices.join("\n\n----------------------------------------\n\n"),
);
console.log(
  `Built local editor bundle and notices for ${packages.size} runtime packages.`,
);
