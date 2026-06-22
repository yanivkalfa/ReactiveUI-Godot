// guitkx language server. Markup intelligence (tag/attribute/directive completion + hover) is
// answered locally from the schema; embedded-GDScript intelligence ({expr}, setup, conditions) is
// forwarded to Godot's GDScript LSP through a virtual `.gd` document + source map. Diagnostics are a
// light structural pass (unbalanced tags/braces); embedded-code diagnostics come from Godot when its
// editor is running. Transport: stdio (VS Code client + VS2022 ILanguageClient both speak this).

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
  Location,
  DocumentSymbol,
  SymbolKind,
  TextEdit,
} from "vscode-languageserver/node";
import { TextDocument } from "vscode-languageserver-textdocument";

import { classifyContext } from "./context";
import { buildVirtualDoc } from "./virtualDoc";
import { offsetToPosition } from "./sourceMap";
import { skipString, findMatching, isIdent } from "./scanner";
import { uriToProjectPath } from "./guitkxFormat";
import { formatGuitkx, FmtOptions, markupWindows, loadFormatterConfig } from "./formatGuitkx";
import { dirname } from "path";
import { reflowEmbedded } from "./reflowEmbedded";
import { hasDump, classProperties, classSignals } from "./classdb";
import { WorkspaceIndex, scanWorkspace, componentTagAt, offsetToPosition as offsetToPos, scanDeclarations } from "./workspaceIndex";
import { scanTagRefs } from "./refs";
import { buildSemanticTokens, TOKEN_TYPES, TOKEN_MODIFIERS, isBodyBrace } from "./semanticTokens";
import { srcHash, readSidecar } from "./diagsSidecar";
import { readFileSync } from "fs";
import { GodotProxy } from "./godotProxy";
import {
  HOST_TAGS,
  STRUCTURAL_ATTRS,
  COMMON_ATTRS,
  PREAMBLE_DIRECTIVES,
  CONTROL_FLOW,
  findTag,
} from "./schema";

const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);
const index = new WorkspaceIndex();
let proxy: GodotProxy;
let godotPort = 6005;
let projectPath = "";
let useGdformat = true;
let proxyEnabled = true;

connection.onInitialize((params: InitializeParams) => {
  const opts = (params.initializationOptions as any) || {};
  if (typeof opts.godotPort === "number") godotPort = opts.godotPort;
  if (typeof opts.useGdformat === "boolean") useGdformat = opts.useGdformat;
  if (typeof opts.enableGodotProxy === "boolean") proxyEnabled = opts.enableGodotProxy;
  const rootUri = params.rootUri || (params.workspaceFolders?.[0]?.uri ?? "");
  projectPath = uriToProjectPath(rootUri);
  proxy = new GodotProxy("127.0.0.1", godotPort, rootUri);
  scanWorkspace(index, projectPath);
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

// In-process markup format (formatGuitkx) + optional gdformat embedded reflow (no-op when absent).
function formatFull(src: string, opts: Partial<FmtOptions>): { text: string; changed: boolean } {
  const base = formatGuitkx(src, opts).text;
  const text = useGdformat ? reflowEmbedded(base) : base;
  return { text, changed: text !== src };
}

connection.onDocumentFormatting((params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];
  const src = doc.getText();
  const r = formatFull(src, formatOptsFor(params.textDocument.uri));
  if (!r.changed) return [];
  return [{ range: { start: { line: 0, character: 0 }, end: doc.positionAt(src.length) }, newText: r.text }];
});

connection.onDocumentRangeFormatting((params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];
  const src = doc.getText();
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
  const ctx = classifyContext(src, offset);

  switch (ctx.kind) {
    case "tagName":
      return HOST_TAGS.map((t) => ({
        label: t.tag,
        kind: CompletionItemKind.Class,
        detail: `${t.factory} (${t.godotClass})`,
        documentation: `Host element — Godot ${t.godotClass}.`,
      }));
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
        // on_<signal> event handlers (signal -> on_<name>)
        for (const s of classSignals(tag.godotClass))
          items.push({
            label: `on_${s.name}`,
            kind: CompletionItemKind.Event,
            detail: `signal ${s.name}(${s.args.map((a) => `${a.name}: ${a.type}`).join(", ")})`,
          });
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
        ...CONTROL_FLOW.map((d) => ({
          label: d.label,
          kind: CompletionItemKind.Keyword,
          insertText: d.insert,
          insertTextFormat: InsertTextFormat.Snippet,
          detail: d.detail,
        })),
      ];
    case "embedded":
      return forwardCompletion(params.textDocument.uri, src, offset);
  }
});

async function forwardCompletion(uri: string, src: string, offset: number): Promise<CompletionItem[]> {
  if (!proxyEnabled) return []; // embedded-GDScript forwarding disabled by the client
  const { text, map } = buildVirtualDoc(src);
  const genOffset = map.toGenerated(offset);
  if (genOffset === null) return [];
  const vUri = uri.replace(/\.guitkx$/, ".__guitkx_virtual.gd");
  await proxy.sync(vUri, text);
  const pos = offsetToPosition(text, genOffset);
  const res = await proxy.completion(vUri, pos.line, pos.character);
  if (!res) return [];
  const items = Array.isArray(res) ? res : res.items ?? [];
  // strip virtual-space textEdits; rely on label/insertText (GDScript symbols are position-free)
  return items.map((it: any) => ({
    label: it.label,
    kind: it.kind,
    detail: it.detail,
    documentation: it.documentation,
    insertText: it.insertText ?? it.label,
    sortText: it.sortText,
  }));
}

// --- hover ---

connection.onHover(async (params): Promise<Hover | null> => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;
  const src = doc.getText();
  const offset = doc.offsetAt(params.position);
  const ctx = classifyContext(src, offset);

  if (ctx.kind === "tagName" || ctx.kind === "attrName") {
    const tag = findTag(ctx.word.replace(/^</, ""));
    if (tag) return md(`**<${tag.tag}>** — host element, compiles to \`${tag.factory}\` (Godot \`${tag.godotClass}\`).`);
    const attr = [...STRUCTURAL_ATTRS, ...COMMON_ATTRS].find((a) => a.name === ctx.word);
    if (attr) return md(`**${attr.name}**: \`${attr.type}\` — ${attr.detail}`);
    return null;
  }
  if (ctx.kind === "embedded" && proxyEnabled) {
    const { text, map } = buildVirtualDoc(src);
    const genOffset = map.toGenerated(offset);
    if (genOffset === null) return null;
    const vUri = params.textDocument.uri.replace(/\.guitkx$/, ".__guitkx_virtual.gd");
    await proxy.sync(vUri, text);
    const pos = offsetToPosition(text, genOffset);
    const res = await proxy.hover(vUri, pos.line, pos.character);
    if (res?.contents) return { contents: res.contents };
  }
  return null;
});

function md(value: string): Hover {
  return { contents: { kind: MarkupKind.Markdown, value } };
}

// --- diagnostics (light structural pass) ---

documents.onDidChangeContent((change) => {
  index.reindex(change.document.uri, change.document.getText());
  const live = [...structuralDiagnostics(change.document), ...markupDiagnostics(change.document)];
  connection.sendDiagnostics({ uri: change.document.uri, diagnostics: mergeCompilerSidecar(change.document, live) });
});

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

connection.onDefinition((params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;
  const src = doc.getText();
  const name = componentTagAt(src, doc.offsetAt(params.position));
  if (!name) return null;
  const entries = index.lookup(name);
  if (!entries.length) return null;
  return entries.map((e) => {
    const targetText = documents.get(e.uri)?.getText() ?? readTextForUri(e.uri);
    return {
      uri: e.uri,
      range: {
        start: offsetToPos(targetText, e.nameStart),
        end: offsetToPos(targetText, e.nameEnd),
      },
    };
  });
});

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

// The component binding under the cursor — a <Foo/> tag OR a component/member declaration name.
function bindingUnderCursor(uri: string, src: string, offset: number): string | null {
  const tag = componentTagAt(src, offset);
  if (tag) return tag;
  for (const e of index.entriesFor(uri)) {
    if (offset >= e.nameStart && offset <= e.nameEnd && e.kind !== "hook") return e.binding;
  }
  return null;
}

// Renameable only for a component binding that is NOT a host tag, IS indexed, and has no @class_name
// override (override-rename would need to retarget the @class_name token — out of v1 scope).
function isRenameable(name: string): boolean {
  if (findTag(name) || !index.has(name)) return false;
  return index.lookup(name).every((e) => e.name === e.binding);
}

function wordRangeAt(src: string, offset: number): { start: number; end: number } {
  let s = offset;
  let e = offset;
  while (s > 0 && isIdent(src[s - 1])) s--;
  while (e < src.length && isIdent(src[e])) e++;
  return { start: s, end: e };
}

// --- find-references ---

connection.onReferences((params): Location[] => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];
  const src = doc.getText();
  const name = bindingUnderCursor(params.textDocument.uri, src, doc.offsetAt(params.position));
  if (!name) return [];
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
  const name = bindingUnderCursor(params.textDocument.uri, src, offset);
  if (!name || !isRenameable(name)) return null;
  const w = wordRangeAt(src, offset);
  if (w.start === w.end) return null;
  return { range: { start: doc.positionAt(w.start), end: doc.positionAt(w.end) }, placeholder: name };
});

connection.onRenameRequest((params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;
  const src = doc.getText();
  const name = bindingUnderCursor(params.textDocument.uri, src, doc.offsetAt(params.position));
  if (!name || !isRenameable(name)) return null;
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
    for (const e of index.entriesFor(uri)) if (e.binding === name) add(e.nameStart, e.nameEnd);
    if (edits.length) changes[uri] = edits;
  }
  return { changes };
});

// --- documentSymbol (outline; module members nested) ---

connection.onDocumentSymbol((params): DocumentSymbol[] => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];
  const src = doc.getText();
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
  return { data: buildSemanticTokens(doc.getText(), (name) => index.has(name)) };
});

// --- signature help (opportunistic): on_<signal>={ func(... ) } on a host element ---

connection.onSignatureHelp((params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;
  return signatureHelpAt(doc.getText(), doc.offsetAt(params.position));
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
  if (!attrName.startsWith("on_")) return null;
  const signal = attrName.slice(3);
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
  const sig = classSignals(td.godotClass).find((s) => s.name === signal);
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
      if (tag.keyLiteral !== null) {
        const scope = scopes[scopes.length - 1];
        if (scope.has(tag.keyLiteral)) {
          diags.push({
            severity: DiagnosticSeverity.Warning,
            range: { start: doc.positionAt(tag.keyStart), end: doc.positionAt(tag.keyEnd) },
            message: `GUITKX0104: duplicate key '${tag.keyLiteral}' among sibling elements.`,
            source: "guitkx",
          });
        }
        scope.add(tag.keyLiteral);
      }
      // unknown-element did-you-mean: PascalCase tag that is neither a host element nor an indexed
      // component, but is a near-miss of one (lowercase tags are host factories — never flagged).
      if (/^[A-Z]/.test(tag.tagName) && !findTag(tag.tagName) && !index.has(tag.tagName)) {
        const sugg = closestTag(tag.tagName);
        if (sugg) {
          diags.push({
            severity: DiagnosticSeverity.Hint,
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
            severity: DiagnosticSeverity.Warning,
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
  let keyStart = lt;
  let keyEnd = lt;
  const attrs: TagAttr2[] = [];
  while (i < end) {
    while (i < end && /\s/.test(src[i])) i++;
    if (src[i] === "/" && src[i + 1] === ">") return { next: i + 2, selfClosing: true, keyLiteral, keyStart, keyEnd, tagName, nameStart, nameEnd, attrs };
    if (src[i] === ">") return { next: i + 1, selfClosing: false, keyLiteral, keyStart, keyEnd, tagName, nameStart, nameEnd, attrs };
    if (i >= end) break;
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
        i = close === -1 ? end : close + 1;
      }
    } else if (an === i) {
      i++;
    }
  }
  return { next: end, selfClosing: false, keyLiteral, keyStart, keyEnd, tagName, nameStart, nameEnd, attrs };
}

// Valid attribute names for a HOST element: the structural attrs (key/ref/style) + every settable
// Control property of its godotClass + its `on_<signal>` events, from the bundled ClassDB dump.
function validHostAttrs(godotClass: string): Set<string> {
  const s = new Set<string>();
  for (const a of STRUCTURAL_ATTRS) s.add(a.name);
  for (const p of classProperties(godotClass)) s.add(p.name);
  for (const sig of classSignals(godotClass)) s.add("on_" + sig.name);
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
