// Per-Control property/signal data from the generated ClassDB dump (Phase 6c). The Node LSP has no
// in-process ClassDB, so addons/reactive_ui/dev/classdb_dump.gd writes own-only members per class and
// we base-flatten here. Bundled with the extension; regenerated per Godot minor.

import { readFileSync } from "fs";
import { join } from "path";

export interface ClassProp {
  name: string;
  type: string;
  enum?: string; // "A,B,C" or "A:0,B:2"
}
export interface ClassSignal {
  name: string;
  args: { name: string; type: string }[];
}
interface ClassEntry {
  base: string;
  properties: ClassProp[];
  signals: ClassSignal[];
}

let DB: Record<string, ClassEntry> | null = null;

function load(): Record<string, ClassEntry> {
  if (DB) return DB;
  try {
    const raw = JSON.parse(readFileSync(join(__dirname, "..", "classdb", "godot-control.json"), "utf8"));
    DB = raw.classes || {};
  } catch {
    DB = {};
  }
  return DB!;
}

export function hasDump(): boolean {
  return Object.keys(load()).length > 0;
}

/** Settable properties of `godotClass`, flattened over its base chain (own members win on shadow). */
export function classProperties(godotClass: string): ClassProp[] {
  const db = load();
  const out: ClassProp[] = [];
  const seen = new Set<string>();
  let c: string | undefined = godotClass;
  let guard = 0;
  while (c && db[c] && guard++ < 50) {
    for (const p of db[c].properties)
      if (!seen.has(p.name)) {
        seen.add(p.name);
        out.push(p);
      }
    c = db[c].base;
  }
  return out;
}

/** Signals of `godotClass`, flattened over its base chain. */
export function classSignals(godotClass: string): ClassSignal[] {
  const db = load();
  const out: ClassSignal[] = [];
  const seen = new Set<string>();
  let c: string | undefined = godotClass;
  let guard = 0;
  while (c && db[c] && guard++ < 50) {
    for (const s of db[c].signals)
      if (!seen.has(s.name)) {
        seen.add(s.name);
        out.push(s);
      }
    c = db[c].base;
  }
  return out;
}

/** Parse an enum hint_string ("A,B,C" or "A:0,B:2") into named-constant completion values. */
export function enumValues(hint: string): { label: string; value: string }[] {
  return hint.split(",").map((tok) => {
    const eq = tok.indexOf(":");
    const label = (eq >= 0 ? tok.slice(0, eq) : tok).trim();
    const value = eq >= 0 ? tok.slice(eq + 1).trim() : "";
    return { label, value };
  });
}
