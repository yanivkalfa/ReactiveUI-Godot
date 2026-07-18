// Cross-file navigation for the 0.10.0 import model: click-through on an import specifier or an
// imported name -> the target `.guitkx` file (and, for a name, its declaration). Pure/fs-only, so it
// composes with the language server's definition handler. Mirrors the compiler's specifier rules
// (`./ ../ ~/`, extensionless; res:// / uid:// are not valid import specifiers).

import { existsSync, readFileSync } from "fs";
import { dirname, join, resolve } from "path";

export interface ImportHit {
  kind: "spec" | "name";
  spec: string;
  name?: string;
}

// The optional COMBINED default binding (`import Def, { … } from` / `import Def, * as X from`,
// 0.11.1): a leading identifier + comma may precede the named/namespace clause.
const IMPORT_RE = /import[ \t]*(?:[A-Za-z_][A-Za-z0-9_]*[ \t]*,[ \t]*)?\{([^}]*)\}[ \t]*from[ \t]*["']([^"']+)["']/g;
// G-05 (ES-modules leg): namespace + default clause shapes.
const IMPORT_NS_RE = /import[ \t]*(?:[A-Za-z_][A-Za-z0-9_]*[ \t]*,[ \t]*)?\*[ \t]*as[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]+from[ \t]*["']([^"']+)["']/g;
const IMPORT_DEFAULT_RE = /import[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]+from[ \t]*["']([^"']+)["']/g;

/** If `offset` sits on an import specifier or an imported name, describe it; else null. Covers all
 *  G-05 clause shapes: named (with `remote as local` renames -- navigation targets the REMOTE
 *  declaration), `* as X` namespace, bare default imports, and the combined forms. */
export function importAt(src: string, offset: number): ImportHit | null {
  IMPORT_RE.lastIndex = 0;
  let m: RegExpExecArray | null;
  while ((m = IMPORT_RE.exec(src)) !== null) {
    const namesText = m[1];
    const spec = m[2];
    const namesStart = m.index + m[0].indexOf("{") + 1;
    const namesEnd = namesStart + namesText.length;
    const specStart = m.index + m[0].lastIndexOf(spec);
    const specEnd = specStart + spec.length;
    if (offset >= specStart && offset <= specEnd) return { kind: "spec", spec };
    if (offset >= namesStart && offset <= namesEnd) {
      // which comma-separated clause is the cursor on? A `remote as local` rename navigates to
      // the REMOTE name (the declaration that actually exists in the target file -- E-08).
      let p = namesStart;
      for (const raw of namesText.split(",")) {
        const clause = raw.trim();
        const at = src.indexOf(clause, p);
        if (clause && offset >= at && offset <= at + clause.length) {
          const asM = /^([A-Za-z_][A-Za-z0-9_]*)[ \t]+as[ \t]+[A-Za-z_][A-Za-z0-9_]*$/.exec(clause);
          return { kind: "name", spec, name: asM ? asM[1] : clause };
        }
        p += raw.length + 1;
      }
      return { kind: "spec", spec };
    }
    // Anywhere else on the clause (the `import` keyword, a combined default binding) — the file
    // itself is the navigation target, same as the namespace/default branches below.
    if (offset >= m.index && offset <= m.index + m[0].length) return { kind: "spec", spec };
  }
  IMPORT_NS_RE.lastIndex = 0;
  while ((m = IMPORT_NS_RE.exec(src)) !== null) {
    const spec = m[2];
    if (offset >= m.index && offset <= m.index + m[0].length) return { kind: "spec", spec };
  }
  IMPORT_DEFAULT_RE.lastIndex = 0;
  while ((m = IMPORT_DEFAULT_RE.exec(src)) !== null) {
    const spec = m[2];
    // The default-import local binds the target's `export default` decl; the file itself is the
    // navigation target (the LSP resolves the decl once there).
    if (offset >= m.index && offset <= m.index + m[0].length) return { kind: "spec", spec };
  }
  return null;
}

export interface ImportBraceContext {
  /** The combined form's default binding (`import Def, { | }`), or null. */
  def: string | null;
  /** The line's `from "…"` specifier, or null while still untyped. */
  spec: string | null;
  /** Names already listed inside the braces — imported names AND their `as` aliases. */
  already: string[];
}

/** The import-brace completion context at `offset` (a caret inside the `{ … }` of an import
 *  line), or null. Line-shaped on purpose: while TYPING the list the import is malformed, so the
 *  parsed-imports channel cannot see it. The prefix allows the COMBINED default binding
 *  (`import Def, { | } from` — 0.11.1 field wave: a bare-`import` prefix check returned nothing
 *  inside a combined form's braces). */
export function importBraceAt(src: string, offset: number): ImportBraceContext | null {
  const lineStart = src.lastIndexOf("\n", offset - 1) + 1;
  let lineEnd = src.indexOf("\n", lineStart);
  if (lineEnd === -1) lineEnd = src.length;
  const line = src.slice(lineStart, lineEnd);
  const col = offset - lineStart;
  const braceOpen = line.indexOf("{");
  if (braceOpen < 0 || col <= braceOpen) return null;
  const prefix = /^[ \t]*import[ \t]*(?:([A-Za-z_][A-Za-z0-9_]*)[ \t]*,[ \t]*)?$/.exec(line.slice(0, braceOpen));
  if (!prefix) return null;
  const braceClose = line.indexOf("}", braceOpen);
  const regionEnd = braceClose < 0 ? line.length : braceClose;
  if (col > regionEnd) return null;
  const specM = /from[ \t]*["']([^"']+)["']/.exec(line.slice(regionEnd));
  const already: string[] = [];
  for (const entry of line.slice(braceOpen + 1, regionEnd).split(",")) {
    // Each entry may be aliased (`a as b`): the imported NAME must not be re-suggested, and the
    // bound ALIAS would collide with a same-named export — track both.
    for (const tok of entry.trim().split(/\s+/)) {
      if (tok && tok !== "as") already.push(tok);
    }
  }
  return { def: prefix[1] ?? null, spec: specM ? specM[1] : null, already };
}

/** The `~/` root directory for a file: the nearest guitkx.config.json's `"root"` (res:// mapped to
 *  `projectDir`), else `projectDir`. Nearest config wins, no merge. */
export function importRoot(fileDir: string, projectDir: string): string {
  let dir = fileDir;
  for (;;) {
    const cfg = join(dir, "guitkx.config.json");
    if (existsSync(cfg)) {
      try {
        const raw = JSON.parse(readFileSync(cfg, "utf8"))?.root;
        if (typeof raw === "string" && raw.length) {
          const rel = raw.startsWith("res://") ? raw.slice("res://".length) : raw;
          return raw.startsWith("res://") ? join(projectDir, rel) : resolve(dir, rel);
        }
      } catch { /* malformed config -> default root */ }
      return projectDir;
    }
    const parent = dirname(dir);
    if (parent === dir) return projectDir;
    dir = parent;
  }
}

/** Resolve an import specifier to a target `.guitkx` absolute path, or null (bad form / not found). */
export function resolveSpecifier(spec: string, fromFile: string, projectDir: string): string | null {
  if (spec.startsWith("res://") || spec.startsWith("uid://")) return null;
  let base: string;
  if (spec.startsWith("~/")) base = join(importRoot(dirname(fromFile), projectDir), spec.slice(2));
  else if (spec.startsWith("./") || spec.startsWith("../")) base = resolve(dirname(fromFile), spec);
  else return null;
  const target = base.endsWith(".guitkx") ? base : base + ".guitkx";
  return existsSync(target) ? target : null;
}
