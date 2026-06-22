// OPTIONAL Tier-1 reflow of embedded GDScript via gdformat (gdscript-toolkit), layered ON TOP of the
// in-process formatter's base-indent normalization (Tier-2). Pure polish: when gdformat is absent (the
// default for most users) this is a no-op and the base-indent output stands. STRICT SAFETY NET: every
// reflowed region must be token-equivalent to the original (whitespace ignored, string-quote style
// normalized) — any anomaly, spawn failure, or non-equivalence leaves the region untouched, so it can
// never corrupt code. Scope: top-level component setup / hook body (modules keep base-indent in v1).

import { spawnSync } from "child_process";
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { skipString } from "./scanner";
import { embeddedRegions } from "./formatGuitkx";

let probe: string | null | undefined;

/** The gdformat binary if available (cached), else null. */
export function gdformatBin(): string | null {
  if (probe !== undefined) return probe;
  try {
    const r = spawnSync("gdformat", ["--version"], { timeout: 4000, encoding: "utf8" });
    probe = r.status === 0 || (r.stdout && /\d/.test(r.stdout)) ? "gdformat" : null;
  } catch {
    probe = null;
  }
  return probe;
}

/** Reflow embedded-GDScript regions of an already-formatted document. No-op when gdformat is absent. */
export function reflowEmbedded(formatted: string): string {
  const bin = gdformatBin();
  if (!bin) return formatted;
  const regions = embeddedRegions(formatted).sort((a, b) => b.start - a.start); // descending: offsets stay valid
  let out = formatted;
  for (const r of regions) {
    const original = out.slice(r.start, r.end);
    const reflowed = reflowRegion(bin, original);
    if (reflowed !== null && tokenEquivalent(stripWrap(original), stripWrap(reflowed))) {
      out = out.slice(0, r.start) + reflowed + out.slice(r.end);
    }
  }
  return out;
}

// Reflow one region, preserving its boundary whitespace; null on any failure.
function reflowRegion(bin: string, region: string): string | null {
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
  const wrapped = "func __rui_reflow():\n" + dedented.map((l) => (l === "" ? "" : "\t" + l)).join("\n") + "\n";
  let dir: string | null = null;
  try {
    dir = mkdtempSync(join(tmpdir(), "guitkx-gdf-"));
    const file = join(dir, "r.gd");
    writeFileSync(file, wrapped, "utf8");
    const res = spawnSync(bin, [file], { timeout: 8000 });
    if (res.status !== 0) return null;
    const fl = readFileSync(file, "utf8").replace(/\r\n/g, "\n").replace(/\n$/, "").split("\n");
    if (!fl.length || !/^func __rui_reflow\(\):/.test(fl[0])) return null;
    const body = fl.slice(1);
    const bodyIndent = commonIndent(body.filter((l) => l.trim() !== ""));
    const reflowedCore = body.map((l) => (l.trim() === "" ? "" : hostIndent + l.slice(bodyIndent.length))).join("\n");
    return lead + reflowedCore + trail;
  } catch {
    return null;
  } finally {
    if (dir) {
      try {
        rmSync(dir, { recursive: true, force: true });
      } catch {
        /* ignore */
      }
    }
  }
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

function stripWrap(s: string): string {
  return s; // tokenEquivalent ignores whitespace anyway; kept for symmetry/clarity
}

// Token-equivalence: identical after removing inter-token whitespace + comments and normalizing string
// quote style. Rejects structural changes (idents/operators/commas/trailing-commas) — conservative but
// guarantees gdformat only reflows whitespace/quote style, never semantics.
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
