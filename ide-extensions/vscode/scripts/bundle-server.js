// Copies the built language server (../lsp-server/out + its runtime node_modules) into ./server so
// `vsce package` produces a self-contained .vsix. Run after building both projects.
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const serverSrc = path.join(root, "..", "lsp-server");
const dest = path.join(root, "server");

function copyDir(from, to) {
  fs.mkdirSync(to, { recursive: true });
  for (const entry of fs.readdirSync(from, { withFileTypes: true })) {
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
copyDir(path.join(serverSrc, "out"), dest);
// runtime deps the server needs at execution time
const deps = ["vscode-languageserver", "vscode-languageserver-textdocument", "vscode-languageserver-protocol", "vscode-jsonrpc", "vscode-languageserver-types"];
for (const dep of deps) {
  const depPath = path.join(serverSrc, "node_modules", dep);
  if (fs.existsSync(depPath)) copyDir(depPath, path.join(dest, "node_modules", dep));
}
// the ClassDB dump (loaded by classdb.js via ../classdb/) — bundle it next to ./server
const classdbSrc = path.join(serverSrc, "classdb");
if (fs.existsSync(classdbSrc)) copyDir(classdbSrc, path.join(root, "classdb"));
console.log("[bundle-server] copied language server into ./server");
