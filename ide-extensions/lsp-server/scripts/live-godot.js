// Live round-trip against a RUNNING Godot editor's GDScript language server (TCP 6005). Proves the
// load-bearing assumption: an in-memory `file://` virtual `.gd` (a path that need not exist on disk)
// gets context-aware completion referencing both a LOCAL symbol and real PROJECT-GLOBAL classes
// (V, Hooks). Run with the Godot editor open on this project. Usage: node scripts/live-godot.js [projDir]
const net = require("net");
const path = require("path");

const projDir = process.argv[2] || path.resolve(__dirname, "..", "..", "..");
const rootUri = "file:///" + projDir.replace(/\\/g, "/").replace(/^\/+/, "");
const docUri = rootUri + "/__guitkx_live_probe.gd";

// A synthetic .gd (what buildVirtualDoc would emit): a local var + references to project globals.
const lines = [
  "extends RefCounted",
  "static func render(props, children) -> RUIVNode:",
  "\tvar my_counter = 0",
  "\tvar a = my_counter",   // probe A: local symbol
  "\tvar b = V.",            // probe B: project global V  (complete after the dot)
  "\tvar c = Hooks.",        // probe C: project global Hooks
  "\treturn null",
];
const text = lines.join("\n") + "\n";
function posOf(lineIdx, ch) { return { line: lineIdx, character: ch }; }

const sock = net.connect(6005, "127.0.0.1");
let buf = Buffer.alloc(0), len = -1, id = 0;
const waiters = new Map();
sock.on("data", (d) => {
  buf = Buffer.concat([buf, d]);
  while (true) {
    if (len < 0) {
      const e = buf.indexOf("\r\n\r\n");
      if (e < 0) return;
      const m = /Content-Length:\s*(\d+)/i.exec(buf.slice(0, e).toString());
      len = m ? +m[1] : 0; buf = buf.slice(e + 4);
    }
    if (buf.length < len) return;
    const msg = JSON.parse(buf.slice(0, len).toString()); buf = buf.slice(len); len = -1;
    if (msg.id !== undefined && waiters.has(msg.id)) { waiters.get(msg.id)(msg); waiters.delete(msg.id); }
  }
});
sock.on("error", (e) => { console.error("CONNECT FAIL:", e.message); process.exit(2); });
function send(m) { const j = JSON.stringify({ jsonrpc: "2.0", ...m }); sock.write(`Content-Length: ${Buffer.byteLength(j)}\r\n\r\n${j}`); }
function req(method, params) { const myId = ++id; return new Promise((r) => { waiters.set(myId, r); send({ id: myId, method, params }); }); }
function notify(method, params) { send({ method, params }); }
function labels(res) { const r = res && res.result; const items = Array.isArray(r) ? r : (r && r.items) || []; return items.map((i) => i.label || i.insertText); }

(async () => {
  await req("initialize", { processId: process.pid, rootUri, capabilities: { textDocument: { completion: { completionItem: {} } } } });
  notify("initialized", {});
  notify("textDocument/didOpen", { textDocument: { uri: docUri, languageId: "gdscript", version: 1, text } });
  await new Promise((r) => setTimeout(r, 800)); // let the server parse

  const probes = [
    { name: "A local symbol (my_counter)", pos: posOf(3, 12), want: "my_counter" },
    { name: "B project global V.*", pos: posOf(4, 11), want: "button" },
    { name: "C project global Hooks.*", pos: posOf(5, 15), want: "use_state" },
  ];
  let ok = 0;
  for (const p of probes) {
    const res = await req("textDocument/completion", { textDocument: { uri: docUri }, position: p.pos });
    const ls = labels(res);
    const hit = ls.some((l) => typeof l === "string" && l.includes(p.want));
    console.log(`${hit ? "PASS" : "----"}  ${p.name}: ${ls.length} items` + (ls.length ? ` (e.g. ${ls.slice(0, 6).join(", ")})` : ""));
    if (hit) ok++;
  }
  console.log(ok > 0 ? `\nLIVE ROUND-TRIP OK — ${ok}/3 probes returned context-aware completion` : "\nLIVE ROUND-TRIP: no context-aware results (see above)");
  sock.end();
  process.exit(ok > 0 ? 0 : 1);
})();
