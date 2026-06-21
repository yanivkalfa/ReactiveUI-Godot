import { test } from "node:test";
import assert from "node:assert";
import { findMatching, skipNoncode, keywordAt } from "../scanner";
import { SourceMap, offsetToPosition, positionToOffset } from "../sourceMap";
import { buildVirtualDoc } from "../virtualDoc";

test("findMatching balances braces, skipping strings/comments", () => {
  const s = '{ a = "}" # }\n ; b }';
  assert.equal(findMatching(s, 0), s.length - 1);
});

test("skipNoncode skips line comments and strings", () => {
  assert.equal(skipNoncode("# c\nx", 0), 3);
  assert.equal(skipNoncode('"ab"x', 0), 4);
  assert.equal(skipNoncode('"""a\nb"""x', 0), 9);
  assert.equal(skipNoncode("xyz", 0), 0);
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
  assert.ok(text.includes("static func render(props, children):"), "has render scaffold");
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
