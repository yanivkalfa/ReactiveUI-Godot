// In-process TypeScript formatter — a faithful port of addons/reactive_ui/guitkx/guitkx_formatter.gd.
// Lets VS Code / VS2022 "Format Document" run instantly, offline, with NO Godot binary (the old path
// shelled out to headless Godot). Output is kept BYTE-IDENTICAL to the GDScript formatter via a shared
// golden-fixture corpus asserted on both sides (test-fixtures/formatter-cases.json). AST-driven re-emit
// over markup.ts; returns the source VERBATIM on any parse error (never corrupts); idempotent.

import { parseMarkup, MarkupNode, Attr } from "./markup";
import { skipNoncode, findMatching, keywordAt, isIdent } from "./scanner";
import { findDecl } from "./declScan";
import { findElementEnd, markupAt } from "./jsxScan";
import { existsSync, readFileSync } from "fs";
import { dirname, join } from "path";

export interface FmtOptions {
  printWidth: number;
  indentStyle: "tab" | "space";
  indentSize: number;
  singleAttributePerLine: boolean;
  insertSpaceBeforeSelfClose: boolean;
}
// Phase D: Unity-exact defaults — spaces at width 2 ([uitkx]'s configurationDefaults), user-set
// "tab is 2 spaces". Keep guitkx_formatter.gd's OPTIONS in lockstep (parity corpus pins both).
const DEFAULTS: FmtOptions = {
  printWidth: 100,
  indentStyle: "space",
  indentSize: 2,
  singleAttributePerLine: false,
  insertSpaceBeforeSelfClose: true,
};

export function formatGuitkx(source: string, opts?: Partial<FmtOptions>): { text: string; changed: boolean } {
  const o: FmtOptions = { ...DEFAULTS, ...(opts || {}) };
  const text = formatOrVerbatim(source, o);
  return { text, changed: text !== source };
}

function formatOrVerbatim(source: string, o: FmtOptions): string {
  const n = source.length;
  let i = 0;
  let classNameLine = "";
  while (i < n) {
    i = skipWsNl(source, i);
    // T3.5: directive keywords require a token boundary (`@class_nameFoo` is not a directive).
    if (source.slice(i, i + 11) === "@class_name" && (i + 11 >= n || !isIdent(source[i + 11]))) {
      let le = source.indexOf("\n", i);
      if (le === -1) le = n;
      classNameLine = source.slice(i, le).trim();
      i = le;
      continue;
    }
    break;
  }
  const decl = findDecl(source, i);
  if (decl.kind === "") return source;
  // T1.3: the preamble (everything before the declaration keyword) is canonicalized ONLY when it is
  // nothing but whitespace + the @class_name line. Leading comments or stray text are preserved
  // byte-for-byte -- Format Document must never delete user content (it used to eat file-header
  // comments whole).
  const pre = source.slice(0, decl.at);
  const preCanonical = pre.replace(/@class_name[^\n]*/, "").trim() === "";
  let out = "";
  if (!preCanonical) out += pre;
  else if (classNameLine !== "") out += classNameLine + "\n\n";
  let declEnd = -1;
  switch (decl.kind) {
    case "component": {
      const pc = parseComponentAt(source, decl.at);
      if (!pc.ok) return source;
      out += fmtComponent(pc.name, pc.params, pc.setup, pc.nodes, o);
      declEnd = pc.next;
      break;
    }
    case "hook": {
      const ph = parseHookAt(source, decl.at);
      if (!ph.ok) return source;
      out += fmtHook(ph.name, ph.params, ph.body, o);
      declEnd = ph.next;
      break;
    }
    case "module": {
      const m = fmtModule(source, decl.at, o);
      if (m === null) return source;
      out += m.text;
      declEnd = m.next;
      break;
    }
    default:
      return source;
  }
  // T1.3: content after the declaration (a second component, stray text) is a GUITKX2105 compile
  // error, but it must round-trip the formatter untouched -- emitted verbatim after exactly one
  // canonical blank line (idempotent).
  if (declEnd >= 0 && declEnd < n) {
    const trailing = source.slice(declEnd);
    if (trailing.trim() !== "") out = out.replace(/[ \t\n]+$/, "") + "\n\n" + trailing.replace(/^[ \t\n]+/, "");
  }
  return out.replace(/[ \t\n]+$/, "") + "\n";
}

// --- declarations ---

function fmtComponent(name: string, params: string, setup: string, nodes: MarkupNode[], o: FmtOptions): string {
  let out = `component ${name}${fmtParams(params)} {\n`;
  const fs = fmtSetup(setup, 1, o);
  if (fs !== "") {
    if (hasLeadingBlank(setup)) out += "\n"; // keep an authored blank line after `{`
    out += fs;
    if (hasTrailingBlank(setup)) out += "\n"; // keep an authored blank line before `return (`
  }
  out += pad(1, o) + "return (\n";
  // T2.1: every window node in order -- the render root plus any sibling comments.
  for (const nd of nodes) {
    if (nd == null) continue;
    out += fmtNode(nd, 2, o);
  }
  out += pad(1, o) + ")\n";
  out += "}\n";
  return out;
}

function fmtHook(name: string, params: string, body: string, o: FmtOptions): string {
  let out = `hook ${name}${fmtParams(params)} {\n`;
  const fb = fmtSetup(body, 1, o);
  if (fb !== "") {
    if (hasLeadingBlank(body)) out += "\n";
    out += fb;
    if (hasTrailingBlank(body)) out += "\n";
  }
  out += "}\n";
  return out;
}

// An authored blank line at the start / end of an embedded block (between `{`→first-stmt or
// last-stmt→`return`). reanchor() strips block-boundary blanks; these let fmtComponent/fmtHook keep
// one. [audit #1]
function hasLeadingBlank(s: string): boolean {
  return /^[ \t]*\n[ \t]*\n/.test(s);
}
function hasTrailingBlank(s: string): boolean {
  return /\n[ \t]*\n[ \t]*$/.test(s);
}

function fmtModule(src: string, mi: number, o: FmtOptions): { text: string; next: number } | null {
  const n = src.length;
  let j = mi;
  while (j < n && isIdent(src[j])) j++; // skip the `module` keyword token
  j = skipWsOnly(src, j);
  const ns = j;
  while (j < n && isIdent(src[j])) j++;
  const modName = src.slice(ns, j);
  j = skipWsOnly(src, j);
  if (j >= n || src[j] !== "{") return null;
  const bclose = findMatching(src, j);
  if (bclose === -1) return null;
  let out = `module ${modName} {\n`;
  let i = j + 1;
  let first = true;
  while (i < bclose) {
    const d = findDecl(src, i);
    // T1.3: real content between members that isn't a declaration would be silently DROPPED by the
    // re-emit below (findDecl skips it). The compiler now errors on it (GUITKX2105); the formatter
    // falls back to verbatim -- it must never delete user text.
    const scanTo = d.kind === "" ? bclose : Math.min(d.at, bclose);
    if (realSpan(src, i, scanTo)) return null;
    if (d.kind === "" || d.at >= bclose) break;
    if (!first) out += "\n";
    first = false;
    if (d.kind === "component") {
      const c = parseComponentAt(src, d.at);
      if (!c.ok) return null;
      out += indentBlock(fmtComponent(c.name, c.params, c.setup, c.nodes, o), 1, o);
      i = c.next;
    } else if (d.kind === "hook") {
      const h = parseHookAt(src, d.at);
      if (!h.ok) return null;
      out += indentBlock(fmtHook(h.name, h.params, h.body, o), 1, o);
      i = h.next;
    } else {
      return null;
    }
  }
  out += "}\n";
  return { text: out, next: bclose + 1 };
}

// --- markup ---

function fmtNode(nd: MarkupNode, indent: number, o: FmtOptions): string {
  switch (nd.t) {
    case "el":
      return fmtElement(nd, indent, o);
    case "frag": {
      const inner = fmtChildren(nd.children, indent + 1, o);
      // T2.2: the named <Fragment> alias keeps the author's spelling + attrs (key/comments).
      if (nd.named) {
        let head = `<${nd.named}`;
        for (const a of nd.attrs ?? []) head += " " + fmtAttr(a);
        return `${pad(indent, o)}${head}>\n${inner}${pad(indent, o)}</${nd.named}>\n`;
      }
      return `${pad(indent, o)}<>\n${inner}${pad(indent, o)}</>\n`;
    }
    case "comment":
      // T2.1: comments are preserved verbatim (re-anchored to the current indent).
      return `${pad(indent, o)}${nd.raw.trim()}\n`;
    case "text":
      return `${pad(indent, o)}${nd.value.trim()}\n`;
    case "expr":
      return `${pad(indent, o)}{ ${nd.code.trim()} }\n`;
    case "if":
      return fmtIf(nd, indent, o);
    case "for":
      return fmtLoop(nd, indent, o, "for");
    case "while":
      return fmtLoop(nd, indent, o, "while");
    case "match":
      return fmtMatch(nd, indent, o);
    default:
      return "";
  }
}

function fmtElement(nd: Extract<MarkupNode, { t: "el" }>, indent: number, o: FmtOptions): string {
  const p = pad(indent, o);
  const tag = nd.tag;
  const attrStrs = nd.attrs.map(fmtAttr);
  const children = nd.children.filter((x) => x != null);
  const selfClose = children.length === 0;
  const attrInline = attrStrs.join(" ");
  let head = `<${tag}`;
  if (attrStrs.length > 0) head += " " + attrInline;
  const singleClose = selfClose ? (o.insertSpaceBeforeSelfClose ? " />" : "/>") : ">";
  const single = head + singleClose;
  let wrap = o.singleAttributePerLine && attrStrs.length > 1;
  if (!wrap && p.length + single.length > o.printWidth && attrStrs.length > 1) wrap = true;
  let out = "";
  if (!wrap) {
    if (selfClose) return p + single + "\n";
    out += p + single + "\n";
  } else {
    out += p + `<${tag}\n`;
    const apad = pad(indent + 1, o);
    for (let k = 0; k < attrStrs.length; k++) {
      const last = k === attrStrs.length - 1;
      if (last && selfClose) out += apad + attrStrs[k] + (o.insertSpaceBeforeSelfClose ? " />" : "/>") + "\n";
      else if (last) out += apad + attrStrs[k] + "\n" + p + ">\n";
      else out += apad + attrStrs[k] + "\n";
    }
    if (selfClose) return out;
  }
  out += fmtChildren(children, indent + 1, o);
  out += p + `</${tag}>\n`;
  return out;
}

function fmtChildren(children: MarkupNode[], indent: number, o: FmtOptions): string {
  let out = "";
  for (const c of children) {
    if (c == null) continue;
    out += fmtNode(c, indent, o);
  }
  return out;
}

function fmtAttr(a: Attr): string {
  switch (a.kind) {
    case "str":
      return `${a.name}="${a.value}"`;
    case "expr":
      return `${a.name}={ ${a.value.trim()} }`;
    case "spread":
      return `{...${a.value.trim()}}`;
    case "bool":
      return a.name;
    case "comment":
      return a.value; // T2.1: `{/* ... */}` preserved verbatim
  }
  return a.name;
}

function fmtIf(nd: Extract<MarkupNode, { t: "if" }>, indent: number, o: FmtOptions): string {
  const p = pad(indent, o);
  let out = "";
  for (let k = 0; k < nd.branches.length; k++) {
    const br = nd.branches[k];
    const kw = k === 0 ? "@if" : "@elif";
    if (k === 0) out += `${p}${kw} (${br.cond.trim()}) {\n`;
    else out = out.replace(/\n$/, "") + ` ${kw} (${br.cond.trim()}) {\n`;
    out += fmtBody(br.body_markup, indent + 1, o);
    out += p + "}\n";
  }
  if (nd.else_body !== null) {
    out = out.replace(/\n$/, "") + " @else {\n";
    out += fmtBody(nd.else_body, indent + 1, o);
    out += p + "}\n";
  }
  return out;
}

function fmtLoop(nd: Extract<MarkupNode, { t: "for" | "while" }>, indent: number, o: FmtOptions, kw: string): string {
  const p = pad(indent, o);
  let out = `${p}@${kw} (${nd.header.trim()}) {\n`;
  out += fmtBody(nd.body_markup, indent + 1, o);
  out += p + "}\n";
  return out;
}

function fmtMatch(nd: Extract<MarkupNode, { t: "match" }>, indent: number, o: FmtOptions): string {
  const p = pad(indent, o);
  let out = `${p}@match (${nd.subject.trim()}) {\n`;
  for (const c of nd.cases) {
    out += `${pad(indent + 1, o)}@case (${c.value.trim()}) {\n`;
    out += fmtBody(c.body_markup, indent + 2, o);
    out += pad(indent + 1, o) + "}\n";
  }
  if (nd.default_body !== null) {
    out += `${pad(indent + 1, o)}@default {\n`;
    out += fmtBody(nd.default_body, indent + 2, o);
    out += pad(indent + 1, o) + "}\n";
  }
  out += p + "}\n";
  return out;
}

// --- Phase D: directive-body splitter (mirrors guitkx.gd _split_body -- change BOTH or neither) ---
// A directive body is CODE: prep statements + directive-level returns. Every directive-level return
// is classified (paren-markup / bare markup / value / null / void); returns inside nested `func():`
// scopes (indent-tracked) belong to the lambda (`rewrite: false` -- markup lowers, `return` stays).
// Markup at statement position outside a return = the pre-0.7 grammar -> `legacy_at` (GUITKX2103).
export type BodyPart =
  | { t: "gd"; from: number; to: number }
  | { t: "ret"; at: number; end: number; m_start: number; m_end: number; shape: "paren" | "bare" | "value" | "null" | "void"; depth: number; markup: boolean; rewrite: boolean };
export interface BodySplit {
  parts: BodyPart[];
  rets: number;
  legacy_at: number;
  unit: number;
  anchor: number;
  error?: { code: string; message: string; at: number };
}

export function splitBody(body: string): BodySplit {
  const n = body.length;
  const lines = body.split("\n");
  const unit = indentUnit(lines);
  let anchor = -1;
  let anchorAny = -1;
  for (const l of lines) {
    const t = l.trim();
    if (t === "") continue;
    const d = indentDepth(l, unit);
    if (anchorAny === -1) anchorAny = d;
    if (!t.startsWith("#")) {
      anchor = d;
      break;
    }
  }
  if (anchor === -1) anchor = anchorAny;
  if (anchor === -1) anchor = 0;
  // per-line lambda floor: innermost enclosing func-header depth (-1 = not inside a lambda)
  const lineStart: number[] = [0];
  for (let ci = 0; ci < n; ci++) if (body[ci] === "\n") lineStart.push(ci + 1);
  const floors: number[] = [];
  const fstack: number[] = [];
  for (const l of lines) {
    const t = l.trim();
    if (t === "" || t.startsWith("#")) {
      floors.push(fstack.length === 0 ? -1 : fstack[fstack.length - 1]);
      continue;
    }
    const d = indentDepth(l, unit);
    while (fstack.length > 0 && d <= fstack[fstack.length - 1]) fstack.pop();
    floors.push(fstack.length === 0 ? -1 : fstack[fstack.length - 1]);
    if (lineOpensFunc(l)) fstack.push(d);
  }
  const parts: BodyPart[] = [];
  let rets = 0;
  let legacyAt = -1;
  let cursor = 0;
  let lineIdx = 0;
  let bdepth = 0;
  let i = 0;
  const pushRet = (ret: Extract<BodyPart, { t: "ret" }>): void => {
    if (ret.at > cursor) parts.push({ t: "gd", from: cursor, to: ret.at });
    parts.push(ret);
    cursor = ret.end;
  };
  while (i < n) {
    const k = skipNoncode(body, i);
    if (k !== i) {
      i = k;
      continue;
    }
    while (lineIdx + 1 < lineStart.length && lineStart[lineIdx + 1] <= i) lineIdx++;
    const ls = lineStart[lineIdx];
    const prefix = body.slice(ls, i);
    const atStmt = prefix.trim() === "" && bdepth <= 0;
    const inLambda = floors[lineIdx] !== -1;
    const c = body[i];
    if (c === "(" || c === "[" || c === "{") {
      bdepth++;
      i++;
      continue;
    }
    if (c === ")" || c === "]" || c === "}") {
      bdepth--;
      i++;
      continue;
    }
    if (c === "<" && markupAt(body, i, n)) {
      if (atStmt && !inLambda && legacyAt === -1) legacyAt = i;
      const ee = findElementEnd(body, i, n);
      i = ee === -1 ? n : ee;
      continue;
    }
    if (c === "@" && atStmt && !inLambda && (keywordAt(body, i + 1, "if") || keywordAt(body, i + 1, "for") || keywordAt(body, i + 1, "while") || keywordAt(body, i + 1, "match"))) {
      if (legacyAt === -1) legacyAt = i;
      i++;
      continue;
    }
    if (!keywordAt(body, i, "return")) {
      i++;
      continue;
    }
    let p = i + 6;
    while (p < n && (body[p] === " " || body[p] === "\t")) p++;
    let depth = indentDepth(prefix, unit);
    const pt = prefix.trim();
    if (pt !== "" && pt.endsWith(":")) depth += 1;
    if (inLambda) {
      if (p < n && body[p] === "(") {
        const lc = findMatching(body, p);
        if (lc === -1) return { parts, rets, legacy_at: legacyAt, unit, anchor, error: { code: "GUITKX0304", message: "unclosed `(` after return", at: p } };
        if (parenHoldsMarkup(body, p + 1, lc)) pushRet({ t: "ret", at: i, end: lc + 1, m_start: p + 1, m_end: lc, shape: "paren", depth, markup: true, rewrite: false });
        i = lc + 1;
        continue;
      }
      if (p < n && body[p] === "<") {
        const lb = findElementEnd(body, p, n);
        if (lb === -1) return { parts, rets, legacy_at: legacyAt, unit, anchor, error: { code: "GUITKX0304", message: "unclosed markup in a `return`", at: p } };
        pushRet({ t: "ret", at: i, end: lb, m_start: p, m_end: lb, shape: "bare", depth, markup: true, rewrite: false });
        i = lb;
        continue;
      }
      i = p;
      continue;
    }
    rets++;
    if (p >= n || body[p] === "\n") {
      pushRet({ t: "ret", at: i, end: p, m_start: p, m_end: p, shape: "void", depth, markup: false, rewrite: true });
      i = p;
      continue;
    }
    if (body[p] === "(") {
      const pc = findMatching(body, p);
      if (pc === -1) return { parts, rets, legacy_at: legacyAt, unit, anchor, error: { code: "GUITKX0304", message: "unclosed `(` after return", at: p } };
      pushRet({ t: "ret", at: i, end: pc + 1, m_start: p + 1, m_end: pc, shape: "paren", depth, markup: parenHoldsMarkup(body, p + 1, pc), rewrite: true });
      i = pc + 1;
      continue;
    }
    if (body[p] === "<") {
      const bb = findElementEnd(body, p, n);
      if (bb === -1) return { parts, rets, legacy_at: legacyAt, unit, anchor, error: { code: "GUITKX0304", message: "unclosed markup in a `return`", at: p } };
      pushRet({ t: "ret", at: i, end: bb, m_start: p, m_end: bb, shape: "bare", depth, markup: true, rewrite: true });
      i = bb;
      continue;
    }
    const se = stmtEnd(body, p);
    const vt = body.slice(p, se).trim();
    const vshape = vt === "null" ? "null" : vt === "" ? "void" : "value";
    pushRet({ t: "ret", at: i, end: se, m_start: p, m_end: se, shape: vshape, depth, markup: false, rewrite: true });
    i = se;
  }
  if (cursor < n) parts.push({ t: "gd", from: cursor, to: n });
  return { parts, rets, legacy_at: legacyAt, unit, anchor };
}

// True when the line opens a lambda scope (a `func` token outside strings/comments).
function lineOpensFunc(l: string): boolean {
  let i = 0;
  const n = l.length;
  while (i < n) {
    const j = skipNoncode(l, i);
    if (j !== i) {
      i = j;
      continue;
    }
    if (keywordAt(l, i, "func")) return true;
    i++;
  }
  return false;
}

// End of the statement starting at `from`: first newline at bracket depth 0, or the body end.
function stmtEnd(body: string, from: number): number {
  let i = from;
  const n = body.length;
  let depth = 0;
  while (i < n) {
    const j = skipNoncode(body, i);
    if (j !== i) {
      i = j;
      continue;
    }
    const c = body[i];
    if (c === "(" || c === "[" || c === "{") depth++;
    else if (c === ")" || c === "]" || c === "}") depth--;
    else if (c === "\n" && depth <= 0) return i;
    i++;
  }
  return n;
}

// Phase D: format one directive body -- CODE segments re-anchored with the WHOLE body's geometry,
// each markup return re-emitted as `return (` + recursively formatted markup + `)` at its own
// relative depth. Mirrors guitkx_formatter.gd _fmt_body (the corpus pins byte parity). Legacy or
// unsplittable bodies re-anchor verbatim (never corrupt).
function fmtBody(bodySrc: string, indent: number, o: FmtOptions): string {
  const sp = splitBody(bodySrc);
  if (sp.error || sp.legacy_at !== -1) return reanchor(bodySrc, indent, o);
  let out = "";
  for (const part of sp.parts) {
    if (part.t === "gd") {
      const seg = bodySrc.slice(part.from, part.to);
      if (seg.trim() !== "") out += reanchorRel(seg, indent, sp.unit, sp.anchor, o);
      continue;
    }
    const lvl = indent + Math.max(0, part.depth - sp.anchor);
    const p = pad(lvl, o);
    if (part.shape === "null") {
      out += p + "return null\n";
      continue;
    }
    if (part.shape === "void") {
      out += p + "return\n";
      continue;
    }
    const payload = bodySrc.slice(part.m_start, part.m_end);
    if (!part.markup) {
      out += part.shape === "paren" ? `${p}return ( ${collapseSpaces(payload.trim())} )\n` : `${p}return ${collapseSpaces(payload.trim())}\n`;
      continue;
    }
    const pr = parseMarkup(bodySrc, part.m_start, part.m_end);
    if (pr.error !== "") {
      out += p + bodySrc.slice(part.at, part.end).trim() + "\n";
      continue;
    }
    out += p + "return (\n";
    for (const nx of pr.nodes.filter((x) => x != null)) out += fmtNode(nx!, lvl + 1, o);
    out += p + ")\n";
  }
  return out;
}

// Re-anchor a body SEGMENT using the whole body's unit/anchor (not its own first line).
function reanchorRel(code: string, indent: number, unit: number, anchor: number, o: FmtOptions): string {
  let out = "";
  for (const l of code.split("\n")) {
    if (l.trim() === "") continue;
    const level = indent + Math.max(0, indentDepth(l, unit) - anchor);
    out += pad(level, o) + collapseSpaces(stripLeadingWs(l)) + "\n";
  }
  return out;
}

// --- embedded GDScript (setup) — structure-preserving base-indent normalization only ---

function fmtSetup(setup: string, indent: number, o: FmtOptions): string {
  if (setup.trim() === "") return "";
  return reanchor(setup, indent, o);
}

// Re-indent an embedded-GDScript block (component setup / hook body) to clean, DEPTH-based indentation
// anchored at `indent`. Depth-based, NOT character-preserving: a tab counts as one unit and the
// space-unit is inferred, so a body indented with mixed tabs+spaces — e.g. a lambda body written `\t␠␠␠␠`
// (a tab then 4 spaces, which RENDERS like two tabs but is byte-different) — is normalized to real tabs
// instead of emitted verbatim as `\t␠␠␠␠` (the "Format Document leaves 4 spaces in nested code" bug).
// Mirrors the compiler's guitkx.gd `_reindent_setup` (identical `indentUnit`/`indentDepth`), so the
// formatted source and the generated `.gd` indent the same. Anchored to the FIRST non-blank
// NON-COMMENT line (in valid GDScript the body's base level), NOT the shallowest: a min-depth anchor
// let one outlier-shallow line push every other line a level deeper. Comments are skipped when
// PICKING the anchor (GDScript allows a comment at any indentation, so a stray over-indented leading
// comment must not shift real code) but re-emitted by depth like any line. A line shallower than the
// anchor clamps to `indent`.
function reanchor(code: string, indent: number, o: FmtOptions): string {
  let lines = code.split("\n");
  while (lines.length > 0 && lines[0].trim() === "") lines.shift();
  while (lines.length > 0 && lines[lines.length - 1].trim() === "") lines.pop();
  if (lines.length === 0) return "";
  const unit = indentUnit(lines);
  let anchor = -1;
  let anchorAny = -1;
  const depths: number[] = [];
  for (const l of lines) {
    const t = l.trim();
    if (t === "") {
      depths.push(-1);
      continue;
    }
    const d = indentDepth(l, unit);
    depths.push(d);
    if (anchorAny === -1) anchorAny = d;
    if (anchor === -1 && !t.startsWith("#")) anchor = d;
  }
  if (anchor === -1) anchor = anchorAny; // comment-only block
  let out = "";
  for (let i = 0; i < lines.length; i++) {
    if (depths[i] === -1) {
      out += "\n";
      continue;
    }
    const level = indent + Math.max(0, depths[i] - anchor);
    out += pad(level, o) + collapseSpaces(stripLeadingWs(lines[i])) + "\n";
  }
  return out;
}

// Inferred space-indent unit: the minimum POSITIVE DIFFERENCE between distinct leading-space
// widths — NOT the minimum width, which is the block's base offset: a spaces-2 body anchored at
// width 4 (4/6/8) divided by 4 folds two levels together and dedents a nested `return` out of its
// guard on reformat (Phase D corruption find). One distinct width keeps the old min-width
// behavior; tab-only source keeps unit 1 (a tab = one level). Mirrors guitkx.gd `_indent_unit`.
// Exported for the T2.5 rules-of-hooks scan (liveMarkup.ts) so both consumers share ONE geometry.
export function indentUnit(lines: string[]): number {
  const widths = new Set<number>();
  for (const l of lines) {
    let sp = 0;
    for (const c of l) {
      if (c === " ") sp++;
      else if (c === "\t") continue;
      else break;
    }
    if (sp > 0) widths.add(sp);
  }
  if (widths.size === 0) return 1;
  const sorted = [...widths].sort((a, b) => a - b);
  let unit = sorted[0];
  for (let i = 1; i < sorted.length; i++) {
    const d = sorted[i] - sorted[i - 1];
    if (d > 0 && d < unit) unit = d;
  }
  return Math.max(unit, 1);
}

// Indentation depth in whole levels: a tab = `unit` columns, a space = 1 column, rounded. Mirrors
// guitkx.gd `_indent_depth`.
export function indentDepth(s: string, unit: number): number {
  let cols = 0;
  for (const c of s) {
    if (c === "\t") cols += unit;
    else if (c === " ") cols += 1;
    else break;
  }
  return Math.round(cols / unit);
}

function stripLeadingWs(s: string): string {
  return s.slice(leadingWs(s).length);
}

// Collapse runs of 2+ spaces to one in a line of embedded GDScript (e.g. `==␣␣␣null` -> `== null`),
// leaving strings/comments verbatim. Uses skipNoncode, which is byte-identical to the GD lexer's
// skip_noncode (cross-tested via scanner-cases.json), so TS + GD stay in lock-step. [audit #6]
function collapseSpaces(s: string): string {
  let out = "";
  let i = 0;
  while (i < s.length) {
    const j = skipNoncode(s, i);
    if (j !== i) {
      out += s.slice(i, j);
      i = j;
      continue;
    }
    if (s[i] === " " && s[i + 1] === " ") {
      out += " ";
      while (i < s.length && s[i] === " ") i++;
      continue;
    }
    out += s[i];
    i++;
  }
  return out;
}

// --- decl parsing (mirrors guitkx_formatter.gd's use of the compiler) ---

interface CompParse {
  ok: boolean;
  name: string;
  params: string;
  setup: string;
  setupStart: number;
  setupEnd: number;
  markupStart: number;
  markupEnd: number;
  nodes: MarkupNode[]; // ALL window nodes incl. comments (T2.1) -- the formatter re-emits them in order
  next: number;
}
function parseComponentAt(src: string, at: number): CompParse {
  const fail: CompParse = { ok: false, name: "", params: "", setup: "", setupStart: at, setupEnd: at, markupStart: at, markupEnd: at, nodes: [], next: at };
  const n = src.length;
  // Skip the declaration keyword TOKEN (not a fixed "component".length) so a recovered typo header
  // (`comssponent Foo {`) parses from the right place. For an exact keyword this is identical.
  let i = at;
  while (i < n && isIdent(src[i])) i++;
  i = skipWsOnly(src, i);
  const ns = i;
  while (i < n && isIdent(src[i])) i++;
  const name = src.slice(ns, i);
  if (name === "") return fail; // nameless `component {` -> verbatim (mirror GUITKX0300)
  i = skipWsOnly(src, i);
  let params = "";
  if (src[i] === "(") {
    const pc = findMatching(src, i);
    if (pc === -1) return fail;
    params = src.slice(i + 1, pc);
    i = pc + 1;
  }
  i = skipWsOnly(src, i);
  if (src[i] !== "{") return fail;
  const bclose = findMatching(src, i);
  if (bclose === -1) return fail;
  const bodyStart = i + 1;
  const split = splitReturn(src, bodyStart, bclose);
  if (!split || split === "unclosed") return fail;
  const setup = src.slice(bodyStart, split.setupEnd);
  const mr = parseMarkup(src, split.markupStart, split.markupEnd);
  // exactly one RENDER root; comments are legal window siblings (T2.1)
  if (mr.error !== "" || mr.nodes.filter((n) => n && n.t !== "comment").length !== 1) return fail;
  return { ok: true, name, params, setup, setupStart: bodyStart, setupEnd: split.setupEnd, markupStart: split.markupStart, markupEnd: split.markupEnd, nodes: mr.nodes, next: bclose + 1 };
}

interface HookParse {
  ok: boolean;
  name: string;
  params: string;
  body: string;
  bodyStart: number;
  bodyEnd: number;
  next: number;
}
function parseHookAt(src: string, at: number): HookParse {
  const fail: HookParse = { ok: false, name: "", params: "", body: "", bodyStart: at, bodyEnd: at, next: at };
  const n = src.length;
  // Skip the keyword token (recovery-safe; identical for an exact `hook`).
  let i = at;
  while (i < n && isIdent(src[i])) i++;
  i = skipWsOnly(src, i);
  const ns = i;
  while (i < n && isIdent(src[i])) i++;
  const name = src.slice(ns, i);
  if (name === "") return fail; // nameless `hook {` -> verbatim (mirror GUITKX0300)
  i = skipWsOnly(src, i);
  let params = "";
  if (src[i] === "(") {
    const pc = findMatching(src, i);
    if (pc === -1) return fail;
    params = src.slice(i + 1, pc);
    i = pc + 1;
  }
  i = skipWsOnly(src, i);
  // optional `-> ReturnHint` between the params and the body (mirror _parse_hook_at)
  if (i + 1 < n && src[i] === "-" && src[i + 1] === ">") {
    i += 2;
    while (i < n && src[i] !== "{") i++;
  }
  if (src[i] !== "{") return fail;
  const bclose = findMatching(src, i);
  if (bclose === -1) return fail;
  return { ok: true, name, params, body: src.slice(i + 1, bclose), bodyStart: i + 1, bodyEnd: bclose, next: bclose + 1 };
}

// The markup (return-window) spans of every component in the document (top-level or module member) —
// the regions where semantic-token scanning is valid; everything else is GDScript (setup/params/conds).
// BUG-V5/V6: per-component, the span of real code AFTER the markup return `)` and before the body `}`
// — unreachable (the compiler drops it). Used to fade + flag it live. Mirrors guitkx.gd _has_unreachable_after.
export function unreachableRegions(src: string): { start: number; end: number }[] {
  const out: { start: number; end: number }[] = [];
  const collect = (from: number, to: number): void => {
    let i = from;
    while (i < to) {
      const d = findDecl(src, i, true); // recover from a typo'd header so analysis still runs
      if (d.kind === "" || d.at >= to) break;
      if (d.kind === "component") {
        // Phase C: an UNCONDITIONAL early markup return makes everything after it dead, including
        // the final return -- the dim anchor moves to it (mirrors guitkx.gd's 0107 `dead_from`).
        const b = declBody(src, d.at);
        const firstTop = b ? splitReturnEx(src, b.start, b.close).early.find((e) => e.top) : undefined;
        if (b && firstTop) {
          const r = realSpan(src, firstTop.stop, b.close);
          if (r) out.push(r);
          i = b.close + 1;
          continue;
        }
        const pc = parseComponentAt(src, d.at);
        if (pc.ok) {
          const r = realSpan(src, pc.markupEnd + 1, pc.next - 1); // (markupEnd = `)`, next-1 = body `}`)
          if (r) out.push(r);
          i = pc.next;
        } else i = d.at + 9;
      } else if (d.kind === "hook") {
        const ph = parseHookAt(src, d.at);
        i = ph.ok ? ph.next : d.at + 4;
      } else if (d.kind === "module") {
        const body = moduleBodyAt(src, d.at);
        if (body) {
          collect(body.start, body.end);
          i = body.end + 1;
        } else i = d.at + 6;
      } else i = d.at + 1;
    }
  };
  collect(0, src.length);
  return out;
}

// The [first, last+1) span of real (non-whitespace, non-comment) code in [from, to), or null.
function realSpan(src: string, from: number, to: number): { start: number; end: number } | null {
  let i = from;
  let first = -1;
  let last = -1;
  while (i < to) {
    const k = skipNoncode(src, i);
    if (k !== i) {
      i = k;
      continue;
    }
    const c = src[i];
    if (!(c === " " || c === "\t" || c === "\n" || c === "\r")) {
      if (first === -1) first = i;
      last = i;
    }
    i++;
  }
  return first === -1 ? null : { start: first, end: last + 1 };
}

// The markup (return-window) spans of every component — the regions markup intelligence (live
// diagnostics, semantic highlighting, completion-context) is valid over. STRUCTURAL: the span is the
// `return ( ... )` located by declBody + splitReturn, NOT gated on a clean markup parse. The old
// version required parseComponentAt to succeed, so a SINGLE malformed tag (`<  a>`) collapsed the whole
// window — killing every markup diagnostic, all tag highlighting, and completion for that component
// while you were mid-edit. Recovering a typo'd header + tolerating in-progress markup keeps the editor
// responsive on broken input. (The formatter keeps its own strict parseComponentAt, unaffected.)
export function markupWindows(src: string): { start: number; end: number }[] {
  const wins: { start: number; end: number }[] = [];
  const collect = (from: number, to: number): void => {
    let i = from;
    while (i < to) {
      const d = findDecl(src, i, true); // recover from a typo'd header so analysis still runs
      if (d.kind === "" || d.at >= to) break;
      if (d.kind === "component") {
        const b = declBody(src, d.at);
        if (b) {
          const ex = splitReturnEx(src, b.start, b.close);
          // Phase C: EARLY markup returns are windows too (in source order, before the final one)
          // -- full live markup intelligence inside a conditional `return ( <markup> )`. Mirrored
          // by contract_dump.gd's _collect_windows; the goldens pin the order.
          for (const e of ex.early) if (e.end > e.start) wins.push({ start: e.start, end: e.end });
          const split = ex.split;
          if (split && split !== "unclosed" && split.markupEnd > split.markupStart) wins.push({ start: split.markupStart, end: split.markupEnd });
          i = b.close + 1;
        } else i = d.at + 1;
      } else if (d.kind === "hook") {
        const ph = parseHookAt(src, d.at);
        i = ph.ok ? ph.next : d.at + 1;
      } else if (d.kind === "module") {
        const body = moduleBodyAt(src, d.at);
        if (body) {
          collect(body.start, body.end);
          i = body.end + 1;
        } else i = d.at + 1;
      } else break;
    }
  };
  collect(0, src.length);
  return wins;
}

// Components whose CLOSED body contains no markup return at all — `splitReturn` found neither
// `return (` nor `return <` (a lone `return null` guard doesn't count). The compiler fails these with
// GUITKX2101 on save (guitkx.gd _split_return); this is the live mirror so the editor flags it while
// typing instead of staying silent until the sidecar lands. The walk is the same recovering walk as
// markupWindows (a typo'd header still gets its body checked); hooks never have markup returns and
// modules recurse, so only real components report — never helper funcs. An UNCLOSED `return (` (the
// half-typed case, the compiler's GUITKX0304) deliberately does not report. Span = the declaration
// head (keyword through name), the natural squiggle anchor.
export function missingReturnComponents(src: string): { start: number; end: number }[] {
  const out: { start: number; end: number }[] = [];
  const collect = (from: number, to: number): void => {
    let i = from;
    while (i < to) {
      const d = findDecl(src, i, true);
      if (d.kind === "" || d.at >= to) break;
      if (d.kind === "component") {
        const b = declBody(src, d.at);
        if (b) {
          if (splitReturn(src, b.start, b.close) === null) out.push(declHead(src, d.at));
          i = b.close + 1;
        } else i = d.at + 1;
      } else if (d.kind === "hook") {
        const ph = parseHookAt(src, d.at);
        i = ph.ok ? ph.next : d.at + 1;
      } else if (d.kind === "module") {
        const body = moduleBodyAt(src, d.at);
        if (body) {
          collect(body.start, body.end);
          i = body.end + 1;
        } else i = d.at + 1;
      } else break;
    }
  };
  collect(0, src.length);
  return out;
}

// T3.5: components whose body holds a markup return with an UNCLOSED `(` -- the compiler's
// GUITKX0304. No window is produced for them, so every window-scoped tier skips the file and the
// live side used to stay silent. Span = the declaration head (same anchor as missing-return).
export function unclosedReturns(src: string): { start: number; end: number }[] {
  const out: { start: number; end: number }[] = [];
  const collect = (from: number, to: number): void => {
    let i = from;
    while (i < to) {
      const d = findDecl(src, i, true);
      if (d.kind === "" || d.at >= to) break;
      if (d.kind === "component") {
        const b = declBody(src, d.at);
        if (b) {
          if (splitReturn(src, b.start, b.close) === "unclosed") out.push(declHead(src, d.at));
          i = b.close + 1;
        } else i = d.at + 1;
      } else if (d.kind === "hook") {
        const ph = parseHookAt(src, d.at);
        i = ph.ok ? ph.next : d.at + 1;
      } else if (d.kind === "module") {
        const body = moduleBodyAt(src, d.at);
        if (body) {
          collect(body.start, body.end);
          i = body.end + 1;
        } else i = d.at + 1;
      } else break;
    }
  };
  collect(0, src.length);
  return out;
}

// The `component Name` head span at a declaration keyword offset (typo'd keywords included).
function declHead(src: string, at: number): { start: number; end: number } {
  const n = src.length;
  let i = at;
  while (i < n && isIdent(src[i])) i++; // the (possibly-misspelled) keyword
  const kwEnd = i;
  while (i < n && (src[i] === " " || src[i] === "\t")) i++;
  const ns = i;
  while (i < n && isIdent(src[i])) i++;
  return { start: at, end: i > ns ? i : kwEnd };
}

// The `{`…matching-`}` body of a component/hook at `at` (keyword-token-agnostic, params-aware), for
// locating the markup span WITHOUT a full parse.
function declBody(src: string, at: number): { start: number; close: number } | null {
  const n = src.length;
  let i = at;
  while (i < n && isIdent(src[i])) i++; // skip the (possibly-misspelled) keyword token
  i = skipWsOnly(src, i);
  while (i < n && isIdent(src[i])) i++; // skip the declaration name
  i = skipWsOnly(src, i);
  if (src[i] === "(") {
    const pc = findMatching(src, i);
    if (pc === -1) return null;
    i = skipWsOnly(src, pc + 1);
  }
  if (src[i] !== "{") return null;
  const close = findMatching(src, i);
  if (close === -1) return null;
  return { start: i + 1, close };
}

function moduleBodyAt(src: string, at: number): { start: number; end: number } | null {
  const n = src.length;
  let i = at;
  while (i < n && isIdent(src[i])) i++; // skip the `module` keyword token (recovery-safe)
  i = skipWsOnly(src, i);
  while (i < n && isIdent(src[i])) i++; // skip the module name
  i = skipWsOnly(src, i);
  if (src[i] !== "{") return null;
  const close = findMatching(src, i);
  if (close === -1) return null;
  return { start: i + 1, end: close };
}

// T2.5: every embedded-GDScript span the rules-of-hooks scan covers -- component setups (body start
// to the chosen return; the whole body when no/unclosed return, matching the compiler's view of an
// all-setup body) and hook declaration bodies, top-level or module members.
export function setupSpans(src: string): { start: number; end: number }[] {
  const out: { start: number; end: number }[] = [];
  const collect = (from: number, to: number): void => {
    let i = from;
    while (i < to) {
      const d = findDecl(src, i, true);
      if (d.kind === "" || d.at >= to) break;
      if (d.kind === "component") {
        const b = declBody(src, d.at);
        if (b) {
          const split = splitReturn(src, b.start, b.close);
          const end = split && split !== "unclosed" ? split.setupEnd : b.close;
          if (end > b.start) out.push({ start: b.start, end });
          i = b.close + 1;
        } else i = d.at + 1;
      } else if (d.kind === "hook") {
        const ph = parseHookAt(src, d.at);
        if (ph.ok) {
          if (ph.bodyEnd > ph.bodyStart) out.push({ start: ph.bodyStart, end: ph.bodyEnd });
          i = ph.next;
        } else i = d.at + 1;
      } else if (d.kind === "module") {
        const body = moduleBodyAt(src, d.at);
        if (body) {
          collect(body.start, body.end);
          i = body.end + 1;
        } else i = d.at + 1;
      } else break;
    }
  };
  collect(0, src.length);
  return out;
}

// The embedded-GDScript spans (component setup / hook body) of a (already-formatted) document — the
// regions an optional gdformat pass may reflow. Top-level component/hook only (modules keep base-indent).
export function embeddedRegions(src: string): { start: number; end: number }[] {
  const decl = findDecl(src, 0);
  if (decl.kind === "component") {
    const pc = parseComponentAt(src, decl.at);
    if (pc.ok && pc.setupEnd > pc.setupStart && src.slice(pc.setupStart, pc.setupEnd).trim() !== "") return [{ start: pc.setupStart, end: pc.setupEnd }];
  } else if (decl.kind === "hook") {
    const ph = parseHookAt(src, decl.at);
    if (ph.ok && ph.bodyEnd > ph.bodyStart && src.slice(ph.bodyStart, ph.bodyEnd).trim() !== "") return [{ start: ph.bodyStart, end: ph.bodyEnd }];
  }
  return [];
}

interface ReturnSplit {
  setupEnd: number;
  markupStart: number;
  markupEnd: number;
}
// `"unclosed"` = a markup return exists but its `(` never closes (the compiler's GUITKX0304, and the
// half-typed `return (` while editing); `null` = NO markup return anywhere in the body (GUITKX2101).
// Distinguished so the live missing-return diagnostic can't fire on an in-progress paren.
//
// T1.4 (Unity useLastReturn parity): the window is the LAST top-level markup return. "Top-level"
// mirrors guitkx.gd _split_return exactly -- the `return` is the first token on its line AND the
// line's indent depth is <= the body's anchor depth (same anchor rule as reanchor/_reindent_setup).
function splitReturn(src: string, start: number, end: number): ReturnSplit | "unclosed" | null {
  return splitReturnEx(src, start, end).split;
}

// The full mirror of guitkx.gd _split_return (Phase C): the chosen window PLUS `early` -- every
// EARLY markup return (an earlier top-level one, a conditional/nested `return ( <markup> )`, a
// bare `return <Tag/>`). Early markup returns are LEGAL and lowered in place by the compiler;
// here each becomes an extra markup WINDOW ({start,end} = its markup content) so the live tier
// gives it full markup intelligence, and `top`/`stop` let unreachableRegions dim after an
// UNCONDITIONAL early return (Unity's Site-B dim). Value returns (`return (x + 1)`) and `return
// null` guards are plain GDScript and produce nothing.
function splitReturnEx(src: string, start: number, end: number): { split: ReturnSplit | "unclosed" | null; early: { start: number; end: number; at: number; stop: number; top: boolean }[] } {
  const lines = src.slice(start, end).split("\n");
  const unit = indentUnit(lines);
  let anchor = -1;
  let anchorAny = -1;
  for (const l of lines) {
    const t = l.trim();
    if (t === "") continue;
    const d = indentDepth(l, unit);
    if (anchorAny === -1) anchorAny = d;
    if (!t.startsWith("#")) {
      anchor = d;
      break;
    }
  }
  if (anchor === -1) anchor = anchorAny;
  const eolAt = (at: number): number => {
    let e = src.indexOf("\n", at);
    if (e === -1 || e > end) e = end;
    return e;
  };
  // every markup-shaped return in scan order; the last TOP-LEVEL one is chosen (mirror guitkx.gd)
  const rets: { at: number; mStart: number; mEnd: number; stop: number; shape: "paren" | "bare"; top: boolean }[] = [];
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
      const ls = Math.max(start, src.lastIndexOf("\n", i - 1) + 1);
      const lead = src.slice(ls, i);
      const topLevel = lead.trim() === "" && indentDepth(lead, unit) <= anchor;
      const eol = eolAt(i);
      if (src[p] === "(") {
        const close = findMatching(src, p);
        // close >= end: the `)` lives beyond the body -- inside the sliced body the compiler sees
        // no close at all, so mirror its GUITKX0304 verdict.
        if (close === -1 || close >= end) return { split: "unclosed", early: [] };
        if (topLevel || parenHoldsMarkup(src, p + 1, close)) {
          rets.push({ at: i, mStart: p + 1, mEnd: close, stop: close + 1, shape: "paren", top: topLevel });
        }
        i = close + 1;
        continue;
      }
      if (src[p] === "<") {
        // bare `return <...` is markup by construction (`<` cannot start a GDScript expression)
        rets.push({ at: i, mStart: p, mEnd: -1, stop: -1, shape: "bare", top: topLevel });
        i = eol;
        continue;
      }
      // `return null` may be a CONDITIONAL guard (e.g. `if not ready: return null`); keep scanning
      // for a later markup return rather than bailing to verbatim. Mirrors guitkx.gd _split_return. [audit]
      if (keywordAt(src, p, "null")) {
        i = p + 4;
        continue;
      }
      i = topLevel ? eol : i + 6;
      continue;
    }
    i++;
  }
  let chosen: (typeof rets)[number] | null = null;
  for (const r of rets) if (r.top) chosen = r;
  if (chosen === null) return { split: null, early: [] };
  const early: { start: number; end: number; at: number; stop: number; top: boolean }[] = [];
  for (const r of rets) {
    if (r.at >= chosen.at) break;
    // an early top-level VALUE return (`return (x + 1)`) is plain GDScript, not a window
    if (r.shape === "paren" && !parenHoldsMarkup(src, r.mStart, r.mEnd)) continue;
    let mEnd = r.mEnd;
    let stop = r.stop;
    if (r.shape === "bare") {
      const be = findElementEnd(src, r.mStart, chosen.at);
      if (be === -1) continue; // unclosed early markup -- the compiler reports 0304; no live window
      mEnd = be;
      stop = be;
    }
    early.push({ start: r.mStart, end: mEnd, at: r.at, stop, top: r.top });
  }
  const split: ReturnSplit =
    chosen.shape === "paren"
      ? { setupEnd: chosen.at, markupStart: chosen.mStart, markupEnd: chosen.mEnd }
      : { setupEnd: chosen.at, markupStart: chosen.mStart, markupEnd: end };
  return { split, early };
}

// Mirrors guitkx.gd _paren_holds_markup: a nested `return ( ... )` is markup-shaped when its first
// real char is `<` or `@` (neither can begin a legal GDScript expression, so a plain parenthesized
// value like `return (x + 1)` in a setup lambda never false-flags). guitkx.gd's _first_real also
// skips markup comments; `return ( /* c */ <X/> )` in setup GDScript is pathological, so a
// whitespace skip suffices for the live mirror.
function parenHoldsMarkup(src: string, from: number, to: number): boolean {
  let i = from;
  while (i < to && /[ \t\r\n]/.test(src[i])) i++;
  return i < to && (src[i] === "<" || src[i] === "@");
}

// --- helpers ---

function fmtParams(params: string): string {
  const p = params.trim();
  return p === "" ? "" : `(${p})`;
}

function indentBlock(block: string, indent: number, o: FmtOptions): string {
  const p = pad(indent, o);
  let out = "";
  for (const l of block.split("\n")) out += (l === "" ? "" : p + l) + "\n";
  return out.replace(/\n+$/, "") + "\n";
}

function pad(indent: number, o: FmtOptions): string {
  if (o.indentStyle === "space") return " ".repeat(indent * o.indentSize);
  return "\t".repeat(indent);
}

function leadingWs(s: string): string {
  let i = 0;
  while (i < s.length && (s[i] === "\t" || s[i] === " ")) i++;
  return s.slice(0, i);
}
function skipWsOnly(src: string, i: number): number {
  const n = src.length;
  while (i < n && (src[i] === " " || src[i] === "\t" || src[i] === "\n" || src[i] === "\r")) i++;
  return i;
}
function skipWsNl(src: string, i: number): number {
  while (true) {
    i = skipWsOnly(src, i);
    const k = skipNoncode(src, i);
    if (k === i) return i;
    i = k;
  }
}

// --- project config: guitkx.config.json (Prettier-style walk-up) — the analogue of uitkx.config.json ---
// Walk up from `fileDir` to the filesystem root; the first guitkx.config.json's `"formatter"` section
// overrides the formatter options. Unknown keys are ignored; a malformed file falls back to {}.
export function loadFormatterConfig(fileDir: string): Partial<FmtOptions> {
  let dir = fileDir;
  while (dir) {
    const candidate = join(dir, "guitkx.config.json");
    if (existsSync(candidate)) {
      try {
        return mapFormatterSection(JSON.parse(readFileSync(candidate, "utf8")).formatter);
      } catch {
        return {};
      }
    }
    const parent = dirname(dir);
    if (!parent || parent === dir) break;
    dir = parent;
  }
  return {};
}

function mapFormatterSection(f: unknown): Partial<FmtOptions> {
  if (!f || typeof f !== "object") return {};
  const r = f as Record<string, unknown>;
  const o: Partial<FmtOptions> = {};
  if (typeof r.printWidth === "number") o.printWidth = r.printWidth;
  if (typeof r.indentSize === "number") o.indentSize = r.indentSize;
  if (r.indentStyle === "tab" || r.indentStyle === "space") o.indentStyle = r.indentStyle;
  if (typeof r.singleAttributePerLine === "boolean") o.singleAttributePerLine = r.singleAttributePerLine;
  if (typeof r.insertSpaceBeforeSelfClose === "boolean") o.insertSpaceBeforeSelfClose = r.insertSpaceBeforeSelfClose;
  return o;
}
