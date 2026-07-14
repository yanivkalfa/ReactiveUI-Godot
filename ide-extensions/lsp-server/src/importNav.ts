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

const IMPORT_RE = /import[ \t]*\{([^}]*)\}[ \t]*from[ \t]*["']([^"']+)["']/g;

/** If `offset` sits on an import specifier or an imported name, describe it; else null. */
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
      // which comma-separated name is the cursor on?
      let p = namesStart;
      for (const raw of namesText.split(",")) {
        const nm = raw.trim();
        const at = src.indexOf(nm, p);
        if (nm && offset >= at && offset <= at + nm.length) return { kind: "name", spec, name: nm };
        p += raw.length + 1;
      }
      return { kind: "spec", spec };
    }
  }
  return null;
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
