// guitkx language server. Markup intelligence (tag/attribute/directive completion + hover) is
// answered locally from the schema; embedded-GDScript intelligence ({expr}, setup, conditions) is
// answered by @gdscript-analyzer/core (a headless GDScript analyzer) over a virtual `.gd` document +
// source map — no running Godot editor required. Diagnostics are a light structural pass (unbalanced
// tags/braces). Transport: stdio (VS Code client + VS2022 ILanguageClient both speak this).

import {
  createConnection,
  TextDocuments,
  ProposedFeatures,
  InitializeParams,
  TextDocumentSyncKind,
  CompletionItem,
  CompletionItemKind,
  InsertTextFormat,
  Hover,
  MarkupKind,
  Diagnostic,
  DiagnosticSeverity,
  DiagnosticTag,
  Location,
  DocumentSymbol,
  SymbolKind,
  TextEdit,
  SignatureHelp,
  InlayHint,
  CodeAction,
} from "vscode-languageserver/node";
import { TextDocument } from "vscode-languageserver-textdocument";

import { classifyContext, CursorContext } from "./context";
import { buildVirtualDoc } from "./virtualDoc";
import { offsetToPosition } from "./sourceMap";
import { skipString, findMatching, isIdent } from "./scanner";
import { uriToProjectPath } from "./guitkxFormat";
import { formatGuitkx, FmtOptions, markupWindows, unreachableRegions, loadFormatterConfig } from "./formatGuitkx";
import { dirname, join, relative } from "path";
import { pathToFileURL } from "url";
import { reflowEmbedded } from "./reflowEmbedded";
import { hasDump, classProperties, classSignals } from "./classdb";
import { eventCompletionsFor, resolveSignalName, validEventAttrs, isEventAttr } from "./events";
import { WorkspaceIndex, scanWorkspace, componentTagAt, offsetToPosition as offsetToPos, scanDeclarations } from "./workspaceIndex";
import { scanTagRefs } from "./refs";
import { markupTokens, encodeTokens, Tok, TOKEN_TYPES, TOKEN_MODIFIERS, isBodyBrace } from "./semanticTokens";
import { srcHash, readSidecar } from "./diagsSidecar";
import { readFileSync, readdirSync, statSync } from "fs";
import { AnalyzerAdapter, AdapterSymbol } from "./analyzerAdapter";
import {
  HOST_TAGS,
  STRUCTURAL_ATTRS,
  COMMON_ATTRS,
  PREAMBLE_DIRECTIVES,
  CONTROL_FLOW,
  findTag,
  STYLE_KEYS,
  BUILTIN_MEMBERS,
} from "./schema";

const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);
const index = new WorkspaceIndex();
const analyzer = new AnalyzerAdapter();
let projectPath = "";
let embeddedReflow = true;
let embeddedEnabled = true;

connection.onInitialize((params: InitializeParams) => {
  const opts = (params.initializationOptions as any) || {};
  // `embeddedReflow` runs embedded GDScript through the analyzer's formatter (so it matches a real .gd
  // file); `useGdformat` is the legacy name for the same toggle.
  if (typeof opts.embeddedReflow === "boolean") embeddedReflow = opts.embeddedReflow;
  else if (typeof opts.useGdformat === "boolean") embeddedReflow = opts.useGdformat;
  // `enableEmbeddedAnalysis` toggles embedded-GDScript intelligence (completion/hover/definition
  // inside {expr}/setup). `enableGodotProxy` is the legacy name, still honored.
  if (typeof opts.enableEmbeddedAnalysis === "boolean") embeddedEnabled = opts.enableEmbeddedAnalysis;
  else if (typeof opts.enableGodotProxy === "boolean") embeddedEnabled = opts.enableGodotProxy;
  const rootUri = params.rootUri || (params.workspaceFolders?.[0]?.uri ?? "");
  projectPath = uriToProjectPath(rootUri);
  // Feed project.godot to the analyzer (enables [autoload] singleton resolution). Best-effort.
  try {
    analyzer.setProjectConfig(readFileSync(join(projectPath, "project.godot"), "utf8"));
  } catch {
    /* no project.godot here — embedded analysis still works per-file */
  }
  scanWorkspace(index, projectPath);
  // Load the project's addon `.gd` libraries (e.g. ReactiveUI's `core/hooks.gd` with `class_name
  // Hooks`) into the analyzer so embedded code resolves cross-file — enabling go-to-definition into
  // the real library files (`useRef` -> hooks.gd, `V.create` -> v.gd). Best-effort, once.
  loadLibraries();
  return {
    capabilities: {
      textDocumentSync: TextDocumentSyncKind.Incremental,
      completionProvider: { triggerCharacters: ["<", "@", ".", " ", "_"] },
      hoverProvider: true,
      documentFormattingProvider: true,
      documentRangeFormattingProvider: true,
      definitionProvider: true,
      referencesProvider: true,
      renameProvider: { prepareProvider: true },
      documentSymbolProvider: true,
      signatureHelpProvider: { triggerCharacters: ["(", ","] },
      inlayHintProvider: true,
      codeActionProvider: true,
      semanticTokensProvider: {
        legend: { tokenTypes: TOKEN_TYPES, tokenModifiers: TOKEN_MODIFIERS },
        full: true,
      },
    },
  };
});

// --- formatting (textDocument/formatting + rangeFormatting) — in-process, no Godot binary needed ---

function formatOptsFor(uri: string): Partial<FmtOptions> {
  // .guitkx embeds GDScript -> default to TAB indentation (the editor's insertSpaces/tabSize is
  // ignored: a spaces base + the embedded code's authored tabs is the classic mixed-indent bug). A
  // project guitkx.config.json (walk-up, like Prettier / uitkx.config.json) overrides printWidth /
  // indentStyle / indentSize / attribute wrapping.
  let dir = "";
  try {
    dir = dirname(uriToProjectPath(uri));
  } catch {
    dir = "";
  }
  return { indentStyle: "tab", indentSize: 4, ...(dir ? loadFormatterConfig(dir) : {}) };
}

// In-process markup format (formatGuitkx) + embedded-GDScript reflow through the analyzer's formatter —
// the SAME gdscript-fmt that drives plain .gd files — so embedded code formats identically (BUG-1).
function formatFull(src: string, opts: Partial<FmtOptions>): { text: string; changed: boolean } {
  const base = formatGuitkx(src, opts).text;
  const text = embeddedReflow ? reflowEmbedded(base, (gd) => analyzer.formatGd(gd)) : base;
  return { text, changed: text !== src };
}

connection.onDocumentFormatting((params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];
  const src = doc.getText();
  if (isGd(params.textDocument.uri)) {
    analyzer.sync(params.textDocument.uri, src);
    const formatted = analyzer.formatAt(params.textDocument.uri);
    return formatted === null || formatted === src
      ? []
      : [{ range: { start: { line: 0, character: 0 }, end: doc.positionAt(src.length) }, newText: formatted }];
  }
  const r = formatFull(src, formatOptsFor(params.textDocument.uri));
  if (!r.changed) return [];
  return [{ range: { start: { line: 0, character: 0 }, end: doc.positionAt(src.length) }, newText: r.text }];
});

connection.onDocumentRangeFormatting((params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];
  const src = doc.getText();
  if (isGd(params.textDocument.uri)) {
    analyzer.sync(params.textDocument.uri, src);
    const e = analyzer.formatRangeAt(params.textDocument.uri, src, doc.offsetAt(params.range.start), doc.offsetAt(params.range.end));
    return e ? [{ range: { start: doc.positionAt(e.start), end: doc.positionAt(e.end) }, newText: e.newText }] : [];
  }
  const r = formatFull(src, formatOptsFor(params.textDocument.uri));
  if (!r.changed) return [];
  // Whole-doc format, then return the single minimal line-hunk (common prefix/suffix diff). The whole
  // minimal hunk is emitted when it intersects the requested range (it may extend slightly past the
  // selection — it is still the minimal edit; we never touch lines outside the changed region).
  const o = src.split("\n");
  const f = r.text.split("\n");
  let start = 0;
  while (start < o.length && start < f.length && o[start] === f[start]) start++;
  let oEnd = o.length;
  let fEnd = f.length;
  while (oEnd > start && fEnd > start && o[oEnd - 1] === f[fEnd - 1]) {
    oEnd--;
    fEnd--;
  }
  if (oEnd <= params.range.start.line || start > params.range.end.line) return [];
  // join with "\n" and add a trailing newline only when the hunk does NOT reach the document's last
  // line (else formatGuitkx's always-present final "\n" would inject a spurious blank line).
  const newText = f.slice(start, fEnd).join("\n") + (oEnd < o.length ? "\n" : "");
  return [{ range: { start: { line: start, character: 0 }, end: { line: oEnd, character: 0 } }, newText }];
});

// --- completion ---

connection.onCompletion(async (params): Promise<CompletionItem[]> => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];
  const src = doc.getText();
  const offset = doc.offsetAt(params.position);
  if (isGd(params.textDocument.uri)) {
    analyzer.sync(params.textDocument.uri, src);
    return analyzer.completionsAt(params.textDocument.uri, src, offset);
  }
  const ctx = classifyContext(src, offset);

  switch (ctx.kind) {
    case "tagName":
      return [
        ...HOST_TAGS.map((t) => ({
          label: t.tag,
          kind: CompletionItemKind.Class,
          detail: `${t.factory} (${t.godotClass})`,
          documentation: `Host element — Godot ${t.godotClass}.`,
        })),
        ...componentNames().map((n) => ({ label: n, kind: CompletionItemKind.Class, detail: "component" })),
      ];
    case "attrName": {
      const items: CompletionItem[] = [];
      // structural attrs are valid on every element
      for (const a of STRUCTURAL_ATTRS)
        items.push({ label: a.name, kind: CompletionItemKind.Property, detail: a.type, documentation: a.detail });
      const tag = ctx.tag ? findTag(ctx.tag) : undefined;
      if (tag && hasDump()) {
        // HOST element: every Control property of its godotClass, from the ClassDB dump
        for (const p of classProperties(tag.godotClass))
          items.push({ label: p.name, kind: CompletionItemKind.Property, detail: `${p.type} (${tag.godotClass})` });
        // React-style event handlers (onClick / onChange / onPointer* / …) resolved from the class's
        // signals; `onChange` is polymorphic. The native on_<signal> spelling stays valid too. (events.ts)
        for (const ev of eventCompletionsFor(classSignals(tag.godotClass)))
          items.push({ label: ev.label, kind: CompletionItemKind.Event, detail: ev.detail });
      } else if (tag) {
        // dump not available: fall back to the static common-attrs + schema events
        for (const a of COMMON_ATTRS)
          items.push({ label: a.name, kind: CompletionItemKind.Property, detail: a.type, documentation: a.detail });
        for (const ev of tag.events ?? [])
          items.push({ label: ev, kind: CompletionItemKind.Event, detail: "Callable" });
      }
      // (a PascalCase component tag has no godotClass -> only structural attrs)
      return items;
    }
    case "directive":
      return [...PREAMBLE_DIRECTIVES, ...CONTROL_FLOW].map((d) => ({
        label: d.label,
        kind: CompletionItemKind.Keyword,
        detail: d.detail,
        insertText: d.insert,
        insertTextFormat: InsertTextFormat.Snippet,
      }));
    case "markup":
      return [
        ...HOST_TAGS.map((t) => ({ label: "<" + t.tag, kind: CompletionItemKind.Class, detail: t.factory })),
        ...componentNames().map((n) => ({ label: "<" + n, kind: CompletionItemKind.Class, detail: "component" })),
        ...CONTROL_FLOW.map((d) => ({
          label: d.label,
          kind: CompletionItemKind.Keyword,
          insertText: d.insert,
          insertTextFormat: InsertTextFormat.Snippet,
          detail: d.detail,
        })),
      ];
    case "embedded": {
      // style={ {…} } dict -> RUIStyle keys (the GDScript analyzer has no vocabulary for these).
      if (inStyleDict(src, offset))
        return STYLE_KEYS.map((a) => ({ label: a.name, kind: CompletionItemKind.Property, detail: a.type, documentation: a.detail }));
      // `<Type>.<frag>` built-in constants (Color.WHITE, …) as a static fallback, merged with Godot's.
      const builtin = builtinMemberCompletions(src, offset);
      const proxied = await forwardCompletion(params.textDocument.uri, src, offset);
      if (builtin.length === 0) return proxied;
      const seen = new Set(proxied.map((p) => p.label));
      return [...builtin.filter((b) => !seen.has(b.label)), ...proxied];
    }
  }
});

// Indexed component bindings that can appear as a `<Tag>`: PascalCase and not a host element. Hooks
// (snake_case) are naturally excluded; module-member components are included. (BUG-7)
function componentNames(): string[] {
  return index.names().filter((n) => /^[A-Z]/.test(n) && !findTag(n));
}

// '{' positions enclosing `offset` (string/comment-aware), innermost last.
function openBraceStack(src: string, offset: number): number[] {
  const stack: number[] = [];
  let i = 0;
  while (i < offset) {
    const c = src[i];
    if (c === '"' || c === "'") {
      i = skipString(src, i);
      continue;
    }
    if (c === "#") {
      while (i < offset && src[i] !== "\n") i++;
      continue;
    }
    if (c === "{") stack.push(i);
    else if (c === "}") stack.pop();
    i++;
  }
  return stack;
}

// True when the cursor sits inside a `style={ {…} }` (or `*_style`) DICT — where the keys are
// RUIStyle's, not Godot's. Requires an inner dict (not the bare `style={ref}` value, preceded by `=`).
function inStyleDict(src: string, offset: number): boolean {
  const stack = openBraceStack(src, offset);
  if (stack.length === 0) return false;
  let j = stack[stack.length - 1] - 1;
  while (j >= 0 && /\s/.test(src[j])) j--;
  if (src[j] === "=") return false; // innermost brace IS the attr value (a ref/expr), not a dict
  for (let s = stack.length - 1; s >= 0; s--) {
    let k = stack[s] - 1;
    while (k >= 0 && /\s/.test(src[k])) k--;
    if (src[k] !== "=") continue;
    k--;
    while (k >= 0 && /\s/.test(src[k])) k--;
    const e = k + 1;
    while (k >= 0 && /[A-Za-z0-9_]/.test(src[k])) k--;
    const name = src.slice(k + 1, e);
    return name === "style" || name.endsWith("_style");
  }
  return false;
}

// `<Type>.<frag>` built-in constant completion (Color.WHITE, Vector2.ZERO, …).
function builtinMemberCompletions(src: string, offset: number): CompletionItem[] {
  let i = offset;
  while (i > 0 && /[A-Za-z0-9_]/.test(src[i - 1])) i--;
  if (i === 0 || src[i - 1] !== ".") return [];
  let j = i - 1;
  const e = j;
  while (j > 0 && /[A-Za-z0-9_]/.test(src[j - 1])) j--;
  const members = BUILTIN_MEMBERS[src.slice(j, e)];
  if (!members) return [];
  const type = src.slice(j, e);
  return members.map((m) => ({ label: m, kind: CompletionItemKind.Constant, detail: `${type}.${m}` }));
}

function forwardCompletion(uri: string, src: string, offset: number): CompletionItem[] {
  if (!embeddedEnabled) return []; // embedded-GDScript intelligence disabled by the client
  const { text, map } = buildVirtualDoc(src);
  const genOffset = map.toGenerated(offset);
  if (genOffset === null) return [];
  const vUri = uri.replace(/\.guitkx$/, ".__guitkx_virtual.gd");
  analyzer.sync(vUri, text);
  // The analyzer answers from the virtual `.gd`; items carry no positions (GDScript symbols are
  // position-free), so we use them as-is. Byte<->char conversion is handled inside the adapter.
  return analyzer.completionsAt(vUri, text, genOffset);
}

// --- hover ---

// BUG-V8: curated hover for the built-in hooks — the analyzer only sees the virtual-doc stub as
// `Callable`, so hovering a hook name returned nothing useful. Signatures mirror core/hooks.gd.
const HOOK_HOVER: Record<string, string> = {
  useState: "**useState**(initial = null) → `[value, setter]`\n\nReactive state: read `s[0]`, set with `s[1].call(v)` (a value or an updater func).",
  useReducer: "**useReducer**(reducer: Callable, initial = null) → `[state, dispatch]`",
  useRef: "**useRef**(initial = null) → `{ current }`\n\nA mutable box that persists across renders (setting it does not re-render).",
  useMemo: "**useMemo**(factory: Callable, deps = []) → value\n\nMemoized value; recomputes only when `deps` change.",
  useCallback: "**useCallback**(cb: Callable, deps = []) → `Callable`",
  useImperativeHandle: "**useImperativeHandle**(factory: Callable, deps = [])",
  useEffect: "**useEffect**(effect: Callable, deps = null)\n\nRun a side effect after commit; return a Callable to clean up. `deps = []` runs once on mount.",
  useLayoutEffect: "**useLayoutEffect**(effect: Callable, deps = null)\n\nLike `useEffect` but runs synchronously after layout.",
  createContext: "**createContext**(default = null, name = \"\") → `RUIContext`\n\nA context handle for `provideContext` / `useContext` (object identity — no string-key collisions).",
  useContext: "**useContext**(key) → value\n\nRead the nearest provided value for a context handle (or string key).",
  provideContext: "**provideContext**(key, value)\n\nProvide a context value to the subtree below.",
  useDeferredValue: "**useDeferredValue**(value, deps = null)",
  useTransition: "**useTransition**() → `[is_pending, start]`",
  useStableCallback: "**useStableCallback**(cb: Callable) → `Callable`\n\nA stable Callable identity that always invokes the latest `cb`.",
  useStableFunc: "**useStableFunc**(cb: Callable) → `Callable`",
  useStableAction: "**useStableAction**(cb: Callable) → `Callable`",
  useSafeArea: "**useSafeArea**() → `Dictionary`",
  useSignal: "**useSignal**(sig: RUISignal, selector = null, comparer = null)",
  useSignalKey: "**useSignalKey**(key: String, initial = null, selector = null, comparer = null)",
  useTween: "**useTween**(ref, property: String, to, duration: float, deps = [])",
  useTweenValue: "**useTweenValue**(from, to, duration: float, on_update: Callable, deps = [])",
  useAnimate: "**useAnimate**(ref, tracks: Array, autoplay = true, deps = [])",
  useSfx: "**useSfx**(bus = \"Master\") → `Callable`",
};

connection.onHover(async (params): Promise<Hover | null> => {
  try {
    const doc = documents.get(params.textDocument.uri);
    if (!doc) return null;
    const src = doc.getText();
    const offset = doc.offsetAt(params.position);
    if (isGd(params.textDocument.uri)) {
      analyzer.sync(params.textDocument.uri, src);
      const c = analyzer.hoverAt(params.textDocument.uri, src, offset);
      return c ? { contents: c } : null;
    }
    const ctx = classifyContext(src, offset);

    if (ctx.kind === "tagName" || ctx.kind === "attrName") return markupHover(src, offset, ctx);
    if (ctx.kind === "embedded" && embeddedEnabled) {
      // BUG-V8: a curated signature for a hook identifier beats the analyzer's bare `Callable`.
      const hw = wordRangeAt(src, offset);
      const hword = src.slice(hw.start, hw.end);
      if (HOOK_HOVER[hword]) return md(HOOK_HOVER[hword]);
      const { text, map } = buildVirtualDoc(src);
      const genOffset = map.toGenerated(offset);
      if (genOffset === null) return null;
      const vUri = params.textDocument.uri.replace(/\.guitkx$/, ".__guitkx_virtual.gd");
      analyzer.sync(vUri, text);
      const contents = analyzer.hoverAt(vUri, text, genOffset);
      if (contents) return { contents };
    }
    return null;
  } catch {
    return null; // hover is best-effort; never throw out of the handler
  }
});

// Markup hover. Resolve the FULL identifier under the cursor (not the truncated word-before) against a
// host element, a workspace component, or — for an attribute — the enclosing host tag's ClassDB
// property/signal dump, mirroring completion. The old path only matched a host tag at the exact end of
// its name and never consulted ClassDB, so real attributes and component tags hovered to nothing (BUG-6).
function markupHover(src: string, offset: number, ctx: CursorContext): Hover | null {
  const w = wordRangeAt(src, offset);
  const word = src.slice(w.start, w.end);
  if (!word) return null;
  if (ctx.kind === "tagName") {
    const tag = findTag(word);
    if (tag) return md(`**<${word}>** — host element · Godot \`${tag.godotClass}\`.`);
    if (index.has(word)) {
      const e = index.lookup(word)[0];
      const kind = e.kind === "member" ? "component" : e.kind;
      const sig = componentSignature(e);
      return md(`**<${word}>** — user ${kind} \`${word}${sig}\`. Press F12 / ctrl+click to open its declaration.`);
    }
    return null;
  }
  // attrName — resolve against the enclosing host tag's ClassDB props/signals, then structural/common.
  const host = ctx.tag ? findTag(ctx.tag) : undefined;
  if (host && hasDump()) {
    // Event handler? Resolve either spelling (React onClick/onChange/… or native on_<signal>) to its
    // underlying Godot signal on this control's class. (events.ts)
    const sigs = classSignals(host.godotClass);
    const signalName = resolveSignalName(word, (s) => sigs.some((x) => x.name === s));
    if (signalName !== undefined) {
      const sig = sigs.find((s) => s.name === signalName);
      if (sig) return md(`**${word}** — Godot signal \`${sig.name}(${sig.args.map((a) => `${a.name}: ${a.type}`).join(", ")})\` on \`${host.godotClass}\`.`);
    }
    const prop = classProperties(host.godotClass).find((p) => p.name === word);
    if (prop) return md(`**${word}**: \`${prop.type}\` — property on \`${host.godotClass}\`.`);
  }
  const attr = [...STRUCTURAL_ATTRS, ...COMMON_ATTRS].find((a) => a.name === word);
  if (attr) return md(`**${attr.name}**: \`${attr.type}\` — ${attr.detail}`);
  return null;
}

function md(value: string): Hover {
  return { contents: { kind: MarkupKind.Markdown, value } };
}

// --- diagnostics (light structural pass) ---

documents.onDidChangeContent((change) => {
  if (isGd(change.document.uri)) {
    connection.sendDiagnostics({ uri: change.document.uri, diagnostics: gdDiagnostics(change.document.uri, change.document.getText()) });
    return;
  }
  index.reindex(change.document.uri, change.document.getText());
  const live = [
    ...structuralDiagnostics(change.document),
    ...markupDiagnostics(change.document),
    ...unreachableDiagnostics(change.document),
    ...embeddedDiagnostics(change.document),
  ];
  connection.sendDiagnostics({ uri: change.document.uri, diagnostics: mergeCompilerSidecar(change.document, live) });
});

// Embedded-GDScript type/parse diagnostics from @gdscript-analyzer/core, mapped back into the .guitkx
// source. Safe to surface: the analyzer's seam design resolves an unknown cross-file symbol (a library
// call like `useState`, a `V.*`/`Hooks.*` reference whose .gd we haven't loaded) to the Unknown seam,
// which NEVER warns — so this adds real diagnostics (INTEGER_DIVISION, TYPE_MISMATCH, syntax errors)
// with no false positives. Diagnostics that land in generated glue (toSource === null) are dropped.
function embeddedDiagnostics(doc: TextDocument): Diagnostic[] {
  if (!embeddedEnabled) return [];
  const src = doc.getText();
  const { text, map } = buildVirtualDoc(src);
  const vUri = doc.uri.replace(/\.guitkx$/, ".__guitkx_virtual.gd");
  analyzer.sync(vUri, text);
  const out: Diagnostic[] = [];
  for (const d of analyzer.diagnosticsAt(vUri, text)) {
    let s = map.toSource(d.range.start);
    let e = map.toSource(d.range.end);
    if (s === null || e === null) continue; // a diagnostic in generated glue, not user code
    if (s > e) [s, e] = [e, s];
    out.push({
      severity: d.severity,
      range: { start: offsetToPosition(src, s), end: offsetToPosition(src, e) },
      message: d.code ? `${d.code}: ${d.message}` : d.message,
      source: "gdscript",
    });
  }
  return out;
}

// Surface the compiler's full diagnostic catalog (from the on-save Foo.guitkx.diags.json sidecar) in
// VS Code without a running editor. Only when the sidecar still matches the buffer (source hash);
// deduped by code against the precise live tier (live wins). Ranged at line 1 — the compiler emits no
// char offsets, so these are file-level "compiler says…" entries; the live tier owns precise squiggles.
function mergeCompilerSidecar(doc: TextDocument, live: Diagnostic[]): Diagnostic[] {
  const sc = readSidecar(uriToProjectPath(doc.uri));
  const text = doc.getText();
  if (!sc || sc.src_hash !== srcHash(text)) return live;
  const liveCodes = new Set<string>();
  for (const d of live) {
    const m = /GUITKX\d+/.exec(d.message);
    if (m) liveCodes.add(m[0]);
  }
  const firstLineLen = (text.indexOf("\n") + 1 || text.length + 1) - 1;
  const extra: Diagnostic[] = [];
  for (const d of sc.diagnostics) {
    if (!d.code || liveCodes.has(d.code)) continue;
    extra.push({
      severity: d.severity === "error" ? DiagnosticSeverity.Error : DiagnosticSeverity.Warning,
      range: { start: { line: 0, character: 0 }, end: { line: 0, character: Math.max(1, firstLineLen) } },
      message: d.message,
      source: "guitkx (compiler)",
    });
  }
  return extra.length ? [...live, ...extra] : live;
}

documents.onDidClose((e) => {
  // keep the on-disk entry: re-scan from disk so the index reflects the saved file, not the closed buffer
  const p = uriToProjectPath(e.document.uri);
  try {
    index.reindex(e.document.uri, readFileSync(p, "utf8"));
  } catch {
    index.evict(e.document.uri);
  }
});

// --- go-to-definition: <Foo/> -> the component/module-member declaration ---

connection.onDefinition(async (params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;
  const src = doc.getText();
  const offset = doc.offsetAt(params.position);
  if (isGd(params.textDocument.uri)) return gdDefinition(params.textDocument.uri, src, offset);
  // A <Component/> tag, the `component`/member decl name, or its `@class_name` token -> the declaration,
  // from the workspace index. Using bindingUnderCursor (not just componentTagAt) means F12 / ctrl+click
  // works from a usage AND from the declaration itself / the @class_name directive, instead of falling
  // through to the analyzer and surfacing VS Code's "no definition found".
  const name = bindingUnderCursor(params.textDocument.uri, src, offset);
  if (name) {
    const entries = index.lookup(name);
    if (entries.length)
      return entries.map((e) => {
        const targetText = documents.get(e.uri)?.getText() ?? readTextForUri(e.uri);
        return { uri: e.uri, range: { start: offsetToPos(targetText, e.nameStart), end: offsetToPos(targetText, e.nameEnd) } };
      });
  }
  // Otherwise an embedded-GDScript symbol -> resolve via @gdscript-analyzer/core; return cross-file (library)
  // locations (e.g. `useRef` -> core/hooks.gd). Same-file (virtual-doc) hits are skipped for now.
  return forwardDefinition(params.textDocument.uri, src, offset);
});

function forwardDefinition(uri: string, src: string, offset: number): Location[] | null {
  if (!embeddedEnabled) return null;
  const { text, map } = buildVirtualDoc(src);
  const genOffset = map.toGenerated(offset);
  if (genOffset === null) return null;
  const vUri = uri.replace(/\.guitkx$/, ".__guitkx_virtual.gd");
  analyzer.sync(vUri, text);
  const out: Location[] = [];
  // Push a library `.gd` def (its range is in that file's own text). Used both directly and for the
  // chained hook-stub target.
  const pushLibrary = (libUri: string, r: { start: number; end: number }) => {
    const t = analyzer.textOf(libUri) ?? "";
    out.push({ uri: libUri, range: { start: offsetToPosition(t, r.start), end: offsetToPosition(t, r.end) } });
  };
  for (const d of analyzer.definitionsAt(vUri, text, genOffset)) {
    // (1) A cross-file target in a project library `.gd` (e.g. `V.create` -> v.gd) -> a direct Location.
    if (d.uri && d.uri !== vUri) {
      pushLibrary(d.uri, d.range);
      continue;
    }
    // (2) A virtual-doc target that maps back into the .guitkx source -> a Location in the source.
    const s = map.toSource(d.range.start);
    const e = map.toSource(d.range.end);
    if (s !== null && e !== null) {
      out.push({ uri, range: { start: offsetToPosition(src, s), end: offsetToPosition(src, e) } });
      continue;
    }
    // (3) A target in generated glue — most usefully a hook stub `var useRef = Hooks.useRef`. Chain
    // ONCE through the `Hooks.<name>` on its RHS to the real library definition (`core/hooks.gd`).
    const rhs = hookStubRhsOffset(text, d.range.start);
    if (rhs === null) continue;
    for (const cd of analyzer.definitionsAt(vUri, text, rhs)) {
      if (cd.uri && cd.uri !== vUri) pushLibrary(cd.uri, cd.range);
    }
  }
  return out.length ? out : null;
}

// The char offset of `<name>` in a `Hooks.<name>` reference on the same line as `lhsOffset` — the RHS
// of a generated hook stub `var <name> = Hooks.<name>`. `null` if that line carries no `Hooks.` ref.
function hookStubRhsOffset(vText: string, lhsOffset: number): number | null {
  const lineStart = vText.lastIndexOf("\n", lhsOffset) + 1;
  let lineEnd = vText.indexOf("\n", lhsOffset);
  if (lineEnd === -1) lineEnd = vText.length;
  const m = /\bHooks\.([A-Za-z_][A-Za-z0-9_]*)/.exec(vText.slice(lineStart, lineEnd));
  return m ? lineStart + m.index + "Hooks.".length : null;
}

// Every `.gd` file under `dir` (recursive); a missing/unreadable dir or entry yields nothing.
function gdFilesUnder(dir: string, out: string[] = []): string[] {
  let entries: string[];
  try {
    entries = readdirSync(dir);
  } catch {
    return out;
  }
  for (const name of entries) {
    const p = join(dir, name);
    let isDir = false;
    try {
      isDir = statSync(p).isDirectory();
    } catch {
      continue;
    }
    if (isDir) gdFilesUnder(p, out);
    else if (name.endsWith(".gd")) out.push(p);
  }
  return out;
}

// Load the project's `.gd` files into the analyzer (with `res://` paths) so both embedded `.guitkx`
// code AND plain `.gd` editing resolve `class_name`s / `preload`s / autoloads cross-file. Walks the
// whole project (skipping the `.godot` cache + hidden dirs), not just `addons/`. Best-effort.
function loadLibraries(): void {
  if (!projectPath) return;
  for (const file of gdFilesUnder(projectPath)) {
    const resPath = "res://" + relative(projectPath, file).replace(/\\/g, "/");
    if (resPath.startsWith("res://.")) continue; // skip res://.godot/** and other hidden dirs
    try {
      analyzer.loadLibrary(pathToFileURL(file).toString(), readFileSync(file, "utf8"), resPath);
    } catch {
      /* unreadable .gd — skip */
    }
  }
}

// The analyzer may report `res://` URIs (preload / res-path resolution); VS Code needs a real file:// URI.
function resToFileUri(uri: string): string {
  if (uri.startsWith("res://") && projectPath) return pathToFileURL(join(projectPath, uri.slice("res://".length))).toString();
  return uri;
}

function readTextForUri(uri: string): string {
  try {
    return readFileSync(uriToProjectPath(uri), "utf8");
  } catch {
    return "";
  }
}

function textForUri(uri: string): string {
  return documents.get(uri)?.getText() ?? readTextForUri(uri);
}

// The `(params)` signature of a component declaration (read from its file), e.g. "(idx, append)" — or
// "" when it takes none. Shown in hover so a <Tag>'s props read like a function signature.
function componentSignature(e: { uri: string; nameEnd: number }): string {
  const text = textForUri(e.uri);
  let i = e.nameEnd;
  while (i < text.length && /\s/.test(text[i])) i++;
  if (text[i] !== "(") return "";
  const close = findMatching(text, i);
  if (close === -1) return "";
  return text.slice(i, close + 1).replace(/\s+/g, " ");
}

// The component binding under the cursor — a <Foo/> tag, a component/member declaration name, OR its
// `@class_name` override token (so navigation / find-references / rename all work from the declaration
// AND the @class_name directive, not just from a usage).
function bindingUnderCursor(uri: string, src: string, offset: number): string | null {
  const tag = componentTagAt(src, offset);
  if (tag) return tag;
  for (const e of index.entriesFor(uri)) {
    if (e.kind === "hook") continue;
    const onName = offset >= e.nameStart && offset <= e.nameEnd;
    const onOverride = e.classNameStart != null && e.classNameEnd != null && offset >= e.classNameStart && offset <= e.classNameEnd;
    if (onName || onOverride) return e.binding;
  }
  return null;
}

// Renameable when it is an indexed component binding that is NOT a host tag. A component WITH an
// `@class_name` override is renameable too: the rename rewrites the override token, the `component` decl
// name, and every `<Tag>` usage atomically (BUG-4), so it never leaves a usage bound to a stale
// `@class_name` (which previously produced a dangling GUITKX0105 "unknown element").
function isRenameable(name: string): boolean {
  return !findTag(name) && index.has(name);
}

// ════════════════════════════════════════════════════════════════════════════════════════════════
// Plain `.gd` mode — drive real GDScript files directly through @gdscript-analyzer/core. Offsets are
// 1:1 (no virtual doc / source map), and cross-file results are honoured in full (a real project-wide
// rename, not the `.guitkx` refuse-cross-file rule). Reached only when the client sends a `.gd` doc,
// which it does only if the user opts in via `guitkx.enableGdscriptAnalysis`. All project `.gd` are
// loaded at init (loadLibraries), so cross-file navigation / rename resolve.
// ════════════════════════════════════════════════════════════════════════════════════════════════

function isGd(uri: string): boolean {
  return uri.endsWith(".gd");
}

// A CHAR offset -> Position in `uri`'s text (the analyzer's loaded copy if present, else disk/open).
function gdPos(uri: string, off: number): { line: number; character: number } {
  return offsetToPosition(analyzer.textOf(uri) ?? textForUri(uri), off);
}

function gdLoc(uri: string, r: { start: number; end: number }): Location {
  return { uri: resToFileUri(uri), range: { start: gdPos(uri, r.start), end: gdPos(uri, r.end) } };
}

function gdDiagnostics(uri: string, src: string): Diagnostic[] {
  analyzer.sync(uri, src);
  return analyzer.diagnosticsAt(uri, src).map((d) => ({
    severity: d.severity,
    range: { start: offsetToPosition(src, d.range.start), end: offsetToPosition(src, d.range.end) },
    message: d.code ? `${d.code}: ${d.message}` : d.message,
    source: "gdscript",
  }));
}

function gdDefinition(uri: string, src: string, offset: number): Location[] {
  analyzer.sync(uri, src);
  return analyzer.definitionsAt(uri, src, offset).flatMap((d) => (d.uri ? [gdLoc(d.uri, d.range)] : []));
}

function gdReferences(uri: string, src: string, offset: number): Location[] {
  analyzer.sync(uri, src);
  return analyzer.referencesAt(uri, src, offset).flatMap((r) => (r.uri ? [gdLoc(r.uri, r.range)] : []));
}

// A project-wide rename: apply EVERY file's edits (the analyzer is correct-or-refuse, so a non-null
// result is safe to apply across files).
function gdRename(uri: string, src: string, offset: number, newName: string): { changes: { [uri: string]: TextEdit[] } } | null {
  if (!/^[A-Za-z_]\w*$/.test(newName)) return null;
  analyzer.sync(uri, src);
  const res = analyzer.renameAt(uri, src, offset, newName);
  if (!("ok" in res)) return null;
  const changes: { [uri: string]: TextEdit[] } = {};
  for (const fe of res.ok) {
    if (!fe.uri) continue;
    changes[resToFileUri(fe.uri)] = fe.edits.map((e) => ({
      range: { start: gdPos(fe.uri!, e.range.start), end: gdPos(fe.uri!, e.range.end) },
      newText: e.newText,
    }));
  }
  return Object.keys(changes).length ? { changes } : null;
}

function gdCodeActions(uri: string, src: string, offset: number): CodeAction[] {
  analyzer.sync(uri, src);
  const out: CodeAction[] = [];
  for (const a of analyzer.codeActionsAt(uri, src, offset)) {
    const changes: { [uri: string]: TextEdit[] } = {};
    for (const fe of a.edits) {
      if (!fe.uri) continue;
      changes[resToFileUri(fe.uri)] = fe.edits.map((e) => ({
        range: { start: gdPos(fe.uri!, e.range.start), end: gdPos(fe.uri!, e.range.end) },
        newText: e.newText,
      }));
    }
    if (Object.keys(changes).length) out.push({ title: a.title, kind: a.kind ?? undefined, edit: { changes } });
  }
  return out;
}

function gdDocumentSymbols(uri: string, src: string): DocumentSymbol[] {
  analyzer.sync(uri, src);
  const conv = (s: AdapterSymbol): DocumentSymbol => ({
    name: s.name,
    detail: s.detail,
    kind: s.kind,
    range: { start: offsetToPosition(src, s.range.start), end: offsetToPosition(src, s.range.end) },
    selectionRange: { start: offsetToPosition(src, s.selectionRange.start), end: offsetToPosition(src, s.selectionRange.end) },
    children: s.children.map(conv),
  });
  return analyzer.documentSymbolsAt(uri, src).map(conv);
}

function gdInlayHints(uri: string, src: string, range: { start: number; end: number }): InlayHint[] {
  analyzer.sync(uri, src);
  return analyzer
    .inlayHintsAt(uri, src)
    .filter((h) => h.offset >= range.start && h.offset <= range.end)
    .map((h) => ({ position: offsetToPosition(src, h.offset), label: h.label, kind: h.kind }));
}

function wordRangeAt(src: string, offset: number): { start: number; end: number } {
  let s = offset;
  let e = offset;
  while (s > 0 && isIdent(src[s - 1])) s--;
  while (e < src.length && isIdent(src[e])) e++;
  return { start: s, end: e };
}

// --- embedded-GDScript references + rename (analyzer-backed, source-mapped, correct-or-refuse) ---

// References to the embedded-GDScript symbol at `offset`. Same-file hits are mapped back from the
// virtual doc into the .guitkx source; a hit in a loaded library `.gd` is returned in that file. The
// analyzer only sees THIS file's virtual doc + libraries, so the set is complete for file-local symbols.
function embeddedReferences(uri: string, src: string, offset: number): Location[] {
  if (!embeddedEnabled) return [];
  const { text, map } = buildVirtualDoc(src);
  const genOffset = map.toGenerated(offset);
  if (genOffset === null) return [];
  const vUri = uri.replace(/\.guitkx$/, ".__guitkx_virtual.gd");
  analyzer.sync(vUri, text);
  const out: Location[] = [];
  const seen = new Set<string>();
  const push = (u: string, t: string, s: number, e: number) => {
    const range = { start: offsetToPosition(t, s), end: offsetToPosition(t, e) };
    const key = `${u}:${range.start.line}:${range.start.character}`;
    if (seen.has(key)) return;
    seen.add(key);
    out.push({ uri: u, range });
  };
  for (const r of analyzer.referencesAt(vUri, text, genOffset)) {
    if (r.uri && r.uri !== vUri) {
      push(r.uri, analyzer.textOf(r.uri) ?? "", r.range.start, r.range.end); // a library `.gd` hit
      continue;
    }
    const s = map.toSource(r.range.start); // a virtual-doc hit -> back to the .guitkx source (drop glue)
    const e = map.toSource(r.range.end);
    if (s !== null && e !== null) push(uri, src, s, e);
  }
  return out;
}

// The source word-range iff the embedded symbol at `offset` is renameable — i.e. its definition is
// LOCAL to this file's embedded code (not a library `.gd`, not generated glue). Library/glue symbols
// are refused (we will not edit core/hooks.gd from a .guitkx, and cross-.guitkx refs aren't loaded).
function embeddedRenameRange(uri: string, src: string, offset: number): { start: number; end: number } | null {
  if (!embeddedEnabled) return null;
  const w = wordRangeAt(src, offset);
  if (w.start === w.end) return null;
  const { text, map } = buildVirtualDoc(src);
  const genOffset = map.toGenerated(offset);
  if (genOffset === null) return null;
  const vUri = uri.replace(/\.guitkx$/, ".__guitkx_virtual.gd");
  analyzer.sync(vUri, text);
  const defs = analyzer.definitionsAt(vUri, text, genOffset);
  const local = defs.length > 0 && defs.every((d) => (!d.uri || d.uri === vUri) && map.toSource(d.range.start) !== null);
  return local ? w : null;
}

// Rename the embedded-GDScript symbol at `offset`. Correct-or-refuse: every edit must map back into
// THIS file's .guitkx source; any edit in a library `.gd` or generated glue refuses the whole rename.
function embeddedRename(uri: string, src: string, offset: number, newName: string): { changes: { [uri: string]: TextEdit[] } } | null {
  if (!embeddedEnabled || !/^[A-Za-z_]\w*$/.test(newName)) return null;
  const { text, map } = buildVirtualDoc(src);
  const genOffset = map.toGenerated(offset);
  if (genOffset === null) return null;
  const vUri = uri.replace(/\.guitkx$/, ".__guitkx_virtual.gd");
  analyzer.sync(vUri, text);
  const res = analyzer.renameAt(vUri, text, genOffset, newName);
  if (!("ok" in res)) return null; // the analyzer refused
  const edits: TextEdit[] = [];
  const seen = new Set<number>();
  for (const fe of res.ok) {
    if (fe.uri !== vUri) return null; // an edit outside this file's virtual doc -> refuse
    for (const e of fe.edits) {
      const s = map.toSource(e.range.start);
      const en = map.toSource(e.range.end);
      if (s === null || en === null) return null; // an edit in generated glue -> refuse
      if (seen.has(s)) continue;
      seen.add(s);
      edits.push({ range: { start: offsetToPosition(src, s), end: offsetToPosition(src, en) }, newText: e.newText });
    }
  }
  return edits.length ? { changes: { [uri]: edits } } : null;
}

// Signature help for an embedded-GDScript call site, via the analyzer over the virtual doc.
function embeddedSignatureHelp(uri: string, src: string, offset: number): SignatureHelp | null {
  if (!embeddedEnabled) return null;
  const { text, map } = buildVirtualDoc(src);
  const genOffset = map.toGenerated(offset);
  if (genOffset === null) return null;
  const vUri = uri.replace(/\.guitkx$/, ".__guitkx_virtual.gd");
  analyzer.sync(vUri, text);
  return analyzer.signatureHelpAt(vUri, text, genOffset);
}

// --- find-references ---

connection.onReferences((params): Location[] => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];
  const src = doc.getText();
  if (isGd(params.textDocument.uri)) return gdReferences(params.textDocument.uri, src, doc.offsetAt(params.position));
  const name = bindingUnderCursor(params.textDocument.uri, src, doc.offsetAt(params.position));
  // Not a component tag -> try an embedded-GDScript symbol (analyzer-backed, source-mapped).
  if (!name) return embeddedReferences(params.textDocument.uri, src, doc.offsetAt(params.position));
  const seen = new Set<string>();
  const locs: Location[] = [];
  const push = (uri: string, text: string, s: number, e: number) => {
    const range = { start: offsetToPos(text, s), end: offsetToPos(text, e) };
    const key = `${uri}:${range.start.line}:${range.start.character}`;
    if (seen.has(key)) return;
    seen.add(key);
    locs.push({ uri, range });
  };
  for (const uri of index.uris()) {
    const text = textForUri(uri);
    if (!text) continue;
    for (const r of scanTagRefs(text, name)) push(uri, text, r.start, r.end);
  }
  if (params.context?.includeDeclaration !== false) {
    for (const e of index.lookup(name)) {
      const text = textForUri(e.uri);
      if (text) push(e.uri, text, e.nameStart, e.nameEnd);
    }
  }
  return locs;
});

// --- rename + prepareRename ---

connection.onPrepareRename((params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;
  const src = doc.getText();
  const offset = doc.offsetAt(params.position);
  if (isGd(params.textDocument.uri)) {
    const gw = wordRangeAt(src, offset);
    return gw.start === gw.end ? null : { range: { start: doc.positionAt(gw.start), end: doc.positionAt(gw.end) }, placeholder: src.slice(gw.start, gw.end) };
  }
  const name = bindingUnderCursor(params.textDocument.uri, src, offset);
  if (!name) {
    // An embedded-GDScript symbol -> renameable iff it's local to this file's embedded code.
    const ew = embeddedRenameRange(params.textDocument.uri, src, offset);
    return ew ? { range: { start: doc.positionAt(ew.start), end: doc.positionAt(ew.end) }, placeholder: src.slice(ew.start, ew.end) } : null;
  }
  if (!isRenameable(name)) return null;
  const w = wordRangeAt(src, offset);
  if (w.start === w.end) return null;
  return { range: { start: doc.positionAt(w.start), end: doc.positionAt(w.end) }, placeholder: name };
});

connection.onRenameRequest((params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;
  const src = doc.getText();
  if (isGd(params.textDocument.uri)) return gdRename(params.textDocument.uri, src, doc.offsetAt(params.position), params.newName);
  const name = bindingUnderCursor(params.textDocument.uri, src, doc.offsetAt(params.position));
  // Not a component tag -> rename an embedded-GDScript symbol (correct-or-refuse, file-local only).
  if (!name) return embeddedRename(params.textDocument.uri, src, doc.offsetAt(params.position), params.newName);
  if (!isRenameable(name)) return null;
  const newName = params.newName;
  if (!/^[A-Za-z_]\w*$/.test(newName)) return null;
  if (findTag(newName) || index.has(newName)) return null; // collide with a host tag or existing component
  const changes: { [uri: string]: TextEdit[] } = {};
  for (const uri of index.uris()) {
    const text = textForUri(uri);
    if (!text) continue;
    const seen = new Set<number>();
    const edits: TextEdit[] = [];
    const add = (s: number, e: number) => {
      if (seen.has(s)) return;
      seen.add(s);
      edits.push({ range: { start: offsetToPos(text, s), end: offsetToPos(text, e) }, newText: newName });
    };
    for (const r of scanTagRefs(text, name)) add(r.start, r.end);
    for (const e of index.entriesFor(uri)) {
      if (e.binding !== name) continue;
      // Rewrite the decl-name token only when it IS the binding (no override, or `@class_name X` over
      // `component X`) — so renaming `@class_name X` over `component Y` (X != Y) does not relabel the
      // unrelated decl name Y; the common X/X case still keeps the decl name + override in sync.
      if (e.name === e.binding) add(e.nameStart, e.nameEnd);
      // The `@class_name` override token always renames in lockstep with the binding (BUG-4).
      if (e.classNameStart != null && e.classNameEnd != null) add(e.classNameStart, e.classNameEnd);
    }
    if (edits.length) changes[uri] = edits;
  }
  return { changes };
});

// --- documentSymbol (outline; module members nested) ---

connection.onDocumentSymbol((params): DocumentSymbol[] => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];
  const src = doc.getText();
  if (isGd(params.textDocument.uri)) return gdDocumentSymbols(params.textDocument.uri, src);
  const top: DocumentSymbol[] = [];
  const modules = new Map<string, DocumentSymbol>();
  for (const d of scanDeclarations(src)) {
    const sym: DocumentSymbol = {
      name: d.name,
      kind: symbolKind(d.kind),
      range: { start: offsetToPos(src, d.declStart), end: offsetToPos(src, d.declEnd) },
      selectionRange: { start: offsetToPos(src, d.nameStart), end: offsetToPos(src, d.nameEnd) },
      children: [],
    };
    if (d.kind === "member" && d.module && modules.has(d.module)) {
      modules.get(d.module)!.children!.push(sym);
    } else {
      top.push(sym);
      if (d.kind === "module") modules.set(d.name, sym);
    }
  }
  return top;
});

function symbolKind(kind: string): SymbolKind {
  switch (kind) {
    case "component":
      return SymbolKind.Class;
    case "hook":
      return SymbolKind.Function;
    case "module":
      return SymbolKind.Namespace;
    default:
      return SymbolKind.Method;
  }
}

// --- semantic tokens (host vs component tag identity, directives, attr names, events) ---

connection.languages.semanticTokens.on((params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return { data: [] };
  // .gd: analyzer-backed semantic tokens (guitkxSemanticTokens handles .guitkx).
  if (isGd(params.textDocument.uri)) {
    analyzer.sync(params.textDocument.uri, doc.getText());
    return { data: analyzer.semanticTokensAt(params.textDocument.uri, doc.getText()) };
  }
  return { data: guitkxSemanticTokens(params.textDocument.uri, doc.getText()) };
});

// .guitkx semantic tokens: the markup tokens (tag identity / @-directive keywords / attr names / events)
// MERGED with the analyzer's embedded-GDScript tokens, mapped back from the virtual doc into the .guitkx
// source — so embedded code highlights the same as a real .gd file (BUG-2). Embedded tokens are
// best-effort: any failure still returns the markup tokens.
function guitkxSemanticTokens(uri: string, src: string): number[] {
  const toks: Tok[] = markupTokens(src, (name) => index.has(name));
  if (embeddedEnabled) {
    try {
      const { text, map } = buildVirtualDoc(src);
      const vUri = uri.replace(/\.guitkx$/, ".__guitkx_virtual.gd");
      analyzer.sync(vUri, text);
      const lineStart = [0];
      for (let i = 0; i < src.length; i++) if (src[i] === "\n") lineStart.push(i + 1);
      const posOf = (off: number) => {
        let lo = 0;
        let hi = lineStart.length - 1;
        while (lo < hi) {
          const mid = (lo + hi + 1) >> 1;
          if (lineStart[mid] <= off) lo = mid;
          else hi = mid - 1;
        }
        return { line: lo, char: off - lineStart[lo] };
      };
      for (const t of analyzer.semanticTokensRawAt(vUri, text)) {
        const s = map.toSource(t.start);
        const e = map.toSource(t.end);
        if (s === null || e === null || e <= s) continue; // generated glue, or maps to nothing
        const p = posOf(s);
        toks.push({ line: p.line, char: p.char, len: e - s, type: t.type, mods: t.mods });
      }
    } catch {
      /* embedded tokens are best-effort; the markup tokens are always returned */
    }
  }
  return encodeTokens(toks);
}

// --- signature help (opportunistic): on_<signal>={ func(... ) } on a host element ---

connection.onSignatureHelp((params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;
  const src = doc.getText();
  const offset = doc.offsetAt(params.position);
  if (isGd(params.textDocument.uri)) {
    analyzer.sync(params.textDocument.uri, src);
    return analyzer.signatureHelpAt(params.textDocument.uri, src, offset);
  }
  // Markup signature help (on_<signal>={ func(…) }) first; otherwise an embedded-GDScript call site.
  return signatureHelpAt(src, offset) ?? embeddedSignatureHelp(params.textDocument.uri, src, offset);
});

// --- inlay hints (embedded-GDScript inferred types, mapped back into the .guitkx source) ---

connection.languages.inlayHint.on((params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];
  const src = doc.getText();
  if (isGd(params.textDocument.uri))
    return gdInlayHints(params.textDocument.uri, src, { start: doc.offsetAt(params.range.start), end: doc.offsetAt(params.range.end) });
  if (!embeddedEnabled) return [];
  const { text, map } = buildVirtualDoc(src);
  const vUri = params.textDocument.uri.replace(/\.guitkx$/, ".__guitkx_virtual.gd");
  analyzer.sync(vUri, text);
  const start = doc.offsetAt(params.range.start);
  const end = doc.offsetAt(params.range.end);
  const out: InlayHint[] = [];
  for (const h of analyzer.inlayHintsAt(vUri, text)) {
    const s = map.toSource(h.offset); // a hint in generated glue (toSource === null) is dropped
    if (s === null || s < start || s > end) continue;
    out.push({ position: offsetToPosition(src, s), label: h.label, kind: h.kind });
  }
  return out;
});

// --- code actions (embedded-GDScript quick-fixes; per-action correct-or-refuse) ---

connection.onCodeAction((params): CodeAction[] => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];
  const src = doc.getText();
  if (isGd(params.textDocument.uri)) return gdCodeActions(params.textDocument.uri, src, doc.offsetAt(params.range.start));
  if (!embeddedEnabled) return [];
  const { text, map } = buildVirtualDoc(src);
  const genOffset = map.toGenerated(doc.offsetAt(params.range.start));
  if (genOffset === null) return [];
  const vUri = params.textDocument.uri.replace(/\.guitkx$/, ".__guitkx_virtual.gd");
  analyzer.sync(vUri, text);
  const out: CodeAction[] = [];
  for (const a of analyzer.codeActionsAt(vUri, text, genOffset)) {
    // Keep an action only if EVERY edit maps back into this file's embedded code (correct-or-refuse);
    // an edit in a library `.gd` or generated glue drops just that action, not the whole list.
    const edits: TextEdit[] = [];
    let ok = a.edits.length > 0;
    for (const fe of a.edits) {
      if (fe.uri !== vUri) {
        ok = false;
        break;
      }
      for (const e of fe.edits) {
        const s = map.toSource(e.range.start);
        const en = map.toSource(e.range.end);
        if (s === null || en === null) {
          ok = false;
          break;
        }
        edits.push({ range: { start: offsetToPosition(src, s), end: offsetToPosition(src, en) }, newText: e.newText });
      }
      if (!ok) break;
    }
    if (ok && edits.length) {
      out.push({ title: a.title, kind: a.kind ?? undefined, edit: { changes: { [params.textDocument.uri]: edits } } });
    }
  }
  return out;
});

function signatureHelpAt(src: string, offset: number): any {
  // 1. back-scan for the enclosing call '(' (bounded by the {expr}/tag boundary; '>' does NOT stop us,
  //    so comparison/shift operators inside the header don't break the lookup as enclosingTag would)
  let depth = 0;
  let i = offset - 1;
  let parenOpen = -1;
  while (i >= 0) {
    const c = src[i];
    if (c === ")") depth++;
    else if (c === "(") {
      if (depth === 0) {
        parenOpen = i;
        break;
      }
      depth--;
    } else if (c === "{" || c === "}" || c === ";" || c === "<") break;
    i--;
  }
  if (parenOpen === -1) return null;
  // 2. require a `func` lambda immediately before '(' (a method-ref like on_pressed={_on_click} -> none).
  //    Word-boundary check so `myfunc(` / `_func(` don't spuriously match.
  let j = parenOpen - 1;
  while (j >= 0 && /\s/.test(src[j])) j--;
  if (src.slice(j - 3, j + 1) !== "func" || (j - 4 >= 0 && isIdent(src[j - 4]))) return null;
  j -= 4;
  // 3. require `{` then `=` then the attribute name
  while (j >= 0 && /\s/.test(src[j])) j--;
  if (src[j] !== "{") return null;
  j--;
  while (j >= 0 && /\s/.test(src[j])) j--;
  if (src[j] !== "=") return null;
  j--;
  while (j >= 0 && /\s/.test(src[j])) j--;
  let ne = j + 1;
  while (j >= 0 && /[A-Za-z0-9_.\-]/.test(src[j])) j--;
  const attrName = src.slice(j + 1, ne);
  if (!isEventAttr(attrName)) return null; // event handler (React onClick/onChange/… or native on_<signal>)
  // 4. find the enclosing opening tag's name — back-scan skipping ={...} exprs + quoted values so a
  //    `<`/`>` operator inside an earlier attribute doesn't halt the lookup.
  let t = j;
  let bdepth = 0;
  while (t >= 0) {
    const ch = src[t];
    if (ch === '"' || ch === "'") {
      t--;
      while (t >= 0 && src[t] !== ch) t--;
      t--;
      continue;
    }
    if (ch === "}") {
      bdepth++;
      t--;
      continue;
    }
    if (ch === "{") {
      if (bdepth > 0) bdepth--;
      t--;
      continue;
    }
    if (ch === "<" && bdepth === 0) break;
    t--;
  }
  if (t < 0 || src[t] !== "<") return null;
  const tn = t + 1;
  let te = tn;
  while (te < src.length && /[A-Za-z0-9_]/.test(src[te])) te++;
  const td = findTag(src.slice(tn, te));
  if (!td) return null; // host elements only
  const sigs = classSignals(td.godotClass);
  const signal = resolveSignalName(attrName, (s) => sigs.some((x) => x.name === s)); // React name -> signal
  if (!signal) return null;
  const sig = sigs.find((s) => s.name === signal);
  if (!sig) return null;
  // 5. activeParameter = top-level comma count between '(' and the cursor (depth-aware, string-safe)
  let active = 0;
  let d2 = 0;
  for (let p = parenOpen + 1; p < offset && p < src.length; p++) {
    const ch = src[p];
    if (ch === '"' || ch === "'") {
      p = skipString(src, p) - 1;
      continue;
    }
    if (ch === "(" || ch === "[" || ch === "{") d2++;
    else if (ch === ")" || ch === "]" || ch === "}") d2--;
    else if (ch === "," && d2 === 0) active++;
  }
  const params2 = sig.args.map((a) => ({ label: `${a.name}: ${a.type}` }));
  const label = `${signal}(${params2.map((p) => p.label).join(", ")})`;
  return { signatures: [{ label, parameters: params2 }], activeSignature: 0, activeParameter: Math.min(active, Math.max(0, params2.length - 1)) };
}

// Live structural-markup diagnostics (the compiler emits the full catalog on save; this is the fast
// in-editor tier): duplicate literal `key="…"` among siblings [GUITKX0104] + unknown-element [0105].
// Scoped to the markup windows (the return(...) of each component) so a `<`/`>` in setup GDScript,
// directive conditions, or child {expr} is never misread as a tag.
// BUG-V5/V6: one Hint + Unnecessary diagnostic per component over the unreachable code after its return.
// VS Code renders Unnecessary-tagged ranges FADED (like dead code) — the requested "dim".
function unreachableDiagnostics(doc: TextDocument): Diagnostic[] {
  return unreachableRegions(doc.getText()).map((r) => ({
    severity: DiagnosticSeverity.Hint,
    tags: [DiagnosticTag.Unnecessary],
    range: { start: doc.positionAt(r.start), end: doc.positionAt(r.end) },
    message: "Unreachable code after the component's return — the compiler drops it.",
    source: "guitkx",
  }));
}

function markupDiagnostics(doc: TextDocument): Diagnostic[] {
  const src = doc.getText();
  const diags: Diagnostic[] = [];
  for (const w of markupWindows(src)) scanWindowDiagnostics(src, doc, w.start, w.end, diags);
  return diags;
}

function scanWindowDiagnostics(src: string, doc: TextDocument, start: number, end: number, diags: Diagnostic[]): void {
  const scopes: Array<Set<string>> = [new Set()];
  let i = start;
  while (i < end) {
    const c = src[i];
    if (c === '"' || c === "'") {
      i = skipString(src, i);
      continue;
    }
    if (c === "#") {
      while (i < end && src[i] !== "\n") i++;
      continue;
    }
    if (c === "(") {
      // a @directive condition — GDScript, skip whole
      const cl = findMatching(src, i);
      i = cl === -1 || cl >= end ? end : cl + 1;
      continue;
    }
    if (c === "{") {
      if (isBodyBrace(src, i)) {
        i++; // control-flow body is markup — enter it
        continue;
      }
      const cl = findMatching(src, i); // child {expr} — GDScript, skip whole
      i = cl === -1 || cl >= end ? end : cl + 1;
      continue;
    }
    if (c === "}") {
      i++;
      continue;
    }
    if (c === "<" && src[i + 1] === ">") {
      scopes.push(new Set()); // fragment OPEN <> -> enter its own child key-scope (symmetric with </> pop)
      i += 2;
      continue;
    }
    if (c === "<" && src[i + 1] === "/") {
      if (scopes.length > 1) scopes.pop(); // close tag (incl. </>) -> leave child scope
      const gt = src.indexOf(">", i);
      i = gt === -1 ? end : gt + 1;
      continue;
    }
    if (c === "<" && /[A-Za-z_]/.test(src[i + 1] || "")) {
      const tag = readTag(src, i, end);
      // BUG-V3: dedup on a signature so BOTH literal (key="x") and expression (key={ str(i) }) keys
      // are caught — two siblings with the same key expression collide every iteration.
      const keySig = tag.keyLiteral !== null ? "s:" + tag.keyLiteral : tag.keyExpr !== null ? "e:" + tag.keyExpr : null;
      if (keySig !== null) {
        const scope = scopes[scopes.length - 1];
        if (scope.has(keySig)) {
          diags.push({
            severity: DiagnosticSeverity.Warning,
            range: { start: doc.positionAt(tag.keyStart), end: doc.positionAt(tag.keyEnd) },
            message: `GUITKX0104: duplicate key '${keySig.slice(2)}' among sibling elements.`,
            source: "guitkx",
          });
        }
        scope.add(keySig);
      }
      // unknown-element did-you-mean: PascalCase tag that is neither a host element nor an indexed
      // component, but is a near-miss of one (lowercase tags are host factories — never flagged).
      if (/^[A-Z]/.test(tag.tagName) && !findTag(tag.tagName) && !index.has(tag.tagName)) {
        const sugg = closestTag(tag.tagName);
        if (sugg) {
          diags.push({
            severity: DiagnosticSeverity.Error,
            range: { start: doc.positionAt(tag.nameStart), end: doc.positionAt(tag.nameEnd) },
            message: `GUITKX0105: unknown element '${tag.tagName}'. Did you mean '${sugg}'?`,
            source: "guitkx",
          });
        }
      }
      // unknown ATTRIBUTE on a host element — only when the ClassDB dump is loaded (else we have no
      // authoritative property list and would false-flag). Component tags take arbitrary props, so skip.
      const hostTd = findTag(tag.tagName);
      if (hostTd && hasDump()) {
        const valid = validHostAttrs(hostTd.godotClass);
        for (const a of tag.attrs) {
          if (valid.has(a.name)) continue;
          const sugg = closestAttr(a.name, hostTd.godotClass);
          diags.push({
            severity: DiagnosticSeverity.Error,
            range: { start: doc.positionAt(a.start), end: doc.positionAt(a.end) },
            message: `GUITKX0107: unknown attribute '${a.name}' on <${tag.tagName}>` + (sugg ? `. Did you mean '${sugg}'?` : "."),
            source: "guitkx",
          });
        }
      }
      if (!tag.selfClosing) scopes.push(new Set()); // enter child scope
      i = tag.next;
      continue;
    }
    i++;
  }
}

interface TagAttr2 {
  name: string;
  start: number;
  end: number;
}
interface TagInfo2 {
  next: number;
  selfClosing: boolean;
  keyLiteral: string | null;
  keyExpr: string | null;
  keyStart: number;
  keyEnd: number;
  tagName: string;
  nameStart: number;
  nameEnd: number;
  attrs: TagAttr2[];
}

function readTag(src: string, lt: number, end: number): TagInfo2 {
  let i = lt + 1;
  const nameStart = i;
  while (i < end && /[A-Za-z0-9_]/.test(src[i])) i++;
  const nameEnd = i;
  const tagName = src.slice(nameStart, nameEnd);
  let keyLiteral: string | null = null;
  let keyExpr: string | null = null;
  let keyStart = lt;
  let keyEnd = lt;
  const attrs: TagAttr2[] = [];
  while (i < end) {
    while (i < end && /\s/.test(src[i])) i++;
    if (src[i] === "/" && src[i + 1] === ">") return { next: i + 2, selfClosing: true, keyLiteral, keyExpr, keyStart, keyEnd, tagName, nameStart, nameEnd, attrs };
    if (src[i] === ">") return { next: i + 1, selfClosing: false, keyLiteral, keyExpr, keyStart, keyEnd, tagName, nameStart, nameEnd, attrs };
    if (i >= end) break;
    if (src[i] === "{") { // a `{...spread}` attribute — skip it whole (not an unknown attribute)
      const close = findMatching(src, i);
      i = close === -1 ? end : close + 1;
      continue;
    }
    const an = i;
    while (i < end && /[A-Za-z0-9_.\-]/.test(src[i])) i++;
    const name = src.slice(an, i);
    const aNameEnd = i;
    if (name !== "") attrs.push({ name, start: an, end: aNameEnd });
    while (i < end && /\s/.test(src[i])) i++;
    if (src[i] === "=") {
      i++;
      while (i < end && /\s/.test(src[i])) i++;
      if (src[i] === '"' || src[i] === "'") {
        const vs = i;
        const ve = skipString(src, i);
        if (name === "key") {
          keyLiteral = src.slice(vs + 1, ve - 1);
          keyStart = vs;
          keyEnd = ve;
        }
        i = ve;
      } else if (src[i] === "{") {
        const close = findMatching(src, i);
        if (name === "key" && close !== -1) {
          keyExpr = src.slice(i + 1, close).trim(); // BUG-V3: capture the key EXPRESSION for dup detection
          keyStart = i;
          keyEnd = close + 1;
        }
        i = close === -1 ? end : close + 1;
      }
    } else if (an === i) {
      i++;
    }
  }
  return { next: end, selfClosing: false, keyLiteral, keyExpr, keyStart, keyEnd, tagName, nameStart, nameEnd, attrs };
}

// Valid attribute names for a HOST element: the structural attrs (key/ref/style) + every settable
// Control property of its godotClass + its events in BOTH spellings — React canonical (onClick /
// onChange / …) and the native on_<signal> escape hatch — from the bundled ClassDB dump. (events.ts)
function validHostAttrs(godotClass: string): Set<string> {
  const s = new Set<string>();
  for (const a of STRUCTURAL_ATTRS) s.add(a.name);
  for (const p of classProperties(godotClass)) s.add(p.name);
  for (const ev of validEventAttrs(classSignals(godotClass))) s.add(ev);
  return s;
}

// Closest valid attribute (edit-distance <= 2) of a host element, for an unknown-attribute did-you-mean.
function closestAttr(name: string, godotClass: string): string | null {
  let best: string | null = null;
  let bestD = 3;
  for (const cand of validHostAttrs(godotClass)) {
    if (cand === name) return null;
    if (Math.abs(cand.length - name.length) > 2) continue;
    const d = levenshtein(name, cand);
    if (d < bestD) {
      bestD = d;
      best = cand;
    }
  }
  return bestD <= 2 ? best : null;
}

// Closest known tag (host element or indexed component) within edit-distance 2, for did-you-mean.
function closestTag(name: string): string | null {
  let best: string | null = null;
  let bestD = 3;
  const pool = [...HOST_TAGS.map((t) => t.tag), ...index.names()];
  for (const cand of pool) {
    if (cand === name) return null; // exact match => known, no suggestion
    if (Math.abs(cand.length - name.length) > 2) continue;
    const d = levenshtein(name, cand);
    if (d < bestD) {
      bestD = d;
      best = cand;
    }
  }
  return bestD <= 2 ? best : null;
}

function levenshtein(a: string, b: string): number {
  const m = a.length;
  const k = b.length;
  let prev = Array.from({ length: k + 1 }, (_, j) => j);
  let cur = new Array(k + 1).fill(0);
  for (let i = 1; i <= m; i++) {
    cur[0] = i;
    for (let j = 1; j <= k; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost);
    }
    [prev, cur] = [cur, prev];
  }
  return prev[k];
}

function structuralDiagnostics(doc: TextDocument): Diagnostic[] {
  const src = doc.getText();
  const diags: Diagnostic[] = [];
  // unbalanced { } at file scope (a crude but useful guard)
  let depth = 0;
  let firstUnmatched = -1;
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    if (c === '"' || c === "'") {
      // skip a simple string
      const q = c;
      i++;
      while (i < src.length && src[i] !== q) {
        if (src[i] === "\\") i++;
        i++;
      }
      continue;
    }
    if (c === "#") {
      while (i < src.length && src[i] !== "\n") i++;
      continue;
    }
    if (c === "{") {
      if (depth === 0) firstUnmatched = i;
      depth++;
    } else if (c === "}") depth--;
  }
  if (depth > 0 && firstUnmatched >= 0) {
    diags.push({
      severity: DiagnosticSeverity.Warning,
      range: { start: doc.positionAt(firstUnmatched), end: doc.positionAt(firstUnmatched + 1) },
      message: "Unbalanced '{' — this block may be missing a closing '}'.",
      source: "guitkx",
    });
  }
  return diags;
}

documents.listen(connection);
connection.listen();
