// Reflow the embedded-GDScript regions of an already-formatted .guitkx document through the analyzer's
// formatter — the SAME gdscript-fmt that drives plain `.gd` files — so a snippet formats IDENTICALLY
// whether it lives in a `.gd` or inside `.guitkx` (BUG-1). Layered on top of the in-process markup
// formatter's base-indent normalization. The bundled analyzer is always available, so this no longer
// depends on an external `gdformat` binary. STRICT SAFETY NET: every reflowed region must be
// token-equivalent to the original (whitespace ignored, string-quote style normalized) — any anomaly or
// non-equivalence leaves the region untouched, so it can never corrupt code. Scope: top-level component
// setup / hook body (modules keep base-indent in v1).

import { skipString } from "./scanner";
import { embeddedRegions } from "./formatGuitkx";

/** A standalone-GDScript formatter (the analyzer's `gdscript-fmt`); returns the tidied text, or null. */
export type GdFormatter = (gd: string) => string | null;

/** Reflow embedded-GDScript regions of an already-formatted document via `format`. A region that fails
 *  to format, or whose reflow is not token-equivalent to the original, is left exactly as-is.
 *  `indentUnit` (Phase D): the document's one-level indent string ("  " for the spaces-2 default) —
 *  gdscript-fmt emits TAB depth, and splicing those tabs verbatim into a spaces file is the classic
 *  mixed-indent bug, so each reflowed line's relative depth is converted to the document's unit. */
export function reflowEmbedded(formatted: string, format: GdFormatter, indentUnit = "  "): string {
  const regions = embeddedRegions(formatted).sort((a, b) => b.start - a.start); // descending: offsets stay valid
  let out = formatted;
  for (const r of regions) {
    const original = out.slice(r.start, r.end);
    const reflowed = reflowRegion(format, original, indentUnit);
    if (reflowed !== null && tokenEquivalent(original, reflowed)) {
      out = out.slice(0, r.start) + reflowed + out.slice(r.end);
    }
  }
  return out;
}

// Reflow one region, preserving its boundary whitespace; null on any failure.
function reflowRegion(format: GdFormatter, region: string, indentUnit: string): string | null {
  const lead = region.slice(0, region.length - region.replace(/^[ \t\r\n]+/, "").length);
  const trail = region.slice(region.replace(/[ \t\r\n]+$/, "").length);
  const core = region.slice(lead.length, region.length - trail.length);
  if (core.trim() === "") return null;
  // bail on constructs the blind line-by-line re-indent could corrupt: a string literal spanning a
  // newline (triple-quoted / multi-line) or a `\` line-continuation. Leave them to base-indent.
  if (hasMultilineString(core) || /\\[ \t]*\n/.test(core)) return null;
  const coreLines = core.split("\n");
  const hostIndent = commonIndent(coreLines);
  const dedented = coreLines.map((l) => (l.startsWith(hostIndent) ? l.slice(hostIndent.length) : l.replace(/^[ \t]+/, "")));
  // Wrap in a throwaway func so the analyzer formats it as a real statement body, format, then lift the
  // body back out and re-anchor to the region's host indentation.
  const wrapped = "func __rui_reflow():\n" + dedented.map((l) => (l === "" ? "" : "\t" + l)).join("\n") + "\n";
  const formatted = format(wrapped);
  if (formatted === null) return null;
  const fl = formatted.replace(/\r\n/g, "\n").replace(/\n$/, "").split("\n");
  if (!fl.length || !/^func __rui_reflow\(\):/.test(fl[0])) return null;
  const body = fl.slice(1);
  const bodyIndent = commonIndent(body.filter((l) => l.trim() !== ""));
  // Relative depth beyond the region base arrives as gdscript-fmt TABS — convert each level to the
  // document's indent unit so a spaces-2 file never gains interior tabs.
  const reflowedCore = body
    .map((l) => {
      if (l.trim() === "") return "";
      const rest = l.slice(bodyIndent.length);
      const rel = rest.match(/^\t*/)![0].length;
      return hostIndent + indentUnit.repeat(rel) + rest.slice(rel);
    })
    .join("\n");
  return lead + reflowedCore + trail;
}

function hasMultilineString(s: string): boolean {
  let i = 0;
  const n = s.length;
  while (i < n) {
    const c = s[i];
    if (c === '"' || c === "'") {
      const end = skipString(s, i);
      if (s.slice(i, end > i ? end : i + 1).includes("\n")) return true;
      i = end > i ? end : i + 1;
    } else if (c === "#") {
      while (i < n && s[i] !== "\n") i++;
    } else {
      i++;
    }
  }
  return false;
}

function commonIndent(lines: string[]): string {
  let prefix: string | null = null;
  for (const l of lines) {
    if (l.trim() === "") continue;
    const lead = l.match(/^[\t ]*/)![0];
    prefix = prefix === null ? lead : common(prefix, lead);
  }
  return prefix ?? "";
}
function common(a: string, b: string): string {
  let i = 0;
  while (i < a.length && i < b.length && a[i] === b[i]) i++;
  return a.slice(0, i);
}

// Token-equivalence: identical after removing inter-token whitespace + comments and normalizing string
// quote style. Rejects structural changes (idents/operators/commas/trailing-commas) — conservative but
// guarantees the reflow only changes whitespace/quote style, never semantics.
export function tokenEquivalent(a: string, b: string): boolean {
  return normalizeGd(a) === normalizeGd(b);
}

export function normalizeGd(s: string): string {
  let out = "";
  const n = s.length;
  let i = 0;
  while (i < n) {
    const c = s[i];
    if (c === " " || c === "\t" || c === "\n" || c === "\r") {
      i++;
      continue;
    }
    if (c === "#") {
      while (i < n && s[i] !== "\n") i++;
      continue;
    }
    if (c === '"' || c === "'") {
      const end = skipString(s, i);
      const triple = s.substr(i, 3) === '"""' || s.substr(i, 3) === "'''";
      const content = triple ? s.slice(i + 3, Math.max(i + 3, end - 3)) : s.slice(i + 1, Math.max(i + 1, end - 1));
      out += '"' + content + '"';
      i = end > i ? end : i + 1;
      continue;
    }
    out += c;
    i++;
  }
  return out;
}
