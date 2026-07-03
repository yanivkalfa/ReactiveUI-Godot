// T5.1: the TS port of guitkx_jsx_scan.gd -- same fixtures as the GD suite's jsx-value tests so the
// two implementations cannot drift silently (§5.1 item 1, the last unported grammar module).

import { test } from "node:test";
import * as assert from "node:assert";

import { findMarkupRanges, neutralizeMarkup } from "../jsxScan";
import { buildVirtualDoc } from "../virtualDoc";

test("T5.1: jsxScan finds ranges at every boundary (mirror of guitkx_jsx_scan.gd)", () => {
  const s1 = "cond if c else <A/>";
  const r1 = findMarkupRanges(s1, 0, s1.length);
  assert.equal(r1.length, 1);
  assert.equal(s1.slice(r1[0].start, r1[0].end), "<A/>");

  const s2 = "is_open and <Panel><Label text={ t } /></Panel>";
  const r2 = findMarkupRanges(s2, 0, s2.length);
  assert.equal(r2[0].op, "and");
  assert.equal(s2.slice(r2[0].start, r2[0].end), "<Panel><Label text={ t } /></Panel>");

  const s3 = "items.map(func(it): return <Row item={ it }/>)";
  const r3 = findMarkupRanges(s3, 0, s3.length);
  assert.equal(s3.slice(r3[0].start, r3[0].end), "<Row item={ it }/>");

  const s4 = 'ready or <label text="w" />';
  assert.equal(findMarkupRanges(s4, 0, s4.length)[0].op, "or");

  // unbalanced markup owns the rest of the expression: { end: -1 }
  const s5 = "open and <Broken>";
  assert.equal(findMarkupRanges(s5, 0, s5.length)[0].end, -1);

  // comparisons never match (no boundary token precedes them)
  assert.equal(findMarkupRanges("a < b", 0, 5).length, 0);
  const s6 = "i < n and x > y";
  assert.equal(findMarkupRanges(s6, 0, s6.length).length, 0);
});

test("T5.1: neutralizeMarkup is length-preserving and yields analyzable GDScript", () => {
  const src = "is_open and <Panel><Label text={ t } /></Panel>";
  const out = neutralizeMarkup(src);
  assert.equal(out.length, src.length);
  assert.ok(out.startsWith("is_open and null"));
  assert.ok(!out.includes("<"));
  // untouched expressions come back identical
  assert.equal(neutralizeMarkup("a < b and c > d"), "a < b and c > d");
});

test("T5.1: nested markup in an {expr} reaches the analyzer as null padding, not garbage", () => {
  const src = 'component C(open: bool = false) {\n\treturn ( <vbox>{ open and <label text="hi" /> }</vbox> )\n}\n';
  const vd = buildVirtualDoc(src);
  assert.ok(!vd.text.includes("<label"), vd.text);
  assert.ok(/open and null/.test(vd.text), vd.text);
});

// T5.3 audit closures ------------------------------------------------------------------------

test("T5.3/G9: a component whose body is only an @for block flags missing-return live", () => {
  const src = "component G9() {\n\t@for (i in 25) {\n\t\t<label text={ str(i) } />\n\t}\n}\n";
  const { missingReturnComponents } = require("../formatGuitkx");
  assert.equal(missingReturnComponents(src).length, 1);
});

test("T5.3: keyless loop roots (element and fragment) fire GUITKX0106 live", () => {
  const { windowStructureDiags } = require("../liveMarkup");
  const { markupWindows } = require("../formatGuitkx");
  const el = "component K(xs: Array = []) {\n\treturn ( <vbox>@for (x in xs) { <label text={ str(x) } /> }</vbox> )\n}\n";
  const d1 = windowStructureDiags(el, markupWindows(el));
  assert.ok(d1.some((x: { code: string }) => x.code === "GUITKX0106"), JSON.stringify(d1));
  const frag = "component K2(xs: Array = []) {\n\treturn ( <vbox>@for (x in xs) { <Fragment><label text={ str(x) } /></Fragment> }</vbox> )\n}\n";
  const d2 = windowStructureDiags(frag, markupWindows(frag));
  assert.ok(d2.some((x: { code: string }) => x.code === "GUITKX0106"), JSON.stringify(d2));
  const keyed = "component K3(xs: Array = []) {\n\treturn ( <vbox>@for (x in xs) { <label key={ str(x) } text={ str(x) } /> }</vbox> )\n}\n";
  assert.equal(windowStructureDiags(keyed, markupWindows(keyed)).filter((x: { code: string }) => x.code === "GUITKX0106").length, 0);
});
