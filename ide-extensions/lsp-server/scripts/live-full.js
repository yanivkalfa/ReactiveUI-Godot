// Full-path live proof using the ACTUAL shipped modules: a real .guitkx -> buildVirtualDoc (virtual
// .gd + source map) -> GodotProxy.sync/completion against the running Godot editor -> map the offset
// of an embedded {expr} into the virtual doc and confirm Godot completes it. Usage:
//   node scripts/live-full.js <projDir>
const { buildVirtualDoc } = require("../out/virtualDoc");
const { GodotProxy } = require("../out/godotProxy");
const { offsetToPosition } = require("../out/sourceMap");

const projDir = process.argv[2];
const rootUri = "file:///" + projDir.replace(/\\/g, "/").replace(/^\/+/, "");

const guitkx = [
  "component Probe() {",
  "\tvar s = use_state(0)",
  "\treturn ( <Label text={ V.lab } /> )",
  "}",
].join("\n");

(async () => {
  const { text, map } = buildVirtualDoc(guitkx);
  const proxy = new GodotProxy("127.0.0.1", 6005, rootUri);
  if (!(await proxy.ensureConnected())) { console.error("could not connect to Godot LSP"); process.exit(2); }

  const vUri = rootUri + "/__probe.__guitkx_virtual.gd";
  await proxy.sync(vUri, text);
  await new Promise((r) => setTimeout(r, 600));

  // offset of the end of "V.lab" inside the .guitkx {expr}
  const srcOff = guitkx.indexOf("V.lab") + 5;
  const genOff = map.toGenerated(srcOff);
  if (genOff === null) { console.error("source offset did not map into the virtual doc"); process.exit(1); }
  const pos = offsetToPosition(text, genOff);

  const res = await proxy.completion(vUri, pos.line, pos.character);
  const items = Array.isArray(res) ? res : (res && res.items) || [];
  const labels = items.map((i) => i.label || i.insertText).filter(Boolean);
  const hit = labels.some((l) => l.includes("label"));
  console.log(`mapped .guitkx offset ${srcOff} -> virtual ${genOff} -> line ${pos.line} char ${pos.character}`);
  console.log(`FULL PATH ${hit ? "PASS" : "----"}: completing { V.lab } returned ${items.length} items (e.g. ${labels.slice(0, 8).join(", ")})`);
  proxy["socket"]?.end?.();
  process.exit(hit ? 0 : 1);
})();
