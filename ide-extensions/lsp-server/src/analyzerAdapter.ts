// In-process GDScript intelligence for embedded code ({expr}, setup, @directive conditions), backed
// by @gdscript-analyzer/core — a headless GDScript static analyzer ("Roslyn for Godot"). This
// REPLACES godotProxy.ts: no TCP, no running Godot editor, results are deterministic and offline.
//
// We analyze the synthetic `.gd` "virtual document" (the same one the proxy used to forward) and
// return LSP-shaped results. The analyzer speaks UTF-8 BYTE offsets; the rest of the server works in
// JS-string (UTF-16) offsets, so this adapter owns the conversion at the boundary — callers pass and
// receive plain character offsets into the virtual-doc text.

import {
  CompletionItem,
  CompletionItemKind,
  DiagnosticSeverity,
  InlayHintKind,
  MarkupContent,
  MarkupKind,
  SignatureHelp,
  SymbolKind,
} from "vscode-languageserver/node";
import { GD_TOKEN_TYPE } from "./semanticTokens";
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
  /** The URI of the target file, reported directly by the analyzer (the binding enriches every
   *  navigation target's `file` id with its `uri`), or `null` if the file isn't tracked. */
  uri: string | null;
  /** char-offset range in `uri`'s text (the TARGET file). */
  range: { start: number; end: number };
  name: string;
  kind: string;
}

/** One reference (find-references result), its range in CHAR offsets within its OWN file's text (`uri`). */
export interface AdapterRef {
  /** The URI of the file the reference is in (the virtual doc for a same-file hit, a library `.gd` for
   *  a cross-file one), or `null` if untracked. */
  uri: string | null;
  /** char-offset range in `uri`'s text. */
  range: { start: number; end: number };
}

/** The edits for one file in a rename, each range in CHAR offsets within that file's text. */
export interface AdapterFileEdit {
  uri: string | null;
  edits: { range: { start: number; end: number }; newText: string }[];
}

/** A rename outcome — per-file edits, or a refusal reason. The analyzer is "correct-or-refuse": it
 *  never returns a partial edit, always an `{ ok }` / `{ error }` envelope. */
export type AdapterRename = { ok: AdapterFileEdit[] } | { error: string };

/** A document-outline node, ranges in CHAR offsets within the file's text (the server builds the LSP
 *  DocumentSymbol from this, converting offsets to positions). Used for plain `.gd` documents. */
export interface AdapterSymbol {
  name: string;
  detail?: string;
  kind: SymbolKind;
  range: { start: number; end: number };
  selectionRange: { start: number; end: number };
  children: AdapterSymbol[];
}

// The analyzer's snake_case SymbolKind -> the LSP SymbolKind enum.
const SYMBOL_KIND: Record<string, SymbolKind> = {
  class: SymbolKind.Class,
  func: SymbolKind.Function,
  function: SymbolKind.Function,
  method: SymbolKind.Method,
  var: SymbolKind.Variable,
  variable: SymbolKind.Variable,
  const: SymbolKind.Constant,
  constant: SymbolKind.Constant,
  signal: SymbolKind.Event,
  enum: SymbolKind.Enum,
  enum_member: SymbolKind.EnumMember,
  enum_value: SymbolKind.EnumMember,
  member: SymbolKind.Field,
  field: SymbolKind.Field,
  property: SymbolKind.Property,
  parameter: SymbolKind.Variable,
};

export class AnalyzerAdapter {
  private az = new AnalysisHandle();
  /** uri -> the doc's current text (for offset<->position mapping at the call site). The analyzer's
   *  binding now reports each navigation target's `uri` directly, so we no longer mirror its FileIds. */
  private docs = new Map<string, string>();

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
    this.docs.set(uri, text);
  }

  /** Load a project library `.gd` file ONCE, with its `res://` path so the analyzer can resolve
   *  cross-file `class_name`/`preload`/`extends` against it (e.g. `Hooks` -> `core/hooks.gd`). A
   *  repeat call is a no-op (the res-path is recorded on first open only). */
  loadLibrary(uri: string, text: string, resPath: string): void {
    if (this.docs.has(uri)) return;
    this.az.openDocument(uri, text, resPath);
    this.docs.set(uri, text);
  }

  /** Create-or-update a project library `.gd` (the file-watcher path): a new file opens with its
   *  `res://` path, a known one gets its text replaced. Keeps the workspace-complete claim true. */
  upsertLibrary(uri: string, text: string, resPath: string): void {
    if (this.docs.has(uri)) this.az.changeDocument(uri, text);
    else this.az.openDocument(uri, text, resPath);
    this.docs.set(uri, text);
  }

  /** Drop a deleted file from the analyzer + the text mirror. No-op if untracked. */
  close(uri: string): void {
    if (!this.docs.has(uri)) return;
    this.az.closeDocument(uri);
    this.docs.delete(uri);
  }

  /** Declare whether the analyzer has been fed the WHOLE project (every `.gd` under the root). Arms
   *  the absence-based UNDEFINED_FUNCTION / UNDEFINED_IDENTIFIER diagnostics (core 0.5.3+) — a
   *  partial view can never prove a name is defined nowhere, so they stay silent until this is set.
   *  Only claim it while a file watcher keeps the view current (see server.ts onInitialized). */
  setWorkspaceComplete(complete: boolean): void {
    this.az.setWorkspaceComplete(complete);
  }

  /** The tracked text of `uri` (for offset->position mapping at the call site), or undefined. */
  textOf(uri: string): string | undefined {
    return this.docs.get(uri);
  }

  /** Completions at a CHAR offset in `text`, as LSP items. The binding returns a native JS array
   *  (no JSON.parse). */
  completionsAt(uri: string, text: string, charOffset: number): CompletionItem[] {
    const items: any[] = this.az.completions(uri, charToByte(text, charOffset)) ?? [];
    return items.map((c) => ({
      label: String(c.label),
      kind: KIND[c.kind] ?? CompletionItemKind.Text,
      detail: c.detail ?? undefined,
      insertText: c.insert_text ?? undefined,
    }));
  }

  /** Hover at a CHAR offset in `text`; markdown (inferred type + doc), or null if nothing is there.
   *  The binding returns a native object (or null) — no JSON.parse. */
  hoverAt(uri: string, text: string, charOffset: number): MarkupContent | null {
    const h: any = this.az.hover(uri, charToByte(text, charOffset));
    if (!h?.ty_label) return null;
    let value = "```gdscript\n" + h.ty_label + "\n```";
    if (h.doc) value += "\n\n" + h.doc;
    return { kind: MarkupKind.Markdown, value };
  }

  /** Parse + type diagnostics for the virtual doc, with ranges mapped to CHAR offsets in `text`. */
  diagnosticsAt(uri: string, text: string): AdapterDiag[] {
    const diags: any[] = this.az.diagnostics(uri) ?? [];
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
   *  (the virtual doc for a same-file hit, a library `.gd` for a cross-file one); the analyzer reports
   *  the target file by `uri` directly (the binding's enrichment), so a cross-file def's byte range is
   *  converted against that file's text. */
  definitionsAt(uri: string, text: string, charOffset: number): AdapterDef[] {
    const defs: any[] = this.az.gotoDefinition(uri, charToByte(text, charOffset)) ?? [];
    return defs.map((d) => {
      const targetUri: string | null = d.uri ?? null;
      // A cross-file def's range is in the TARGET file; convert with that file's text (falling back to
      // the queried text for an untracked file).
      const targetText = (targetUri ? this.docs.get(targetUri) : undefined) ?? text;
      const r = d.focus_range ?? d.full_range ?? d.range ?? { start: 0, end: 0 };
      return {
        file: d.file ?? 0,
        uri: targetUri,
        range: { start: byteToChar(targetText, r.start), end: byteToChar(targetText, r.end) },
        name: d.name,
        kind: d.kind,
      };
    });
  }

  /** Every reference to the symbol at a CHAR offset in `text`. Each reference's range is in its OWN
   *  file's text (the virtual doc `uri` for a same-file hit, a library `.gd` for a cross-file one), so
   *  the caller maps virtual-doc hits back to the `.guitkx` source and keeps library hits as-is. The
   *  analyzer only sees this session's open docs, so the set is complete for file-local symbols. */
  referencesAt(uri: string, text: string, charOffset: number): AdapterRef[] {
    const refs: any[] = this.az.findReferences(uri, charToByte(text, charOffset)) ?? [];
    return refs.map((r) => {
      const targetUri: string | null = r.uri ?? null;
      const targetText = (targetUri ? this.docs.get(targetUri) : undefined) ?? text;
      const rr = r.range ?? { start: 0, end: 0 };
      return { uri: targetUri, range: { start: byteToChar(targetText, rr.start), end: byteToChar(targetText, rr.end) } };
    });
  }

  /** Rename the symbol at a CHAR offset in `text` to `newName`. Returns per-file edits (each edit's
   *  range in CHAR offsets within that file's text) on success, or `{ error }` on the analyzer's
   *  "correct-or-refuse" refusal. The binding always returns an envelope, never a partial edit. */
  renameAt(uri: string, text: string, charOffset: number, newName: string): AdapterRename {
    const res: any = this.az.rename(uri, charToByte(text, charOffset), newName);
    if (!res || res.ok === undefined) {
      const err = res?.error;
      return { error: typeof err === "string" ? err : err ? JSON.stringify(err) : "rename refused" };
    }
    return { ok: this.mapFileEdits(res.ok.edits, text) };
  }

  /** Map analyzer per-file edits (byte ranges) to AdapterFileEdits (CHAR offsets in each file's text).
   *  Shared by rename and code actions; each `FileEdit`'s ranges are converted against that file's text. */
  private mapFileEdits(fileEdits: any[], text: string): AdapterFileEdit[] {
    return (fileEdits ?? []).map((fe: any) => {
      const targetUri: string | null = fe.uri ?? null;
      const targetText = (targetUri ? this.docs.get(targetUri) : undefined) ?? text;
      const edits = (fe.edits ?? []).map((e: any) => {
        const r = e.range ?? { start: 0, end: 0 };
        return {
          range: { start: byteToChar(targetText, r.start), end: byteToChar(targetText, r.end) },
          newText: String(e.new_text ?? ""),
        };
      });
      return { uri: targetUri, edits };
    });
  }

  /** Code actions (quick-fixes) at a CHAR offset in `text`. Each action's edits are per-file (ranges in
   *  CHAR offsets within each file's text) — the caller maps virtual-doc edits back to the .guitkx
   *  source and refuses any action carrying a non-local or generated-glue edit. */
  codeActionsAt(uri: string, text: string, charOffset: number): { title: string; kind: string | null; edits: AdapterFileEdit[] }[] {
    const actions: any[] = this.az.codeActions(uri, charToByte(text, charOffset)) ?? [];
    return actions.map((a) => ({
      title: String(a.title ?? "action"),
      kind: (a.kind as string) ?? null,
      edits: this.mapFileEdits(a.edit?.edits ?? [], text),
    }));
  }

  /** Signature help at a CHAR offset in `text` (a call site in embedded GDScript), as an LSP
   *  SignatureHelp, or null when not at a call site. */
  signatureHelpAt(uri: string, text: string, charOffset: number): SignatureHelp | null {
    const s: any = this.az.signatureHelp(uri, charToByte(text, charOffset));
    if (!s?.signatures?.length) return null;
    return {
      signatures: s.signatures.map((sig: any) => ({
        label: String(sig.label ?? ""),
        documentation: sig.doc ? { kind: MarkupKind.Markdown, value: sig.doc } : undefined,
        parameters: (sig.params ?? []).map((p: any) => ({
          label: String(p.label ?? ""),
          documentation: p.doc ? { kind: MarkupKind.Markdown, value: p.doc } : undefined,
        })),
      })),
      activeSignature: s.active_signature ?? 0,
      activeParameter: s.active_parameter ?? 0,
    };
  }

  /** Inlay hints for the virtual doc, each at a CHAR offset in `text` (the caller maps it back to the
   *  .guitkx source and drops hints landing in generated glue). `kind` is the LSP InlayHintKind. */
  inlayHintsAt(uri: string, text: string): { offset: number; label: string; kind: InlayHintKind }[] {
    const hints: any[] = this.az.inlayHints(uri) ?? [];
    return hints.map((h) => ({
      offset: byteToChar(text, h.offset ?? 0),
      label: String(h.label ?? ""),
      kind: h.kind === "parameter" ? InlayHintKind.Parameter : InlayHintKind.Type,
    }));
  }

  /** The document outline for a real `.gd` document, as a tree with CHAR-offset ranges in `text`
   *  (used for plain `.gd` — for a `.guitkx` virtual doc the markup-level outline is used instead). */
  documentSymbolsAt(uri: string, text: string): AdapterSymbol[] {
    const conv = (sym: any): AdapterSymbol => {
      const r = sym.range ?? { start: 0, end: 0 };
      const sr = sym.selection_range ?? r;
      return {
        name: String(sym.name ?? ""),
        detail: sym.detail ?? undefined,
        kind: SYMBOL_KIND[String(sym.kind)] ?? SymbolKind.Variable,
        range: { start: byteToChar(text, r.start), end: byteToChar(text, r.end) },
        selectionRange: { start: byteToChar(text, sr.start), end: byteToChar(text, sr.end) },
        children: (sym.children ?? []).map(conv),
      };
    };
    return ((this.az.documentSymbols(uri) as any[]) ?? []).map(conv);
  }

  /** Format the whole document `uri` (a real `.gd`); the tidied text, or null if unknown/unchanged. */
  formatAt(uri: string): string | null {
    return this.az.format(uri) ?? null;
  }

  /** Format a standalone GDScript snippet through the SAME formatter that drives plain `.gd` files, so
   *  embedded `.guitkx` code reflows identically (BUG-1). Synced under a private scratch URI; returns the
   *  tidied text (possibly identical to the input), or null if the analyzer can't format it. */
  formatGd(text: string): string | null {
    const uri = "inmemory://__rui_reflow.gd";
    this.sync(uri, text);
    return this.az.format(uri) ?? null;
  }

  /** Format the lines overlapping the CHAR range `[charStart, charEnd)` in `text`; one edit (range in
   *  CHAR offsets + `newText`), or null when nothing changes / `uri` is unknown. */
  formatRangeAt(uri: string, text: string, charStart: number, charEnd: number): { start: number; end: number; newText: string } | null {
    const r: any = this.az.formatRange(uri, charToByte(text, charStart), charToByte(text, charEnd));
    if (!r) return null;
    const range = r.range ?? { start: 0, end: 0 };
    return { start: byteToChar(text, range.start), end: byteToChar(text, range.end), newText: String(r.new_text ?? "") };
  }

  /** RAW semantic tokens for `uri`, each range in CHAR offsets within `text` + its unified-legend type
   *  index and modifier bitset. Lets the `.guitkx` path map a virtual-doc token back to the source and
   *  merge it with the markup tokens before encoding (BUG-2); the `.gd` path encodes them directly. */
  semanticTokensRawAt(uri: string, text: string): { start: number; end: number; type: number; mods: number }[] {
    const raw: any[] = this.az.semanticTokens(uri) ?? [];
    return raw
      .map((t) => {
        const rg = t.range ?? { start: 0, end: 0 };
        return {
          start: byteToChar(text, rg.start),
          end: byteToChar(text, rg.end),
          type: GD_TOKEN_TYPE[String(t.token_type)] ?? 0,
          mods: Number(t.modifiers ?? 0),
        };
      })
      // Drop empty AND multi-line tokens: the LSP semantic-tokens spec requires each token to stay on
      // one line, so a token spanning a newline (e.g. a triple-quoted string) would be invalid — let the
      // TextMate grammar colour those instead.
      .filter((t) => t.end > t.start && !text.slice(t.start, t.end).includes("\n"));
  }

  /** Semantic-highlighting tokens for a real `.gd` document, delta-encoded per the LSP spec (ready to
   *  hand back as `{ data }`). Token-type names map onto the unified legend; the analyzer's modifier
   *  bitset carries over directly (same bit order). */
  semanticTokensAt(uri: string, text: string): number[] {
    const lineStarts = [0];
    for (let i = 0; i < text.length; i++) if (text[i] === "\n") lineStarts.push(i + 1);
    const pos = (charOff: number) => {
      let lo = 0;
      let hi = lineStarts.length - 1;
      while (lo < hi) {
        const mid = (lo + hi + 1) >> 1;
        if (lineStarts[mid] <= charOff) lo = mid;
        else hi = mid - 1;
      }
      return { line: lo, char: charOff - lineStarts[lo] };
    };
    const items = this.semanticTokensRawAt(uri, text)
      .map((t) => {
        const p = pos(t.start);
        return { line: p.line, char: p.char, len: t.end - t.start, type: t.type, mods: t.mods };
      })
      .sort((a, b) => a.line - b.line || a.char - b.char);
    const data: number[] = [];
    let prevLine = 0;
    let prevChar = 0;
    for (const t of items) {
      const dLine = t.line - prevLine;
      const dChar = dLine === 0 ? t.char - prevChar : t.char;
      data.push(dLine, dChar, t.len, t.type, t.mods);
      prevLine = t.line;
      prevChar = t.char;
    }
    return data;
  }
}
