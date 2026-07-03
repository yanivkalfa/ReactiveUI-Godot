// A7 (0.6.0 field triage): fail `vsce package`/`vsce publish` loudly when ./server is stale or
// incomplete. `vscode:prepublish` used to run ONLY the extension tsc build — a `vsce publish`
// outside `npm run package` (which rebundles) would ship whatever ./server happened to contain;
// this repo's history had a bundle missing vocabulary.json and liveMarkup.js, i.e. a server that
// dies on MODULE_NOT_FOUND at startup. This guard deliberately does NOT rebundle: CI bundles with
// `--target <platform>` before packaging, and an unconditional rebundle here would clobber that
// platform-specific layout. It only verifies and tells you what to run.
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const serverSrc = path.join(root, "..", "lsp-server");
const dest = path.join(root, "server");

const required = [
  "server.js",
  "schema.js",
  "liveMarkup.js",
  "vocabulary.json",
  path.join("node_modules", "vscode-languageserver"),
  path.join("node_modules", "@gdscript-analyzer", "core"),
];
const missing = required.filter((r) => !fs.existsSync(path.join(dest, r)));
if (missing.length) {
  console.error(
    `[verify-server] ./server is incomplete (missing: ${missing.join(", ")}). ` +
      "Run `npm run bundle-server` (or `node scripts/bundle-server.js --target <vsce-target>`) after building ../lsp-server."
  );
  process.exit(1);
}

// The vocabulary must be the CURRENT one — a stale copy resurrects already-fixed diagnostic behavior.
const srcVocab = path.join(serverSrc, "src", "vocabulary.json");
if (fs.existsSync(srcVocab) && fs.readFileSync(srcVocab, "utf8") !== fs.readFileSync(path.join(dest, "vocabulary.json"), "utf8")) {
  console.error("[verify-server] ./server/vocabulary.json differs from lsp-server/src/vocabulary.json — rebundle before packaging.");
  process.exit(1);
}

// Staleness: any lsp-server/out file newer than the bundle means ./server predates the last server
// build (fs.copyFileSync stamps copy time, so a fresh bundle is always newer than its sources).
const outDir = path.join(serverSrc, "out");
if (fs.existsSync(outDir)) {
  const bundledAt = fs.statSync(path.join(dest, "server.js")).mtimeMs;
  let newest = 0;
  let newestName = "";
  for (const f of fs.readdirSync(outDir)) {
    const st = fs.statSync(path.join(outDir, f));
    if (st.isFile() && st.mtimeMs > newest) {
      newest = st.mtimeMs;
      newestName = f;
    }
  }
  if (newest > bundledAt) {
    console.error(`[verify-server] ./server is STALE (lsp-server/out/${newestName} is newer than the bundle). Run \`npm run bundle-server\`.`);
    process.exit(1);
  }
}
console.log("[verify-server] ./server bundle is complete and current");
