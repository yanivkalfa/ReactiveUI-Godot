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
} from "vscode-languageserver/node";
import { TextDocument } from "vscode-languageserver-textdocument";

import { classifyContext } from "./context";
import { buildVirtualDoc } from "./virtualDoc";
import { offsetToPosition } from "./sourceMap";
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
let proxy: GodotProxy;
let godotPort = 6005;

connection.onInitialize((params: InitializeParams) => {
  const opts = (params.initializationOptions as any) || {};
  if (typeof opts.godotPort === "number") godotPort = opts.godotPort;
  const rootUri = params.rootUri || (params.workspaceFolders?.[0]?.uri ?? "");
  proxy = new GodotProxy("127.0.0.1", godotPort, rootUri);
  return {
    capabilities: {
      textDocumentSync: TextDocumentSyncKind.Incremental,
      completionProvider: { triggerCharacters: ["<", "@", ".", " ", "_"] },
      hoverProvider: true,
    },
  };
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
      for (const a of STRUCTURAL_ATTRS)
        items.push({ label: a.name, kind: CompletionItemKind.Property, detail: a.type, documentation: a.detail });
      for (const a of COMMON_ATTRS)
        items.push({ label: a.name, kind: CompletionItemKind.Property, detail: a.type, documentation: a.detail });
      const tag = ctx.tag ? findTag(ctx.tag) : undefined;
      for (const ev of tag?.events ?? [])
        items.push({ label: ev, kind: CompletionItemKind.Event, detail: "Callable", documentation: `Signal handler for ${ctx.tag}.` });
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
  if (ctx.kind === "embedded") {
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
  const diags = structuralDiagnostics(change.document);
  connection.sendDiagnostics({ uri: change.document.uri, diagnostics: diags });
});

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
