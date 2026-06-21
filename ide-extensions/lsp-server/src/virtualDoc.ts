// Build the synthetic GDScript "virtual document" we hand to Godot's LSP, plus a source map.
// Strategy (Volar technique, hand-rolled): splice the embedded-GDScript regions of a .guitkx
// (the component setup, each {expr}, each @if/@for/... condition) VERBATIM into a minimal GDScript
// scaffold, recording a length-preserving span for each so offsets round-trip 1:1. Markup/glue is
// not copied, so Godot's LSP only ever parses real GDScript. Completion/hover/diagnostics requested
// at a .guitkx offset are translated into the virtual doc, forwarded, and mapped back.

import { skipNoncode, skipString, findMatching, keywordAt } from "./scanner";
import { SourceMap } from "./sourceMap";

export interface VirtualDoc {
  text: string;
  map: SourceMap;
}

const CONTROL_PAREN = ["if", "elif", "for", "while", "match", "case"];

/** Build a virtual .gd for `src` (a .guitkx document). Best-effort: unparseable input yields the
 *  scaffold with whatever spans were found before the problem. */
export function buildVirtualDoc(src: string): VirtualDoc {
  const map = new SourceMap();
  let gen = "extends RefCounted\n";

  const decl = findDecl(src);
  if (!decl) return { text: gen, map };

  if (decl.kind === "hook") {
    // hook body is plain GDScript: splice it verbatim inside a function scope
    const body = readDeclBody(src, decl.at);
    if (!body) return { text: gen, map };
    gen += "static func __hook(props, children):\n";
    const genStart = gen.length;
    gen += body.text;
    map.addSpan(body.start, genStart, body.text.length);
    gen += "\n";
    return { text: gen, map };
  }

  // component: setup verbatim + each embedded expression as `var __eN = (<expr>)`
  const body = readDeclBody(src, decl.at);
  if (!body) {
    gen += "static func render(props, children):\n\tpass\n";
    return { text: gen, map };
  }
  gen += "static func render(props, children):\n";

  const split = splitReturn(src, body.start, body.start + body.text.length);
  // setup (verbatim — already indented one level inside the component body)
  if (split && split.setupEnd > body.start) {
    const setupText = src.slice(body.start, split.setupEnd);
    const genStart = gen.length;
    gen += setupText;
    map.addSpan(body.start, genStart, setupText.length);
    if (!setupText.endsWith("\n")) gen += "\n";
  }

  // embedded expressions inside the markup window
  const exprs: { start: number; text: string }[] = [];
  if (split) {
    collectExprs(src, split.markupStart, split.markupEnd, exprs);
  }
  let n = 0;
  for (const e of exprs) {
    const prefix = `\tvar __e${n} = (`;
    gen += prefix;
    const genStart = gen.length;
    gen += e.text;
    map.addSpan(e.start, genStart, e.text.length);
    gen += ")\n";
    n++;
  }
  if (exprs.length === 0 && (!split || split.setupEnd <= body.start)) gen += "\tpass\n";

  return { text: gen, map };
}

// --- declaration / body helpers (mirror guitkx.gd) ---

interface Decl {
  kind: "component" | "hook" | "module";
  at: number;
}

function findDecl(src: string): Decl | null {
  const n = src.length;
  let i = 0;
  while (i < n) {
    const k = skipNoncode(src, i);
    if (k !== i) {
      i = k;
      continue;
    }
    if (keywordAt(src, i, "component")) return { kind: "component", at: i };
    if (keywordAt(src, i, "hook")) return { kind: "hook", at: i };
    if (keywordAt(src, i, "module")) return { kind: "module", at: i };
    i++;
  }
  return null;
}

/** From a declaration keyword, find the `{ ... }` body. Returns the inner text + its start offset. */
function readDeclBody(src: string, declAt: number): { text: string; start: number } | null {
  const n = src.length;
  let j = declAt;
  // skip to the first top-level `{` after the signature
  while (j < n && src[j] !== "{") {
    const k = skipNoncode(src, j);
    if (k !== j) {
      j = k;
      continue;
    }
    if (src[j] === "(") {
      const pc = findMatching(src, j);
      if (pc === -1) return null;
      j = pc + 1;
      continue;
    }
    j++;
  }
  if (j >= n || src[j] !== "{") return null;
  const close = findMatching(src, j);
  if (close === -1) return null;
  return { text: src.slice(j + 1, close), start: j + 1 };
}

interface ReturnSplit {
  setupEnd: number;
  markupStart: number;
  markupEnd: number;
}

function splitReturn(src: string, start: number, end: number): ReturnSplit | null {
  let i = start;
  while (i < end) {
    const k = skipNoncode(src, i);
    if (k !== i) {
      i = k;
      continue;
    }
    if (keywordAt(src, i, "return")) {
      let p = i + 6;
      while (p < end && /\s/.test(src[p])) p++;
      if (src[p] === "(") {
        const close = findMatching(src, p);
        if (close === -1) return null;
        return { setupEnd: i, markupStart: p + 1, markupEnd: close };
      }
      if (src[p] === "<") return { setupEnd: i, markupStart: p, markupEnd: end };
    }
    i++;
  }
  return { setupEnd: end, markupStart: end, markupEnd: end };
}

/** Walk a markup window and collect every embedded-GDScript expression: {expr} attribute/child
 *  values and @if/@for/... conditions. Recurses into control-flow bodies. */
function collectExprs(src: string, start: number, end: number, out: { start: number; text: string }[]): void {
  let i = start;
  while (i < end) {
    const c = src[i];
    if (c === '"' || c === "'") {
      i = skipString(src, i);
      continue;
    }
    if (c === "@") {
      const kw = readWord(src, i + 1);
      if (CONTROL_PAREN.includes(kw)) {
        // condition `( ... )`
        let p = i + 1 + kw.length;
        while (p < end && /\s/.test(src[p])) p++;
        if (src[p] === "(") {
          const pc = findMatching(src, p);
          if (pc !== -1 && pc < end) {
            out.push({ start: p + 1, text: src.slice(p + 1, pc) });
            i = pc + 1;
            // body brace
            i = recurseBody(src, i, end, out);
            continue;
          }
        }
      } else if (kw === "else" || kw === "default") {
        i = recurseBody(src, i + 1 + kw.length, end, out);
        continue;
      }
      i++;
      continue;
    }
    if (c === "{") {
      const close = findMatching(src, i);
      if (close !== -1 && close < end) {
        out.push({ start: i + 1, text: src.slice(i + 1, close) });
        i = close + 1;
        continue;
      }
    }
    i++;
  }
}

function recurseBody(src: string, i: number, end: number, out: { start: number; text: string }[]): number {
  while (i < end && /\s/.test(src[i])) i++;
  if (src[i] === "{") {
    const bclose = findMatching(src, i);
    if (bclose !== -1 && bclose < end) {
      collectExprs(src, i + 1, bclose, out);
      return bclose + 1;
    }
  }
  return i + 1;
}

function readWord(src: string, i: number): string {
  let j = i;
  while (j < src.length && /[A-Za-z_]/.test(src[j])) j++;
  return src.slice(i, j);
}
