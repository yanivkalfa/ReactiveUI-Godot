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
// An identifier is only a boundary when it is a value-introducing keyword. Shared with componentTagAt.
export function isTagBoundary(text: string, ltIndex: number): boolean {
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

export interface ClauseRef {
  start: number;
  end: number;
}

// REMOTE-name occurrences of `name` inside named import clauses whose specifier satisfies
// `specMatches` — the tokens a project-wide rename of the declaration must rewrite (E-08: for a
// `remote as local` clause only the remote half moves; the local alias and its uses stay). A plain
// `Name` clause is its own remote, so renaming it also renames the local binding — consistent,
// because the tag references in that file are rewritten by the same rename pass. Namespace
// (`* as X`) and default (`import X from`) clauses carry no remote NAME and never match.
export function scanImportClauseRefs(text: string, name: string, specMatches: (spec: string) => boolean): ClauseRef[] {
  const out: ClauseRef[] = [];
  const re = /import[ \t]*\{([^}]*)\}[ \t]*from[ \t]*["']([^"']+)["']/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) {
    if (!specMatches(m[2])) continue;
    const bodyStart = m.index + m[0].indexOf("{") + 1;
    const body = m[1];
    // Clause walk with offsets: `remote [as local]` per comma-separated entry.
    let p = 0;
    while (p < body.length) {
      while (p < body.length && /[\s,]/.test(body[p])) p++;
      const rs = p;
      while (p < body.length && isIdent(body[p])) p++;
      if (p === rs) {
        p++;
        continue;
      }
      const remote = body.slice(rs, p);
      // optional `as local`
      let q = p;
      while (q < body.length && /[ \t]/.test(body[q])) q++;
      if (body.startsWith("as", q) && !isIdent(body[q + 2] ?? "")) {
        q += 2;
        while (q < body.length && /[ \t]/.test(body[q])) q++;
        while (q < body.length && isIdent(body[q])) q++;
        p = q;
      }
      if (remote === name) out.push({ start: bodyStart + rs, end: bodyStart + rs + remote.length });
    }
  }
  return out;
}

// Occurrences of `name` in the declaring file's E-07/E-09 export markers (`export default Name`,
// `export { a, Name, b }`) — these tokens must rename in lockstep with the declaration.
export function scanExportMarkerRefs(text: string, name: string): ClauseRef[] {
  const out: ClauseRef[] = [];
  const defRe = /^[ \t]*export[ \t]+default[ \t]+([A-Za-z_]\w*)/gm;
  let m: RegExpExecArray | null;
  while ((m = defRe.exec(text)) !== null) {
    if (m[1] === name) {
      const s = m.index + m[0].length - m[1].length;
      out.push({ start: s, end: s + name.length });
    }
  }
  const listRe = /^[ \t]*export[ \t]*\{([^}]*)\}/gm;
  while ((m = listRe.exec(text)) !== null) {
    const bodyStart = m.index + m[0].indexOf("{") + 1;
    const body = m[1];
    let p = 0;
    while (p < body.length) {
      while (p < body.length && /[\s,]/.test(body[p])) p++;
      const s = p;
      while (p < body.length && isIdent(body[p])) p++;
      if (p > s && body.slice(s, p) === name) out.push({ start: bodyStart + s, end: bodyStart + p });
    }
  }
  return out;
}
