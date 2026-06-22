// Live verification of the SCOPE-AWARE virtual doc (Phase 4 §2): does Godot's LSP resolve a @for
// loop variable referenced inside the emitted `for ... in ...:` block? Run with the editor open.
const { buildVirtualDoc } = require("../out/virtualDoc");
const { GodotProxy } = require("../out/godotProxy");
const { offsetToPosition } = require("../out/sourceMap");

const projDir = process.argv[2];
const rootUri = "file:///" + projDir.replace(/\\/g, "/").replace(/^\/+/, "");

const guitkx = [
  "component L(items: Array = []) {",
  "\treturn (",
  "\t\t<VBox>",
  "\t\t\t@for (it in items) { <Label text={ it } /> }",
  "\t\t</VBox>",
  "\t)",
  "}",
].join("\n");

(async () => {
  const { text, map } = buildVirtualDoc(guitkx);
  const proxy = new GodotProxy("127.0.0.1", 6005, rootUri);
  if (!(await proxy.ensureConnected())) { console.error("could not connect to Godot LSP"); process.exit(2); }
  const vUri = rootUri + "/__scope.__guitkx_virtual.gd";
  await proxy.sync(vUri, text);
  await new Promise((r) => setTimeout(r, 700));

  // complete at the end of `it` inside the {expr} child
  const srcOff = guitkx.indexOf("text={ it }") + "text={ ".length + 2;
  const genOff = map.toGenerated(srcOff);
  if (genOff === null) { console.error("loop-var offset did not map"); process.exit(1); }
  const pos = offsetToPosition(text, genOff);
  const res = await proxy.completion(vUri, pos.line, pos.character);
  const items = Array.isArray(res) ? res : (res && res.items) || [];
  const labels = items.map((i) => i.label || i.insertText).filter(Boolean);
  const hit = labels.includes("it") || labels.includes("items");
  console.log(`LOOP-VAR SCOPE ${hit ? "PASS" : "----"}: ${items.length} items (e.g. ${labels.slice(0, 8).join(", ")})`);
  proxy["socket"]?.end?.();
  process.exit(hit ? 0 : 1);
})();
