# GODOT_EDITOR_EXTENSION_PLAN — bring full `.guitkx` tooling into the Godot editor

Goal: a Godot **editor addon** that gives `.guitkx` authors, inside the Godot editor itself, the SAME
language experience our VS Code + VS 2022 extensions give — syntax highlighting, diagnostics, completion,
hover, go-to-definition, find-references, rename, signature help, inlay hints, code actions, document
symbols, formatting, and semantic highlighting — with **complete parity** to the IDE tooling of both
ReactiveUIToolKit (Unity) and ReactiveUI-Godot.

Status: PLAN (research complete, all claims source-cited against Godot 4.2–4.5 docs + engine source).

**Settled decisions (user):**
1. **Engine floor = Godot 4.4+.** Unlocks `OS.execute_with_pipe` (stdio) and `symbol_hovered` /
   `symbol_tooltip_on_hover`, removing almost all the 4.2/4.3 version-gating below (TCP fallback,
   `_make_custom_tooltip`-only hover). Treat the 4.2/4.3 notes in this doc as reference, not requirements.
2. **Phase first, decide the deep-intelligence backend later.** Ship **P1–P2 in pure GDScript** (highlighting
   + diagnostics + markup intelligence — no dependency, no backend commitment); choose §4 Path 1 (Node
   subprocess) vs Path 2 (native gdext + GDScript) **at P3**, with real usage data.
3. **Additive React-style event aliases (§7).** Add `on_click`→`pressed`, `on_change`→`text_changed`, … as
   non-breaking aliases alongside the existing `on_<signal>`. Library/compiler change, independent of the editor.
   *(Shipped: `onClick`/`onChange`/… camelCase aliases are implemented in `host_config.gd`.)*
4. **[RESOLVED 2026-07] Backend = §4 Path 2 (native gdext binding of `gdscript-analyzer`).** Research-confirmed
   feasible and chosen; the analyzer's `gdscript-session` core is wrapped as a third ~200-line delegator
   alongside napi/wasm, giving all 16 IDE queries in-process (no TCP, no Node, no config). Markup intelligence
   is ported to GDScript (reusing the existing GDScript compiler + schema JSON); embedded GDScript is bridged
   to the gdext analyzer. **Full design: [GODOT_ANALYZER_INTEGRATION_PLAN.md](GODOT_ANALYZER_INTEGRATION_PLAN.md).**
   This supersedes the §4 "decide at P3" wording and §10 open question 1.

> Docs caveat baked into every citation: `docs.godotengine.org/en/stable` now resolves to **4.7**, which
> deprecated `add_control_to_dock` (→ `add_dock`/`EditorDock`) and added `DOCK_SLOT_BOTTOM` + completion
> `KIND_KEYWORD` + `symbol_hovered`. **None of those exist in 4.2–4.5.** Use version-pinned `/en/4.x/` URLs.

---

## 1. The parity surface — what we must reproduce

The bar is "everything our LSP server (`ide-extensions/lsp-server`, TypeScript, embeds the Rust
`@gdscript-analyzer/core`) already does," for both `.guitkx` and plain `.gd`:

| Capability | `.guitkx` (markup + embedded GDScript) | plain `.gd` |
|---|---|---|
| Diagnostics | markup GUITKX codes (compiler) + embedded GDScript (analyzer) | analyzer |
| Completion | tags / attrs / directives (schema + ClassDB) + components (index) + embedded (analyzer) | analyzer |
| Hover | host element / attr / component-signature (schema + ClassDB + index) + embedded (analyzer) | analyzer |
| Go-to-definition | component tag / decl / `@class_name` (index) + embedded cross-file (analyzer) | analyzer |
| Find-references | component (index + tag scan) + embedded (analyzer) | analyzer |
| Rename | component atomic incl. `@class_name` (index) + embedded correct-or-refuse (analyzer) | project-wide (analyzer) |
| Signature help | markup `on_<signal>` + embedded calls (analyzer) | analyzer |
| Inlay hints | embedded inferred types (analyzer) | analyzer |
| Code actions | embedded quick-fixes (analyzer) | analyzer |
| Document symbols | component / hook / module outline | analyzer |
| Formatting | markup (`formatGuitkx`) + embedded reflow (analyzer `gdscript-fmt`) | analyzer |
| Semantic tokens | markup tokens + embedded (analyzer) | analyzer |
| Config | `guitkx.config.json` (formatter options) | — |

Plus the on-save **compile** `.guitkx` → sibling `.gd` (already an editor plugin in `addons/reactive_ui`).

---

## 2. What Godot 4.x actually permits (the hard constraints, source-verified)

These five facts shape the whole design:

1. **Godot's editor is an LSP _server_, not a client.** The GDScript Language Server is compiled into the
   editor (TCP 127.0.0.1:6005, GDScript-only) and cannot be pointed at an external server for a custom
   language. "Include an LSP client in the script editor" is an **open, unimplemented** proposal
   ([godot-proposals #2215](https://github.com/godotengine/godot-proposals/issues/2215)). → We cannot
   "just register our `.guitkx` LSP with Godot." Any client is code we write in the addon.

2. **`ScriptLanguageExtension` is the only path to _native_ editor parity — and it's the wrong tool.** It
   adds a whole scripting language via GDExtension, with **60+ required virtuals** including a full runtime
   + debugger contract (`_create_script`, instancing, `_debug_get_stack_level_*`, …) that is meaningless
   for a markup language that merely compiles to GDScript. It is a native (C++/Rust) per-platform binary
   with known fatal edges: **segfault at exit** (no unregister, [godot#66475](https://github.com/godotengine/godot/issues/66475))
   and **editor crash on hot-reload** of an extension carrying a ScriptLanguageExtension. → **Rejected.**
   It defines the "parity ceiling" (§9), not the plan.

3. **The built-in script editor CAN open + highlight `.guitkx` — but only as a dumb `TextFile`.**
   `EditorNode::load_resource()` routes a double-clicked file in a fixed order (engine source, 4.5):
   `(1)` if `ResourceLoader::exists()` → **Inspector**; else `(2)` if the extension is in the
   `docks/filesystem/textfile_extensions` editor setting → **built-in script editor** as a `TextFile`;
   else `(3)` if in `other_file_extensions` → OS shell-open; else nothing. And `ScriptEditor::edit()`
   auto-applies an `EditorSyntaxHighlighter` whose `_get_supported_languages()` contains the bare file
   **extension** (`"guitkx"` — there is no `_get_supported_extensions()`). **But a `TextFile` gets no
   completion / hover / diagnostics / symbol-lookup** — those are Script-only. ([editor_node.cpp](https://github.com/godotengine/godot/blob/master/editor/editor_node.cpp),
   [class_editorsyntaxhighlighter](https://docs.godotengine.org/en/4.5/classes/class_editorsyntaxhighlighter.html))

4. **Registering ANY `ResourceFormatLoader`/`EditorImportPlugin` for `.guitkx` makes
   `ResourceLoader::exists()` true → permanently diverts double-click to the Inspector**, killing the
   text-editor route (field-confirmed regression). So "custom Resource" and "built-in text editor" are
   **mutually exclusive**. ([godot-proposals #13867](https://github.com/godotengine/godot-proposals/issues/13867))

5. **`CodeEdit` is a fully drivable editor substrate.** Everything we need is on `CodeEdit`/`TextEdit`
   and can be driven per-instance from pure GDScript: a `SyntaxHighlighter`, code completion
   (`code_completion_enabled`, `code_completion_prefixes`, override `_request_code_completion(force)` →
   `add_code_completion_option(KIND_*, …)` → `update_code_completion_options(force)`), icon gutters for
   diagnostics (`add_gutter` + `GUTTER_TYPE_ICON` + `set_line_gutter_icon`/`_metadata` + `gutter_clicked`),
   ctrl+click go-to-def (`symbol_lookup_on_click` + `symbol_validate` → `set_symbol_lookup_word_as_valid` →
   `symbol_lookup(symbol,line,col)`), hover tooltips (`Control._make_custom_tooltip`/`_get_tooltip`;
   `symbol_hovered`/`symbol_tooltip_on_hover` are **4.4+ only**), folding, auto-indent (`indent_automatic`),
   comment/string delimiters, auto-brace pairs. ([class_codeedit](https://docs.godotengine.org/en/4.4/classes/class_codeedit.html))

**Conclusion:** native parity ⇒ host **our own `CodeEdit`** (Strategy B), because the built-in editor only
gives highlighting.

**Reference implementation — Dialogic 2** (`dialogic-godot/dialogic`) is almost exactly our case and proves
the whole approach in production: a **main-screen** plugin (`_has_main_screen`/`_get_plugin_name`/`_make_visible`),
a **text-based** custom format `.dtl` backed by `DialogicTimeline : Resource` + a `ResourceFormatLoader`/`Saver`
pair that parse/serialize human-readable text (`from_text`/`as_text`), `_handles`/`_edit` routing a
double-clicked resource into an internal `editors_manager` (extension→sub-editor map), and a timeline editor
with a **`CodeEdit` text mode** whose `syntax_highlighter` is a custom `SyntaxHighlighter` subclass (RegEx,
theme-aware) plus a `CodeCompletionHelper`. Notably Dialogic **auto-registers** its loader/saver purely via
`class_name`-declared `ResourceFormatLoader`/`Saver` subclasses (no `add_resource_format_loader` calls, no
`EditorImportPlugin`) — the simplest registration path (our other source found explicit registration in
`_enter_tree` more reliable; we can do either). Secondary precedents: **LimboAI** and **Blockflow** (same
main-screen + `Resource` + `_handles`/`_edit` shape, with `.tres` resources and bespoke visual editors).
Counter-examples worth noting: **inkgd / godot-ink** deliberately do NOT author in-editor — they use an
external app (Inky) + an import plugin that compiles on import + a read-only preview dock; that's the model
to AVOID for us (we want full in-editor authoring).

---

## 3. Reuse inventory — what already exists (and in what language)

| Asset | Where | Language | Reusable for the addon? |
|---|---|---|---|
| `.guitkx` **compiler** `RUIGuitkx.compile(src) → {ok, gd, diagnostics}` | `addons/reactive_ui/guitkx` | **pure GDScript** | YES — direct in-editor diagnostics, no subprocess |
| `.guitkx` **lexer** `RUIGuitkxLexer` | `addons/reactive_ui/guitkx` | **pure GDScript** | YES — basis for the `CodeHighlighter` |
| `.guitkx` **formatter** `guitkx_formatter.gd` | `addons/reactive_ui/guitkx` | **pure GDScript** | YES — Format Document (markup) |
| on-save compile hook (`EditorFileSystem.filesystem_changed` → compile → `update_file`) | `addons/reactive_ui/plugin.gd` | **pure GDScript** | YES — already shipping |
| **markup LSP logic** (schema completion/hover, component index, virtual-doc + source-map, the gd* handlers) | `ide-extensions/lsp-server` | **TypeScript** | logic reusable by PORT, not directly |
| schema data (HOST_TAGS, STRUCTURAL/COMMON_ATTRS, directives, STYLE_KEYS) + ClassDB dump | `ide-extensions/lsp-server` (+ `vscode/classdb`) | TS + JSON | the **JSON** is reusable as-is in GDScript |
| **embedded-GDScript intelligence** (`@gdscript-analyzer/core`) | `gdscript-analyzer` (Rust) | **Rust** (napi + wasm bindings) | via a **new gdext binding** (native) or napi-over-Node |

Key insight: **the markup half is mostly data + already-GDScript code; only the embedded-GDScript half
needs the Rust analyzer.** The compiler/lexer/formatter are already pure GDScript.

---

## 4. The architecture decision (the one I need your call on)

Highlighting + diagnostics are free (pure-GDScript compiler/lexer, no dependency). The fork is **how to
get the deep, type-aware intelligence** (completion/hover/goto/refs/rename inside `{expr}`/setup, and full
`.gd`):

### Path 1 — Subprocess our existing TypeScript LSP
Spawn `node out/server.js` from the addon and speak LSP over **stdio** (`OS.execute_with_pipe`, **4.4+**)
or **TCP** (`StreamPeerTCP`, 4.2/4.3 fallback), with a hand-written GDScript LSP client (~few hundred
lines: `Content-Length` framing, request/response correlation) mapping results into the `CodeEdit`.
- ➕ Reuses **100%** of the maintained TS server → fastest to full parity; one source of truth with VS Code.
- ➖ Ships a **Node.js runtime dependency** (bundle node ≈ 30–50 MB/platform, or require it on PATH) — a
  real wart for Godot users; plus the napi `.node` binary per platform. Process lifecycle/crash-restart.

### Path 2 — Native: port the markup LSP to GDScript + bind the Rust analyzer via GDExtension
Reimplement the markup-side LSP logic in GDScript (schema-driven completion/hover, the component index,
the virtual-doc + source-map) — reusing the existing pure-GDScript compiler/lexer/formatter and the schema
**JSON** — and add a **third gdext binding** of `gdscript-session` (alongside napi/wasm) for the
embedded-GDScript intelligence.
- ➕ **No runtime dependency**, fully native, best addon UX; the analyzer binding is in-process (no IPC).
- ➕ The gdext binding is a natural third wrapper over the same Rust `Session` that already returns JSON.
- ➖ Biggest effort: a GDScript port of the markup LSP (a second implementation to keep in sync with the
  TS one — precedent exists: `formatGuitkx.ts` ↔ `guitkx_formatter.gd` are already kept byte-identical),
  plus a per-platform native gdext build + CI.

### Path 3 — Phased hybrid (recommended sequencing regardless of 1 vs 2)
Ship value immediately in pure GDScript (P1–P2 below), then choose the deep-intelligence backend (Path 1
or 2) for P3–P4. This de-risks: highlighting + diagnostics + markup completion need **no** decision.

**My recommendation:** **Path 3 sequencing, with Path 2 (native) as the deep-intelligence backend.**
Rationale: Godot addon users strongly resist external runtimes; the compiler/lexer/formatter are already
GDScript; the schema is JSON; and a gdext binding of the analyzer is something the analyzer project should
have anyway. Path 1 is the right choice **only if** speed-to-full-parity outweighs shipping Node. This is
the decision to confirm before P3.

---

## 5. Phased delivery plan

### Phase 0 — Decide + scaffold (small)
- Confirm the §4 backend decision (Path 1 vs 2 for P3+).
- Extend the existing `addons/reactive_ui` plugin (it already compiles `.guitkx`→`.gd`) OR ship a sibling
  `addons/reactive_ui_editor`. `@tool extends EditorPlugin`; register/cleanup in `_enter_tree`/`_exit_tree`
  (autoloads, if any, in `_enable_plugin`/`_disable_plugin`). Use the `EditorInterface` singleton directly
  (`get_editor_interface()` is deprecated 4.2+).
- Version-gate helpers via `Engine.get_version_info()` (e.g. stdio pipe + `symbol_hovered` are 4.4+).

### Phase 1 — Highlighting + diagnostics (pure GDScript, no dependency) — ships first
Two sub-options for the editing surface; **B is the parity path**, A is a 1-day freebie:
- **1A (freebie):** register an `EditorSyntaxHighlighter` whose `_get_supported_languages()` returns
  `["guitkx"]` via `EditorInterface.get_script_editor().register_syntax_highlighter(...)`, and add `guitkx`
  to `docks/filesystem/textfile_extensions`. Now double-click opens `.guitkx` in the **built-in** editor
  with coloring. No intelligence — but instant. (Driven by the `RUIGuitkxLexer` → a `CodeHighlighter`.)
- **1B (the real editor):** a **main-screen** plugin (`_has_main_screen`→true, `_get_plugin_name`,
  `_get_plugin_icon`, `_make_visible`) hosting our own `CodeEdit`. Configure it: `syntax_highlighter` =
  a `CodeHighlighter` built from the lexer; `add_comment_delimiter`/`add_string_delimiter` from the lexer;
  `auto_brace_completion_enabled` + `add_auto_brace_completion_pair("<", ">")`; `indent_automatic` +
  `indent_use_spaces=false` (tabs, to match the compiler). To make `.guitkx` double-click-openable into it,
  follow the **LimboAI/Blockflow** pattern: a `GuitkxResource : Resource` + a `ResourceFormatLoader`/`Saver`
  (registered explicitly in `_enter_tree` via `ResourceLoader.add_resource_format_loader`), and `_handles`
  returns true for `GuitkxResource` → `_edit` loads the text into the `CodeEdit` → `_make_visible(true)`.
  (Accept §2.4: this routes double-click to our editor, not the built-in one — which is what we want.)
- **Diagnostics (both):** on `text_changed`/`lines_edited_from`, run `RUIGuitkx.compile(text)` (pure
  GDScript, already returns `{diagnostics}`); render via an **icon gutter** (`add_gutter` +
  `GUTTER_TYPE_ICON` + `set_line_gutter_icon` + `set_line_gutter_metadata`) and a problems list
  (bottom-panel). Embedded-GDScript diagnostics come later with the analyzer backend (P3).

### Phase 2 — Markup intelligence (completion / hover / goto / refs / rename), pure GDScript
Port the **schema-driven** markup features (no analyzer needed) into GDScript, reusing the schema JSON
+ ClassDB dump + the component index (a project `.guitkx` scan, mirroring `workspaceIndex.ts`):
- **Completion:** `code_completion_enabled=true`, `code_completion_prefixes=["<","@"," ",".","_"]`,
  override `_request_code_completion(force)` → classify context (port `classifyContext`) → emit tags
  (`KIND_CLASS`), attributes/`on_<signal>` (`KIND_MEMBER`/`KIND_SIGNAL` from ClassDB), directives
  (`KIND_PLAIN_TEXT`/snippet), component tags (from the index) → `update_code_completion_options(force)`.
- **Hover:** `_make_custom_tooltip(for_text)` (rich) / `_get_tooltip` → resolve the word (port `markupHover`)
  to host-element / attr / component-signature info.
- **Go-to-def + refs + rename (component/`@class_name`):** `symbol_lookup_on_click=true` + `symbol_validate`
  → `set_symbol_lookup_word_as_valid` + `symbol_lookup` → jump via the index; refs/rename reuse the index +
  tag-scan logic (port `componentTagAt`/`bindingUnderCursor`/`scanTagRefs`, incl. the atomic `@class_name`
  rename we just fixed). Apply rename edits into open `CodeEdit` buffers + on-disk files.

### Phase 3 — Embedded-GDScript intelligence (the analyzer backend; needs §4 decision)
Wire completion/hover/goto/refs/rename/signature-help/inlay/code-actions **inside `{expr}`/setup** by
driving the analyzer over the **virtual-doc + source-map** (port the source map; it's pure logic). Backend
per §4: Path 1 = LSP requests to the Node subprocess; Path 2 = direct calls into the gdext-bound `Session`.
Map results onto the same `CodeEdit` hooks as Phase 2. This closes embedded diagnostics too.

### Phase 4 — Formatting + semantic highlighting + polish
- **Format Document:** markup via `guitkx_formatter.gd` (exists); embedded reflow via the analyzer
  (Path 1/2). Wire to a toolbar action + format-on-save.
- **Semantic highlighting:** the `CodeHighlighter` covers lexical coloring; type-aware semantic tokens
  (analyzer) can overlay via a custom `SyntaxHighlighter._get_line_syntax_highlighting` painting from the
  analyzer's token ranges (the same merge we just built in `guitkxSemanticTokens`).
- **Polish:** completion item icons/detail/snippets, multi-file rename UX, inlay hints (4.4+ niceties),
  `guitkx.config.json` reading (already GDScript-friendly), live UI preview (optional, big — a separate
  proposal: render the compiled `.gd` component into a preview viewport).

---

## 6. Capability → Godot mechanism map (the parity checklist)

| LSP capability | Godot editor mechanism | Backend |
|---|---|---|
| Markup diagnostics | icon gutter + problems list | GDScript compiler (P1) |
| Embedded diagnostics | icon gutter | analyzer (P3) |
| Tag/attr/directive completion | `_request_code_completion` + `add_code_completion_option` | schema/index (P2) |
| Embedded completion | same | analyzer (P3) |
| Hover (markup) | `_make_custom_tooltip` | schema/index (P2) |
| Hover (embedded) | same | analyzer (P3) |
| Go-to-def (component) | `symbol_lookup` signal | index (P2) |
| Go-to-def (embedded, cross-file) | `symbol_lookup` → open target file | analyzer (P3) |
| Find-references / rename | index + tag-scan; apply WorkspaceEdit to buffers | index (P2) / analyzer (P3) |
| Signature help | a popup `Control` on `(`/`,` (no built-in; we draw it) | schema/analyzer |
| Inlay hints | `CodeEdit` has none → draw via gutter/line decorations (4.4+ niceties) | analyzer (P4) |
| Code actions | a context menu / lightbulb we build | analyzer (P4) |
| Document symbols | a tree dock listing component/hook/module | GDScript scan (P2) |
| Formatting | toolbar action | `guitkx_formatter.gd` + analyzer |
| Semantic tokens | custom `SyntaxHighlighter` overlay | analyzer (P4) |

Note: a few VS Code niceties (rich markdown hover, inlay hints, lightbulb code-actions) are **harder** in
`CodeEdit` than in Monaco — achievable but more hand-built glue (see §9).

---

## 7. The `on_pressed` vs `onClick` decision (folded in, per your ask)

Today event props are a raw per-class Godot-signal passthrough: `on_<signal>` → `node.connect(signal, cb)`
(`host_config.gd`), validated only at connect time. There is **no clean universal `onClick`** because Godot
signals are class-specific (`pressed`=BaseButton, `text_changed`=LineEdit, `toggled`=CheckButton…). Options:
- **(a) Additive alias table (recommended):** a curated map `on_click→pressed`, `on_change→text_changed`,
  `on_toggle→toggled`, … applied in `host_config._signal_name` + surfaced in completion/validation. Both
  spellings work; **non-breaking**; React devs get familiar names; Godot devs keep signal names. The alias
  is per-element (only where the target class has that signal).
- **(b) Replace** `on_<signal>` with React names — breaking, and lossy (Godot has signals with no React
  analogue). Not recommended.
Decision needed: ship (a) as part of the schema/runtime, and the Godot-editor completion will offer both.

---

## 8. Risks + the 4.2–4.5 version matrix

| Concern | Mitigation |
|---|---|
| `OS.execute_with_pipe` (stdio) is **4.4+** | Path 1 falls back to `StreamPeerTCP` on 4.2/4.3 |
| `symbol_hovered`/`symbol_tooltip_on_hover` **4.4+** | gate behind `Engine.get_version_info()`; use `_make_custom_tooltip` on 4.2/4.3 |
| completion `KIND_KEYWORD` **not in ≤4.5** | use `KIND_PLAIN_TEXT` for directive keywords |
| `add_dock`/`EditorDock`/`DOCK_SLOT_BOTTOM` are **4.7-only** | use `add_control_to_dock` + main-screen; never `add_dock` on ≤4.5 |
| registering a loader/importer kills the text-editor route | deliberate: Strategy B owns the editor; never register one if 1A is also wanted |
| `update_code_completion_options` at the wrong time crashed historically ([#62199]) | only populate inside `_request_code_completion` |
| GDScript port drifting from the TS server | keep a shared fixture corpus (as `formatGuitkx.ts`↔`guitkx_formatter.gd` already do) |
| gdext native build per platform (Path 2) | reuse the analyzer's existing release CI (napi/wasm) for a third target |

## 9. The parity ceiling (be honest about it)
**Reachable** (custom `CodeEdit` dock): completion, hover, diagnostics, goto, refs, rename, formatting,
semantic highlighting — i.e. **language-intelligence parity with the VS Code extension**, since the same
engines back both. **Not reachable without `ScriptLanguageExtension`** (and thus off the table): `.guitkx`
as a first-class *Script* type, editing in the **built-in** script editor with intelligence, the integrated
**debugger** stepping `.guitkx`, and engine-level `.guitkx`↔`.tscn`/`.gd` cross-refs. Those are the only
gaps, and they only matter for "feels like GDScript to the engine," not for the authoring experience.

## 10. Open questions for you
1. **§4 backend: Path 1 (subprocess Node LSP, fast/full reuse, Node dep) vs Path 2 (native GDScript +
   gdext Rust, no dep, more work)?** I lean Path 2 with the Path-3 phasing. Your call before P3.
2. Engine floor — is **4.2** the right floor, or can we require **4.4** (unlocks stdio + hover signals and
   simplifies a lot)?
3. Editing surface — Strategy **B** (our own main-screen editor; needed for parity) confirmed, or also ship
   the **1A** built-in-editor highlighting freebie alongside?
4. `on_pressed` aliases (§7) — approve the additive (a) approach?
