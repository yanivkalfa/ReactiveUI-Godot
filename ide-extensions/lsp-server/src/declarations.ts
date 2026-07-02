// Live declaration validation for `.guitkx` — the "floor" the LSP was missing. The markup and
// embedded-GDScript passes both key off a valid `component`/`hook`/`module` header (markupWindows
// finds the `return(...)` of one). A single typo like `comssponent` yields NO window, so the LSP
// used to skip ALL analysis and report NOTHING — the whole file went dark silently. This validates
// the header itself, mirroring guitkx.gd compile() preamble + _find_decl / _nearest_decl_keyword,
// so a mistyped keyword / `@class_name` is reported live without a running Godot editor.
//
// Offset-based (no LSP types) so it stays unit-testable; server.ts wraps the results into Diagnostics.

import { skipNoncode, isIdent } from "./scanner";
import { scanDeclarations } from "./workspaceIndex";

export interface DeclDiag {
  start: number;
  end: number;
  code: string;
  message: string;
}

const DECL_KWS = ["component", "hook", "module"];

// Bounded Levenshtein (two-row DP), mirroring guitkx.gd _edit_distance.
function editDistance(a: string, b: string): number {
  const la = a.length, lb = b.length;
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

// The first top-level identifier and the declaration keyword it most resembles (edit distance <= 3),
// for a "did you mean 'component'?" hint. null if none is close.
export function nearestDeclKeyword(src: string): { word: string; kw: string; start: number; end: number } | null {
  let i = 0;
  while (i < src.length) {
    const k = skipNoncode(src, i);
    if (k !== i) { i = k; continue; }
    if (src[i] === "@") { // a directive line (e.g. a mistyped @class_name) — skip past it
      const nl = src.indexOf("\n", i);
      i = nl === -1 ? src.length : nl + 1;
      continue;
    }
    if (isIdent(src[i])) {
      const s = i;
      while (i < src.length && isIdent(src[i])) i++;
      const word = src.slice(s, i);
      let best = "", bestD = 99;
      for (const kw of DECL_KWS) {
        const d = editDistance(word.toLowerCase(), kw);
        if (d < bestD) { bestD = d; best = kw; }
      }
      return best && bestD <= 3 ? { word, kw: best, start: s, end: i } : null;
    }
    i++;
  }
  return null;
}

// GUITKX0300 (`@class_name` value) + GUITKX0102 (misspelled / missing declaration).
export function declarationDiags(src: string): DeclDiag[] {
  const out: DeclDiag[] = [];

  // @class_name preamble: the value must be a single valid identifier.
  let p = 0;
  while (p < src.length && (src[p] === " " || src[p] === "\t" || src[p] === "\n" || src[p] === "\r")) p++;
  if (src.startsWith("@class_name", p)) {
    let le = src.indexOf("\n", p);
    if (le === -1) le = src.length;
    let raw = src.slice(p + "@class_name".length, le);
    const hash = raw.indexOf("#");
    if (hash !== -1) raw = raw.slice(0, hash);
    const val = raw.trim();
    if (val === "" || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(val)) {
      out.push({
        start: p,
        end: le,
        code: "GUITKX0300",
        message: `GUITKX0300: \`@class_name\` value must be a single valid identifier (got '${val}').`,
      });
    }
  }

  // No valid component/hook/module declaration -> flag the nearest misspelled keyword, else say none
  // was found. Either way the author learns the header is broken instead of getting silence.
  if (scanDeclarations(src).length === 0) {
    const near = nearestDeclKeyword(src);
    if (near) {
      out.push({
        start: near.start,
        end: near.end,
        code: "GUITKX0102",
        message: `GUITKX0102: unknown declaration '${near.word}' — did you mean '${near.kw}'?`,
      });
    } else {
      out.push({
        start: 0,
        end: Math.min(src.length, 1),
        code: "GUITKX0102",
        message: "GUITKX0102: no `component`, `hook`, or `module` declaration found.",
      });
    }
  }
  return out;
}
