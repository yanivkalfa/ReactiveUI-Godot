# Godot Port — Parity Plan & Live Status (ReactiveUIToolKit → ReactiveUI-Godot)

> **STATUS UPDATE — 2026-06-30.** This file is the living source of truth for *where we stand*. Two
> things changed since the original 2026-06-21 gap analysis, and the older design docs never captured them:
>
> 1. **The IDE LSP swapped from Godot's built-in LSP to our own `@gdscript-analyzer/core`.** Embedded
>    GDScript inside `.guitkx` (the `{expr}` / setup / `@if`/`@for` conditions) is now answered **in-process,
>    headless, offline** by the Rust analyzer — *no running Godot editor, no TCP port 6005*. The old
>    "Godot LSP proxy / port 6005 / shell-out to headless Godot" model described in `PHASE_2_GUITKX_PLAN`,
>    `PHASE_4_DESIGN`, `PHASE_5_6_DESIGN`, and `IDE_EXTENSION_ISSUES` is **DEAD/SUPERSEDED** — `godotProxy.ts`
>    was deleted. See *Analyzer integration* below.
> 2. **The core runtime reached ~Unity parity.** `PHASE_7_PLAN` is COMPLETE: full router, 21 hooks (+~14
>    router hooks), signals + registry, Suspense, 3-layer styles, item-model adapters, 63 `V.*` factories,
>    green suite on Godot 4.7. The original "Core 62%" line below is the *baseline*, not the current state.
>
> **The decision going forward (set 2026-06-30): swap to our analyzer COMPLETELY** — not just the
> `.guitkx`-embedded surface, but drive plain `.gd` too and wire the analyzer's full capability set. The
> Forward Roadmap section is the operative plan; the Phase 3–10 history below is kept as record.

---

## Current status by goal — 2026-06-30

**G1 — use `@gdscript-analyzer/core` instead of Godot's built-in LSP → DONE for `.guitkx`-embedded; not yet "complete".**
- Shipped: `ide-extensions/lsp-server` embeds `@gdscript-analyzer/core` via `analyzerAdapter.ts` (`AnalysisHandle`);
  `godotProxy.ts` deleted; release 0.2.6 (commits `5e5dc5d → 4f4c5d8 → 4f74cfd`).
- Gaps to "complete swap": (a) only **4 of 13** analyzer queries wired (completions/hover/diagnostics/gotoDefinition);
  find-refs, rename, documentSymbols, foldingRanges, inlayHints, signatureHelp, codeActions, workspaceSymbols are
  not analyzer-backed for embedded GDScript. (b) `format`/`semantic_tokens` exist in `gdscript-ide` + standalone
  `gdscript-lsp` but are **not in the napi binding** — need new `#[napi]` delegators in the analyzer repo. (c) The
  IDE `documentSelector` is `language:'guitkx'` only — plain `.gd` still uses Godot's `godot-tools`. (d) Pinned
  `^0.4.0` (0.4.0 installed); **npm latest is 0.5.0**.

**G2 — finish the reactive_ui library → ~Unity parity (PHASE_7 COMPLETE); a few edges + docs left.**
- Done: see PHASE_7. Remaining: **custom-draw escape hatch** (`onGenerateVisualContent` / `_draw` + `redraw_key`)
  — not ported, but the Unity/C# sibling shipped it @0.6.3 as a reference; optional niche adapters (SubViewport /
  GraphEdit / GraphNode); **badly stale README** (claims MVP / 10 elements / 6 hooks vs the real 21+ hooks / 63
  factories); Tests (~28%) + Docs (~8%) parity (Phases 10/9).

**G3 — Godot's own editor learns `.guitkx` → HALF done.**
- Done: `@tool EditorPlugin` (`addons/reactive_ui/plugin.gd`) compiles each `Foo.guitkx` → sibling `Foo.gd` and
  hot-reloads it (deliberately NOT an EditorImportPlugin, NOT a ScriptLanguageExtension).
- Not started: **no `EditorSyntaxHighlighter`** — Godot's own script editor shows `.guitkx` as plain text; all
  syntax intelligence lives in the external VS Code / VS 2022 extensions. Native in-Godot intelligence beyond
  highlighting would need a C++/GDExtension `ScriptLanguageExtension` — out of scope for a GDScript-only addon.

---

## Analyzer integration (the corrected model)

```
.guitkx file ─▶ LSP server (ide-extensions/lsp-server, TS, shared by VS Code + VS 2022)
                 ├─ markup language  → local schema + ClassDB dump (tags, attrs, style keys)
                 └─ embedded GDScript → virtualDoc.ts (synthetic length-preserving .gd) + sourceMap.ts
                                         └─▶ analyzerAdapter.ts → @gdscript-analyzer/core (AnalysisHandle)
                                              completions · hover · diagnostics · gotoDefinition   [4 of 13 wired]
```
- Headless/offline/deterministic. `setProjectConfig(project.godot)` resolves `[autoload]`; `loadLibrary(res://…)`
  loads `addons/**/*.gd` so embedded code resolves cross-file (`Hooks.use_ref` → `core/hooks.gd`).
- UTF-16 ↔ UTF-8 byte-offset conversion is owned at the adapter boundary (the analyzer speaks byte offsets).
- The compiler's full diagnostic catalog is surfaced offline via the `Foo.guitkx.diags.json` sidecar (FNV-1a
  hash-gated), independent of the analyzer.

---

## Parity — baseline (2026-06-21) → now (2026-06-30)

| Area | Baseline | Now | Notes |
|---|---|---|---|
| Core library | 62% | **~parity** | PHASE_7 COMPLETE. Left: custom-draw hatch, niche adapters |
| GDScript fidelity | 45% | **high** | scope-aware virtual doc shipped; backend is now `@gdscript-analyzer/core` |
| Compiler | 25% | **~90%** | PHASE_4 COMPLETE: jsx-as-value, module, full diagnostics catalog |
| LSP features | 15% | **high** | ClassDB completion, index, goto, refs/rename (markup), diagnostics, symbols, sig-help, semantic tokens + embedded GDScript via analyzer |
| Formatter | 3% | **DONE** | PHASE_5: GDScript authority + byte-identical TS port |
| Publishing | 15% | **DONE** | PHASE_3: changelog.json + idempotent version-gated publish workflow |
| HMR | 25% | **partial** | Godot-native reload works; live-root re-render + hook-shape guard still open (PHASE_8) |
| Tests | 28% | **~40%** | per-suite green, but no golden codegen corpus / rules-of-hooks matrix (PHASE_10) |
| Docs/samples | 8% | **low** | README stale; no docs site (PHASE_9) |

Guiding constraints (unchanged): full GDScript everywhere embedded (not a subset), GDScript-in-markup, all Control
types, pure GDScript, audience = everyone. Goal = ReactiveUIToolKit's *capabilities*, not an MVP.

---

## Forward roadmap — user-set order (2026-06-30)

**0. Update the stale plans ← (in progress this session).** This file refreshed; correction banners added to
   `PHASE_2_GUITKX_PLAN`, `PHASE_4_DESIGN`, `PHASE_5_6_DESIGN`, `IDE_EXTENSION_ISSUES`.

**1. G1 — complete the analyzer swap.**  *(status — 2026-06-30)*
   - ✅ **Bumped `@gdscript-analyzer/core` → 0.5.1** in `lsp-server`; verified no `AnalysisHandle` API drift (36 tests green).
   - ✅ **Wired the embedded-GDScript analyzer queries**: find-references, rename (**correct-or-refuse**, file-local
     only), signatureHelp, inlayHints, codeActions — on top of the existing completion/hover/diagnostics/gotoDefinition.
     **9 of 13** capabilities now analyzer-backed; the rest (foldingRanges/documentSymbols/workspaceSymbols/syntaxTree)
     are owned by the markup-level handlers or N/A for the embedded surface. (`analyzerAdapter.ts` + `server.ts`.)
   - ✅ **format/formatRange + semanticTokens** — shipped in `@gdscript-analyzer/core` **0.5.2** (`#[napi]` +
     `#[wasm_bindgen]` delegators) and consumed: `.gd` formatting (`textDocument/formatting` + rangeFormatting →
     `analyzer.format`/`formatRange`) and semantic tokens (a unified legend over markup + GDScript) are now wired.
   - ✅ **Drive plain `.gd`** — DONE for VS Code (opt-in `guitkx.enableGdscriptAnalysis`, default off). Dedicated
     `.gd` handlers in `server.ts` (offsets 1:1; **project-wide** `.gd` load at init so cross-file nav + rename
     resolve), wiring diagnostics / completion / hover / definition / **project-wide references + rename** /
     signatureHelp / inlayHints / codeActions / documentSymbols + **formatting + semantic tokens** (analyzer-backed
     via core 0.5.2's `format`/`semanticTokens`). Runs alongside `godot-tools` — the setting tells the user to
     disable it to fully swap. **VS 2022 `.gd`
     registration deferred** (low value — VS 2022 is a `.guitkx`-authoring tool; `.gd` editing lives in VS Code / Godot).
   - ◻ Clean the stale "forwarded to Godot's LSP" comments in `context.ts`/`virtualDoc.ts`/`sourceMap.ts` (fold into G3).

**2. G2 — finish the library.**
   - Port the **custom-draw escape hatch** (`onGenerateVisualContent` / `_draw` + `redraw_key`) from the Unity 0.6.3
     sibling → Godot `_draw()` / `RenderingServer` + `redraw_key`.
   - Refresh the **stale README** to the real surface (21+ hooks, ~14 router hooks, 63 `V.*` factories, router /
     signals / suspense / styles / adapters).
   - Decide the niche adapters (SubViewport / GraphEdit / GraphNode) — port or explicitly defer.
   - Close Tests (PHASE_10) + Docs (PHASE_9) parity.

**3. G3 — finish `.guitkx → .gd`; native editor support is a SEPARATE future plan.**
   - The compile-on-save EditorPlugin is done; harden + update stale in-code docs (the `guitkx.gd` "walking
     skeleton" docstring, the schema's `module = reserved` note — both now implemented).
   - **Native Godot-editor syntax understanding = deferred planning track** (per the user): an
     `EditorSyntaxHighlighter` (pure GDScript, highlighting only) vs a `ScriptLanguageExtension` (C++/GDExtension,
     full intelligence). To be designed in its own plan when G1/G2 land.

---

## Phase history (3–10) — status as of 2026-06-30

### Phase 3 — Publishing & release infrastructure — **DONE**
`ide-extensions/changelog.json` + `scripts/changelog.mjs` + `publish-extensions.yml` (workflow-dispatch, idempotent
per-extension version gating, VS Marketplace + Open VSX + VS2022 VsixPublisher, auto-tag) + local publish scripts +
`VERSIONING_PROCESS.md`. (The publish workflow is healthy; jobs are version-gated and *skip* when a version is not
bumped — that is by design, not a regression.)

### Phase 4 — Compiler parity + embedded-GDScript fidelity — **DONE** (see PHASE_4_DESIGN)
JSX-as-value splicing, setup-embedded markup, scope-aware virtual doc, module declarations, full `GUITKX####`
diagnostics catalog, hook-alias token-boundary fix, fidelity leaf fixes + byte-identity CI. **Backend correction:**
the virtual doc is now consumed by `@gdscript-analyzer/core`, not Godot's LSP.

### Phase 5 — Formatter — **DONE** (see PHASE_5_6_DESIGN)
In-process TS formatter (`formatGuitkx.ts`) kept byte-identical with the GDScript authority
(`guitkx_formatter.gd`) via a shared golden corpus; `textDocument/formatting` + rangeFormatting; optional gdformat
Tier-1 embedded reflow. Verbatim-on-parse-error; idempotent. (Open: an analyzer-driven embedded reflow once the
napi `format` delegator lands — see Roadmap G1.)

### Phase 6 — LSP feature depth — **DONE v1** (see PHASE_5_6_DESIGN)
ClassDB-driven completion, workspace index + go-to-definition, live dup-key/unknown-element diagnostics,
find-references + rename + prepareRename, documentSymbol, signatureHelp, semanticTokens, compiler-diagnostics
sidecar. **Note:** refs/rename/symbols here are *markup-level* (component tags); the embedded-GDScript equivalents
are the G1 "wire the remaining analyzer queries" work.

### Phase 7 — Core library breadth — **DONE** (see PHASE_7_PLAN)
Router rewrite (nested/layout routes, `<Outlet>`, basename, query, blockers, NavLink, full `use_*` router hooks),
signal registry, Suspense, dev diagnostics + strict flags, `V.text`/`V.memo`, remaining hooks
(`use_deferred_value`/`use_transition`/`use_animate`/`use_sfx`), `V.audio`/`V.video`, item-model adapters. Left for
G2: custom-draw hatch, niche adapters, README.

### Phase 8 — HMR hardening — **PARTIAL**
Godot-native reload works; the live-root re-render registry + hook-shape-change guard + effect-cleanup-on-reload
remain open. Low priority unless a consumer hits the footguns.

### Phase 9 — Documentation & samples — **OPEN**
Docs site / structured `docs/`, `.guitkx` language guide, per-component reference, style vocabulary; port a subset
of the Unity samples; **refresh the stale README** (folded into G2).

### Phase 10 — Test parity — **OPEN**
Formatter idempotency + snapshot tests, golden codegen corpus (replace substring asserts), rules-of-hooks
loop/switch/handler matrix, virtual-doc/source-map round-trip breadth, consolidated runner + CI aggregation.

---

### Sequencing
Plans first (0), then the G1 complete-swap, then G2 (library finish + docs), then G3 cleanup; native Godot-editor
support is designed in its own plan afterward. Each step ships green tests before the next.
