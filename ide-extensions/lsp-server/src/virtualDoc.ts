// Build the synthetic GDScript "virtual document" handed to @gdscript-analyzer/core, plus a source map.
// SCOPE-AWARE (Phase 4 §2): models Unity's VirtualDocumentGenerator — emit the REAL control-flow
// structure (`for x in xs:`, `if cond:`, `match subj:`) so loop/branch variables are in scope, with
// each embedded `{expr}` (attribute or child) as a `var _eN = (expr)` check INSIDE its block,
// recursively nested. Hook names are pre-declared as in-scope stubs so `use_state(...)` resolves.
// Markup/glue is never copied, so Godot only ever parses real GDScript. Embedded code is spliced
// VERBATIM (length-preserving), so the offset SourceMap round-trips 1:1 and survives future rewrites.

import { skipNoncode, skipString, findMatching, keywordAt } from "./scanner";
import { SourceMap } from "./sourceMap";

export interface VirtualDoc {
  text: string;
  map: SourceMap;
}

const HOOK_STUBS = [
  "use_state", "use_reducer", "use_ref", "use_memo", "use_callback", "use_effect",
  "use_layout_effect", "use_context", "use_signal", "use_tween_value", "use_tween",
];

interface Ctx {
  src: string;
  gen: string;
  map: SourceMap;
  counter: number;
}

export function buildVirtualDoc(src: string): VirtualDoc {
  const ctx: Ctx = { src, gen: "extends RefCounted\n", map: new SourceMap(), counter: 0 };
  const decl = findDecl(src);
  if (!decl) return { text: ctx.gen, map: ctx.map };

  if (decl.kind === "hook") {
    const body = readDeclBody(src, decl.at);
    if (!body) return { text: ctx.gen, map: ctx.map };
    ctx.gen += "static func __hook(props, children):\n";
    declareHookStubs(ctx, 1);
    const gs = ctx.gen.length;
    const block = reindent(body.text, 1);
    ctx.gen += block;
    // reindent() can change per-line lengths; only map when it didn't, else offsets drift. Mirrors
    // the component path's emitVerbatimBlock guard so hover/completion inside a hook stay accurate.
    if (block.length === body.text.length) ctx.map.addSpan(body.start, gs, body.text.length);
    ctx.gen += "\n\tpass\n";
    return { text: ctx.gen, map: ctx.map };
  }

  const body = readDeclBody(src, decl.at);
  ctx.gen += "static func render(props: Dictionary, children: Array) -> RUIVNode:\n";
  if (!body) {
    ctx.gen += "\tpass\n";
    return { text: ctx.gen, map: ctx.map };
  }
  for (const name of paramNames(readParams(src, decl.at))) ctx.gen += `\tvar ${name} = props.get("${name}")\n`;
  declareHookStubs(ctx, 1);
  const split = splitReturn(src, body.start, body.start + body.text.length);

  // setup verbatim (mapped, one line at a time so the per-line indent never shifts an expr offset)
  if (split && split.setupEnd > body.start) {
    emitVerbatimBlock(ctx, body.start, split.setupEnd, 1);
  }
  // scope-aware markup
  let emitted = false;
  if (split) {
    emitted = emitMarkup(ctx, split.markupStart, split.markupEnd, 1);
  }
  if (!emitted && (!split || split.setupEnd <= body.start)) ctx.gen += "\tpass\n";
  return { text: ctx.gen, map: ctx.map };
}

// --- scope-aware markup emitter -------------------------------------------------------------

const CONTROL_PAREN = ["if", "elif", "for", "while", "match", "case"];

// Walk markup [start,end) linearly at GDScript `indent`. A `<Tag>` adds no GDScript scope, so its
// children stay at the same indent (walked by this same loop); only control-flow adds scope (via
// emitControl, which recurses at indent+1). Returns true if any statement was emitted.
function emitMarkup(ctx: Ctx, start: number, end: number, indent: number): boolean {
  const src = ctx.src;
  let i = start;
  let any = false;
  while (i < end) {
    const c = src[i];
    if (c === '"' || c === "'") {
      i = skipString(src, i);
      continue;
    }
    if (c === "@") {
      const kw = readWord(src, i + 1);
      if (kw === "if" || kw === "for" || kw === "while" || kw === "match") {
        i = emitControl(ctx, i, kw, end, indent);
        any = true;
        continue;
      }
      i++;
      continue;
    }
    if (c === "<") {
      if (src[i + 1] === "/") {
        const gt = src.indexOf(">", i);
        i = gt === -1 || gt >= end ? end : gt + 1;
        continue;
      }
      if (/[A-Za-z_]/.test(src[i + 1] || "")) {
        const r = emitTagAttrs(ctx, i, end, indent);
        if (r.emitted) any = true;
        i = r.next;
        continue;
      }
      i++;
      continue;
    }
    if (c === "{") {
      const close = findMatching(src, i);
      if (close !== -1 && close < end) {
        emitExpr(ctx, i + 1, close, indent);
        any = true;
        i = close + 1;
        continue;
      }
    }
    i++;
  }
  return any;
}

// Emit a tag's `={expr}` attribute checks at `indent`; return the index past `>`/`/>` (children are
// walked by the caller's loop, same indent).
function emitTagAttrs(ctx: Ctx, lt: number, end: number, indent: number): { next: number; emitted: boolean } {
  const src = ctx.src;
  let i = lt + 1;
  while (i < end && /[A-Za-z0-9_]/.test(src[i])) i++; // tag name
  let emitted = false;
  while (i < end) {
    while (i < end && /\s/.test(src[i])) i++;
    if (i >= end) break;
    if (src[i] === "/" && src[i + 1] === ">") return { next: i + 2, emitted };
    if (src[i] === ">") return { next: i + 1, emitted };
    const an = i;
    while (i < end && /[A-Za-z0-9_.\-]/.test(src[i])) i++;
    if (i === an) {
      i++;
      continue;
    }
    while (i < end && /\s/.test(src[i])) i++;
    if (src[i] === "=") {
      i++;
      while (i < end && /\s/.test(src[i])) i++;
      if (src[i] === '"' || src[i] === "'") i = skipString(src, i);
      else if (src[i] === "{") {
        const close = findMatching(src, i);
        if (close !== -1 && close < end) {
          emitExpr(ctx, i + 1, close, indent);
          emitted = true;
          i = close + 1;
        } else i++;
      }
    }
  }
  return { next: end, emitted };
}

// Emit a control-flow block: `for <header>:` / `if <cond>:` / `match <subj>:` with the body's
// exprs nested at indent+1. Returns the index past the directive.
function emitControl(ctx: Ctx, at: number, kw: string, end: number, indent: number): number {
  const src = ctx.src;
  const pad = "\t".repeat(indent);
  // read (header)
  let p = at + 1 + kw.length;
  while (p < end && /\s/.test(src[p])) p++;
  if (src[p] !== "(") return p;
  const pc = findMatching(src, p);
  if (pc === -1 || pc >= end) return p;
  const headerStart = p + 1;
  const headerText = src.slice(headerStart, pc).trim();
  // body { ... }
  let b = pc + 1;
  while (b < end && /\s/.test(src[b])) b++;
  if (src[b] !== "{") return pc + 1;
  const bclose = findMatching(src, b);
  if (bclose === -1 || bclose >= end) return pc + 1;

  if (kw === "match") {
    ctx.gen += `${pad}match ${mapInline(ctx, headerStart, headerText)}:\n`;
    emitMatchArms(ctx, b + 1, bclose, indent + 1);
  } else {
    const keyword = kw === "elif" ? "if" : kw; // first-pass @if; elif/else handled in caller chain
    ctx.gen += `${pad}${keyword} ${mapInline(ctx, headerStart, headerText)}:\n`;
    const inner = emitMarkup(ctx, b + 1, bclose, indent + 1);
    if (!inner) ctx.gen += `${"\t".repeat(indent + 1)}pass\n`;
  }
  // @elif / @else chain
  let i = bclose + 1;
  while (i < end) {
    let k = i;
    while (k < end && /\s/.test(src[k])) k++;
    if (src[k] === "@" && keywordAt(src, k + 1, "elif")) {
      let ep = k + 5;
      while (ep < end && /\s/.test(src[ep])) ep++;
      if (src[ep] !== "(") break;
      const epc = findMatching(src, ep);
      if (epc === -1) break;
      const cond = src.slice(ep + 1, epc).trim();
      let eb = epc + 1;
      while (eb < end && /\s/.test(src[eb])) eb++;
      const ebc = findMatching(src, eb);
      if (ebc === -1) break;
      ctx.gen += `${pad}elif ${mapInline(ctx, ep + 1, cond)}:\n`;
      if (!emitMarkup(ctx, eb + 1, ebc, indent + 1)) ctx.gen += `${"\t".repeat(indent + 1)}pass\n`;
      i = ebc + 1;
    } else if (src[k] === "@" && keywordAt(src, k + 1, "else")) {
      let eb = k + 5;
      while (eb < end && /\s/.test(src[eb])) eb++;
      const ebc = findMatching(src, eb);
      if (ebc === -1) break;
      ctx.gen += `${pad}else:\n`;
      if (!emitMarkup(ctx, eb + 1, ebc, indent + 1)) ctx.gen += `${"\t".repeat(indent + 1)}pass\n`;
      i = ebc + 1;
    } else break;
  }
  return i;
}

function emitMatchArms(ctx: Ctx, start: number, end: number, indent: number): void {
  const src = ctx.src;
  const pad = "\t".repeat(indent);
  let i = start;
  let emittedArm = false;
  while (i < end) {
    while (i < end && /\s/.test(src[i])) i++;
    if (i >= end) break;
    if (src[i] === "@" && keywordAt(src, i + 1, "case")) {
      let p = i + 5;
      while (p < end && /\s/.test(src[p])) p++;
      if (src[p] !== "(") break;
      const pc = findMatching(src, p);
      if (pc === -1) break;
      const val = src.slice(p + 1, pc).trim();
      let b = pc + 1;
      while (b < end && /\s/.test(src[b])) b++;
      const bclose = findMatching(src, b);
      if (bclose === -1) break;
      ctx.gen += `${pad}${mapInline(ctx, p + 1, val)}:\n`;
      if (!emitMarkup(ctx, b + 1, bclose, indent + 1)) ctx.gen += `${"\t".repeat(indent + 1)}pass\n`;
      emittedArm = true;
      i = bclose + 1;
    } else if (src[i] === "@" && keywordAt(src, i + 1, "default")) {
      let b = i + 8;
      while (b < end && /\s/.test(src[b])) b++;
      const bclose = findMatching(src, b);
      if (bclose === -1) break;
      ctx.gen += `${pad}_:\n`;
      if (!emitMarkup(ctx, b + 1, bclose, indent + 1)) ctx.gen += `${"\t".repeat(indent + 1)}pass\n`;
      emittedArm = true;
      i = bclose + 1;
    } else i++;
  }
  if (!emittedArm) ctx.gen += `${pad}_:\n${"\t".repeat(indent + 1)}pass\n`;
}

// Emit `var _eN = (<expr>)` at `indent`, mapping the expr text verbatim.
function emitExpr(ctx: Ctx, start: number, end: number, indent: number): void {
  const text = ctx.src.slice(start, end);
  const trimmed = text.replace(/^\s+/, "");
  const lead = text.length - trimmed.length;
  if (trimmed.trim() === "") return;
  const prefix = `${"\t".repeat(indent)}var _e${ctx.counter++} = (`;
  ctx.gen += prefix;
  const gs = ctx.gen.length;
  ctx.gen += trimmed;
  ctx.map.addSpan(start + lead, gs, trimmed.length);
  ctx.gen += ")\n";
}

// Splice an inline expression (a condition/header/match value) into the current line, mapped.
function mapInline(ctx: Ctx, srcStart: number, text: string): string {
  const gs = ctx.gen.length;
  ctx.map.addSpan(srcStart, gs, text.length);
  return text;
}

// Emit a verbatim source block [start,end) at `indent`, mapping it (best-effort, line-preserving).
function emitVerbatimBlock(ctx: Ctx, start: number, end: number, indent: number): void {
  const text = ctx.src.slice(start, end);
  const block = reindent(text, indent);
  // map the whole block verbatim where lengths line up (setup is rarely re-indented in practice)
  const gs = ctx.gen.length;
  ctx.gen += block;
  if (block.length === text.length) ctx.map.addSpan(start, gs, text.length);
  if (!block.endsWith("\n")) ctx.gen += "\n";
}

function declareHookStubs(ctx: Ctx, indent: number): void {
  const pad = "\t".repeat(indent);
  for (const h of HOOK_STUBS) ctx.gen += `${pad}var ${h} = Hooks.${h}\n`;
}

function reindent(text: string, indent: number): string {
  // dedent to common leading whitespace, re-indent to `indent` tabs
  const lines = text.split("\n");
  let prefix: string | null = null;
  for (const l of lines) {
    if (l.trim() === "") continue;
    const lead = l.match(/^[\t ]*/)![0];
    prefix = prefix === null ? lead : commonPrefix(prefix, lead);
  }
  const pad = "\t".repeat(indent);
  return lines
    .map((l) => (l.trim() === "" ? "" : pad + l.slice((prefix ?? "").length)))
    .join("\n");
}

function commonPrefix(a: string, b: string): string {
  let i = 0;
  while (i < a.length && i < b.length && a[i] === b[i]) i++;
  return a.slice(0, i);
}

// --- declaration / window helpers (mirror guitkx.gd) ----------------------------------------

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

function readDeclBody(src: string, declAt: number): { text: string; start: number } | null {
  const n = src.length;
  let j = declAt;
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

function readWord(src: string, i: number): string {
  let j = i;
  while (j < src.length && /[A-Za-z_]/.test(src[j])) j++;
  return src.slice(i, j);
}

// The `(...)` parameter list of a component/hook declaration (between the name and the body `{`).
function readParams(src: string, declAt: number): string {
  const n = src.length;
  let j = declAt;
  while (j < n && src[j] !== "(" && src[j] !== "{") {
    const k = skipNoncode(src, j);
    if (k !== j) {
      j = k;
      continue;
    }
    j++;
  }
  if (src[j] !== "(") return "";
  const pc = findMatching(src, j);
  if (pc === -1) return "";
  return src.slice(j + 1, pc);
}

// Parameter names from a params string ("a: int = 0, b: String") — split on top-level commas, take
// the identifier before any `:` type-hint or `=` default. NONCODE-AWARE (mirrors the GDScript
// authority's _split_top_commas/_find_top): strings, comments and bracket groups are skipped, so a
// comma/colon inside a default like `label: String = "a, b"` or `"x:y"` never mis-splits. [audit #26]
function paramNames(params: string): string[] {
  if (params.trim() === "") return [];
  const out: string[] = [];
  const n = params.length;
  let start = 0;
  let i = 0;
  const push = (chunk: string) => {
    // Strip the type hint (`: …`) and default (`= …`), finding the boundary noncode-aware.
    let endName = chunk.length;
    let j = 0;
    while (j < chunk.length) {
      const k = skipNoncode(chunk, j);
      if (k !== j) {
        j = k;
        continue;
      }
      const cc = chunk[j];
      if (cc === "(" || cc === "[" || cc === "{") {
        const m = findMatching(chunk, j);
        j = m === -1 ? chunk.length : m + 1;
        continue;
      }
      if (cc === "=" || cc === ":") {
        endName = j;
        break;
      }
      j++;
    }
    const name = chunk.slice(0, endName).trim();
    if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) out.push(name);
  };
  while (i < n) {
    const k = skipNoncode(params, i);
    if (k !== i) {
      i = k;
      continue;
    }
    const ch = params[i];
    if (ch === "(" || ch === "[" || ch === "{") {
      const m = findMatching(params, i);
      i = m === -1 ? i + 1 : m + 1;
      continue;
    }
    if (ch === ",") {
      push(params.slice(start, i));
      start = i + 1;
    }
    i++;
  }
  push(params.slice(start));
  return out;
}
