// End-to-end smoke test: spawn the server over stdio, run the LSP handshake, open a .guitkx doc,
// and request completion at a tag-name and an attribute-name position. Asserts the markup-side
// intelligence works without a Godot editor (the embedded-GDScript proxy path degrades gracefully).
const cp = require("child_process");
const path = require("path");

const server = cp.spawn("node", [path.join(__dirname, "..", "out", "server.js"), "--stdio"]);
let buf = Buffer.alloc(0);
let contentLength = -1;
const waiters = new Map();

server.stdout.on("data", (d) => {
  buf = Buffer.concat([buf, d]);
  while (true) {
    if (contentLength < 0) {
      const e = buf.indexOf("\r\n\r\n");
      if (e < 0) return;
      const m = /Content-Length:\s*(\d+)/i.exec(buf.slice(0, e).toString());
      contentLength = m ? +m[1] : 0;
      buf = buf.slice(e + 4);
    }
    if (buf.length < contentLength) return;
    const msg = JSON.parse(buf.slice(0, contentLength).toString());
    buf = buf.slice(contentLength);
    contentLength = -1;
    if (msg.id !== undefined && waiters.has(msg.id)) {
      waiters.get(msg.id)(msg);
      waiters.delete(msg.id);
    }
  }
});

let id = 0;
function send(msg) {
  const j = JSON.stringify({ jsonrpc: "2.0", ...msg });
  server.stdin.write(`Content-Length: ${Buffer.byteLength(j)}\r\n\r\n${j}`);
}
function request(method, params) {
  const myId = ++id;
  return new Promise((res) => {
    waiters.set(myId, res);
    send({ id: myId, method, params });
  });
}
function notify(method, params) {
  send({ method, params });
}

function fail(m) {
  console.error("SMOKE FAIL:", m);
  server.kill();
  process.exit(1);
}

(async () => {
  await request("initialize", { processId: process.pid, rootUri: null, capabilities: {}, initializationOptions: { enableGodotProxy: false } });
  notify("initialized", {});

  const uri = "file:///tmp/Counter.guitkx";
  const text = "component Counter() {\n\treturn (\n\t\t<VBox>\n\t\t\t<La\n\t\t</VBox>\n\t)\n}\n";
  notify("textDocument/didOpen", { textDocument: { uri, languageId: "guitkx", version: 1, text } });

  // completion at the "<La" position (line 3, after "\t\t\t<La" => char 6)
  const tagRes = await request("textDocument/completion", { textDocument: { uri }, position: { line: 3, character: 6 } });
  const tagItems = Array.isArray(tagRes.result) ? tagRes.result : tagRes.result?.items ?? [];
  if (!tagItems.some((i) => i.label === "Label")) fail("tag completion did not include Label: " + JSON.stringify(tagItems.slice(0, 5)));
  console.log(`tag completion OK (${tagItems.length} items, includes Label)`);

  // completion at an attribute position: "<Button " then request
  const uri2 = "file:///tmp/B.guitkx";
  const text2 = "component B() {\n\treturn ( <Button  /> )\n}\n";
  notify("textDocument/didOpen", { textDocument: { uri: uri2, languageId: "guitkx", version: 1, text: text2 } });
  const attrRes = await request("textDocument/completion", { textDocument: { uri: uri2 }, position: { line: 1, character: 18 } });
  const attrItems = Array.isArray(attrRes.result) ? attrRes.result : attrRes.result?.items ?? [];
  if (!attrItems.some((i) => i.label === "on_pressed")) fail("attr completion missing Button event on_pressed: " + JSON.stringify(attrItems.map((i) => i.label)));
  if (!attrItems.some((i) => i.label === "key")) fail("attr completion missing structural 'key'");
  console.log(`attr completion OK (${attrItems.length} items, includes on_pressed + key)`);

  console.log("SMOKE PASSED");
  server.kill();
  process.exit(0);
})();
