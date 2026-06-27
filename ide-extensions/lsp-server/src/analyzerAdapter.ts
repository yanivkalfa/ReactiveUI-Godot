// In-process GDScript intelligence for embedded code ({expr}, setup, @directive conditions), backed
// by @gdscript-analyzer/core — a headless GDScript static analyzer ("Roslyn for Godot"). This
// REPLACES godotProxy.ts: no TCP, no running Godot editor, results are deterministic and offline.
//
// We analyze the synthetic `.gd` "virtual document" (the same one the proxy used to forward) and
// return LSP-shaped results. The analyzer speaks UTF-8 BYTE offsets; the rest of the server works in
// JS-string (UTF-16) offsets, so this adapter owns the conversion at the boundary — callers pass and
// receive plain character offsets into the virtual-doc text.

import { CompletionItem, CompletionItemKind, DiagnosticSeverity, MarkupContent, MarkupKind } from "vscode-languageserver/node";
import { AnalysisHandle } from "@gdscript-analyzer/core";

const enc = new TextEncoder();

/** UTF-16 code-unit offset (a JS string index) -> UTF-8 byte offset. */
function charToByte(text: string, u16: number): number {
  return enc.encode(text.slice(0, Math.max(0, Math.min(u16, text.length)))).length;
}

/** UTF-8 byte offset -> UTF-16 code-unit offset (a JS string index). */
function byteToChar(text: string, byte: number): number {
  let b = 0;
  let u = 0;
  for (const ch of text) {
    if (b >= byte) break;
    b += enc.encode(ch).length;
    u += ch.length;
  }
  return u;
}

// The analyzer's completion `kind` is a string; map it to the LSP CompletionItemKind enum.
const KIND: Record<string, CompletionItemKind> = {
  keyword: CompletionItemKind.Keyword,
  variable: CompletionItemKind.Variable,
  parameter: CompletionItemKind.Variable,
  constant: CompletionItemKind.Constant,
  function: CompletionItemKind.Function,
  method: CompletionItemKind.Method,
  constructor: CompletionItemKind.Constructor,
  property: CompletionItemKind.Property,
  field: CompletionItemKind.Field,
  member: CompletionItemKind.Field,
  class: CompletionItemKind.Class,
  type: CompletionItemKind.Class,
  enum: CompletionItemKind.Enum,
  enum_member: CompletionItemKind.EnumMember,
  signal: CompletionItemKind.Event,
  namespace: CompletionItemKind.Module,
  module: CompletionItemKind.Module,
  snippet: CompletionItemKind.Snippet,
};

/** One embedded-GDScript diagnostic, its range mapped to CHAR offsets in the virtual-doc text. */
export interface AdapterDiag {
  /** char-offset range in the virtual `.gd` text. */
  range: { start: number; end: number };
  /** LSP severity (mapped from the analyzer's string severity). */
  severity: DiagnosticSeverity;
  /** The analyzer diagnostic code (e.g. `INTEGER_DIVISION`, `UNSAFE_METHOD_ACCESS`). */
  code: string;
  /** The human message. */
  message: string;
}

// The analyzer's diagnostic `severity` is a lowercase string; map to the LSP enum.
const SEVERITY: Record<string, DiagnosticSeverity> = {
  error: DiagnosticSeverity.Error,
  warning: DiagnosticSeverity.Warning,
  warn: DiagnosticSeverity.Warning,
  info: DiagnosticSeverity.Information,
  information: DiagnosticSeverity.Information,
  hint: DiagnosticSeverity.Hint,
};

/** A go-to-definition target. `range` is mapped to CHAR offsets in the TARGET file's text (the file
 *  `uri` identifies — the virtual doc for a same-file hit, a project library `.gd` for a cross-file
 *  one), so the caller maps it back without re-guessing which document the offsets belong to. */
export interface AdapterDef {
  /** FileId reported by the analyzer. */
  file: number;
  /** The URI of `file` via the adapter's id↔uri mirror, or `null` if the file isn't tracked. */
  uri: string | null;
  /** char-offset range in `uri`'s text (the TARGET file). */
  range: { start: number; end: number };
  name: string;
  kind: string;
}

export class AnalyzerAdapter {
  private az = new AnalysisHandle();
  /** uri -> { the FileId the analyzer assigned (mirrored), the doc's current text }. */
  private docs = new Map<string, { id: number; text: string }>();
  /** Reverse of `docs`: FileId -> uri. The analyzer interns sequentially from 0 and we are its sole
   *  opener (we never close a doc), so mirroring the counter reproduces its FileId↔uri map exactly —
   *  the binding does not expose one, and a cross-file def reports only the numeric FileId. */
  private fileIds = new Map<number, string>();
  private nextId = 0;

  /** Record a doc's FileId (first open) + current text, mirroring the analyzer's sequential interning. */
  private track(uri: string, text: string): void {
    const existing = this.docs.get(uri);
    if (existing) existing.text = text;
    else {
      const id = this.nextId++;
      this.docs.set(uri, { id, text });
      this.fileIds.set(id, uri);
    }
  }

  /** Set the project's project.godot text (enables `[autoload]` singleton resolution). Best-effort. */
  setProjectConfig(text: string): void {
    try {
      this.az.setProjectConfig(text);
    } catch {
      /* malformed project.godot — ignore */
    }
  }

  /** Open (first time) or replace the virtual `.gd` document at `uri`. */
  sync(uri: string, text: string): void {
    if (this.docs.has(uri)) this.az.changeDocument(uri, text);
    else this.az.openDocument(uri, text, null);
    this.track(uri, text);
  }

  /** Load a project library `.gd` file ONCE, with its `res://` path so the analyzer can resolve
   *  cross-file `class_name`/`preload`/`extends` against it (e.g. `Hooks` -> `core/hooks.gd`). A
   *  repeat call is a no-op (the res-path is recorded on first open only). */
  loadLibrary(uri: string, text: string, resPath: string): void {
    if (this.docs.has(uri)) return;
    this.az.openDocument(uri, text, resPath);
    this.track(uri, text);
  }

  /** The tracked text of `uri` (for offset->position mapping at the call site), or undefined. */
  textOf(uri: string): string | undefined {
    return this.docs.get(uri)?.text;
  }

  /** Completions at a CHAR offset in `text`, as LSP items. */
  completionsAt(uri: string, text: string, charOffset: number): CompletionItem[] {
    let items: any[];
    try {
      items = JSON.parse(this.az.completions(uri, charToByte(text, charOffset)));
    } catch {
      return [];
    }
    return items.map((c) => ({
      label: String(c.label),
      kind: KIND[c.kind] ?? CompletionItemKind.Text,
      detail: c.detail ?? undefined,
      insertText: c.insert_text ?? undefined,
    }));
  }

  /** Hover at a CHAR offset in `text`; markdown (inferred type + doc), or null if nothing is there. */
  hoverAt(uri: string, text: string, charOffset: number): MarkupContent | null {
    const raw = this.az.hover(uri, charToByte(text, charOffset));
    if (!raw) return null;
    let h: any;
    try {
      h = JSON.parse(raw);
    } catch {
      return null;
    }
    if (!h?.ty_label) return null;
    let value = "```gdscript\n" + h.ty_label + "\n```";
    if (h.doc) value += "\n\n" + h.doc;
    return { kind: MarkupKind.Markdown, value };
  }

  /** Parse + type diagnostics for the virtual doc, with ranges mapped to CHAR offsets in `text`. */
  diagnosticsAt(uri: string, text: string): AdapterDiag[] {
    let diags: any[];
    try {
      diags = JSON.parse(this.az.diagnostics(uri));
    } catch {
      return [];
    }
    return diags.map((d) => {
      const r = d.range ?? { start: 0, end: 0 };
      return {
        range: { start: byteToChar(text, r.start), end: byteToChar(text, r.end) },
        severity: SEVERITY[String(d.severity).toLowerCase()] ?? DiagnosticSeverity.Warning,
        code: String(d.code ?? ""),
        message: String(d.message ?? ""),
      };
    });
  }

  /** Definition target(s) at a CHAR offset in `text`. Each target's range is in its OWN file's text
   *  (the virtual doc for a same-file hit, a library `.gd` for a cross-file one), resolved via the
   *  id↔uri mirror — so a cross-file def's byte range is converted against the TARGET file's text. */
  definitionsAt(uri: string, text: string, charOffset: number): AdapterDef[] {
    let defs: any[];
    try {
      defs = JSON.parse(this.az.gotoDefinition(uri, charToByte(text, charOffset)));
    } catch {
      return [];
    }
    return defs.map((d) => {
      const file: number = d.file ?? 0;
      const targetUri = this.fileIds.get(file) ?? null;
      // A cross-file def's range is in the TARGET file; convert with that file's text (falling back to
      // the queried text for an untracked file id).
      const targetText = (targetUri ? this.docs.get(targetUri)?.text : undefined) ?? text;
      const r = d.focus_range ?? d.full_range ?? d.range ?? { start: 0, end: 0 };
      return {
        file,
        uri: targetUri,
        range: { start: byteToChar(targetText, r.start), end: byteToChar(targetText, r.end) },
        name: d.name,
        kind: d.kind,
      };
    });
  }
}
