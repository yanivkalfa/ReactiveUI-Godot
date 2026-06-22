// In-process TypeScript formatter — a faithful port of addons/reactive_ui/guitkx/guitkx_formatter.gd.
// Lets VS Code / VS2022 "Format Document" run instantly, offline, with NO Godot binary (the old path
// shelled out to headless Godot). Output is kept BYTE-IDENTICAL to the GDScript formatter via a shared
// golden-fixture corpus asserted on both sides (test-fixtures/formatter-cases.json). AST-driven re-emit
// over markup.ts; returns the source VERBATIM on any parse error (never corrupts); idempotent.

import { parseMarkup, MarkupNode, Attr } from "./markup";
import { skipNoncode, findMatching, keywordAt, isIdent } from "./scanner";

export interface FmtOptions {
  printWidth: number;
  indentStyle: "tab" | "space";
  indentSize: number;
  singleAttributePerLine: boolean;
  insertSpaceBeforeSelfClose: boolean;
}
const DEFAULTS: FmtOptions = {
  printWidth: 100,
  indentStyle: "tab",
  indentSize: 4,
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
    if (source.slice(i, i + 11) === "@class_name") {
      let le = source.indexOf("\n", i);
      if (le === -1) le = n;
      classNameLine = source.slice(i, le).trim();
      i = le;
      continue;
    }
    break;
  }
  const decl = findDecl(source, i);
  let out = "";
  if (classNameLine !== "") out += classNameLine + "\n\n";
  switch (decl.kind) {
    case "component": {
      const pc = parseComponentAt(source, decl.at);
      if (!pc.ok) return source;
      out += fmtComponent(pc.name, pc.params, pc.setup, pc.root, o);
      break;
    }
    case "hook": {
      const ph = parseHookAt(source, decl.at);
      if (!ph.ok) return source;
      out += fmtHook(ph.name, ph.params, ph.body, o);
      break;
    }
    case "module": {
      const m = fmtModule(source, decl.at, o);
      if (m === null) return source;
      out += m;
      break;
    }
    default:
      return source;
  }
  return out.replace(/[ \t\n]+$/, "") + "\n";
}

// --- declarations ---

function fmtComponent(name: string, params: string, setup: string, root: MarkupNode, o: FmtOptions): string {
  let out = `component ${name}${fmtParams(params)} {\n`;
  out += fmtSetup(setup, 1, o);
  out += pad(1, o) + "return (\n";
  out += fmtNode(root, 2, o);
  out += pad(1, o) + ")\n";
  out += "}\n";
  return out;
}

function fmtHook(name: string, params: string, body: string, o: FmtOptions): string {
  let out = `hook ${name}${fmtParams(params)} {\n`;
  out += fmtSetup(body, 1, o);
  out += "}\n";
  return out;
}

function fmtModule(src: string, mi: number, o: FmtOptions): string | null {
  const n = src.length;
  let j = skipWsOnly(src, mi + 6);
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
    if (d.kind === "" || d.at >= bclose) break;
    if (!first) out += "\n";
    first = false;
    if (d.kind === "component") {
      const c = parseComponentAt(src, d.at);
      if (!c.ok) return null;
      out += indentBlock(fmtComponent(c.name, c.params, c.setup, c.root, o), 1, o);
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
  return out;
}

// --- markup ---

function fmtNode(nd: MarkupNode, indent: number, o: FmtOptions): string {
  switch (nd.t) {
    case "el":
      return fmtElement(nd, indent, o);
    case "frag": {
      const inner = fmtChildren(nd.children, indent + 1, o);
      return `${pad(indent, o)}<>\n${inner}${pad(indent, o)}</>\n`;
    }
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
    case "bool":
      return a.name;
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

// Re-parse a raw control-flow body string and format its nodes; verbatim re-indent fallback on error.
function fmtBody(bodySrc: string, indent: number, o: FmtOptions): string {
  const pr = parseMarkup(bodySrc, 0, bodySrc.length);
  if (pr.error !== "") return reanchor(bodySrc, indent, o);
  const nodes = pr.nodes.filter((x) => x != null);
  let out = "";
  for (const nx of nodes) out += fmtNode(nx, indent, o);
  return out;
}

// --- embedded GDScript (setup) — structure-preserving base-indent normalization only ---

function fmtSetup(setup: string, indent: number, o: FmtOptions): string {
  if (setup.trim() === "") return "";
  return reanchor(setup, indent, o);
}

function reanchor(code: string, indent: number, o: FmtOptions): string {
  let lines = code.split("\n");
  while (lines.length > 0 && lines[0].trim() === "") lines.shift();
  while (lines.length > 0 && lines[lines.length - 1].trim() === "") lines.pop();
  if (lines.length === 0) return "";
  let prefix: string | null = null;
  for (const l of lines) {
    if (l.trim() === "") continue;
    const lead = leadingWs(l);
    prefix = prefix === null ? lead : commonPrefix(prefix, lead);
  }
  const px = prefix ?? "";
  const p = pad(indent, o);
  let out = "";
  for (const l of lines) {
    if (l.trim() === "") out += "\n";
    else out += p + l.slice(px.length) + "\n";
  }
  return out;
}

// --- decl parsing (mirrors guitkx_formatter.gd's use of the compiler) ---

function findDecl(src: string, from: number): { kind: string; at: number } {
  const n = src.length;
  let i = from;
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
  return { kind: "", at: -1 };
}

interface CompParse {
  ok: boolean;
  name: string;
  params: string;
  setup: string;
  setupStart: number;
  setupEnd: number;
  markupStart: number;
  markupEnd: number;
  root: MarkupNode;
  next: number;
}
function parseComponentAt(src: string, at: number): CompParse {
  const fail: CompParse = { ok: false, name: "", params: "", setup: "", setupStart: at, setupEnd: at, markupStart: at, markupEnd: at, root: { t: "text", value: "" }, next: at };
  const n = src.length;
  let i = skipWsOnly(src, at + "component".length);
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
  if (!split) return fail;
  const setup = src.slice(bodyStart, split.setupEnd);
  const mr = parseMarkup(src, split.markupStart, split.markupEnd);
  if (mr.error !== "" || mr.nodes.length !== 1) return fail;
  return { ok: true, name, params, setup, setupStart: bodyStart, setupEnd: split.setupEnd, markupStart: split.markupStart, markupEnd: split.markupEnd, root: mr.nodes[0], next: bclose + 1 };
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
  let i = skipWsOnly(src, at + "hook".length);
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
export function markupWindows(src: string): { start: number; end: number }[] {
  const wins: { start: number; end: number }[] = [];
  const collect = (from: number, to: number): void => {
    let i = from;
    while (i < to) {
      const d = findDecl(src, i);
      if (d.kind === "" || d.at >= to) break;
      if (d.kind === "component") {
        const pc = parseComponentAt(src, d.at);
        if (pc.ok) wins.push({ start: pc.markupStart, end: pc.markupEnd });
        i = pc.ok ? pc.next : d.at + 9;
      } else if (d.kind === "hook") {
        const ph = parseHookAt(src, d.at);
        i = ph.ok ? ph.next : d.at + 4;
      } else if (d.kind === "module") {
        const body = moduleBodyAt(src, d.at);
        if (body) {
          collect(body.start, body.end);
          i = body.end + 1;
        } else i = d.at + 6;
      } else break;
    }
  };
  collect(0, src.length);
  return wins;
}

function moduleBodyAt(src: string, at: number): { start: number; end: number } | null {
  const n = src.length;
  let i = skipWsOnly(src, at + 6);
  while (i < n && isIdent(src[i])) i++;
  i = skipWsOnly(src, i);
  if (src[i] !== "{") return null;
  const close = findMatching(src, i);
  if (close === -1) return null;
  return { start: i + 1, end: close };
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
      // `return null` may be a CONDITIONAL guard (e.g. `if not ready: return null`); keep scanning
      // for a later markup return rather than bailing to verbatim. Mirrors guitkx.gd _split_return. [audit]
      if (keywordAt(src, p, "null")) {
        i = p + 4;
        continue;
      }
    }
    i++;
  }
  return null;
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
function commonPrefix(a: string, b: string): string {
  let i = 0;
  while (i < a.length && i < b.length && a[i] === b[i]) i++;
  return a.slice(0, i);
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
