// T0.1 contract harness — the TypeScript half. tests/contract/golden/*.json are dumped by the
// GDScript compiler of record (tests/contract_dump.gd; CI re-checks them with `-- --check`), one per
// real .guitkx fixture under tests/contract/fixtures/. This suite asserts the LSP's whole-file walk
// (markupWindows) and markup parser (parseMarkup) reproduce the goldens EXACTLY — window offsets,
// node trees, parse errors — so the two hand-maintained grammar implementations can never silently
// diverge on real files (SYNTAX_PARITY_EXECUTION_PLAN §5.1).
//
// *.pending.guitkx fixtures are KNOWN divergences (e.g. declScan typo-recovery finds a window the
// exact-keyword compiler does not). For those the test asserts the divergence STILL EXISTS — when a
// phase fixes one, this fails with "now agrees" and the fixture is promoted by dropping `.pending`.
//
// Regen after any deliberate grammar change (BOTH sides!):
//   godot --headless --path . --script res://tests/contract_dump.gd

import { test } from "node:test";
import * as assert from "node:assert";
import { readFileSync, readdirSync } from "fs";
import { join } from "path";

import { markupWindows } from "../formatGuitkx";
import { parseMarkup, MarkupNode, Attr } from "../markup";
import { utf16ToCp } from "../codePoints";

const ROOT = join(__dirname, "..", "..", "..", "..");
const FIXTURES = join(ROOT, "tests", "contract", "fixtures");
const GOLDEN = join(ROOT, "tests", "contract", "golden");

interface GoldenMarkup {
  error: string;
  error_code: string;
  error_at: number;
  tree: string;
}
interface Golden {
  ok: boolean;
  diagnostics: { code: string; severity: number; off: number; len: number }[];
  windows: { start: number; end: number }[];
  markup: GoldenMarkup[];
}

function fixtureNames(): string[] {
  return readdirSync(FIXTURES)
    .filter((f) => f.endsWith(".guitkx"))
    .sort();
}

// The comparable slice both sides produce, normalized to plain JSON-able data. The canonical offset
// unit for goldens is Unicode CODE POINTS (GDScript String indices — see codePoints.ts), so every
// UTF-16 offset the TS side produces is converted here. If a future MarkupNode field carries an
// offset and is not converted below, the emoji-bearing demo fixtures fail loudly — by design.
function tsDerive(src: string): { windows: { start: number; end: number }[]; markup: { error: string; error_code: string; error_at: number; nodes: unknown }[] } {
  const cp = (n: number): number => utf16ToCp(src, n);
  const cpAttr = (a: Attr): Attr => ({ ...a, at: cp(a.at), vat: cp(a.vat), end: cp(a.end) });
  const cpNode = (nd: MarkupNode): MarkupNode => {
    switch (nd.t) {
      case "el":
        return { ...nd, at: cp(nd.at), attrs: nd.attrs.map(cpAttr), children: nd.children.map(cpNode) };
      case "frag":
        return { ...nd, at: cp(nd.at), children: nd.children.map(cpNode) };
      case "text":
        return { ...nd, at: cp(nd.at) };
      case "expr":
        return { ...nd, at: cp(nd.at), vat: cp(nd.vat) };
      case "if":
        return { ...nd, at: cp(nd.at), branches: nd.branches.map((b) => ({ ...b, body_at: cp(b.body_at) })), else_body_at: cp(nd.else_body_at) };
      case "for":
      case "while":
        return { ...nd, at: cp(nd.at), body_at: cp(nd.body_at) };
      case "match":
        return { ...nd, at: cp(nd.at), cases: nd.cases.map((c) => ({ ...c, body_at: cp(c.body_at) })), default_body_at: cp(nd.default_body_at) };
    }
  };
  const windows = markupWindows(src);
  const markup = windows.map((w) => {
    const pr = parseMarkup(src, w.start, w.end);
    return { error: pr.error, error_code: pr.error_code, error_at: cp(pr.error_at), nodes: JSON.parse(JSON.stringify(pr.nodes.map(cpNode))) };
  });
  return { windows: windows.map((w) => ({ start: cp(w.start), end: cp(w.end) })), markup };
}

function goldenComparable(g: Golden): { windows: { start: number; end: number }[]; markup: { error: string; error_code: string; error_at: number; nodes: unknown }[] } {
  return {
    windows: g.windows,
    markup: g.markup.map((m) => ({ error: m.error, error_code: m.error_code, error_at: m.error_at, nodes: JSON.parse(m.tree) })),
  };
}

test("contract corpus: fixtures and goldens pair 1:1 and the corpus is broad", () => {
  const fixtures = fixtureNames();
  const goldens = readdirSync(GOLDEN)
    .filter((f) => f.endsWith(".json"))
    .sort();
  assert.ok(fixtures.length >= 25, `expected a broad corpus, got ${fixtures.length} fixtures`);
  assert.deepStrictEqual(
    goldens,
    fixtures.map((f) => f.replace(/\.guitkx$/, ".json")).sort(),
    "every fixture has exactly one golden (regen: godot --headless --path . --script res://tests/contract_dump.gd)",
  );
});

for (const name of fixtureNames()) {
  const pending = name.includes(".pending.");
  test(`contract ${pending ? "(pending divergence) " : ""}${name}`, () => {
    const src = readFileSync(join(FIXTURES, name), "utf8").replace(/\r/g, "");
    const golden = JSON.parse(readFileSync(join(GOLDEN, name.replace(/\.guitkx$/, ".json")), "utf8")) as Golden;
    const got = tsDerive(src);
    const want = goldenComparable(golden);
    if (pending) {
      assert.notDeepStrictEqual(got, want, `${name} now AGREES with the compiler — the divergence is fixed; drop '.pending' from the fixture name and regen goldens`);
      return;
    }
    assert.deepStrictEqual(got.windows, want.windows, `${name}: markup windows diverge (markupWindows vs guitkx.gd walk)`);
    for (let i = 0; i < want.markup.length; i++) {
      assert.strictEqual(got.markup[i].error, want.markup[i].error, `${name} window ${i}: parse error text diverges`);
      assert.strictEqual(got.markup[i].error_code, want.markup[i].error_code, `${name} window ${i}: parse error code diverges`);
      assert.strictEqual(got.markup[i].error_at, want.markup[i].error_at, `${name} window ${i}: parse error offset diverges`);
      assert.deepStrictEqual(got.markup[i].nodes, want.markup[i].nodes, `${name} window ${i}: node tree diverges (markup.ts vs guitkx_markup.gd)`);
    }
  });
}
