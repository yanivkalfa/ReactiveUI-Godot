// Shared tag-reference scanner for textDocument/references + rename. Finds <Name ...> and </Name>
// occurrences of a component binding, skipping strings/comments (scanner.skipNoncode). The opening `<`
// is gated on a non-operand boundary so a GDScript comparison `a < Name` is NOT matched, while real
// markup tags AND jsx-as-value refs inside {expr} (Phase 4, e.g. `prop={ c if x else <Card/> }`) ARE.
// (The naive "skip every {...}" approach is wrong — it would jump over every component body and every
// @if/@for block, which is exactly where refs live.)

import { skipNoncode, isIdent } from "./scanner";

export interface Ref {
  start: number; // offset of the tag NAME (not the `<`)
  end: number;
}

export function scanTagRefs(text: string, name: string): Ref[] {
  const refs: Ref[] = [];
  const n = text.length;
  let i = 0;
  while (i < n) {
    const k = skipNoncode(text, i);
    if (k !== i) {
      i = k;
      continue;
    }
    if (text[i] === "<") {
      const closing = text[i + 1] === "/";
      let p = i + (closing ? 2 : 1);
      const s = p;
      while (p < n && isIdent(text[p])) p++;
      const ident = text.slice(s, p);
      if (ident === name && (p >= n || /[\s/>]/.test(text[p]))) {
        // a closing tag `</X>` is unambiguous; an opening `<X` must be at a tag boundary (not `a < X`)
        if (closing || isTagBoundary(text, i)) refs.push({ start: s, end: p });
      }
      i = p === i ? i + 1 : p;
      continue;
    }
    i++;
  }
  return refs;
}

// GDScript keywords that introduce a value position, so `<` after them starts markup (jsx-as-value),
// not a comparison. MUST match the compiler's jsx-scan authority (guitkx_jsx_scan.gd), which
// whitelists ONLY return / else / and (+ the `,` `=` `&&` `:` operators) — so references/rename never
// edit a `<Name` that the compiler treats as a less-than operator (e.g. `if <`, `not <`, `await <`). [audit]
const VALUE_KEYWORDS = new Set(["else", "return", "and"]);

// The token before `<` (skipping inline whitespace) must not be an operand — else `<` is a comparison.
// An identifier is only a boundary when it is a value-introducing keyword.
function isTagBoundary(text: string, ltIndex: number): boolean {
  let b = ltIndex - 1;
  while (b >= 0 && (text[b] === " " || text[b] === "\t" || text[b] === "\n" || text[b] === "\r")) b--;
  if (b < 0) return true;
  if (isIdent(text[b])) {
    let s = b;
    while (s >= 0 && isIdent(text[s])) s--;
    return VALUE_KEYWORDS.has(text.slice(s + 1, b + 1));
  }
  const c = text[b];
  // operand-closers: a value ending in ) ] } " ' before `<` makes `<` a comparison (e.g. dict `}` < X)
  return !(c === ")" || c === "]" || c === "}" || c === '"' || c === "'");
}
