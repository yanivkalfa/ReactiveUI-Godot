# Phase 2 — `guitkx` Markup Language + IDE Extensions (Godot/GDScript port of `uitkx`)

> Goal: full markup parity with ReactiveUIToolkit's `.uitkx` toolchain, but the embedded
> component-body language is **GDScript** instead of C#. A developer writes a `.guitkx` file
> (JSX-like markup + GDScript), it compiles to a `.gd` component, and an IDE extension
> (**VS Code + Visual Studio 2022**, matching the editors uitkx supports today) gives
> highlighting, completion, diagnostics, hover, and formatting.
>
> This plan is grounded in a full read of the Unity toolchain: the Roslyn
> `IIncrementalGenerator` (`SourceGenerator~/`), the language library (`ide-extensions~/language-lib/`,
> `ReactiveUITK.Language.dll`), the LSP server (`ide-extensions~/lsp-server/`, C#/OmniSharp/Roslyn),
> the VS Code (TypeScript) and VS2022 (C# VSIX) extensions, the TextMate grammar + JSON schema
> (`ide-extensions~/grammar/`), and the CI (`.github/workflows/{test,publish}.yml`).

---

## 0b. RESEARCH VALIDATION (2026-06-21) — corrections from a 3-investigation deep dive

Before any code, three deep investigations were run (Unity compiler blueprint, Unity extensions
blueprint, Godot/web validation reading Godot's actual C++ LSP source). They **confirm most of this
plan** and force three corrections, recorded inline below:

- **🔴 D1 was WRONG.** An `EditorImportPlugin` CANNOT make `preload("Foo.guitkx")` return a runnable,
  hot-reloading GDScript class — Godot's import pipeline is resource-conversion (emits a serialized
  binary Resource into `.godot/imported/`), not script compilation. **CORRECTED:** the compiler runs
  from a **`@tool` `EditorPlugin` that watches `EditorFileSystem` and codegens a SIBLING `Foo.gd`
  source file** (then nudges `EditorFileSystem.update_file()`/`scan()`). The generated `.gd` is a real
  source file Godot's compiler owns → genuine `.new()`/`render()`/hot-reload. Precedent:
  `github.com/jacobcoughenour/gdscript_source_generation`. (A `ScriptLanguageExtension` could make the
  ext load as a script, but only via C++/GDExtension — out of scope for a GDScript-only addon.)
- **🟡 Control-flow lowering (B.3) corrected:** GDScript lambdas can't hold multi-statement
  `return`-based control flow, so `@if`/`@for`/`@switch` lower to a **hidden per-directive helper
  method** (`_render_if_N`/`_render_loop_N`) called inline — NOT an inline IIFE lambda. The `__r`
  list-build + `append`/`continue` rewrite (`RewriteReturnsForInline`) transfers directly.
- **🟣 LSP LANGUAGE — REVISED to TypeScript during implementation (supersedes the lean-C# call below).**
  The research leaned C# *because it assumed reusing the Unity C# `language-lib`*. But the Godot port's
  compiler/parser is GDScript and the embedded language is GDScript — there is **no C# to reuse**, so a
  C# LSP would mean porting the parser to C# anyway. Given that, Godot-specific factors flip it to
  **TypeScript**: VS Code is the primary Godot audience (godot-tools users; VSCodium/Cursor via Open
  VSX), a Node server ships **zero runtime**, and VS2022 can still drive a Node LSP over stdio
  (server-language-agnostic, per the research). So: TS LSP server (`ide-extensions/lsp-server/`) + thin
  VS Code client, adopting Volar's *technique* (whitespace-blanked virtual `.gd` + bidirectional source
  map) and a TCP proxy to Godot's LSP — in TS, not C#.
- **🟢 LSP transport confirmed (D2/D3):** proxy to **Godot's GDScript LSP (TCP, port 6005 — NOT 6008,
  which is godot-tools' own default)**. The LSP accepts in-memory `file://` virtual docs via `didOpen`
  (full-text sync only); it emits **NO semantic tokens and NO formatting**, so coloring is TextMate-only
  and markup formatting is ours. Editor must be running; proxy needs robust reconnect. Adopt Volar's
  *technique* (whitespace-blanked virtual doc + bidirectional source map), not the framework.

## 0. Strategic decisions (the load-bearing choices, made up front)

| # | Decision | Why |
|---|---|---|
| D1 | **The compiler (`.guitkx`→`.gd`) is written in GDScript**, run by a **`@tool` `EditorPlugin` file-watcher** that codegens a SIBLING `.gd` (see 0b — NOT an import plugin). | Self-contained: no .NET/Roslyn/Node needed to *use* guitkx. The sibling `.gd` is a real script → free GDScript hot-reload + inspectable output. This is the MVP — guitkx is usable with zero IDE extension installed. |
| D2 | **The IDE LSP reuses the C# `language-lib` markup half** (parser/AST/formatter/structural diagnostics — it's language-agnostic, extracts embedded code as raw strings) and **replaces the Roslyn half** with a **GDScript proxy**. | ~60-70% of `language-lib` and ~40-50% of the LSP scaffolding port directly (per research). Rebuilding the parser from scratch is wasted effort. |
| D3 | **Embedded-GDScript intelligence is delegated to Godot's built-in GDScript Language Server** (Godot ships an LSP over TCP, default `127.0.0.1:6005`). | We do NOT reimplement a GDScript analyzer. We splice a synthetic `.gd` virtual document + a position map and proxy completion/hover/diagnostics to Godot's own LSP — the analog of uitkx's Roslyn `VirtualDocumentGenerator`. |
| D4 | **Editor scope = VS Code + VS 2022 only.** Rider is out of scope (it's commented-out in uitkx CI too). | Matches what uitkx ships today, per the requirement. |
| D5 | **Two parser implementations are acceptable**: GDScript (in the import-plugin compiler, self-contained) + C# (`language-lib`, in the LSP). | The grammar is specified once (Part A); both implement it. The compiler must be dependency-free for Godot users; the LSP benefits from reusing the proven C# lib. A future consolidation (LSP shells out to a headless-Godot guitkx tool) is possible but not required for v1. |
| D6 | **Extension/addon names:** the language id + grammar scope is `guitkx`; the VS Code extension and VSIX are `guitkx`; the in-Godot importer lives in `addons/reactive_ui/` (or a sibling `addons/reactive_ui_guitkx/`). | Mirrors `uitkx`. |

**What we deliberately DROP from the Unity toolchain** (Unity-specific, no Godot analog):
`#if UNITY_EDITOR` HMR scaffolding (`__fam_*`, `__UitkxRefresh`, trampolines), `[ModuleInitializer]`
polyfills, props-pooling (`BaseProps.__Rent`), the Roslyn analyzer-DLL + `AdditionalFiles` plumbing
(`Editor/UitkxCsprojPostprocessor.cs`), `.asmdef`/`Library/ScriptAssemblies` resolution, the
`#line`-directive source mapping (GDScript has no `#line`; we use a position table).

---

## PART A — The `.guitkx` language specification

Same shape as `.uitkx` (JSX over a host language + React directives), Godot-adapted. A `.guitkx`
file is one of: **component**, **hook**, or **module**. Setup/expression code is **GDScript**.

### A.1 Header directives (optional)
- `@class_name Foo` — give the generated `.gd` a `class_name` (replaces uitkx's `@namespace`; Godot
  has no namespaces — the *file* is the unit).
- `@use res://path/Other.guitkx as Other` — import another component (compiles to
  `const Other = preload(...)`). Bare `preload`/`const`/`load` also allowed in setup.
- `@icon`, `@tool` — pass through to the generated script's `@icon`/`@tool` annotations.

### A.2 Component (the dominant form)
```guitkx
@class_name Counter

component Counter(start: int = 0, label: String = "Count") {
    var s = use_state(start)                    # setup: GDScript + hooks (auto-prefixed to Hooks.*)
    var inc = func(): s[1].call(s[0] + 1)

    return (
        <VBox style={ {"separation": 8} }>
            <Label text={ "%s: %d" % [label, s[0]] } font_size={20} />
            <Button text="+1" on_pressed={inc} />
        </VBox>
    )
}
```
- **Params → props**: `component Counter(start: int = 0, ...)` → the generated `render(props, children)`
  unpacks `var start = props.get("start", 0)`. Types are optional (GDScript hints).
- Exactly one top-level `return ( <markup> )`.
- **Elements**: `<Tag .../>` self-closing or `<Tag>...</Tag>`. **PascalCase tag = component** (a
  `.guitkx`/`.gd` component), **lower/snake tag = host element** (a `V.*` factory: `<Button>`→`V.button`,
  `<VBox>`→`V.vbox`, or `<button>`/`<v_box>`). `<>...</>` = fragment.
- **Attributes**: `text="literal"`, `text={ <gdscript expr> }`, boolean shorthand `disabled`, JSX-as-attr
  `fallback={ <Label/> }`. `key={ id }` → routed to the factory key arg. `ref={ box }` → the `ref` prop.
  `style={ <gdscript dict> }`.
- **`{expr}` as a child** renders the expression (a vnode/text). `<Label text={ "%d" % n } />`.
- **Events**: any `on_*` attribute → an `on_*` prop wired to the node's signal (`on_pressed`,
  `on_text_changed`, …).
- **Child components**: `<Counter start={3} label="Score" />` — resolved by `@use`/preload or a peer
  `.guitkx`/`.gd` in the same dir (the compiler scans siblings).

### A.3 Control-flow directives (inside markup; each branch body is GDScript ending in `return (...)`)
```guitkx
@if (n > 0) { return (<Label text={ "+%d" % n } />) }
@elif (n < 0) { return (<Label text="neg" />) }
@else { return (<Label text="zero" />) }

@for (item in items) { return (<Label key={item.id} text={item.name} />) }
@while (i < rows) { var v = i; i += 1; return (<Label key={str(v)} text={str(v)} />) }
@match (mode) { @case "a": return (<Label text="A"/>); @default: return (<Label text="?"/>) }
```
`@for`/`@elif`/`@match`/`@case` use GDScript keywords (vs uitkx's `@foreach`/`@else if`/`@switch`).
`return null` skips rendering that item.

### A.4 Hook & module files
- `Foo.hooks.guitkx` → `hook use_foo(args) { <gdscript> }` declarations → a generated `.gd` with the
  hook functions (auto-imported into sibling `Foo.guitkx`). Holds heavy logic (game loops, effects).
- `Foo.style.guitkx` → `module { <gdscript const/static> }` → a generated `.gd` of shared style
  constants (`const PANEL := {"bg_color": ...}`). Referenced from markup as `FooStyles.PANEL`.

> The `Foo` / `Foo.hooks` / `Foo.style` split is an ergonomic convention, not a hard rule — each file
> compiles independently. A single-file component is fully valid.

---

## PART B — The compiler: `.guitkx` → `.gd` (GDScript, EditorImportPlugin)

**Tech:** pure GDScript, packaged as a Godot `EditorImportPlugin`. Pipeline mirrors `SourceGenerator~/UitkxPipeline.cs` but emits GDScript and runs in-editor.

### B.1 Godot integration (how files compile + hot-reload)
- An `EditorImportPlugin` (`addons/reactive_ui/guitkx/import_plugin.gd`, registered by `plugin.gd`)
  with `_get_importer_name() = "reactive_ui.guitkx"`, `_get_recognized_extensions() = ["guitkx"]`,
  `_get_resource_type() = "GDScript"`, `_get_save_extension() = "gd"`.
- `_import(source_file, save_path, ...)`: read the `.guitkx`, run the pipeline, write the emitted
  GDScript via `ResourceSaver` / `FileAccess` so that **`preload("res://Counter.guitkx")` returns the
  compiled GDScript class**. Editing + saving a `.guitkx` triggers a reimport → regenerated script →
  **Godot hot-reloads it for free** (the reason no HMR subsystem is needed).
- Usage in app code: `V.fc(preload("res://Counter.guitkx").render, { "start": 3 })`, or directly as a
  child element `<Counter start={3}/>` from another `.guitkx`.
- Errors: the pipeline returns diagnostics with `.guitkx` line/col; emitted as editor import errors +
  (where possible) a generated `.gd` that `push_error`s with the mapped location.

### B.2 Pipeline (per file) — ports from `language-lib` + `SourceGenerator~`
1. **DirectiveParser** (GDScript port of `language-lib/Parser/DirectiveParser.cs`) — header directives +
   the `component/hook/module` declaration; split body into setup-GDScript and the `return (...)` markup
   range. Hand-written char scanner with balanced brace/paren/bracket + string/comment skipping.
2. **MarkupParser** (port of `UitkxParser.cs`) — recursive-descent → AST (`ElementNode`, `AttributeNode`,
   `TextNode`, `ExpressionNode`, `IfNode/IfBranch`, `ForNode`, `WhileNode`, `MatchNode/Case`, `FragmentNode`,
   `CommentNode`). Each node carries source offsets.
3. **Resolve** — map each tag to host (`V.*`) vs component (`preload(...).render`); scan sibling files +
   `@use` for component resolution.
4. **Validate** — rules-of-hooks (port `HooksValidator` against our hook list), structure (unclosed/mismatched
   tags, single-root, duplicate keys) → diagnostic codes `GUITKX0xxx`.
5. **GDScriptEmitter** (NEW — the back-end) → the `.gd` text.

### B.3 What the emitter produces (concrete)
For `component Counter(start=0)` it emits:
```gdscript
class_name Counter
extends RefCounted
## AUTO-GENERATED from Counter.guitkx — do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
    var start = props.get("start", 0)
    # --- user setup spliced verbatim (with hook auto-prefix rewrite) ---
    var s = Hooks.use_state(start)
    var inc = func(): s[1].call(s[0] + 1)
    # --- return expression (markup lowered to V.* calls) ---
    return V.vbox({ "style": { "separation": 8 } }, [
        V.label({ "text": "%s: %d" % [label, s[0]], "font_size": 20 }),
        V.button({ "text": "+1", "on_pressed": inc }),
    ])
```
- **Hooks**: setup text rewrite `use_state(` → `Hooks.use_state(` (and the rest of our hook names);
  setter-sugar `set_x(func(v): ...)` works as-is (our setter already accepts a Callable updater).
- **Host element** `<Button text="Hi" on_pressed={inc}/>` → `V.button({ "text": "Hi", "on_pressed": inc })`.
- **Child component** `<Counter start={3}/>` → `V.fc(Counter.render, { "start": 3 })` (or
  `V.fc(preload("res://Counter.guitkx").render, ...)` when imported by path).
- **`{expr}` child** → the expression directly (a vnode) in the children array.
- **Control-flow → GDScript IIFE lambdas** (GDScript supports `(func(): ...).call()` as an expression —
  the direct analog of uitkx's `((Func<...>)(() => {...}))()`):
  - `@if/@elif/@else` → `(func(): if c: return X; elif d: return Y; else: return Z).call()`
  - `@for/@while` → `(func(): var __r: Array = []; for item in items: __r.append(X); return __r).call()`
    (a `return EXPR` in the loop body lowers to `__r.append(EXPR); continue`).
  - `@match` → `(func(): match m: "a": return X; _: return Y).call()`.
  - A `__c(...)` child-flattening helper (port of uitkx's `__C`) drops nulls + flattens arrays — though
    our reconciler already normalizes children, so this can be a thin pass.
- **`style={dict}`** → `"style": <dict>`; **`key={x}`** → routed to the `V.*` `key` arg, never a prop.

### B.4 Golden-file test suite
Mirror `SourceGenerator~/Tests`: a corpus of `.guitkx` inputs → expected `.gd` outputs, run headless
(`godot --headless --script tests/guitkx_golden.gd`), plus runtime tests that mount the compiled output.

---

## PART C — IDE extensions (`guitkx`) for VS Code + Visual Studio 2022

Architecture mirrors uitkx: thin/thick editor clients over **one shared LSP server**, plus a shared
TextMate grammar + JSON schema.

### C.1 The grammar + schema (shared assets) — port from `ide-extensions~/grammar/`
- **`guitkx.tmLanguage.json`** (scope `source.guitkx`): port the markup/tag/directive/attribute scopes
  from `uitkx.tmLanguage.json` verbatim; **swap the embedded-language rules** — replace the hand-rolled
  C# tokenizer (`cs-keywords`, `expression-content`) with **GDScript**: keywords (`func var const if elif
  else for while match return await signal class_name extends static`), GDScript strings incl. `"%s" %`,
  `&"..."` StringNames, operators, `$NodePath`, comments `#`.
- **`guitkx-schema.json`**: re-author the element catalog as **Godot Control nodes** (the 60 instantiable
  controls from `research/GODOT_UI_SURFACE.md`) — each tag → properties + events + `sinceGodot` version
  annotations (e.g. `FoldableContainer` since 4.3). Format reused from `uitkx-schema.json`; content new.
- **`guitkx.language-configuration.json`**: port (brackets, indentation rules, `onEnterRules` for JSX).

### C.2 The language server — `GuitkxLanguageServer` (C#, net8, OmniSharp)
Port `ide-extensions~/lsp-server/`. **Reuse** `language-lib` (fork as `ReactiveUITK.Guitkx.Language` /
`GuitkxLanguage.dll`): the markup parser, AST, `AstFormatter`, `SourceMap`, structural `DiagnosticsAnalyzer`,
semantic-token mapping, schema loading — all language-agnostic. **Replace** the Roslyn stack:

- **`GDScriptVirtualDocument`** (replaces `VirtualDocumentGenerator.cs`): splice the extracted GDScript
  expressions into a synthetic `.gd` file (component render fn + hook stubs + props vars) and build a
  **position table** mapping synthetic-`.gd` offsets ↔ `.guitkx` offsets (GDScript has no `#line`, so the
  map is table-based, not directive-based).
- **`GodotLspProxy`** (replaces `RoslynHost.cs`): a JSON-RPC client to **Godot's built-in GDScript Language
  Server** (`ws://127.0.0.1:6005` by default; configurable). For completion/hover/diagnostics/definition
  inside `{expr}`/`attr={expr}`, forward the request on the synthetic `.gd` and map results back through
  the position table. Falls back to grammar-only + markup features if Godot's LSP isn't reachable.
- **Native (no Godot needed)** features from `language-lib`: tag/attribute/directive completion (from the
  Godot schema + peer-component scan), structural diagnostics, markup formatting, hover for elements/attrs/
  directives/hooks (a `HookRegistry` of our hook list), semantic tokens for markup.
- Keep the OmniSharp handler skeletons (`CompletionHandler`, `HoverHandler`, `DefinitionHandler`,
  `FormattingHandler`, `SemanticTokensHandler`, `DiagnosticsPublisher`, `TextSyncHandler`) and the
  `CapabilityPatchStream` (VS2022 needs static capabilities injected).
- **Project discovery** (replaces `ReferenceAssemblyLocator`/`AsmdefResolver`): locate `project.godot`,
  autoloads, the Godot version, and the project's `.gd`/`.guitkx` files — to seed completion + resolve
  component references.

> *Alt considered:* writing the LSP in TypeScript/Node (no .NET). Rejected for v1 because reusing the
> proven C# `language-lib` + OmniSharp scaffolding is far less work; the server ships as a bundled binary
> so end users need neither .NET nor Node.

### C.3 VS Code extension — port from `ide-extensions~/vscode/` (TypeScript)
- TypeScript + **esbuild** bundle; dependency **`vscode-languageclient`**; `@vscode/vsce` to package.
- `package.json`: `contributes.languages` (`guitkx`, `.guitkx`), `contributes.grammars`
  (`source.guitkx`→`guitkx.tmLanguage.json`), `contributes.configuration` (`guitkx.server.path`,
  `guitkx.godot.lspPort` default 6005, `guitkx.dotnetPath`), `configurationDefaults` (formatter, tabSize 4
  — GDScript convention, formatOnSave), the 5 semantic-token types. `activationEvents: ["onLanguage:guitkx"]`.
- `src/extension.ts`: spawn the bundled `GuitkxLanguageServer` over **stdio** (`server/GuitkxLanguageServer.exe`
  on Windows, else `dotnet server/GuitkxLanguageServer.dll`); the completion-`@`-strip middleware + the
  explicit `DocumentFormattingEditProvider` registration (OmniSharp quirk) port directly.

### C.4 Visual Studio 2022 extension — port from `ide-extensions~/visual-studio/UitkxVsix/` (C# VSIX)
- net472 VSIX, `Microsoft.VSSDK.BuildTools` + `Microsoft.VisualStudio.SDK`; `source.extension.vsixmanifest`
  targeting VS `[17.0,19.0)`. Bundles the LSP server under `server/` (CI asserts it's in the `.vsix`).
- Ports: `GuitkxLanguageClient` (`ILanguageClient`, spawns server `--vs2022`), and the native fallbacks VS
  needs for custom content types — `GuitkxClassifier` (hand-written GDScript-aware lexer + classification
  colors), `GuitkxCompletionSource`, `GuitkxQuickInfoSource`, `GuitkxDiagnosticTagger`,
  `GuitkxFormatDocumentHandler`, `BufferSyncService`, `GuitkxMiddleLayer`. (VS's LSP client is weak for
  custom content, so this native layer is unavoidable — same as uitkx.)

### C.5 Feature parity target (delivered to devs)
Syntax highlighting (TextMate + LSP semantic tokens), tag/attribute/directive/component completion, hover
docs (elements/attrs/directives/hooks), diagnostics (parser + structural + embedded-GDScript via Godot LSP),
formatting (markup via `AstFormatter`, GDScript via Godot's formatter or `gdformat`), go-to-definition/
references for components & GDScript symbols (via the Godot LSP proxy).

---

## PART D — Build, package, publish

Port the uitkx model (`.github/workflows/publish.yml`): **manual `workflow_dispatch`**, per-artifact SemVer,
**skip-if-tag-exists + auto-tag-on-success**, centralized changelog (`changelog.json` + `scripts/changelog.mjs`).
- **VS Code** → esbuild + `npx @vscode/vsce package/publish` → **VS Code Marketplace** (`VSCE_PAT`) +
  **Open VSX** (`OVSX_TOKEN`). LSP server `dotnet publish`ed into `vscode/server/`.
- **VS 2022** → `windows-latest`, locate VS via `vswhere`, `msbuild … CreateVsixContainer`, publish via
  **`VsixPublisher.exe`** → **VS Marketplace** (`VS_MARKETPLACE_TOKEN`). LSP server `--runtime win-x64`
  into the VSIX `server/`.
- **The Godot addon itself** (the runtime + the guitkx import-plugin) → tagged GitHub release + **Godot
  Asset Library** submission (see Part 4 of the master plan / the distribution note).

---

## PART E — Reuse vs rebuild ledger (concrete, by Unity file)

| Unity component | guitkx disposition |
|---|---|
| `language-lib/Parser/*`, `Nodes/AstNode.cs` | **Reuse (C#)** in LSP; **re-port to GDScript** in the import-plugin compiler. Markup grammar is language-agnostic. |
| `language-lib/Formatter/AstFormatter.cs` | Reuse (markup); GDScript-format delegate replaces the C# one. |
| `language-lib/Roslyn/VirtualDocumentGenerator.cs`, `SourceMap.cs` | **Rebuild** as `GDScriptVirtualDocument` + table-based position map. |
| `lsp-server/Roslyn/RoslynHost.cs` + Roslyn providers | **Rebuild** as `GodotLspProxy` (client of Godot's GDScript LSP). |
| `lsp-server/Program.cs`, `CapabilityPatchStream.cs`, handler skeletons | **Reuse/adapt** (OmniSharp scaffolding). |
| `lsp-server/ReferenceAssemblyLocator`, `AsmdefResolver` | **Rebuild** as Godot project discovery (`project.godot`, autoloads, version). |
| `grammar/uitkx.tmLanguage.json` | **Port**, swap embedded-C# rules → GDScript. |
| `grammar/uitkx-schema.json` | **Re-author** as Godot Control schema (60 controls). |
| `vscode/` (TS extension) | **Port** (rename, new grammar/schema, GDScript LSP port setting). |
| `visual-studio/UitkxVsix/` | **Port** (rename, GDScript-aware classifier). |
| `SourceGenerator~/` (Roslyn IIncrementalGenerator + emit) | **Replace** with the GDScript import-plugin compiler (Part B). Emit logic re-authored for GDScript. |
| `rider/`, `Editor/UitkxCsprojPostprocessor.cs`, HMR, props-pooling, `[ModuleInitializer]` | **Drop** (out of scope / Unity-specific). |

Estimated reuse: ~60-70% of `language-lib`, ~40-50% of LSP scaffolding, most of the grammar/schema *format*
and the VS Code/VS2022 extension shells; rebuild the GDScript virtual-doc + Godot-LSP proxy + the GDScript
emitter + the schema content.

---

## Milestones

- **2.0 — Language spec** (`plans/`): finalize the `.guitkx` grammar (Part A), with example corpus.
- **2.1 — Compiler MVP** (Part B): GDScript lexer+parser+emitter + `EditorImportPlugin`; golden-file tests.
  *guitkx is usable here with NO extension installed.*
- **2.2 — Grammar + schema** (Part C.1): `guitkx.tmLanguage.json` + `guitkx-schema.json` + language-config.
  *Basic highlighting in any TextMate editor.*
- **2.3 — LSP server** (Part C.2): fork `language-lib`, OmniSharp scaffolding, markup features native,
  embedded-GDScript via Godot LSP proxy.
- **2.4 — VS Code extension** (Part C.3): thin client + bundled LSP; publish to VS Code Marketplace + Open VSX.
- **2.5 — VS 2022 extension** (Part C.4): VSIX + native fallbacks; publish to VS Marketplace.
- **2.6 — CI/publish** (Part D): `publish.yml` parity (manual, skip-if-tagged, auto-tag, changelog).

## Risk register
| Risk | Severity | Mitigation |
|---|---|---|
| Godot GDScript LSP coverage/stability for embedded-expr intelligence | Med-High | Markup features work without it; degrade gracefully; pin to Godot 4.x LSP behavior; consider a headless-Godot analysis fallback. |
| Two parsers (GDScript + C#) drift | Med | Single grammar spec + a shared golden-file corpus both must pass. |
| Position-map fidelity without `#line` | Med | Table-based map with per-region offsets; heavy golden tests on mapping. |
| VS2022 native layer effort (LSP client weakness) | Med | It's a direct port of the proven uitkx VS layer; scope to highlight+complete+hover first. |
| Marketplace publishing toolchain (VsixPublisher quirks) | Low-Med | Port uitkx's CI exactly (incl. its known exit-0 workaround). |
| Scope (one person, large surface) | Med | Ship 2.1 (compiler) standalone first — full value without any extension; extension is additive. |
