// T1.5 live structural checks per markup window, offset-based and pure (the declarations.ts
// pattern) so they are unit-testable; server.ts wraps the results into LSP Diagnostics.
//
// Two checks the live tier used to silently lack (filed bug G5):
//  1. Markup PARSE errors (mismatched close 0302, unclosed tag 0301, ...) were computed and then
//     DISCARDED -- publish the parser's own code/message/offset.
//  2. Lowercase tags are emitted verbatim as `V.<tag>()` calls, so an unknown one is a guaranteed
//     runtime failure -- check them against the shared vocabulary (deterministic, no project
//     knowledge needed). PascalCase component tags stay with the compiler's known_components check
//     and the (suggestion-gated) index probe in server.ts until T4.5 feeds .guitkx declarations
//     into the analyzer -- firing ungated here would false-flag hand-written .gd components.
//
// The AST walk mirrors guitkx.gd _validate_node/_cbase: control-flow bodies are raw substrings that
// re-parse with offsets relative to their own start, composed via the node's body_at.

import { parseMarkup, MarkupNode } from "./markup";
import { VOCABULARY } from "./schema";
import { editDistance } from "./declScan";
import { skipNoncode, keywordAt, isIdent } from "./scanner";
import { indentUnit, indentDepth } from "./formatGuitkx";

export interface LiveMarkupDiag {
  start: number;
  end: number;
  code: string;
  message: string;
  severity?: "warning"; // absent = error
}

/** Parse errors + unknown lowercase tags for every markup window of a document. */
export function windowStructureDiags(src: string, windows: { start: number; end: number }[]): LiveMarkupDiag[] {
  const out: LiveMarkupDiag[] = [];
  for (const w of windows) {
    const pr = parseMarkup(src, w.start, w.end);
    if (pr.error !== "") {
      const at = Math.max(w.start, pr.error_at);
      out.push({ start: at, end: Math.min(w.end, at + 1), code: pr.error_code, message: `${pr.error_code}: ${pr.error_msg}` });
    }
    walkTags(pr.nodes, 0, out);
  }
  return out;
}

// `base` composes nested-body offsets (0 for the window parse, whose `at`s are already absolute).
function walkTags(nodes: (MarkupNode | null)[], base: number, out: LiveMarkupDiag[]): void {
  for (const nd of nodes) {
    if (!nd) continue;
    switch (nd.t) {
      case "el": {
        if (/^[a-z]/.test(nd.tag) && !VOCABULARY.v_factories.includes(nd.tag)) {
          const at = base + nd.at + 1; // nd.at is the `<`; squiggle the name
          out.push({
            start: at,
            end: at + nd.tag.length,
            code: "GUITKX0105",
            message: `GUITKX0105: unknown element <${nd.tag}>${suggestTag(nd.tag)}`,
          });
        }
        attrHookChecks(nd.attrs, base, out);
        walkTags(nd.children, base, out);
        break;
      }
      case "frag":
        attrHookChecks(nd.attrs ?? [], base, out);
        walkTags(nd.children, base, out);
        break;
      case "expr":
        // T2.5 (Unity 0016): a hook CALL inside a markup expression runs per-render out of hook
        // order -- using a hook RESULT is fine, only the call is flagged.
        if (exprCallsHook(nd.code)) {
          out.push({
            start: base + nd.vat,
            end: base + nd.vat + Math.max(1, nd.code.length),
            code: "GUITKX0016",
            message: "GUITKX0016: hook called inside a markup expression -- call it in setup and reference the result",
          });
        }
        break;
      case "text":
        // T2.4 migration warning: braces inside text are LITERAL under the Unity-parity text model.
        if (nd.value.includes("{")) {
          out.push({
            start: base + nd.at,
            end: base + nd.at + nd.value.length,
            code: "GUITKX0150",
            message: "GUITKX0150: braces inside text are literal -- interpolate with a leading `{expr}` node or a `text={ ... }` attribute instead",
            severity: "warning",
          });
        }
        break;
      case "if":
        for (const br of nd.branches) walkBody(br.body_markup, base + br.body_at, out);
        if (nd.else_body !== null) walkBody(nd.else_body, base + nd.else_body_at, out);
        break;
      case "for":
      case "while":
        walkBody(nd.body_markup, base + nd.body_at, out);
        break;
      case "match":
        for (const c of nd.cases) walkBody(c.body_markup, base + c.body_at, out);
        if (nd.default_body !== null) walkBody(nd.default_body, base + nd.default_body_at, out);
        break;
    }
  }
}

function walkBody(bodySrc: string, base: number, out: LiveMarkupDiag[]): void {
  const pr = parseMarkup(bodySrc, 0, bodySrc.length);
  // Directive bodies are OPAQUE to the enclosing window parse (raw text), so a malformed body is
  // invisible to it -- report the inner parser's error here, exactly like the compiler's
  // _validate_body does since T1.2.
  if (pr.error !== "") {
    const at = base + Math.max(0, pr.error_at);
    out.push({ start: at, end: at + 1, code: pr.error_code, message: `${pr.error_code}: ${pr.error_msg}` });
    return;
  }
  walkTags(pr.nodes, base, out);
}

function attrHookChecks(attrs: { kind: string; value: string; vat: number }[], base: number, out: LiveMarkupDiag[]): void {
  for (const a of attrs) {
    if (a.kind === "expr" && exprCallsHook(a.value)) {
      out.push({
        start: base + a.vat,
        end: base + a.vat + Math.max(1, a.value.length),
        code: "GUITKX0016",
        message: "GUITKX0016: hook called inside a markup expression -- call it in setup and reference the result",
      });
    }
  }
}

// Token-boundary hook-call detection -- a `my_useState(` look-alike or `obj.useState(` member call
// is NOT a hook call. Mirrors guitkx.gd _expr_calls_hook.
function exprCallsHook(code: string): boolean {
  let i = 0;
  const n = code.length;
  while (i < n) {
    const j = skipNoncode(code, i);
    if (j !== i) {
      i = j;
      continue;
    }
    if (i === 0 || (!isIdent(code[i - 1]) && code[i - 1] !== ".")) {
      for (const h of VOCABULARY.hooks) {
        if (keywordAt(code, i, h) && isCallAt(code, i + h.length)) return true;
      }
    }
    i++;
  }
  return false;
}

function isCallAt(s: string, at: number): boolean {
  while (at < s.length && (s[at] === " " || s[at] === "\t")) at++;
  return s[at] === "(";
}

// T2.5 (a)-(c) + lambda: the compiler's _validate_hooks ported line-for-line -- a deterministic
// block-opener stack over each setup span (component setup / hook body from setupSpans()).
export function hookContextDiags(src: string, spans: { start: number; end: number }[]): LiveMarkupDiag[] {
  const out: LiveMarkupDiag[] = [];
  for (const sp of spans) {
    const lines = src.slice(sp.start, sp.end).split("\n");
    const unit = indentUnit(lines);
    const stack: { depth: number; kind: string }[] = [];
    let off = 0;
    for (const l of lines) {
      const t = l.trim();
      if (t === "" || t.startsWith("#")) {
        off += l.length + 1;
        continue;
      }
      const d = indentDepth(l, unit);
      while (stack.length && stack[stack.length - 1].depth >= d) stack.pop();
      if (exprCallsHook(l)) {
        let kind = "";
        if (stack.length) kind = stack[stack.length - 1].kind;
        else if (t.includes(":")) kind = blockOpenerKind(t.slice(0, t.indexOf(":") + 1)); // single-line `if c: use_y()`
        if (kind !== "") {
          let code = "GUITKX0013";
          let what = "conditionally (inside an if/else block)";
          if (kind === "for" || kind === "while") {
            code = "GUITKX0014";
            what = "inside a loop";
          } else if (kind === "match") {
            code = "GUITKX0015";
            what = "inside a match branch";
          } else if (kind === "func") {
            code = "GUITKX0016";
            what = "inside a callback/lambda";
          }
          const lead = l.length - l.replace(/^[\t ]+/, "").length;
          out.push({
            start: sp.start + off + lead,
            end: sp.start + off + lead + t.length,
            code,
            message: `${code}: hook called ${what} -- hooks must run unconditionally at the top of setup`,
          });
        }
      }
      if (t.endsWith(":")) {
        const k2 = blockOpenerKind(t);
        if (k2 !== "") stack.push({ depth: d, kind: k2 });
      }
      off += l.length + 1;
    }
  }
  return out;
}

// Mirrors guitkx.gd _block_opener_kind.
function blockOpenerKind(t: string): string {
  for (const kw of ["if", "elif", "else", "for", "while", "match"]) {
    if (t === kw + ":" || t.startsWith(kw + " ") || t.startsWith(kw + "(")) return kw === "elif" || kw === "else" ? "if" : kw;
  }
  if (t.startsWith("func") || t.includes("func(") || t.includes("func (")) return "func";
  return "";
}

function suggestTag(tag: string): string {
  const candidates: string[] = [...VOCABULARY.v_factories, ...Object.keys(VOCABULARY.host_tags)];
  let best = "";
  let bestD = 3;
  for (const c of candidates) {
    const d = editDistance(tag.toLowerCase(), c.toLowerCase());
    if (d < bestD) {
      bestD = d;
      best = c;
    }
  }
  return best ? ` -- did you mean <${best}>?` : "";
}
