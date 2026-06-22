// Workspace component index (Phase 6b) for go-to-definition / find-references on <Tag> references.
// Keyed by BINDING IDENTITY = (@class_name override) ?? (component decl name) — NOT basename: a
// cross-file <Foo/> compiles to V.fc(Foo.render, ...) where `Foo` is the generated class_name, which
// the @class_name preamble can override (the decl name may even differ — GUITKX0103). Module members
// bind by their member name (intra-module). Multi-valued byName + byUri eviction (Unity's model) so a
// copy+rename never deletes a live declarant.

import { skipNoncode, findMatching, keywordAt, isIdent } from "./scanner";
import { readdirSync, readFileSync } from "fs";
import { join } from "path";

export interface DeclInfo {
  kind: "component" | "hook" | "module" | "member";
  name: string;
  binding: string;
  module?: string;
  nameStart: number;
  nameEnd: number;
  declStart: number; // offset of the component/hook/module keyword (for documentSymbol range)
  declEnd: number; // offset just past the closing `}` (or nameEnd if bodyless) — also bounds a module's members
}

/** All top-level + module-member declarations (not just the first), mirroring the compiler dispatch. */
export function scanDeclarations(src: string): DeclInfo[] {
  const classOverride = readClassName(src);
  return scanRange(src, 0, src.length, classOverride, undefined);
}

function scanRange(src: string, start: number, end: number, classOverride: string, mod: string | undefined): DeclInfo[] {
  const out: DeclInfo[] = [];
  let i = start;
  let firstComponent = true;
  while (i < end) {
    const k = skipNoncode(src, i);
    if (k !== i) {
      i = k;
      continue;
    }
    let kw = "";
    let kind: DeclInfo["kind"] | null = null;
    if (keywordAt(src, i, "component")) {
      kw = "component";
      kind = mod ? "member" : "component";
    } else if (keywordAt(src, i, "hook")) {
      kw = "hook";
      kind = mod ? "member" : "hook";
    } else if (keywordAt(src, i, "module")) {
      kw = "module";
      kind = "module";
    }
    if (kind) {
      const declStart = i;
      const j = skipWs(src, i + kw.length);
      const nm = readIdent(src, j);
      if (nm.text === "") {
        i = j + 1;
        continue;
      }
      const isComp = kw === "component";
      const binding = isComp && !mod && firstComponent && classOverride ? classOverride : nm.text;
      if (isComp) firstComponent = false;
      const body = readBody(src, nm.end);
      const declEnd = body ? body.end + 1 : nm.end;
      out.push({ kind, name: nm.text, binding, module: mod, nameStart: nm.start, nameEnd: nm.end, declStart, declEnd });
      if (kw === "module" && body) out.push(...scanRange(src, body.start, body.end, "", nm.text));
      i = declEnd;
      continue;
    }
    i++;
  }
  return out;
}

function readClassName(src: string): string {
  const n = src.length;
  let i = 0;
  while (i < n) {
    i = skipWs(src, i);
    const k = skipNoncode(src, i);
    if (k !== i) {
      i = k;
      continue;
    }
    if (src.startsWith("@class_name", i) && (i + 11 >= n || /\s/.test(src[i + 11]))) {
      return readIdent(src, skipWs(src, i + 11)).text;
    }
    if (keywordAt(src, i, "component") || keywordAt(src, i, "hook") || keywordAt(src, i, "module")) break;
    i++;
  }
  return "";
}

function readBody(src: string, from: number): { start: number; end: number } | null {
  const n = src.length;
  let j = from;
  while (j < n && src[j] !== "{") {
    const k = skipNoncode(src, j);
    if (k !== j) {
      j = k;
      continue;
    }
    if (src[j] === "(") {
      const pc = findMatching(src, j);
      if (pc === -1) return null;
      j = pc + 1;
      continue;
    }
    j++;
  }
  if (j >= n || src[j] !== "{") return null;
  const close = findMatching(src, j);
  if (close === -1) return null;
  return { start: j + 1, end: close };
}

function skipWs(src: string, i: number): number {
  while (i < src.length && /\s/.test(src[i])) i++;
  return i;
}
function readIdent(src: string, i: number): { text: string; start: number; end: number } {
  const start = i;
  while (i < src.length && isIdent(src[i])) i++;
  return { text: src.slice(start, i), start, end: i };
}

// --- the index ---

export interface IndexEntry {
  uri: string;
  binding: string;
  name: string;
  kind: string;
  module?: string;
  nameStart: number;
  nameEnd: number;
}

export class WorkspaceIndex {
  private byName = new Map<string, IndexEntry[]>();
  private byUri = new Map<string, IndexEntry[]>();
  ready = false;

  reindex(rawUri: string, text: string): void {
    const uri = normalizeUri(rawUri);
    this.evict(uri);
    let decls: DeclInfo[];
    try {
      decls = scanDeclarations(text);
    } catch {
      return; // parse-failure tolerant: keep nothing rather than corrupt the index
    }
    const entries: IndexEntry[] = decls.map((d) => ({
      uri,
      binding: d.binding,
      name: d.name,
      kind: d.kind,
      module: d.module,
      nameStart: d.nameStart,
      nameEnd: d.nameEnd,
    }));
    this.byUri.set(uri, entries);
    for (const e of entries) {
      const arr = this.byName.get(e.binding) ?? [];
      arr.push(e);
      this.byName.set(e.binding, arr);
    }
  }

  evict(rawUri: string): void {
    const uri = normalizeUri(rawUri);
    const prev = this.byUri.get(uri);
    if (!prev) return;
    this.byUri.delete(uri);
    for (const e of prev) {
      const arr = this.byName.get(e.binding);
      if (!arr) continue;
      const left = arr.filter((x) => x.uri !== uri);
      if (left.length) this.byName.set(e.binding, left);
      else this.byName.delete(e.binding);
    }
  }

  lookup(name: string): IndexEntry[] {
    return this.byName.get(name) ?? [];
  }
  has(name: string): boolean {
    return this.byName.has(name);
  }
  names(): string[] {
    return [...this.byName.keys()];
  }
  entriesFor(uri: string): IndexEntry[] {
    return this.byUri.get(normalizeUri(uri)) ?? [];
  }
  uris(): string[] {
    return [...this.byUri.keys()];
  }
}

/** Recursively walk a project dir, indexing every .guitkx (skips dot-dirs like .godot/.git). */
export function scanWorkspace(index: WorkspaceIndex, rootPath: string): void {
  if (rootPath) walk(rootPath, index);
  index.ready = true;
}

function walk(dir: string, index: WorkspaceIndex): void {
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const e of entries) {
    if (e.name.startsWith(".")) continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, index);
    else if (e.name.endsWith(".guitkx")) {
      try {
        index.reindex(pathToUri(p), readFileSync(p, "utf8"));
      } catch {
        /* unreadable file — skip */
      }
    }
  }
}

export function pathToUri(p: string): string {
  let n = p.replace(/\\/g, "/");
  if (!n.startsWith("/")) n = "/" + n;
  return normalizeUri("file://" + encodeURI(n).replace(/[?#]/g, (c) => "%" + c.charCodeAt(0).toString(16)));
}

// Canonicalize a file URI so disk-walked paths and editor URIs key the same index entry: lowercase the
// Windows drive letter and encode its colon as %3A (VS Code's form, e.g. file:///c%3A/Users/...).
export function normalizeUri(uri: string): string {
  const m = /^file:\/\/\/([A-Za-z])(?::|%3[Aa])(\/.*)$/.exec(uri);
  return m ? `file:///${m[1].toLowerCase()}%3A${m[2]}` : uri;
}

/** Component <Tag> identity under `offset`, or null. PascalCase only (lowercase = host factory). */
export function componentTagAt(src: string, offset: number): string | null {
  let s = offset;
  let e = offset;
  while (s > 0 && isIdent(src[s - 1])) s--;
  while (e < src.length && isIdent(src[e])) e++;
  if (s === e) return null;
  const name = src.slice(s, e);
  if (!/^[A-Z]/.test(name)) return null;
  let b = s - 1;
  if (src[b] === "/") b--;
  while (b > 0 && (src[b] === " " || src[b] === "\t")) b--;
  return src[b] === "<" ? name : null;
}

export function offsetToPosition(text: string, offset: number): { line: number; character: number } {
  let line = 0;
  let last = 0;
  for (let i = 0; i < offset && i < text.length; i++) {
    if (text[i] === "\n") {
      line++;
      last = i + 1;
    }
  }
  return { line, character: offset - last };
}
