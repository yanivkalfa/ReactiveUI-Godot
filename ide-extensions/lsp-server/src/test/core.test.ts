import { test } from "node:test";
import assert from "node:assert";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { findMatching, skipNoncode, keywordAt } from "../scanner";
import { SourceMap, offsetToPosition, positionToOffset } from "../sourceMap";
import { buildVirtualDoc } from "../virtualDoc";
import { scanDeclarations, WorkspaceIndex, componentTagAt } from "../workspaceIndex";
import { classProperties, classSignals } from "../classdb";
import { formatGuitkx } from "../formatGuitkx";
import { tokenEquivalent, reflowEmbedded } from "../reflowEmbedded";
import { scanTagRefs } from "../refs";
import { buildSemanticTokens } from "../semanticTokens";
import { normalizeUri } from "../workspaceIndex";
import { srcHash } from "../diagsSidecar";
import { parseMarkup } from "../markup";
import { AnalyzerAdapter } from "../analyzerAdapter";

test("findMatching balances braces, skipping strings/comments", () => {
  const s = '{ a = "}" # }\n ; b }';
  assert.equal(findMatching(s, 0), s.length - 1);
});

test("scanDeclarations keys component binding by @class_name override", () => {
  const src = "@class_name Fancy\ncomponent Card(title: String) {\n\treturn ( <Label /> )\n}\n";
  const decls = scanDeclarations(src);
  assert.equal(decls.length, 1);
  assert.equal(decls[0].name, "Card");
  assert.equal(decls[0].binding, "Fancy"); // tag-binding identity, NOT basename/decl-name
});

test("scanDeclarations enumerates module members with enclosing module", () => {
  const src = "module M {\n component A() { return (<Label />) }\n component B() { return (<A />) }\n}\n";
  const names = scanDeclarations(src).map((d) => d.name);
  assert.ok(names.includes("M") && names.includes("A") && names.includes("B"));
  assert.equal(scanDeclarations(src).find((d) => d.name === "A")!.module, "M");
});

test("componentTagAt resolves PascalCase tags and ignores lowercase host factories", () => {
  const a = "return (<Card />)";
  assert.equal(componentTagAt(a, a.indexOf("Card") + 1), "Card");
  const b = "return (<vbox />)";
  assert.equal(componentTagAt(b, b.indexOf("vbox") + 1), null);
});

test("WorkspaceIndex multi-valued lookup + eviction", () => {
  const idx = new WorkspaceIndex();
  idx.reindex("file:///X.guitkx", "component Card() { return (<Label />) }");
  assert.equal(idx.lookup("Card").length, 1);
  idx.evict("file:///X.guitkx");
  assert.equal(idx.lookup("Card").length, 0);
});

test("parseMarkup is structurally identical to the GDScript parser over the shared markup corpus", () => {
  const corpus = JSON.parse(readFileSync(join(__dirname, "..", "..", "test-fixtures", "markup-cases.json"), "utf8"));
  assert.ok(corpus.length >= 13, "markup corpus should have the generated cases");
  for (const c of corpus) {
    const r = parseMarkup(c.input, 0, c.input.length);
    assert.equal(r.error, c.error, `parser error for '${c.name}'`);
    // deep-equal is key-order-independent (GDScript JSON.stringify sorts keys; TS does not)
    assert.deepStrictEqual(r.nodes, JSON.parse(c.tree), `parser node tree for '${c.name}'`);
  }
});

test("parseMarkup handles a `<`/`>` comparison inside a child {expr} (the structural-fix bug class)", () => {
  assert.equal(parseMarkup("<Label>{ a < b }</Label>", 0, 24).error, ""); // was GUITKX0301
  assert.equal(parseMarkup("<Label v={a > b}/>", 0, 18).error, "");
  assert.equal(parseMarkup("<VBox><HBox></VBox>", 0, 19).error.startsWith("GUITKX0302"), true); // still errors
});

test("formatGuitkx is byte-identical to the GDScript formatter over the shared golden corpus", () => {
  const corpus = JSON.parse(readFileSync(join(__dirname, "..", "..", "test-fixtures", "formatter-cases.json"), "utf8"));
  assert.ok(corpus.length >= 9, "corpus should have the generated cases");
  for (const c of corpus) {
    assert.equal(formatGuitkx(c.input).text, c.expected, `formatter case '${c.name}' must match GDScript output`);
    assert.equal(formatGuitkx(c.expected).text, c.expected, `formatter case '${c.name}' must be idempotent`);
  }
});

test("scanTagRefs: jsx-as-value ref after a value keyword counts; a comparison does not", () => {
  assert.equal(scanTagRefs("x = cond if c else <Card />", "Card").length, 1); // else <Card/> is a ref
  assert.equal(scanTagRefs("if a < Card: pass", "Card").length, 0); // `a < Card` is a comparison
  assert.equal(scanTagRefs('<VBox><Card key="x" /></VBox>', "Card").length, 1); // plain child ref
});

test("buildSemanticTokens only scans markup windows — a `<` in setup GDScript is never mis-tokenized", () => {
  // `a<B` in the setup would, under a whole-doc scan, be read as a `<B` tag and spew bogus tokens.
  const src = 'component X() {\n\tvar t = a<B\n\treturn (\n\t\t<Label text="hi" />\n\t)\n}\n';
  const data = buildSemanticTokens(src, () => false);
  assert.equal(data.length, 10); // exactly 2 tokens — <Label> + text — setup excluded
  assert.equal(data[3], 1); // host 'type' (Label)
  assert.equal(data[8], 3); // 'property' (attr name `text`)
});

test("normalizeUri canonicalizes the Windows drive so disk + editor URIs key the same entry", () => {
  assert.equal(normalizeUri("file:///C:/a/b.guitkx"), "file:///c%3A/a/b.guitkx");
  assert.equal(normalizeUri("file:///c%3A/a/b.guitkx"), "file:///c%3A/a/b.guitkx");
  assert.equal(normalizeUri("file:///tmp/x.guitkx"), "file:///tmp/x.guitkx"); // non-Windows untouched
});

test("srcHash iterates code points (astral-plane safe) and stays stable for ASCII", () => {
  assert.equal(srcHash("hello"), 1335831723); // matches the GDScript src_hash cross-check
  assert.equal(typeof srcHash("emoji 😀 here"), "number"); // no surrogate-pair miscount / crash
});

test("gdformat reflow safety net: token-equivalence ignores whitespace/quote, rejects structural change", () => {
  assert.ok(tokenEquivalent("var a=b+c", "var a = b + c")); // whitespace only -> equivalent
  assert.ok(tokenEquivalent("x = 'hi'", 'x = "hi"')); // quote style -> equivalent
  assert.ok(!tokenEquivalent("[a, b]", "[a, b,]")); // trailing comma -> rejected (conservative)
  assert.ok(!tokenEquivalent("a + b", "a - b")); // operator change -> rejected
});

test("reflowEmbedded never corrupts (no-op without gdformat; token-equivalent with it)", () => {
  const formatted = "component X {\n\tvar a = 1\n\treturn (\n\t\t<Label />\n\t)\n}\n";
  assert.ok(tokenEquivalent(formatted, reflowEmbedded(formatted)));
});

test("classdb dump base-flattens Button props (text + inherited disabled) and signals", () => {
  const props = classProperties("Button").map((p) => p.name);
  assert.ok(props.includes("text")); // own
  assert.ok(props.includes("disabled")); // inherited from BaseButton
  assert.ok(classSignals("Button").some((s) => s.name === "pressed"));
});

test("skipNoncode skips line comments and strings", () => {
  assert.equal(skipNoncode("# c\nx", 0), 3);
  assert.equal(skipNoncode('"ab"x', 0), 4);
  assert.equal(skipNoncode('"""a\nb"""x', 0), 9);
  assert.equal(skipNoncode("xyz", 0), 0);
});

test("skipNoncode handles node-path string prefixes with a token-boundary guard", () => {
  assert.equal(skipNoncode('$"a/b"x', 0), 6); // $"a/b" node-path string skipped
  assert.equal(skipNoncode('%"u"x', 0), 4); // %"u" unique-name string skipped
  assert.equal(skipNoncode('&"n"', 0), 4); // &"n" StringName
  assert.equal(skipNoncode('^"p"', 0), 4); // ^"p" NodePath
  // operators after a value must NOT be treated as a string prefix
  assert.equal(skipNoncode('a%"f"', 1), 1); // % after 'a' -> format operator, not skipped
  assert.equal(skipNoncode('b&"x"', 1), 1); // & after 'b' -> bitwise op, not skipped
  // R is no longer a prefix (byte-identity with guitkx_lexer.gd)
  assert.equal(skipNoncode('R"x"', 0), 0);
});

test("scanner stays byte-identical with the GDScript lexer (shared fixture)", () => {
  const fx = JSON.parse(readFileSync(join(__dirname, "..", "..", "test-fixtures", "scanner-cases.json"), "utf8"));
  for (const c of fx.skipNoncode)
    assert.equal(skipNoncode(c.input, c.at), c.expect, `skipNoncode(${JSON.stringify(c.input)}, ${c.at})`);
  for (const c of fx.findMatching)
    assert.equal(findMatching(c.input, c.at), c.expect, `findMatching(${JSON.stringify(c.input)}, ${c.at})`);
});

test("keywordAt respects identifier boundaries", () => {
  assert.ok(keywordAt("component X", 0, "component"));
  assert.ok(!keywordAt("components", 0, "component"));
  assert.ok(!keywordAt("xcomponent", 1, "component"));
});

test("SourceMap round-trips offsets within a span", () => {
  const m = new SourceMap();
  m.addSpan(10, 50, 5);
  assert.equal(m.toGenerated(12), 52);
  assert.equal(m.toSource(52), 12);
  assert.equal(m.toGenerated(100), null);
  assert.equal(m.toSource(5), null);
});

test("offset <-> position helpers agree", () => {
  const text = "ab\ncde\nf";
  const pos = offsetToPosition(text, 5); // 'd' on line 1
  assert.deepEqual(pos, { line: 1, character: 2 });
  assert.equal(positionToOffset(text, pos), 5);
});

test("virtualDoc splices setup + {expr} with a correct round-trip mapping", () => {
  const src = [
    "component Counter(start: int = 0) {",
    "\tvar s = use_state(start)",
    "\treturn (",
    "\t\t<Label text={ str(s[0]) } />",
    "\t)",
    "}",
  ].join("\n");
  const { text, map } = buildVirtualDoc(src);
  assert.ok(text.includes("static func render(props: Dictionary, children: Array)"), "has render scaffold");
  assert.ok(text.includes("var s = use_state(start)"), "setup spliced verbatim");
  assert.ok(text.includes("str(s[0])"), "expr spliced");
  const exprIdx = src.indexOf("str(s[0])") + 1; // inside the expr
  const genIdx = map.toGenerated(exprIdx);
  assert.notEqual(genIdx, null, "source offset maps into generated");
  assert.equal(map.toSource(genIdx!), exprIdx, "generated maps back to source");
});

test("virtualDoc extracts @if/@for conditions", () => {
  const src = [
    "component L(items: Array = []) {",
    "\treturn (",
    "\t\t<VBox>",
    "\t\t\t@if (items.size() > 0) { <Label /> }",
    "\t\t\t@for (it in items) { <Label text={ it } /> }",
    "\t\t</VBox>",
    "\t)",
    "}",
  ].join("\n");
  const { text } = buildVirtualDoc(src);
  assert.ok(text.includes("items.size() > 0"), "@if condition extracted");
  assert.ok(text.includes("it in items"), "@for header extracted");
});

test("virtualDoc is scope-aware (loop var visible to its {expr})", () => {
  const src = [
    "component L(items: Array = []) {",
    "\treturn (",
    "\t\t<VBox>",
    "\t\t\t@for (it in items) { <Label text={ it.name } /> }",
    "\t\t</VBox>",
    "\t)",
    "}",
  ].join("\n");
  const { text } = buildVirtualDoc(src);
  const lines = text.split("\n");
  const forLine = lines.find((l) => l.includes("for it in items:"));
  const exprLine = lines.find((l) => l.includes("it.name"));
  assert.ok(forLine, "emits `for it in items:`");
  assert.ok(exprLine, "emits the loop-var {expr}");
  const lead = (s: string) => s.match(/^\t*/)![0].length;
  assert.ok(lead(exprLine!) > lead(forLine!), "the {expr} is nested INSIDE the for block (loop var in scope)");
});

test("cross-file goto: a Hooks.<hook> reference resolves INTO the library file (binding-reported uri)", () => {
  // The §7(a) headline: with the addon library loaded (res:// path + `class_name Hooks`), a
  // `Hooks.use_ref` reference in the virtual doc resolves cross-file to the real hooks.gd — and the
  // adapter reports the target by URI (the binding enriches each navigation target's FileId with its
  // uri) with its range in THAT file's text. The server chains a bare `use_ref` to this RHS; here we
  // drive both steps.
  const az = new AnalyzerAdapter();
  const hooksUri = "file:///proj/addons/reactive_ui/core/hooks.gd";
  const hooks = "class_name Hooks\nstatic func use_ref(initial = null) -> Dictionary:\n\treturn {}\n";
  az.loadLibrary(hooksUri, hooks, "res://addons/reactive_ui/core/hooks.gd");

  const vUri = "file:///proj/x.__guitkx_virtual.gd";
  const vtext =
    "extends RefCounted\n" +
    "static func render(props, children):\n" +
    "\tvar use_ref = Hooks.use_ref\n" +
    "\tvar _e0 = (use_ref(0))\n" +
    "\tpass\n";
  az.sync(vUri, vtext);

  // (1) The bare `use_ref(0)` in the embedded expr resolves to the in-scope hook STUB (same file).
  const bareUse = vtext.indexOf("use_ref(0)") + 1;
  const localDefs = az.definitionsAt(vUri, vtext, bareUse);
  assert.ok(localDefs.length >= 1, "bare use_ref resolves to the local stub");
  assert.equal(localDefs[0].uri, vUri, "the stub lives in the virtual doc (same file)");

  // (2) The stub's RHS `Hooks.use_ref` resolves CROSS-FILE to the real method in hooks.gd.
  const rhs = vtext.indexOf("Hooks.use_ref") + "Hooks.".length;
  const libDefs = az.definitionsAt(vUri, vtext, rhs);
  const d = libDefs.find((x) => x.uri === hooksUri);
  assert.ok(d, `Hooks.use_ref should point at the library file, got ${JSON.stringify(libDefs)}`);
  assert.equal(hooks.slice(d!.range.start, d!.range.end), "use_ref", "range lands on hooks.gd's use_ref decl");
});

test("virtualDoc paramNames is noncode-aware (comma/colon inside a string default does not mis-split)", () => {
  // [audit #26] A default value containing a comma or colon inside a string must not break the split,
  // so EVERY param still gets an in-scope stub for completion/hover.
  const src = [
    'component C(label: String = "a, b", path: String = "x:y", n: int = 0) {',
    "\treturn ( <Label text={ label } /> )",
    "}",
  ].join("\n");
  const { text } = buildVirtualDoc(src);
  assert.ok(text.includes('var label = props.get("label")'), "param `label` stub present (string default with comma)");
  assert.ok(text.includes('var path = props.get("path")'), "param `path` stub present (string default with colon)");
  assert.ok(text.includes('var n = props.get("n")'), "param `n` after a comma-in-string default still survives");
});
