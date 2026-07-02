// Shared declaration scanning for `.guitkx` — the SINGLE source of truth for locating the
// `component`/`hook`/`module` header, with optional typo-recovery. Used by the formatter's window
// finder (formatGuitkx.ts), the virtual-doc builder (virtualDoc.ts) and the live declaration linter
// (declarations.ts), so all three degrade IDENTICALLY when the header keyword is misspelled.
//
// THE BUG THIS FIXES: markupWindows / buildVirtualDoc keyed off an EXACT keyword, so a single typo like
// `comssponent` produced no window and no virtual doc — the LSP then skipped markup AND embedded
// analysis and the whole file went dark, surfacing only one "unknown declaration" error. With recovery,
// a near-miss keyword at a real declaration position (`<word> <Name> [(...)] {`) is treated as that
// declaration for ANALYSIS, so the file's markup + embedded code keep being checked. Recovery is
// analysis-only: the formatter never recovers, so it can't silently rewrite a user's typo.

import { skipNoncode, findMatching, isIdent, keywordAt } from "./scanner";

export type DeclKind = "component" | "hook" | "module";
export const DECL_KEYWORDS: DeclKind[] = ["component", "hook", "module"];

export interface FoundDecl {
  kind: "" | DeclKind;
  at: number;
}

// Bounded Levenshtein (two-row DP). Kept here as the one implementation the recovery + linter share.
export function editDistance(a: string, b: string): number {
  const la = a.length;
  const lb = b.length;
  if (!la) return lb;
  if (!lb) return la;
  let prev = Array.from({ length: lb + 1 }, (_, i) => i);
  for (let x = 1; x <= la; x++) {
    const curr = [x];
    for (let y = 1; y <= lb; y++) {
      const cost = a[x - 1] === b[y - 1] ? 0 : 1;
      curr[y] = Math.min(prev[y] + 1, curr[y - 1] + 1, prev[y - 1] + cost);
    }
    prev = curr;
  }
  return prev[lb];
}

// The declaration keyword `word` most resembles (edit-distance <= 2, length >= 3 to avoid tiny
// coincidences), or null. An exact keyword returns null here — callers match those directly first.
export function nearestDeclKind(word: string): DeclKind | null {
  const w = word.toLowerCase();
  if (w.length < 3) return null;
  let best: DeclKind | null = null;
  let bestD = 3;
  for (const kw of DECL_KEYWORDS) {
    if (w === kw) return null;
    const d = editDistance(w, kw);
    if (d < bestD) {
      bestD = d;
      best = kw;
    }
  }
  return bestD <= 2 ? best : null;
}

// `<Name> [(...)] [-> Type] {` follows offset `i` (whitespace-skipped): the shape of a declaration head.
// Confirms a near-miss keyword really introduces a declaration, so a stray misspelled identifier
// elsewhere is never mistaken for one.
export function looksLikeDecl(src: string, i: number): boolean {
  const n = src.length;
  i = skipWs(src, i);
  if (i >= n || !isIdent(src[i])) return false; // a name must follow
  while (i < n && isIdent(src[i])) i++;
  i = skipWs(src, i);
  if (src[i] === "(") {
    const c = findMatching(src, i);
    if (c === -1) return false;
    i = skipWs(src, c + 1);
  }
  if (src[i] === "-" && src[i + 1] === ">") {
    i += 2;
    while (i < n && src[i] !== "{" && src[i] !== "\n") i++;
  }
  return src[i] === "{";
}

// The next declaration at/after `from`: an EXACT keyword, else (when `recover`) the first near-miss
// keyword at a declaration position. `{ kind: "", at: -1 }` when none.
export function findDecl(src: string, from: number, recover = false): FoundDecl {
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
  return recover ? recoverDecl(src, from) : { kind: "", at: -1 };
}

function recoverDecl(src: string, from: number): FoundDecl {
  const n = src.length;
  let i = from;
  while (i < n) {
    const k = skipNoncode(src, i);
    if (k !== i) {
      i = k;
      continue;
    }
    if (isIdent(src[i]) && (i === 0 || !isIdent(src[i - 1]))) {
      const s = i;
      while (i < n && isIdent(src[i])) i++;
      const kind = nearestDeclKind(src.slice(s, i));
      if (kind && looksLikeDecl(src, i)) return { kind, at: s };
      continue;
    }
    i++;
  }
  return { kind: "", at: -1 };
}

function skipWs(src: string, i: number): number {
  const n = src.length;
  while (i < n && (src[i] === " " || src[i] === "\t" || src[i] === "\n" || src[i] === "\r")) i++;
  return i;
}
