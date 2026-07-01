// Faithful TypeScript port of addons/reactive_ui/guitkx/guitkx_markup.gd (the markup recursive-descent
// parser). It MUST produce node shapes byte-identical to the GDScript parser; the in-process formatter
// (formatGuitkx.ts) re-emits from this AST, kept identical to guitkx_formatter.gd via a shared golden
// fixture corpus asserted on both sides (the same discipline as scanner.ts === guitkx_lexer.gd). Built
// only on scanner.ts primitives — no second lexer.
//
// Node shapes (the `t` tag discriminates), matching guitkx_markup.gd:
//   { t:"el",    tag, attrs:[{name,kind,value}], children, line }   kind: "str"|"expr"|"bool"
//   { t:"frag",  children }
//   { t:"text",  value }
//   { t:"expr",  code }
//   { t:"if",    branches:[{cond, body_markup}], else_body }        cond/body are raw strings
//   { t:"for",   header, body_markup }
//   { t:"while", header, body_markup }
//   { t:"match", subject, cases:[{value, body_markup}], default_body }

import { skipString, findMatching, keywordAt } from "./scanner";

export interface Attr {
  name: string;
  kind: "str" | "expr" | "bool" | "spread";
  value: string;
}
export type MarkupNode =
  | { t: "el"; tag: string; attrs: Attr[]; children: MarkupNode[]; line: number }
  | { t: "frag"; children: MarkupNode[] }
  | { t: "text"; value: string }
  | { t: "expr"; code: string }
  | { t: "if"; branches: { cond: string; body_markup: string }[]; else_body: string | null }
  | { t: "for"; header: string; body_markup: string }
  | { t: "while"; header: string; body_markup: string }
  | { t: "match"; subject: string; cases: { value: string; body_markup: string }[]; default_body: string | null };

export interface ParseResult {
  nodes: MarkupNode[];
  error: string;
}

export function parseMarkup(src: string, start: number, end: number): ParseResult {
  return new MarkupParser(src).parse(start, end);
}

class MarkupParser {
  private src: string;
  private err = "";
  constructor(src: string) {
    this.src = src;
  }

  parse(start: number, end: number): ParseResult {
    this.err = "";
    const r = this.parseNodes(start, end);
    return { nodes: r.nodes, error: this.err };
  }

  // Returns { nodes, next } where `next` is where parsing stopped — on an unconsumed `</` (close tag
  // belongs to the caller) or at `end`. The caller locates the close tag from `next` with no weaker
  // second walk (which a `<`/`>` inside an embedded {expr} could fool).
  private parseNodes(start: number, end: number): { nodes: MarkupNode[]; next: number } {
    const nodes: MarkupNode[] = [];
    let i = start;
    while (i < end && this.err === "") {
      i = this.skipWs(i, end);
      if (i >= end) break;
      const c = this.src[i];
      if (c === "<") {
        if (i + 1 < end && this.src[i + 1] === "/") break; // closing tag belongs to the caller
        const r = this.parseElement(i, end);
        if (this.err !== "") break;
        nodes.push(r.node!);
        i = r.next;
      } else if (c === "@") {
        const r = this.parseDirective(i, end);
        if (this.err !== "") break;
        nodes.push(r.node!);
        i = r.next;
      } else if (c === "{") {
        const close = findMatching(this.src, i);
        if (close === -1 || close >= end) {
          this.err = "GUITKX0304: unclosed `{` expression";
          break;
        }
        const code = this.src.slice(i + 1, close).trim();
        nodes.push({ t: "expr", code });
        i = close + 1;
      } else {
        const r = this.parseText(i, end);
        if (r.node !== null) nodes.push(r.node);
        i = r.next;
      }
    }
    return { nodes, next: i };
  }

  private parseElement(openI: number, end: number): { node: MarkupNode | null; next: number } {
    let i = openI + 1;
    const line = this.lineOf(openI);
    const nameStart = i;
    while (i < end && isTagChar(this.src[i])) i++;
    const tag = this.src.slice(nameStart, i);
    // A `<` must be directly followed by a tag name, or `>` for a fragment. Whitespace/other after `<`
    // is an invalid/empty tag name (not a silent fragment). [BUG-V4] (mirror of guitkx_markup.gd)
    if (tag === "" && (i >= end || this.src[i] !== ">")) {
      this.err = "GUITKX0300: invalid tag name -- `<` must be followed by a tag name, or `<>` for a fragment";
      return { node: null, next: end };
    }
    const attrs: Attr[] = [];
    while (i < end) {
      i = this.skipWs(i, end);
      if (i >= end) {
        this.err = `GUITKX0303: unexpected EOF in <${tag}>`;
        return { node: null, next: end };
      }
      const c = this.src[i];
      if (c === "/" && i + 1 < end && this.src[i + 1] === ">") {
        return { node: this.mkEl(tag, attrs, [], line), next: i + 2 };
      }
      if (c === ">") {
        i += 1;
        break;
      }
      const ar = this.parseAttribute(i, end);
      if (this.err !== "") return { node: null, next: end };
      attrs.push(ar.attr!);
      i = ar.next;
    }
    const cr = this.parseNodes(i, end);
    if (this.err !== "") return { node: null, next: end };
    const children = cr.nodes;
    const j = cr.next;
    if (j >= end || this.src[j] !== "<" || (j + 1 < end && this.src[j + 1] !== "/")) {
      this.err = `GUITKX0301: unclosed tag <${tag}>`;
      return { node: null, next: end };
    }
    // j points at "</": read the close name to ">" (a close tag holds no {expr}/strings)
    const ce = this.src.indexOf(">", j);
    if (ce === -1 || ce >= end) {
      this.err = `GUITKX0303: malformed closing tag for <${tag}>`;
      return { node: null, next: end };
    }
    const closeName = this.src.slice(j + 2, ce).trim();
    if (closeName !== tag) {
      this.err = `GUITKX0302: mismatched tag </${closeName}> (expected </${tag}>)`;
      return { node: null, next: end };
    }
    return { node: this.mkEl(tag, attrs, children, line), next: ce + 1 };
  }

  private mkEl(tag: string, attrs: Attr[], children: MarkupNode[], line: number): MarkupNode {
    if (tag === "") return { t: "frag", children };
    return { t: "el", tag, attrs, children, line };
  }

  private parseAttribute(start: number, end: number): { attr: Attr | null; next: number } {
    let i = start;
    // spread attribute `{...expr}` (React `{...obj}`): merged into props at codegen. kind "spread".
    if (this.src[i] === "{") {
      const sclose = findMatching(this.src, i);
      if (sclose === -1 || sclose >= end) {
        this.err = "GUITKX0304: unclosed `{` in spread attribute";
        return { attr: null, next: end };
      }
      const inner = this.src.slice(i + 1, sclose).trim();
      if (!inner.startsWith("...")) {
        this.err = "GUITKX0300: expected `...spread` or an attribute name";
        return { attr: null, next: end };
      }
      return { attr: { name: "", kind: "spread", value: inner.slice(3).trim() }, next: sclose + 1 };
    }
    const ns = i;
    while (i < end && isAttrNameChar(this.src[i])) i++;
    const name = this.src.slice(ns, i);
    if (name === "") {
      this.err = "GUITKX0300: unexpected token in attributes";
      return { attr: null, next: end };
    }
    i = this.skipWs(i, end);
    if (i >= end || this.src[i] !== "=") {
      return { attr: { name, kind: "bool", value: "true" }, next: i };
    }
    i += 1; // past "="
    i = this.skipWs(i, end);
    if (i >= end) {
      this.err = `GUITKX0303: missing attribute value for '${name}'`;
      return { attr: null, next: end };
    }
    const c = this.src[i];
    if (c === '"' || c === "'") {
      const se = skipString(this.src, i);
      const val = this.src.slice(i + 1, se - 1);
      return { attr: { name, kind: "str", value: val }, next: se };
    }
    if (c === "{") {
      const close = findMatching(this.src, i);
      if (close === -1 || close >= end) {
        this.err = `GUITKX0304: unclosed \`{\` in attribute '${name}'`;
        return { attr: null, next: end };
      }
      const code = this.src.slice(i + 1, close).trim();
      return { attr: { name, kind: "expr", value: code }, next: close + 1 };
    }
    this.err = `GUITKX0300: attribute '${name}' value must be a string or {expr}`;
    return { attr: null, next: end };
  }

  private parseText(start: number, end: number): { node: MarkupNode | null; next: number } {
    let i = start;
    while (i < end && this.src[i] !== "<" && this.src[i] !== "{") i++;
    const raw = this.src.slice(start, i);
    if (raw.trim() === "") return { node: null, next: i };
    return { node: { t: "text", value: raw.trim() }, next: i };
  }

  // --- control-flow directives ---
  private parseDirective(at: number, end: number): { node: MarkupNode | null; next: number } {
    if (keywordAt(this.src, at + 1, "if")) return this.parseIf(at, end);
    if (keywordAt(this.src, at + 1, "for")) return this.parseLoop(at, end, "for", 4);
    if (keywordAt(this.src, at + 1, "while")) return this.parseLoop(at, end, "while", 6);
    if (keywordAt(this.src, at + 1, "match")) return this.parseMatch(at, end);
    this.err = "GUITKX0305: unknown @directive";
    return { node: null, next: end };
  }

  private readParen(i: number, end: number): { text: string; next: number } {
    i = this.skipWs(i, end);
    if (i >= end || this.src[i] !== "(") {
      this.err = "GUITKX0306: directive expects `(...)`";
      return { text: "", next: end };
    }
    const close = findMatching(this.src, i);
    if (close === -1 || close >= end) {
      this.err = "GUITKX0304: unclosed `(` in directive";
      return { text: "", next: end };
    }
    return { text: this.src.slice(i + 1, close).trim(), next: close + 1 };
  }

  private readBraceBody(i: number, end: number): { text: string; next: number } {
    i = this.skipWs(i, end);
    if (i >= end || this.src[i] !== "{") {
      this.err = "GUITKX0303: directive expects `{ ... }` body";
      return { text: "", next: end };
    }
    const close = findMatching(this.src, i);
    if (close === -1 || close >= end) {
      this.err = "GUITKX0304: unclosed `{` directive body";
      return { text: "", next: end };
    }
    return { text: this.src.slice(i + 1, close), next: close + 1 };
  }

  private parseIf(at: number, end: number): { node: MarkupNode | null; next: number } {
    const branches: { cond: string; body_markup: string }[] = [];
    let elseBody: string | null = null;
    let i = at + 3; // past "@if"
    const p = this.readParen(i, end);
    if (this.err !== "") return { node: null, next: end };
    const b = this.readBraceBody(p.next, end);
    if (this.err !== "") return { node: null, next: end };
    branches.push({ cond: p.text, body_markup: b.text });
    i = b.next;
    while (true) {
      const k = this.skipWs(i, end);
      if (k + 5 <= end && keywordAt(this.src, k + 1, "elif")) {
        const pe = this.readParen(k + 5, end);
        if (this.err !== "") return { node: null, next: end };
        const be = this.readBraceBody(pe.next, end);
        if (this.err !== "") return { node: null, next: end };
        branches.push({ cond: pe.text, body_markup: be.text });
        i = be.next;
      } else if (k + 5 <= end && keywordAt(this.src, k + 1, "else")) {
        const bb = this.readBraceBody(k + 5, end);
        if (this.err !== "") return { node: null, next: end };
        elseBody = bb.text;
        i = bb.next;
        break;
      } else {
        break;
      }
    }
    return { node: { t: "if", branches, else_body: elseBody }, next: i };
  }

  private parseLoop(at: number, end: number, kind: "for" | "while", kwlen: number): { node: MarkupNode | null; next: number } {
    const p = this.readParen(at + kwlen, end);
    if (this.err !== "") return { node: null, next: end };
    const b = this.readBraceBody(p.next, end);
    if (this.err !== "") return { node: null, next: end };
    return { node: { t: kind, header: p.text, body_markup: b.text } as MarkupNode, next: b.next };
  }

  private parseMatch(at: number, end: number): { node: MarkupNode | null; next: number } {
    const p = this.readParen(at + 6, end); // past "@match"
    if (this.err !== "") return { node: null, next: end };
    let bi = this.skipWs(p.next, end);
    if (bi >= end || this.src[bi] !== "{") {
      this.err = "GUITKX0303: @match expects `{ ... }` with @case/@default arms";
      return { node: null, next: end };
    }
    const bclose = findMatching(this.src, bi);
    if (bclose === -1 || bclose >= end) {
      this.err = "GUITKX0304: unclosed @match body";
      return { node: null, next: end };
    }
    const cases: { value: string; body_markup: string }[] = [];
    let defaultBody: string | null = null;
    let j = bi + 1;
    while (j < bclose) {
      j = this.skipWs(j, bclose);
      if (j >= bclose) break;
      if (this.src[j] === "@" && keywordAt(this.src, j + 1, "case")) {
        const cp = this.readParen(j + 5, bclose);
        if (this.err !== "") return { node: null, next: end };
        const cb = this.readBraceBody(cp.next, bclose);
        if (this.err !== "") return { node: null, next: end };
        cases.push({ value: cp.text, body_markup: cb.text });
        j = cb.next;
      } else if (this.src[j] === "@" && keywordAt(this.src, j + 1, "default")) {
        const db = this.readBraceBody(j + 8, bclose);
        if (this.err !== "") return { node: null, next: end };
        defaultBody = db.text;
        j = db.next;
      } else {
        this.err = "GUITKX0306: @match body expects @case (...) { } or @default { }";
        return { node: null, next: end };
      }
    }
    return { node: { t: "match", subject: p.text, cases, default_body: defaultBody }, next: bclose + 1 };
  }

  // --- helpers ---
  private skipWs(i: number, end: number): number {
    while (i < end && (this.src[i] === " " || this.src[i] === "\t" || this.src[i] === "\n" || this.src[i] === "\r")) i++;
    return i;
  }

  private lineOf(idx: number): number {
    let n = 0;
    for (let k = 0; k < idx; k++) if (this.src[k] === "\n") n++;
    return n + 1;
  }
}

function isTagChar(c: string): boolean {
  return c === "_" || (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (c >= "0" && c <= "9");
}
function isAttrNameChar(c: string): boolean {
  return isTagChar(c) || c === "-" || c === ".";
}
