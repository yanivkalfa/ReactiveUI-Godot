// textDocument/semanticTokens/full — a THIN additive overlay emitting only what the static TextMate
// grammar provably cannot decide: tag IDENTITY (host element vs user component vs unknown), @-directive
// keywords, attribute names, and on_<signal> events. Nothing inside {expr}/setup GDScript (Godot owns
// that). One linear scan over scanner.ts primitives, delta-encoded per the LSP spec.

import { skipNoncode, skipNoncodeMarkup, skipString, findMatching, isIdent } from "./scanner";
import { findTag } from "./schema";
import { markupWindows } from "./formatGuitkx";
import { isEventAttr } from "./events";

// A UNIFIED semantic-tokens legend covering BOTH the markup tokens (this file) and the embedded /
// plain-`.gd` GDScript tokens (analyzer-backed, in server.ts). The first 15 mirror
// @gdscript-analyzer/core's `SemanticTokenType` (camelCase); `keyword` + `event` are markup-only. The
// 4 modifiers mirror the analyzer's bit order, so its modifier bitset maps onto this legend directly.
export const TOKEN_TYPES = [
  "function", "method", "variable", "parameter", "property", "class", "enum", "enumMember",
  "type", "decorator", "number", "string", "comment", "signal", "constant",
  "keyword", "event",
];
export const TOKEN_MODIFIERS = ["declaration", "readonly", "static", "defaultLibrary"];

/** The analyzer's camelCase `SemanticTokenType` -> this legend's index (used by the `.gd` path). */
export const GD_TOKEN_TYPE: Record<string, number> = Object.fromEntries(TOKEN_TYPES.map((t, i) => [t, i]));

// The markup tokenizer emits a small subset; index it onto the unified legend.
const T = {
  class: TOKEN_TYPES.indexOf("class"),
  type: TOKEN_TYPES.indexOf("type"),
  keyword: TOKEN_TYPES.indexOf("keyword"),
  property: TOKEN_TYPES.indexOf("property"),
  event: TOKEN_TYPES.indexOf("event"),
};
const MOD_DEFAULT_LIBRARY = 1 << TOKEN_MODIFIERS.indexOf("defaultLibrary"); // bit 3

const DIRECTIVES = new Set(["if", "elif", "else", "for", "while", "match", "case", "default"]);

export interface Tok {
  line: number;
  char: number;
  len: number;
  type: number;
  mods: number;
}

/** The RAW markup tokens (tag identity, @-directive keywords, attribute names, on_<signal> events), in
 *  document order. The server merges these with the analyzer's embedded-GDScript tokens (mapped back
 *  from the virtual doc) before encoding, so `.guitkx` highlights the embedded code the same way a real
 *  `.gd` file does (BUG-2). `isComponent(name)` is the workspace-index membership test. */
export function markupTokens(src: string, isComponent: (name: string) => boolean): Tok[] {
  const toks: Tok[] = [];
  const lineStart = [0];
  for (let i = 0; i < src.length; i++) if (src[i] === "\n") lineStart.push(i + 1);
  const posOf = (off: number) => {
    let lo = 0;
    let hi = lineStart.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (lineStart[mid] <= off) lo = mid;
      else hi = mid - 1;
    }
    return { line: lo, char: off - lineStart[lo] };
  };
  const emit = (off: number, len: number, type: number, mods = 0) => {
    if (len <= 0) return;
    const p = posOf(off);
    toks.push({ line: p.line, char: p.char, len, type, mods });
  };

  // Only scan the markup windows (the return(...) of each component). Everything else — params, setup,
  // @directive conditions, {expr} bodies — is GDScript where `<` is a comparison, not a tag.
  for (const w of markupWindows(src)) scanWindow(src, w.start, w.end, emit, isComponent);
  return toks;
}

/** Sort tokens into document order and delta-encode per the LSP spec. Tolerates an unordered, merged
 *  set (markup + embedded), which the plain `markupTokens` scan would not produce on its own. */
export function encodeTokens(toks: Tok[]): number[] {
  return encode([...toks].sort((a, b) => a.line - b.line || a.char - b.char));
}

/** Build the delta-encoded markup-only token data (used by tests + as the `.guitkx` fallback). */
export function buildSemanticTokens(src: string, isComponent: (name: string) => boolean): number[] {
  return encodeTokens(markupTokens(src, isComponent));
}

function scanWindow(src: string, start: number, end: number, emit: (off: number, len: number, type: number, mods?: number) => void, isComponent: (name: string) => boolean): void {
  let i = start;
  while (i < end) {
    // G-01: this window is markup -- `#` in text (e.g. "Score #3") must stay literal, and
    // `//`/`/* */`/`<!-- -->` are the real comment forms here, not `#`.
    const k = skipNoncodeMarkup(src, i);
    if (k !== i) {
      i = Math.min(k, end);
      continue;
    }
    const c = src[i];
    if (c === "(") {
      // an @directive condition — GDScript, skip it whole
      const cl = findMatching(src, i);
      i = cl === -1 || cl >= end ? end : cl + 1;
      continue;
    }
    if (c === "{") {
      if (isBodyBrace(src, i)) {
        i++; // control-flow body is markup — enter it
        continue;
      }
      const cl = findMatching(src, i); // child {expr} — GDScript, skip it whole
      i = cl === -1 || cl >= end ? end : cl + 1;
      continue;
    }
    if (c === "}") {
      i++; // closing a control-flow body
      continue;
    }
    if (c === "@" && /[A-Za-z]/.test(src[i + 1] || "")) {
      let p = i + 1;
      while (p < end && isIdent(src[p])) p++;
      if (DIRECTIVES.has(src.slice(i + 1, p))) {
        emit(i, p - i, T.keyword); // colours the leading @ too
        i = p;
        continue;
      }
    }
    if (c === "<" && /[A-Za-z_/]/.test(src[i + 1] || "")) {
      const closing = src[i + 1] === "/";
      let p = i + (closing ? 2 : 1);
      const s = p;
      while (p < end && /[A-Za-z0-9_]/.test(src[p])) p++;
      const tag = src.slice(s, p);
      if (tag.length) {
        if (findTag(tag)) emit(s, p - s, T.type, MOD_DEFAULT_LIBRARY); // host element
        else if (/^[A-Z]/.test(tag) && isComponent(tag)) emit(s, p - s, T.class); // user component
        if (!closing) p = scanAttrs(src, p, end, emit);
        i = p;
        continue;
      }
    }
    i++;
  }
}

// A `{` opens a BODY (markup) — vs a child/attr {expr} (GDScript) — when it follows a `)` (component
// params or `@if/@for/@while/@match` condition), `@else`/`@default`, a `component`/`hook`/`module`
// NAME (paren-less wrapper declaration, deprecation window), a `-> Type` return annotation (plain
// E-01 callable header), or a line-leading bare identifier (paramless plain decl `Name {`). Shared
// by enclosingTag + markupDiagnostics + semanticTokens + context.ts. MIRROR: guitkx_context.gd
// _is_body_brace.
export function isBodyBrace(src: string, bi: number): boolean {
  let b = bi - 1;
  while (b >= 0 && /\s/.test(src[b])) b--;
  if (b < 0) return false;
  if (src[b] === ")") return true;
  let s = b;
  while (s >= 0 && isIdent(src[s])) s--;
  const w = src.slice(s + 1, b + 1);
  if (w === "else" || w === "default") return true;
  if (w.length > 0) {
    // `-> Type {` — the word before `{` is the TYPE of a plain-decl return annotation (E-01).
    // Whitespace INCLUDING newlines, mirroring guitkx_context.gd's _is_ws (a body `{` may open
    // on the line after the annotation).
    let ka = s;
    while (ka >= 0 && /[ \t\r\n]/.test(src[ka])) ka--;
    if (ka >= 1 && src[ka] === ">" && src[ka - 1] === "-") return true;
    // a decl name with no params: `component X {` / `hook use_x {` / `module M {`
    let k = s;
    while (k >= 0 && /\s/.test(src[k])) k--;
    let ks = k;
    while (ks >= 0 && isIdent(src[ks])) ks--;
    const kw = src.slice(ks + 1, k + 1);
    if (kw === "component" || kw === "hook" || kw === "module") return true;
    // paramless plain decl `Name {` / `export Name {`: the identifier chain before the `{` starts
    // at the beginning of its line (a top-level declaration header).
    const ls = src.lastIndexOf("\n", s) + 1;
    const lead = src.slice(ls, s + 1).trim();
    if (lead === "" || lead === "export") return true;
  }
  return false;
}

function scanAttrs(src: string, i: number, n: number, emit: (off: number, len: number, type: number, mods?: number) => void): number {
  while (i < n) {
    while (i < n && /\s/.test(src[i])) i++;
    if (i >= n) return n;
    if (src[i] === "/" && src[i + 1] === ">") return i + 2;
    if (src[i] === ">") return i + 1;
    if (src[i] === "{") { // a `{...spread}` attribute — skip whole (not a property-name token)
      const cl = findMatching(src, i);
      i = cl === -1 ? n : cl + 1;
      continue;
    }
    const as = i;
    while (i < n && /[A-Za-z0-9_.\-]/.test(src[i])) i++;
    const name = src.slice(as, i);
    if (name) emit(as, i - as, isEventAttr(name) ? T.event : T.property);
    else {
      i++; // not an attr-name char and not a terminator — advance to avoid stalling
      continue;
    }
    while (i < n && /\s/.test(src[i])) i++;
    if (src[i] === "=") {
      i++;
      while (i < n && /\s/.test(src[i])) i++;
      if (src[i] === '"' || src[i] === "'") i = skipString(src, i);
      else if (src[i] === "{") {
        const cl = findMatching(src, i);
        i = cl === -1 ? n : cl + 1;
      }
    }
  }
  return n;
}

function encode(toks: Tok[]): number[] {
  const data: number[] = [];
  let prevLine = 0;
  let prevChar = 0;
  for (const t of toks) {
    const dLine = t.line - prevLine;
    const dChar = dLine === 0 ? t.char - prevChar : t.char;
    data.push(dLine, dChar, t.len, t.type, t.mods);
    prevLine = t.line;
    prevChar = t.char;
  }
  return data;
}
