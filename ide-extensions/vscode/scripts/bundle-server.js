// Copies the built language server (../lsp-server/out + its runtime node_modules) into ./server so
// `vsce package` produces a self-contained .vsix. Run after building both projects.
//
// Cross-platform packaging: pass `--target <vsce-target>` (e.g. win32-x64, darwin-arm64, linux-x64)
// to bundle ONLY that platform's @gdscript-analyzer/core-<triple> native addon, producing a
// platform-specific .vsix (`vsce package --target <vsce-target>`). The CI publish matrix installs the
// matching `core-<triple>` package into ../lsp-server/node_modules before calling this. With NO
// --target, every @gdscript-analyzer package currently installed is bundled — the local-dev path,
// which yields a .vsix that runs only on the builder's own platform.
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const serverSrc = path.join(root, "..", "lsp-server");
const dest = path.join(root, "server");

// vsce target triple -> the @gdscript-analyzer/core-<suffix> napi sub-package for that platform.
const VSCE_TO_NAPI = {
  "win32-x64": "core-win32-x64-msvc",
  "win32-arm64": "core-win32-arm64-msvc",
  "linux-x64": "core-linux-x64-gnu",
  "linux-arm64": "core-linux-arm64-gnu",
  "linux-armhf": "core-linux-arm-gnueabihf",
  "alpine-x64": "core-linux-x64-musl",
  "alpine-arm64": "core-linux-arm64-musl",
  "darwin-x64": "core-darwin-x64",
  "darwin-arm64": "core-darwin-arm64",
};

const targetArg = process.argv.indexOf("--target");
const vsceTarget = targetArg >= 0 ? process.argv[targetArg + 1] : null;
if (vsceTarget && !VSCE_TO_NAPI[vsceTarget]) {
  console.error(`[bundle-server] unknown --target '${vsceTarget}'. Known: ${Object.keys(VSCE_TO_NAPI).join(", ")}`);
  process.exit(1);
}

function copyDir(from, to, exclude) {
  fs.mkdirSync(to, { recursive: true });
  for (const entry of fs.readdirSync(from, { withFileTypes: true })) {
    if (exclude && exclude.has(entry.name)) continue;
    const s = path.join(from, entry.name);
    const d = path.join(to, entry.name);
    if (entry.isDirectory()) copyDir(s, d);
    else fs.copyFileSync(s, d);
  }
}

if (!fs.existsSync(path.join(serverSrc, "out", "server.js"))) {
  console.error("[bundle-server] lsp-server is not built. Run `npm run build` in ../lsp-server first.");
  process.exit(1);
}

fs.rmSync(dest, { recursive: true, force: true });
// flatten out/*.js to ./server/*.js so extension.ts can require ./server/server.js
// (repo hygiene: out/test/** is compiled test code, never needed at runtime -- excluded so it
// doesn't bloat the shipped .vsix)
copyDir(path.join(serverSrc, "out"), dest, new Set(["test"]));
// A7: the vocabulary must ride along — schema.js require()s it at runtime, so a bundle without it
// is a server that dies on MODULE_NOT_FOUND at startup (a 0.5.x-era layout shipped exactly that).
if (!fs.existsSync(path.join(dest, "vocabulary.json"))) {
  console.error("[bundle-server] out/vocabulary.json missing — the lsp-server build must emit it (tsconfig resolveJsonModule include). Rebuild ../lsp-server.");
  process.exit(1);
}
// runtime deps the server needs at execution time
const deps = ["vscode-languageserver", "vscode-languageserver-textdocument", "vscode-languageserver-protocol", "vscode-jsonrpc", "vscode-languageserver-types"];
for (const dep of deps) {
  const depPath = path.join(serverSrc, "node_modules", dep);
  if (fs.existsSync(depPath)) copyDir(depPath, path.join(dest, "node_modules", dep));
}
// the headless GDScript analyzer (@gdscript-analyzer/core — a native napi addon) + the per-platform
// binary sub-package(s). With --target, bundle ONLY that platform's `core-<triple>` (alongside the
// main `core` loader package) → a platform-specific .vsix. Without it, bundle every @gdscript-analyzer
// package present (the host's, for local dev).
const analyzerScope = path.join(serverSrc, "node_modules", "@gdscript-analyzer");
if (fs.existsSync(analyzerScope)) {
  const destScope = path.join(dest, "node_modules", "@gdscript-analyzer");
  if (vsceTarget) {
    const wanted = new Set(["core", VSCE_TO_NAPI[vsceTarget]]);
    let bundledNative = false;
    for (const entry of fs.readdirSync(analyzerScope, { withFileTypes: true })) {
      if (!entry.isDirectory() || !wanted.has(entry.name)) continue;
      copyDir(path.join(analyzerScope, entry.name), path.join(destScope, entry.name));
      if (entry.name === VSCE_TO_NAPI[vsceTarget]) bundledNative = true;
    }
    if (!bundledNative) {
      console.error(
        `[bundle-server] --target ${vsceTarget} needs '@gdscript-analyzer/${VSCE_TO_NAPI[vsceTarget]}' installed in ` +
          `../lsp-server/node_modules (run: npm i --no-save @gdscript-analyzer/${VSCE_TO_NAPI[vsceTarget]}@<version>).`
      );
      process.exit(1);
    }
    console.log(`[bundle-server] bundled analyzer for ${vsceTarget} (@gdscript-analyzer/${VSCE_TO_NAPI[vsceTarget]})`);
  } else {
    copyDir(analyzerScope, destScope);
  }
}
// the ClassDB dump (loaded by classdb.js via ../classdb/) — bundle it next to ./server
const classdbSrc = path.join(serverSrc, "classdb");
if (fs.existsSync(classdbSrc)) copyDir(classdbSrc, path.join(root, "classdb"));
console.log("[bundle-server] copied language server into ./server");
