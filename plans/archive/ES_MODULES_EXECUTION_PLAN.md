# ES-Modules Layer 2 — Godot leg (.guitkx) — EXECUTION PLAN

> **Family contract:** `plans/ES_MODULES_GENERAL_PLAN.md` (owner-approved 2026-07-17, copied
> VERBATIM into this repo). That document's locked decisions **G-01..G-13 BIND this plan**; this
> plan adds Godot detail and may NOT contradict it. **Any conflict = STOP AND ASK the owner.**
> **Status:** authored 2026-07-17; every anchor below verified by grep/read against the live tree
> the same day (runtime addon 0.10.2, editor addon 0.8.1, extensions 0.10.3), then independently
> re-audited 2026-07-17 (anchors re-confirmed; missed touch points added: declarations.ts,
> context routing both sides, bundled schema copy, editor_view probes, CI workflows; sidecar
> invalidation mechanism corrected in M2.3); §4's 2320-band harmonized the same day to the
> family-canonical Unreal-audited allocation (one wrapper warn, merged undeclared-export code,
> new alias-collision code, 2322 reserved-not-emitted). Re-verify anchors only if the tree moved.
> **Branch:** one branch `feat/guitkx-es-modules` off `origin/dev`, one PR into `dev`, master
> fast-forward at release (repo flow since 2026-07-03: feature → dev → master; master is
> release-only).
> **Rollout order (G-13):** Unreal → **Godot** → Unity. Legs may run in parallel ONLY after M0's
> family gates (corpus cases + diagnostic allocations pinned) are green.
> **House rules:** research → develop → test → bughunt → fix → commit per milestone;
> production-grade only; never weaken a gate; do NOT commit/push without an explicit owner ask.
>
> **This repo's delta is Layer 2 only.** Strict imports shipped here in 0.10.0
> (`plans/archive/IMPORT_EXPORT_PLAN.md` — read it once for mechanism context; do NOT redo its
> work). What remains: (a) remove the `component` / `hook` / `module` wrapper keywords in favor
> of plain, signature-classified declarations (G-03), (b) add value exports (NEW — no `.guitkx`
> surface can export a plain constant today), (c) the full ES import surface (G-05 — `* as`,
> default, rename-as, deferred export lists; a dated SUPERSEDE of 0.10.0's named-only lock),
> (d) the deprecation window + codemod (G-10), (e) the full sync surface (G-12).

---

## 0. Locked decisions — family echo (G-01..G-13) + Godot-local decisions (E-01..E-12)

### 0.1 Family echo (Godot reading; full text in `ES_MODULES_GENERAL_PLAN.md` — that text wins)

- **G-01 — File = module.** Exports are the file's whole public surface; module identity = file
  path. Renaming a file changes module AND hot-reload identity of its private members —
  documented, accepted (see M4's rename re-verification: this repo's flat class registry makes
  renames MORE load-bearing than on the other legs).
- **G-02 — One visibility mechanism.** Imports only. Hand-written `.gd` (`class_name` scripts:
  DoomTypes, DoomTextures, …) stay AMBIENT per rule A4 — never policed, never imported.
- **G-03 — Wrapper keywords removed.** Classification from the SIGNATURE ALONE at parse time:
  `-> RUIVNode` return ⇒ component (PascalCase ENFORCED); `use_`-prefixed name ⇒ hook; `=` after
  the name ⇒ value export; anything else ⇒ util function. Cross-guards are errors.
- **G-04 — Native idiom.** GDScript spelling: `-> Type` return annotations (ALREADY-SHIPPED
  grammar — `_parse_hook_at` ret_hint, `guitkx.gd:1266-1272`) + `: Type =` / `:=` value
  annotations. `:=` is this leg's inference sugar (the initializer types it).
- **G-05 — Full ES import surface** (supersedes "named exports only"): named, `{ a as b }`
  rename, `* as X` namespace, default import + `export default <Name>`, deferred `export { a, b }`
  lists. Re-exports (`export { a } from "./x"`) stay DEFERRED. Specifiers stay extensionless
  `./ ../ ~/` only; preamble-only; 2308 boundary rule unchanged.
- **G-06 — Privacy is real.** Un-exported ⇒ no `class_name`, no global registration (shipped
  0.10.0 semantics — keep). Runtime/HMR identity for private members keys on FILE + name (G-09).
- **G-07 — Escape hatches stay.** **`@class_name` is KEPT.** This plan ANSWERS the decision
  tabled in `plans/MASTER_PLAN.md` §2.3: **keep the directive, revisit removal later** (it is the
  binding/collision/interop hatch AND this leg's module-migration tool — see M6). M8 records the
  answer in MASTER_PLAN.
- **G-08 — Eager/lazy is kind-driven (the Godot parity rule, family-wide).** Component references
  stay LAZY via `V.comp(path, fn)` path-keyed Callables (`v.gd:41-46`) — component cycles stay
  legal. Value/hook/util references stay EAGER `const … = preload(…)` lowerings — value cycles
  stay GUITKX2306 (TDZ-parity policy). Nothing in this leg may flip a component reference eager.
- **G-09 — Hot-reload identity** = exported name (unique via 2106) for exports; file+name for
  privates. Signature change still resets hook state (`__RUI_HOOK_SIG` / per-decl `sig` compare).
- **G-10 — Deprecation window.** Old wrapper syntax parses for ONE minor with deprecation
  diagnostics from the family block **2320–2329**; idempotent codemod ships in the SAME release;
  removal later, owner-triggered.
- **G-11 — Versions:** runtime addon `0.10.2 → 0.11.0` (minor). Other lanes per §M8.
- **G-12 — Full sync surface is part of DONE** — §M8 + §9 checklist; family corpus hash re-pinned
  IN LOCKSTEP across the three repos.
- **G-13 — Order Unreal → Godot → Unity;** parallel only after the corpus cases for the new
  grammar are agreed and pinned (M0 gate).

### 0.2 Godot-local decisions (do not re-litigate mid-execution; conflicts with G-* = G-* wins)

- **E-01 — Plain-declaration grammar** (one decl = one of):
  - callable: `[export] Name[(params)] [-> Type] { body }`
  - value: `[export] Name = expr` | `[export] Name: Type = expr` | `[export] Name := expr`
  Classification order (parse-time, signature-only, NO body inspection): (1) `=`/`: Type =`/`:=`
  after the name ⇒ **value**; (2) return annotation exactly `RUIVNode` ⇒ **component**; (3) name
  begins `use_` ⇒ **hook**; (4) else ⇒ **util**. Consequence (documented, taught, codemod-enforced):
  **a component MUST annotate `-> RUIVNode`** — a PascalCase callable without it is a util (the
  price of no-body-inspection classification; the codemod adds the annotation when rewriting
  `component X {}`, and the docs/Reference page teach it as the component signature).
- **E-02 — Cross-guards (errors):** `use_` prefix + `-> RUIVNode` ⇒ GUITKX2321 ("did you mean a
  component?"); `-> RUIVNode` + non-PascalCase ⇒ the EXISTING GUITKX2100 (message unchanged,
  `guitkx.gd:748-750`) — no new code minted for that guard.
- **E-03 — GUITKX2203 (`use_` naming warning) retires with the wrappers.** Under E-01 the prefix
  IS the classification — a helper without `use_` is simply a util, no warning. 2203 keeps firing
  only on deprecated `hook` wrapper decls during the window; registry row stays (number reserved),
  divergence note per the 0103-retirement precedent (`plans/archive/CLASSNAME_CLEANUP_PLAN.md`).
- **E-04 — Value/util extent:** value decl extent = the initializer expression — brace/bracket/
  paren-matched when it opens with `{`/`[`/`(`, else to end of line (GDScript-lexis, strings
  skipped). Util/hook/component extent = existing brace-matched body (`_decl_body_end`,
  `guitkx.gd:620-644`; its hook-only `->` branch at `:628-631` generalizes to ALL callables).
- **E-05 — Value exports emit `static var Name[: Type] = expr`** (NOT `const`): GDScript `const`
  rejects non-constant-foldable initializers (user-func calls) and we cannot verify foldability at
  parse time; `static var` is uniformly valid, initializes eagerly at script load (exactly the
  TDZ/2306 semantics G-08 wants), and is reachable cross-file via `preload(gd).Name`. Importer
  side stays `const X = preload(…)` — unchanged. If the owner prefers `const`-when-foldable,
  STOP AND ASK before building it.
- **E-06 — Namespace imports (`* as X`) address values/hooks/utils only in v1.** Setup/`{expr}`
  references `X.name(…)` lower via ONE eager `const X = preload("<target>.gd")` (a VALUE edge —
  participates in the 2306 DFS). Namespace-qualified component TAGS (`<X.Comp/>`) are NOT v1 —
  component tags require named/default imports (keeps every tag lowering on the lazy `V.comp`
  path). If the Unreal leg ships namespace component tags, STOP AND ASK before diverging.
- **E-07 — Default exports:** `export default Name` — a top-level line, at most one per file
  (duplicate = GUITKX2327), `Name` must be a declared top-level decl (else GUITKX2323).
  `import X from "./f"` binds the
  default under local name `X` and lowers per the default decl's KIND (component ⇒ `V.comp`
  lazy; value/hook/util ⇒ const-preload eager). Formatter canonical position: directly after the
  last declaration.
- **E-08 — Rename-on-import `{ a as b }`:** binds local `b` to export `a`. Lowering: component ⇒
  `known[b] = { gd, func: <a's func> }` (tag `<b/>` → `V.fc(V.comp(gd, func))`); value ⇒
  `const b = preload(gd).a`; bare hook ⇒ alias-rewrite `b(` → `__RUI_IMP_<hash>.a(` (the existing
  `_lower_hook_imports` map, `guitkx.gd:518-530`, gains distinct local/remote names). A local
  alias — `b` here, or a `* as X` / default-import name — that collides with an in-file
  declaration or another import = GUITKX2325.
- **E-09 — Deferred export lists:** `export { a, b }` — top-level line(s), names must be declared
  in-file (GUITKX2323), duplicate export of an already-exported name = GUITKX2324. Mixable with
  inline `export`. Position: anywhere at top level; formatter canonicalizes to directly above the
  first declaration.
- **E-10 — Binding model UNCHANGED** (0.10.0 rules): binding = `@class_name` override, else first
  EXPORTED decl's name, else "" (fully-private file ⇒ no `class_name` emitted). The binding
  component still emits as `render`; `render_component()` (`guitkx.gd:1388`) stays the single
  source of truth. Value/util decls CAN be the binding decl (first exported) — the class is still
  named after them; nothing else changes.
- **E-11 — `__RUI_DECLS` shape is PRESERVED** — `{ "<name>": { "kind", "sig"?, "export" } }`
  (`guitkx.gd:1513-1522`) and the resolver decl-table `{ kind, export, func }`
  (`guitkx_resolve.gd:42-47`) gain only two new `kind` strings, `"value"` and `"util"`, plus a
  file-level `"default"` key in sidecar/exports. NO key renames, NO shape change — this bounds the
  HMR/LSP blast radius (hmr.gd reads it via `get_script_constant_map()` — `hmr.gd:210-215`).
- **E-12 — Wrapper-decl emission is BYTE-FROZEN during the window.** A file still using
  `component`/`hook`/`module` wrappers compiles through the EXISTING paths with byte-identical
  output (plus nothing — deprecation diags are sidecar/warning-only, never emitted into `.gd`).
  Contract fixtures pin this (§9).

---

## 1. Where the repo starts — verified anchors (2026-07-17)

Compiler monolith `addons/reactive_ui/guitkx/guitkx.gd`:

| Anchor | Line(s) | Role in this leg |
|---|---|---|
| `compile()` | 138 | entry; preamble loop 174-235; import resolution 242-250; strict-2305 sweep 256-274; decl dispatch 276-314; value-import insertion 319-325 |
| `_find_decl` | 341-366 | keyword scan + `export` prefix — REPLACE with signature-driven scan (M1) |
| `_parse_import_at` | 374-426 | named-only `{ a, b } from "spec"` — EXTEND (`as`, `* as`, default) |
| `import_specifier` / `_relative_specifier` | 435 / 446 | canonical specifier — unchanged |
| `scan_imports` | 463 | graph-truth preamble scan — extend for new forms |
| `_insert_value_imports` / `_insert_after_banner` | 488-497 / 501-512 | eager const lowering — reused by `* as` / default-value / rename |
| `_lower_hook_imports` / `_rewrite_bare_calls` | 518-530 / 535-557 | bare-hook alias rewrite — gains rename (E-08) |
| `_name_referenced` | 561-588 | 2304 unused-import drive — must learn `X.` namespace refs |
| `_enumerate_decls` / `_decl_body_end` | 594-615 / 620-644 | decl enumeration — value extent (E-04); `->` branch 628-631 generalizes |
| `_nearest_decl_keyword` (2101 hint) | 661-686 | did-you-mean — retarget messages for keywordless grammar |
| `_compile_component` / `_parse_component_at` (2100 at 748-750) | 707 / 735 | single-decl path — frozen for wrappers (E-12); plain components join via classification shim |
| `_compile_hook` / `_parse_hook_at` (ret_hint 1266-1272) | 1219 / 1242 | same; `-> Type` grammar already shipped here |
| `_compile_module` (member loop 1311-1346; module-2105 at 1320) | 1285 | wrapper path — frozen; modules allow ONLY component/hook members today (so value exports are new EVERYWHERE, incl. modules) |
| `render_component` | 1388 | binding-component truth — unchanged (E-10) |
| `_compile_mixed` (emit header 1506-1527: `__RUI_DECLS` 1513, `__RUI_KIND := "mixed"` 1523, `__RUI_HOOK_SIG` 1527) | 1410 | THE emitter plain decls route through — gains value/util emission |
| `_emit_module_inner` | 1632 | inner-class module emission — frozen (wrapper window) |
| `_emit` (single-component header; `__RUI_HOOK_SIG` 2156, `__RUI_KIND` 2162) | 2144 | frozen byte-shape for single-decl files |
| `_hook_signature` | 2173 | Fast-Refresh fingerprint — UNTOUCHED (family key stability) |
| `_apply_hook_aliases` | 3127 | intra-file hook aliasing — unchanged |
| `_ret_suffix` | 3166 | `-> Type` emission — reused by utils |

Codegen `addons/reactive_ui/guitkx/guitkx_codegen.gd`:

| Anchor | Line(s) | Role |
|---|---|---|
| `write_diags_sidecar` (schema v3) | 38-64 | sidecar → v4: exports rows gain `kind: value/util`, file gains `default` (M2) |
| `exports_of` / `export_hash` | 68-83 / 84-102 | export table + reverse-edge staleness hash — must cover new kinds + default marker |
| `is_stale` / `_read_sidecar_raw` / `sidecar_error_diags` | 104 / 126 / 154 | staleness is mtime + src_hash ONLY (no `v` read) — the v4 rewrite rides the compiler-fingerprint force (`compiler_changed:284`, `_COMPILER_SOURCES:246-254`; see M2.3) |
| `_binding_name` (order-agnostic preamble skip) / `_skip_import_span` | 324-368 / 369-391 | binding scan — must skip `export default` / `export { … }` lines too (M1, FIRST — every identity table keys on it) |
| `project_bindings` (2106 arbitration) | 398-440 | exported-names-only ledger — unchanged semantics, new kinds flow through |
| `compile_file` (`parse_check` deferral) | 441 | two-pass seam — unchanged |
| `compile_all` (2106 emission 547-611) | 536 | sweep — M4 re-verifies under more eager symbols |
| `_compute_refresh_roots` / `_reverse_edge_stale` / `_value_import_edges` / `_detect_value_cycles` | 699 / 746 / 776 / 797 | HMR roots + staleness + 2306 DFS — value/namespace/default-value edges join `_value_import_edges` |
| `find_all` / `_is_orphaned_output` / `_remove_orphaned_output` | 817 / 856 / 877 | rename-ghost cleanup helpers (M4) |

Resolver `addons/reactive_ui/guitkx/guitkx_resolve.gd`: `resolve_specifier:20`,
`decl_table:47` (shape `{ binding, decls: { name -> { kind, export, func } } }` — E-11),
`_binding_of:67`, `_class_name_override:79`, `_skip_import:111`, `resolve_file_imports:137`
(returns `{ comps, values, hooks, diags }` — gains `ns` + `default` resolution),
`referenced_names:192`, `value_cycle:223` (2306 chain printer).

Other GDScript:

- `addons/reactive_ui/core/v.gd` — `comp(path, fn)` + `_comp_cache` keyed `path::fn` (40-46):
  UNCHANGED (the lazy mechanism G-08 preserves).
- `addons/reactive_ui/core/hmr.gd` — `apply:58` (value-decl change → refresh_roots targeting,
  110-122; BH-15 sig-reset independence 123-129); `_inject_unregistered_bindings:143` (const-
  injection dedupe `_has_const_decl:203` — M5 re-audit: must ALSO skip `static var` decls);
  `_hook_sig:181`; `_is_module:191`; `_has_value_decl:210` (reads `__RUI_DECLS` for hook/module
  kinds — gains `"value"`).
- `addons/reactive_ui/guitkx/guitkx_formatter.gd` — `format:30`, `_format_or_verbatim:38`
  (preamble canonicalization 39-77: `@class_name`-only; imports/`export` prefix take the verbatim
  branch; single-decl dispatch 83-101; trailing-content verbatim rule 108-113): M1 rewrites the
  decl dispatch around classification; new-form preamble lines must stay verbatim-preserved,
  never reordered.
- `addons/reactive_ui/guitkx/guitkx_migrate.gd` — `migrate_all:21`, `migrate_source:44` (export-
  prefix + import insertion; BH-03 `start`-vs-`at` insertion), `_scan_references:97`,
  `_specifier:132`: M6 EXTENDS this file (wrapper-removal pass) + new runner
  `addons/reactive_ui/dev/migrate_0_11_0.gd` (precedent: `dev/migrate_0_10_0.gd`).
- `addons/reactive_ui/guitkx/guitkx_lexer.gd` — `skip_noncode:56`, `find_matching:122`,
  `skip_noncode_markup:152`, `find_matching_markup:205`, `keyword_at:338`: reused as-is; NO lexer
  grammar change expected (new keywords `as`, `default` are contextual — parsed positionally).
- `addons/reactive_ui/guitkx/vocabulary.json` + `guitkx_vocabulary.gen.gd` (265 lines) — 23xx
  rows end at 2309 today; **232x block is FREE (verified: zero hits)**. Regen via
  `godot --headless --path . --script res://addons/reactive_ui/dev/gen_vocabulary.gd`
  (**FLAG: commits the .gen.gd**). Mirror copy: `ide-extensions/lsp-server/src/vocabulary.json`
  (byte-identical, test-enforced).

Editor addon `addons/reactive_ui_editor/`:

- `plugin.gd` — `_on_file_moved:165` → `cleanup_moved_guitkx:178-195` (rename ghost-registration
  cleanup: removes the old name's orphaned `.gd`/sidecar synchronously). **File=module makes
  renames MORE load-bearing** — M4 adds an explicit re-verification milestone item.
- `lsp/guitkx_workspace.gd` — `_decl_re:15-23` (regex `(?:export[ \t]+)?(component|hook|module)…`
  — the wrapper-keyword assumption to replace), `_cn_re:24-26`, index consume at 86-95.
- `lsp/` suite: `guitkx_completion.gd`, `guitkx_hover.gd`, `guitkx_outline.gd`, `guitkx_refs.gd`,
  `guitkx_scan_diags.gd`, `guitkx_signature.gd`, `guitkx_virtual_doc.gd` (header const synthesis —
  length-preserving map), `guitkx_config.gd`, `guitkx_source_map.gd`, `guitkx_analyzer_bridge.gd`.
- `lsp/guitkx_context.gd` — cursor-context routing: body-brace vs `{expr}` classification at
  164-187 assumes a body `{` is preceded by `)` / `else` / `default` / **`module <ident>`**
  (special case at 181-187). Plain paramless decls (`Name {`, value `Name := {`) break the
  heuristic — M1 must retarget it (mirror: `isBodyBrace`, TS side).
- `lsp/guitkx_schema.gd` — loads the grammar schema from a **bundled copy**
  `addons/reactive_ui_editor/data/guitkx-schema.json` (dev fallback to
  `ide-extensions/grammar/guitkx-schema.json`); the schema's `keywords` rows name
  component/hook/module (`guitkx-schema.json:9-11`) and drive keyword completion/hover — BOTH
  copies change in M1.5 (a "schema sync" tripwire in `tests/guitkx_editor_test.gd` guards them).
- `editor/guitkx_editor_view.gd` — `_basename()` scratch-buffer identity probe `_decl_probe`
  regex `(?:component|hook|module)[ \t]+ident` at :764 (wrapper-only, no `export` prefix) and the
  tokenizer-kind dispatch at :266-268 — both learn plain decls in M1.
- `editor/guitkx_tokenizer.gd` + `guitkx_code_highlighter.gd` — wrapper keywords + `export`/
  `import` highlighting; gain `as` / `default` / value-decl faces, lose nothing during the window.
- `editor/guitkx_problems_panel.gd` + `guitkx_diagnostics_renderer.gd` — verified code-agnostic
  (severity/code pass-through rows); the new 232x warns flow through with NO change needed.

TS mirrors `ide-extensions/`:

- `lsp-server/src/declScan.ts` — `DECL_KEYWORDS:16`, `nearestDeclKind:45`, `findDecl:84`
  (keyword-driven — the M1 mirror of the GD classification rewrite).
- `lsp-server/src/workspaceIndex.ts` — `scanDeclarations:37`, `readClassName:104`,
  `guitkxVirtualLibText:255`, `componentTagAt:312`.
- `lsp-server/src/formatGuitkx.ts` — `formatGuitkx:40` (+ `guitkxFormat.ts` glue).
- `lsp-server/src/importNav.ts` — `importAt:18`, `importRoot:46`, `resolveSpecifier:67` (new
  clause shapes: `* as X`, default, `as` — go-to-def must hit through all of them).
- `lsp-server/src/declarations.ts` — LIVE decl-header validation (the "file goes dark on a typo"
  floor): its OWN keyword list `DECL_KWS:22` + `nearestDeclKeyword:26`, mirrors
  `_find_decl`/`_nearest_decl_keyword` — must learn plain-decl headers + the 2320 window
  warn, or every new-style file mis-flags live (M1 mirror alongside `declScan.ts`).
- `lsp-server/src/semanticTokens.ts` — `isBodyBrace:143-162` is THE TS body-brace vs `{expr}`
  test (`kw === "component"|"hook"|"module"` at :162) and is ALSO imported by `context.ts`
  (:6/:48/:87) for cursor-context routing — one retarget fixes both (mirror of
  `guitkx_context.gd`).
- `lsp-server/src/scanner.ts`, `server.ts`, `virtualDoc.ts`, `diagsSidecar.ts` (v-accept list
  `j.v === 2 || j.v === 3` at :45 — must accept 4 in M2.3) — consumers of the above.
- Grammar/schema (shared): `ide-extensions/grammar/guitkx.tmLanguage.json` +
  `ide-extensions/grammar/guitkx-schema.json`; VS Code copy
  `ide-extensions/vscode/syntaxes/guitkx.tmLanguage.json` (plain committed copy — no prebuild
  sync script; update it by hand) + bundled editor-addon schema copy
  `addons/reactive_ui_editor/data/guitkx-schema.json`.
- Corpus: `ide-extensions/lsp-server/test-fixtures/guitkx-scanner-cases.json`
  (`_tiers.familyCore = ["skipNoncodeMarkup","findMatchingMarkup","fileScan"]`) +
  `guitkx-formatter-cases.json`; gate `scripts/corpus-hash.mjs` + `plans/family-corpus.hash`
  (current pin `917dd8cd…de52169`).

Tests: `tests/guitkx_build.gd` (two-pass + counted parse gate — pass 1 `parse_check=false`,
pass 2 `gd_path_parses`, exits 1), `tests/guitkx_test.gd`, `tests/hmr_test.gd`,
`tests/demos_test.gd`, `tests/doom_game_test.gd`, `tests/guitkx_editor_test.gd` (changelog
byte-mirror tripwire :370-375; "schema sync" tripwire for the bundled schema copy),
`tests/guitkx_lsp_test.gd`, `tests/core_test.gd`,
`tests/contract_dump.gd -- --check` (66 committed goldens under `tests/contract/golden/`,
fixtures under `tests/contract/fixtures/`), `tests/guitkx_migrate.gd` (0.10.0 codemod runner —
stays idempotent-0 on a migrated tree).

CI workflows `.github/workflows/`: `test.yml` (engine-free corpus-hash gate :35-39 +
per-suite headless steps in the SAME two-pass class-cache order as §10 — any suite this leg
adds/renames must land there too; note it currently runs neither `doom_game_test.gd` nor
`guitkx_migrate.gd`), `ide-extensions.yml` (changelog verify + lsp build/test/smoke + vsix
package), `publish.yml` (release packaging — version bumps flow through). Owning milestone M8.

Docs site `ReactiveUIGodotDocs~/src/pages/UITKX/`: `Imports/UitkxImportsPage.tsx` (+
`.example.ts`), `CompanionFiles/CompanionFilesPage.tsx` (+ `.example.ts`),
`Reference/UitkxReferencePage.tsx`, `Diagnostics/UitkxDiagnosticsPage.tsx` (+ every page whose
examples use wrapper keywords — enumerate by grep in M8).

Versions/changelogs: `addons/reactive_ui/plugin.cfg` 0.10.2; `addons/reactive_ui_editor/plugin.cfg`
0.8.1; `ide-extensions/vscode/package.json` + `lsp-server/package.json` 0.10.3; VS2022
`ide-extensions/visual-studio/GuitkxVsix/…vsixmanifest` 0.10.3. Root `CHANGELOG.md` +
`addons/reactive_ui/CHANGELOG.md` (byte-mirror), `addons/reactive_ui_editor/CHANGELOG.md`,
`ide-extensions/changelog.json` (+ `node ide-extensions/scripts/changelog.mjs verify`),
`plans/DISCORD_CHANGELOG.md` (≤2000 chars per entry). `MIGRATION-0.9.md` / `MIGRATION-0.10.md`
exist at repo root — this leg adds `MIGRATION-0.11.md`.

---

## 2. Grammar — Godot dialect (the G-03/G-04/G-05 shapes)

### 2.1 A full new-style file (transliterates the contract's §3 reference example)

```guitkx
import { format_time } from "../shared/time_utils"
import { StatusChip as Chip } from "./status_chip"
import * as HudStyles from "./hud_styles"

export container := { "theme_type_variation": "PanelDark" }   # value — := inference
export MAX_ITEMS: int = 5                                     # value — typed
export theme = { "modulate": Color(0.5, 0.5, 0.5) }           # value — plain `=`

export format_score(score: int) -> String {                   # util — no use_, no RUIVNode
	return "Score: %d" % score
}

export use_countdown(start: int) -> Dictionary {              # hook — use_ prefix
	var pair = Hooks.useState(start)
	return { "value": pair[0], "reset": func(): pair[1].call(start) }
}

row_style := { "custom_minimum_size": Vector2(0, 24) }        # value, un-exported — file-private

export ScoreRow(label: String) -> RUIVNode {                  # component — -> RUIVNode
	return (<Label text={label}/>)
}

ScorePanel(title: String) -> RUIVNode {                       # private component
	var cd = use_countdown(MAX_ITEMS)
	return (
		<PanelContainer theme_type_variation={HudStyles.panel_variation}>
			<Label text={format_score(cd.value)}/>
			<ScoreRow label={format_time()}/>
		</PanelContainer>
	)
}

export default ScorePanel
```

- Preamble unchanged: imports + `@class_name` + `@uss`/`@theme`, any order, before the first
  decl (2309 preamble rule unchanged). `export { a, b }` lists and `export default X` are
  TOP-LEVEL lines (not preamble-bound), E-07/E-09.
- Content between declarations that is not a decl stays GUITKX2105.

### 2.2 Import-surface table (G-05)

| Form | Example | Lowering (per target kind) |
|---|---|---|
| named | `import { ScoreRow } from "./score"` | component ⇒ `V.comp(gd, fn)` tag path; value ⇒ `const ScoreRow = preload(gd).ScoreRow`; bare hook ⇒ `__RUI_IMP_*` alias rewrite (all SHIPPED — unchanged) |
| rename | `import { StatusChip as Chip } from "./status_chip"` | same as named with local/remote split (E-08) |
| namespace | `import * as X from "./hud_styles"` | ONE eager `const X = preload(gd)`; members `X.name` resolve as script statics; VALUE edge for 2306; no component tags via `X.` in v1 (E-06) |
| default | `import Panel from "./score_panel"` | binds the target's `export default` decl under `Panel`; lowers per that decl's kind (E-07) |
| deferred list | `export { container, MAX_ITEMS }` | export marker only — no lowering of its own (E-09) |
| default marker | `export default ScorePanel` | export-table `default` entry (E-07) |
| re-export | `export { a } from "./x"` | **DEFERRED — do not implement** (G-05) |

### 2.3 Deprecated (window) syntax — G-10

`component X(…) { … }`, `hook use_x(…) [-> T] { … }`, `module M { … }` (with or without
`export`) keep parsing for the 0.11 minor, compile byte-identically through the frozen legacy
paths (E-12), and emit ONE GUITKX2320 warning per wrapper decl (arg = the wrapper kind).
Removal is a LATER minor, owner-triggered.

---

## 3. Emission shapes — exact before/after `.gd`

### 3.1 Wrapper file (window) — BYTE-IDENTICAL, before and after this leg

```gdscript
class_name DoomFace
extends RefCounted
## AUTO-GENERATED from doom_face.guitkx -- do not edit.

const __RUI_HOOK_SIG := "useState|useEffect"

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RUIVNode: …
```
(the `_emit` path, `guitkx.gd:2144-2166` — pinned by the existing contract fixtures; only the
sidecar gains 2320-family warning rows.)

### 3.2 New-style mixed file (the §2.1 example `score_panel.guitkx`) — NEW shape

```gdscript
class_name container                       # binding = first EXPORTED decl (E-10; here a value —
extends RefCounted                         # @class_name overrides when that reads badly)
## AUTO-GENERATED from score_panel.guitkx -- do not edit.
const format_time = preload("res://shared/time_utils.gd").format_time   # value imports (eager)
const Chip = preload("res://ui/status_chip.gd")                          # rename: local const, remote fn addressing
const HudStyles = preload("res://ui/hud_styles.gd")                      # namespace import (eager)

const __RUI_DECLS := {
	"container":    { "kind": "value", "export": true },
	"MAX_ITEMS":    { "kind": "value", "export": true },
	"theme":        { "kind": "value", "export": true },
	"format_score": { "kind": "util", "export": true },
	"use_countdown":{ "kind": "hook", "export": true },
	"row_style":    { "kind": "value", "export": false },
	"ScoreRow":     { "kind": "component", "sig": "", "export": true },
	"ScorePanel":   { "kind": "component", "sig": "useState|use_countdown", "export": false },
}

const __RUI_DEFAULT := "ScorePanel"        # NEW const — absent when no default export

const __RUI_KIND := "mixed"

const __RUI_HOOK_SIG := ""                 # = binding component's sig; binding is a value here -> ""

static var container := { "theme_type_variation": "PanelDark" }   # value decls: static var (E-05)
static var MAX_ITEMS: int = 5
static var theme = { "modulate": Color(0.5, 0.5, 0.5) }
static var row_style := { "custom_minimum_size": Vector2(0, 24) }

# util format_score
static func format_score(score: int) -> String:
	return "Score: %d" % score

# hook use_countdown
static func use_countdown(start: int) -> Dictionary: …

# component ScoreRow
static func ScoreRow(props: Dictionary, children: Array) -> RUIVNode: …

# component ScorePanel  (not the binding component -> named func, NOT `render`)
static func ScorePanel(props: Dictionary, children: Array) -> RUIVNode: …
```

Rules (all M2):
- `render_component()` truth unchanged: the binding-NAMED component emits `render`; when the
  binding decl is a value/util (as above) there is no `render` alias — cross-file component refs
  address the decl-named func via the export table (`func` field), exactly the mixed-file
  mechanism shipped in 0.10.0.
- `__RUI_DEFAULT` is a NEW script const (name of the default-exported decl); readers treat
  absence as "no default" — old outputs stay valid.
- Value decls emit grouped after the header consts, in source order, before callables.
- Importer-side lowerings unchanged in shape: `_insert_value_imports` (`guitkx.gd:488`) gains
  `.member`-less namespace form + renamed members.

### 3.3 Importer of a default component

```guitkx
import Panel from "./score_panel"
export Shell() -> RUIVNode { return (<Panel title="hi"/>) }
```
lowers the tag to `V.fc(V.comp("res://…/score_panel.gd", "ScorePanel"), …)` — the default is
RESOLVED AT COMPILE TIME to its decl func via the target's export table; no runtime default
lookup, laziness preserved (E-07 + G-08).

---

## 4. Diagnostics — new allocations (2320–2329) + family gate

**Family block discipline:** 2300–2309 emitted (frozen 0.10.0), 2310–2315 reserved family-wide —
DO NOT touch. This leg allocates from **2320–2329** per G-10. Meanings/wording must be identical
family-wide (engine prefix + extension substitution only). **M0 registers this table in the
canonical family registry (Unreal repo) BEFORE any emission lands here; if the Unreal leg pins
different numbers/wording, THEIRS wins — renumber here, never ship divergent codes (the 26xx→23xx
lesson from the imports leg).**

*(Harmonized 2026-07-17 to the family-canonical, Unreal-audited allocation: the former
2320/2321/2322 wrapper-warn trio collapses into ONE code 2320 (arg = wrapper kind); the
cross-guard moves 2323→2321; 2322 is the family's value-export type-inference failure —
reserved-to-meaning, NOT emitted in Godot; the former 2324+2326 undeclared-export pair merges
into 2323; dup export 2327→2324; 2325 is NEW (import alias collision); no-default 2328→2326;
dup default 2325→2327; 2328/2329 reserved.)*

| Code | Sev | Message (exact; `%s` args noted) | Fires at |
|---|---|---|---|
| GUITKX2320 | warn | ``the `%s` wrapper keyword is deprecated -- write a plain declaration (the codemod rewrites it: dev/migrate_0_11_0.gd); the wrapper is removed in a later minor`` (wrapper kind: `component` / `hook` / `module`) | scan (one per wrapper decl) |
| GUITKX2321 | err | `` `%s` is `use_`-prefixed but returns a markup node -- did you mean a component? (components are PascalCase and return RUIVNode)`` (name) | scan (cross-guard, E-02) |
| GUITKX2322 | err | *family meaning:* value-export type-inference failure (initializer must name the type) — **RESERVED-TO-THIS-MEANING, NOT EMITTED IN GODOT** (dynamically-typed dialect: `:=` / plain `=` are always legal; precedent: UETKX2316 is LSP-only). Do NOT reuse the number. | — (never fires on this leg) |
| GUITKX2323 | err | ``%s names `%s`, which is not a top-level declaration in this file`` (export form: `` `export default` `` / `` `export { ... }` ``, name) | scan |
| GUITKX2324 | err | `` `%s` is already exported -- remove the duplicate export`` (name) | scan |
| GUITKX2325 | err | ``import alias `%s` collides with %s -- rename the import`` (local name; `a declaration in this file` / `another import`) | scan (imports + decl names both known) |
| GUITKX2326 | err | ``%s has no default export -- use a named import: import { %s } from "%s"`` (target file, suggested name = target's binding, specifier) | resolve |
| GUITKX2327 | err | ``duplicate `export default` -- a file has at most one default export`` | scan |
| GUITKX2328 | — | reserved (family) — never mint without canonical registration | — |
| GUITKX2329 | — | reserved (family) — never mint without canonical registration | — |

**Recorded family divergences** (registry divergence notes; precedent: the 2105 severity
divergence): **(a)** GUITKX2322 is registered to the family meaning but never emitted by the
Godot leg — GDScript's dynamic typing means a value initializer cannot fail type inference; the
row exists so the number can never be reused. **(b)** Mixed wrapper + plain declarations in ONE
file are LEGAL during the window in Godot and Unreal, but an ERROR in Unity (its per-file
namespace mode makes mixing ambiguous) — Unity records that as a LOCAL diagnostic OUTSIDE the
2320-band; do not mirror it here.

Existing codes that stretch (message text UNCHANGED — verify against `vocabulary.json` before
assuming): 2100 (PascalCase — now the component cross-guard, E-02); 2101 (no decl found —
reword ONLY if the family rewords: today's "no `component`, `hook`, or `module` declaration
found" names dead keywords; proposed family rewording "file has no declarations" goes through
the same M0 registration); 2301/2302 (named import misses — now also fire for `a as b`'s remote
name `a`); 2304 (unused — now also namespace/default locals); 2306 (chain — new eager edge kinds
join the DFS, message unchanged).

Vocabulary work: add rows to BOTH `vocabulary.json` copies, regenerate
`guitkx_vocabulary.gen.gd` (**FLAG**), mirror severities in the TS `vocabulary.json`
(byte-identical, test-enforced). GUITKX2322 gets a registry row pinned to its family meaning
with the divergence-(a) not-emitted note (0103/2203 retired-row precedent) — never an emitter.

---

## 5. Deprecation-window behavior matrix (G-10)

| File content | Parses | Emission | Diagnostics |
|---|---|---|---|
| pure wrapper (today's tree) | yes | byte-identical legacy paths (E-12) | 2320 warns (one per wrapper decl; arg = kind) |
| pure plain (new style) | yes | §3.2 shape | none (plus any real errors) |
| mixed wrapper + plain decls in ONE file | yes — **divergence (b), §4: LEGAL here + Unreal; ERROR in Unity (local code, outside the band)** | each decl by its own form; file routes through `_compile_mixed` when >1 decl (existing rule) | 2320 warns on the wrapper decls only |
| wrapper decls + NEW import forms (`* as`, default, `as`, `export {}`) | yes | new imports lower normally | warns on wrappers only — import surface is orthogonal |
| plain decls + OLD named-only imports | yes | normal | none |
| after the removal minor (LATER, owner-triggered — NOT this leg) | wrappers = parse error | — | 2101-family |

The codemod (M6) migrates the whole tree in the SAME release, so in-repo files never rely on the
window; the window exists for USER projects.

---

## 6. Milestones

Every milestone ends green on the FULL verify list (§10) and is committed on its own (no push).
Research each anchor before editing it — line numbers drift.

### M0 — prerequisites + family gates

1. Branch `feat/guitkx-es-modules` off `origin/dev` (fetch first).
2. Run §10 once untouched; record the build line (expect `49 file(s), 0 error(s), 5 warning(s)`
   — same baseline as the classname leg) and hash the generated demo `.gd` set (the
   CLASSNAME_CLEANUP M0 recipe) for later byte-identity checks on wrapper files.
3. **Family gate A — corpus:** agree + pin the new-grammar corpus cases (plain-decl fileScan
   cases, import-form cases) with the family (Unreal leg first per G-13). They land in
   `guitkx-scanner-cases.json` under the `familyCore` tiers with TKX-normalized codes; the new
   `plans/family-corpus.hash` value is agreed family-wide BEFORE M1. Until then: STOP.
4. **Family gate B — diagnostics:** register §4's 2320–2327 table (incl. the 2322
   reserved-not-emitted row and both divergence notes) in the canonical family registry (Unreal
   repo). Numbers/wording pinned there win. Until registered: STOP.
5. Confirm 232x is still free in ALL THREE repos' registries (this repo verified 2026-07-17).

### M1 — grammar + scan (GD + TS, both in lockstep)

1. `guitkx.gd`: classification scan per E-01 — new `_classify_decl_at()` used by `_find_decl` /
   `_enumerate_decls` (`:341/:594`): recognize plain callable/value decl heads; keep wrapper
   keywords recognized (window) tagging `deprecated: true`; emit 2320 at scan (one per wrapper
   decl, arg = kind); cross-guards 2321 (+2100 reuse). Value extent per E-04 (`_decl_body_end:620`
   + a `_value_end()` sibling).
2. `_parse_import_at` (`:374`): `{ a as b }` clauses, `* as X`, bare default `import X from`;
   `scan_imports` (`:463`) mirrors. New top-level line parsers: `export { a, b }` (E-09),
   `export default X` (E-07) — parsed in the decl loop, NOT the preamble loop (they may follow
   decls); 2323/2324/2327 at scan, plus 2325 (import alias collision, E-08) once imports and
   decl names are both known — still scan-local, no resolution needed.
3. `guitkx_codegen.gd` `_binding_name` (`:324`) **FIRST, with tests, before any emission work**
   (the imports-leg lesson — every identity table keys on it): skip `export default` /
   `export { … }` lines in the preamble walk; first-EXPORTED-decl rule now sees inline `export`,
   list-exports, and default marks as "exported".
4. TS mirror: `declScan.ts` (classification replaces `DECL_KEYWORDS` dispatch; keep wrapper
   recognition for the window; `nearestDeclKind:45` retargeted), `declarations.ts` (live header
   validation: `DECL_KWS:22` + `nearestDeclKeyword:26` learn plain heads + emit the window
   warns), `workspaceIndex.ts` (`scanDeclarations:37` + `_decl_re` replacement logic;
   export-list/default awareness), `guitkx_workspace.gd` `_decl_re:15-23` (regex must match
   plain decls — likely becomes a scan-function, not a regex; do NOT leave a wrapper-only regex
   behind), `importNav.ts` new clause shapes, `scanner.ts` untouched unless corpus says
   otherwise. Context routing BOTH sides: `semanticTokens.ts` `isBodyBrace:143-162` (shared with
   `context.ts`) and `guitkx_context.gd:164-187` must classify plain-decl body braces
   (paramless `Name {` and value-initializer `{` included) or embedded completion/highlighting
   misroutes. Editor probes: `guitkx_editor_view.gd` `_decl_probe:764` (`_basename` fallback)
   + tokenizer-kind dispatch `:266-268`.
5. Tokenizer/highlighter (`guitkx_tokenizer.gd`, `guitkx_code_highlighter.gd`), TextMate
   (`ide-extensions/grammar/guitkx.tmLanguage.json` + the hand-synced VS Code copy
   `ide-extensions/vscode/syntaxes/guitkx.tmLanguage.json`), schema
   (`grammar/guitkx-schema.json` `keywords` rows :9-11 + the bundled editor copy
   `addons/reactive_ui_editor/data/guitkx-schema.json` — the guitkx_editor_test schema-sync
   tripwire must stay green), `semanticTokens.ts`: `as`/`default` in import context,
   value-decl heads, keep wrapper faces for the window.
6. Formatter BOTH sides (`guitkx_formatter.gd:38` dispatch; `formatGuitkx.ts:40`): format plain
   decls of all four kinds; value decls one-per-line; canonical order preserved (imports verbatim
   — the 0.10.0 rule stands); `export { … }` canonicalizes above the first decl, `export default`
   after the last (E-07/E-09); wrapper files format EXACTLY as today (window byte-stability);
   idempotency corpus cases for every new form.
7. Vocabulary rows (§4) in both copies + regen `guitkx_vocabulary.gen.gd` (**FLAG**).

### M2 — data model + emission

1. `_compile_mixed` (`:1410`) becomes the plain-decl emitter: value decls → `static var` group
   (E-05, §3.2), util decls → plain static funcs (reuse hook emission minus hook validation),
   `__RUI_DECLS` new kinds (E-11), `__RUI_DEFAULT` const. Single-PLAIN-decl files also route
   through the mixed emitter (only WRAPPER single-decl files keep the frozen legacy paths —
   E-12); pin the new single-plain shapes as fixtures. **Verify first (untested GDScript
   corner):** when the binding decl IS a value (§3.2 — `class_name container` + a
   `static var container` member in the SAME script), confirm Godot 4 accepts the member
   shadowing its own class_name at parse AND that `preload(gd).container` resolves the member;
   if it errors, the emitter must force the `@class_name`-style fallback (binding skips value
   decls) — STOP AND ASK before changing E-10's rule.
2. Importer lowerings: namespace const (E-06), default resolution (E-07), rename (E-08) in
   `_insert_value_imports:488` / `_lower_hook_imports:518` / tag lowering via `known`.
3. Sidecar schema v3→v4 (`write_diags_sidecar:38`, payload `"v": 3` at :56): exports rows
   `{name, kind, func}` gain kinds `value`/`util`; file-level `default`; `exports_of:68` +
   `export_hash:84` cover both (a default flip must move the hash — reverse-edge staleness
   depends on it). **Invalidation correction (verified):** `is_stale:104` never reads `v` — it
   is mtime + `src_hash` only — so a v-bump does NOT auto-invalidate by itself. What actually
   forces the rewrite is the compiler fingerprint (`compiler_fingerprint:265` /
   `compiler_changed:284` over `_COMPILER_SOURCES:246-254` → recompile-all): `guitkx.gd` and
   both vocabulary files are IN that list (this leg touches them, so every sidecar rewrites as
   v4), but `guitkx_codegen.gd` / `guitkx_resolve.gd` are NOT — if an emission-affecting change
   lands only in those two, either add them to `_COMPILER_SOURCES` or verify a listed source
   moved too. `_reverse_edge_stale:746` skips sidecars lacking `export_hash` (:754-755 —
   pre-v3 tolerated); TS reader `diagsSidecar.ts:45` accepts `v === 2 || v === 3` and must
   accept 4.
4. Privacy: unchanged rules — no exports ⇒ no `class_name`; 2106 keys exported bindings only
   (`project_bindings:398`).
5. **FLAG (committed generated output):** `tests/contract/fixtures/*.gd` + `*.diags.json` +
   `tests/contract/golden/*.json` re-pin via `contract_dump.gd` after every emitter change.
   Wrapper-file goldens must NOT move except added 2320 sidecar rows — any other drift in a
   wrapper case is an E-12 violation: STOP.

### M3 — resolution + strict diagnostics

1. `guitkx_resolve.gd`: `decl_table:47` gains value/util kinds + `default` (E-11);
   `resolve_file_imports:137` resolves `as` (remote name validated → 2301/2302 on the REMOTE
   name), `* as` (whole-file preload edge), default (2326 when target has no default);
   `referenced_names:192` learns namespace-qualified refs (`X.member`) and renamed locals so
   2304/2305 stay accurate; `_name_referenced` (`guitkx.gd:561`) same.
2. 2306 edges: `_value_import_edges:776` adds namespace imports, default-VALUE imports, and
   value named-imports; component/default-COMPONENT edges stay exempt (G-08). Chain text
   unchanged.
3. Strict-2305 sweep (`guitkx.gd:256-274`): suggestion text must offer the right form for the
   missing name's kind (component/value → named import; module-era qualified refs → `* as`).

### M4 — build ordering + rename ghosts + staleness (re-verification milestone)

*This leg ADDS eager symbols (value exports, namespace consts) — every ordering hazard the
imports leg fixed gets MORE load-bearing. Nothing here is new machinery; it is mandatory
re-verification with new adversarial tests.*

1. **Two-pass write-all-then-check-all MUST survive** (`compile_all:536`, `guitkx_build.gd`
   pass-1 `parse_check=false` / pass-2 counted `gd_path_parses` exit-1): add an adversarial
   fixture pair where `a_value.guitkx` namespace-imports `z_values.guitkx` (lexicographic
   pass-1 order compiles the importer FIRST) — pass 2 must heal it; a deliberately-broken value
   initializer must still exit 1.
2. **Reverse-edge staleness:** flipping a value's export status / the default mark must
   recompile importers in the SAME sweep (`export_hash` + `_reverse_edge_stale:746`).
3. **Rename ghost-registration re-verification** (file=module, G-01): `plugin.gd`
   `cleanup_moved_guitkx:178` — new editor test: create + compile `a.guitkx` (exported value →
   `class_name` registered), simulate `_on_file_moved` rename to `b.guitkx`; assert the OLD
   `.gd`/`.uid`/sidecar are gone, no duplicate `class_name` survives a sweep, and an importer
   still holding the old specifier gets GUITKX2300 (not a silent stale preload) on the next
   sweep. Folder-move path (`_on_folder_moved:197`) same assertions.
4. **Class-cache two-pass scan order stays REQUIRED** (CLAUDE.md): ambient hand-written classes
   still only resolve after the editor scan; §10's order is the law. Do not "optimize" it away.

### M5 — HMR

1. `hmr.gd`: `_has_value_decl:210` gains `"value"` (and treats `"util"` like hook/module for
   refresh purposes); a value-decl change targets its component importers via `refresh_roots`
   (`apply:58` flow at 110-122 — mechanism unchanged, `_compute_refresh_roots:699` picks up the
   new edge kinds from M3.2). Wire format stays the shipped 3-element message; 2-element
   back-compat preserved.
2. **Injector dedupe re-audit** (`_inject_unregistered_bindings:143` + `_has_const_decl:203`):
   generated files now contain `static var <name>` declarations — extend the skip to
   `(?m)^(const|static var)[ \t]+<name>\b` so the injector never splices a `const X` above a
   same-named `static var X` (duplicate declaration = reload ERR_PARSE_ERROR — the A6c failure
   class). Regression test in `tests/hmr_test.gd`.
3. State semantics (G-09): per-decl `sig` compare unchanged; a value initializer edit re-renders
   importers but resets no hook state; test pins that.

### M6 — codemod + migration guide (same release, G-10)

Pipeline (idempotent, re-runnable, zero-diagnostics gate): **tidy → export-normalize → rewrite
wrappers → insert/fix imports → compile gate.**

1. Extend `guitkx_migrate.gd` with `modernize_source()` + runner
   `addons/reactive_ui/dev/migrate_0_11_0.gd` (precedent `migrate_0_10_0.gd`); the 0.10.0
   `migrate_source:44` stays untouched (its runner must keep reporting `migrated 0`).
2. Rewrites (lexer-aware, offset-safe — reverse order like `migrate_source`'s export pass):
   - `[export] component X(p) {` → `[export] X(p) -> RUIVNode {` (annotation added — E-01).
   - `[export] hook use_x(p) [-> T] {` → `[export] use_x(p) [-> T] {` (keyword dropped).
   - `[export] module M { members }` → members hoisted to top level (dedent one step, member
     order preserved, each member's export = the module's export flag) **+ insert
     `@class_name M` when absent** so the file's binding/global identity stays `M` (the G-07
     hatch doing exactly its job; hand-written `M.member` callers keep working).
   - Importers of a hoisted module: `import { M } from "./f"` whose `M` is consumed QUALIFIED
     (`M.x`) → `import * as M from "./f"`; consumed as a tag → leave named (it now names the
     component decl directly).
3. Idempotency: a second run reports 0 changed; running on an already-plain file changes nothing.
4. Acceptance corpus = the whole tree (49 demos incl. doom + the 4 module companions:
   `doom_game_screen.hooks`, `gallery_table`, `stress_native.hooks`, `stress_test.hooks` — the
   module-hoist cases). Gate: post-codemod tree compiles with ZERO 2320-2329 AND zero 23xx
   errors, then the FULL §10 list passes (demos/doom render checks are the real proof).
5. `MIGRATION-0.11.md` (repo root, sibling of MIGRATION-0.10.md) outline: why (family ES-module
   end-state); the classification table; before/after of each wrapper kind; value exports;
   new import forms; the module→`* as` recipe (+ `@class_name` note); the rename=identity
   semantic (G-01); codemod invocation
   (`godot --headless --path . --script res://addons/reactive_ui/dev/migrate_0_11_0.gd` — like
   `migrate_0_10_0.gd`, ALWAYS whole-project (`migrate_all("res://")`, deliberately no subtree
   mode: reference resolution needs every decl in its universe)); deprecation timeline.

### M7 — LSP / editor tooling depth (beyond M1's scan parity)

1. Editor lsp/: `guitkx_completion.gd` (offer imported names incl. namespace members after
   `X.`; auto-import edit for exported names elsewhere), `guitkx_hover.gd` (kind-aware hover:
   value/util/hook/component + default badge), `guitkx_outline.gd` (plain decls with kind +
   export badges), `guitkx_refs.gd` (go-to-def/find-refs through `as`-renames, `* as` members,
   defaults), `guitkx_scan_diags.gd` (live 232x), `guitkx_virtual_doc.gd` (synthesize
   `static var` value decls + namespace consts in the header region — LENGTH-PRESERVING inserts
   only, same trick as today's consts).
2. TS: same feature set in `server.ts`/`refs.ts`/`virtualDoc.ts`/`importNav.ts`; completion/
   hover/rename lockstep (rename of an exported name must rewrite import clauses incl. `as`
   remote names).
3. `tests/guitkx_editor_test.gd` + `tests/guitkx_lsp_test.gd` + `node --test` suites cover each.

### M8 — docs + changelogs + versions + corpus lockstep + bookkeeping

1. Docs site (`ReactiveUIGodotDocs~/src/pages/UITKX/`): `Imports/` — full ES surface (all five
   forms, eager/lazy table, cycles); `CompanionFiles/` — REWRITTEN (companion-file *convention*
   pages become "a file is a module" + plain multi-decl guidance); `Reference/` — wrapper rows
   replaced by the classification table; `@class_name` row stays "optional override, rarely
   needed" (G-07); `Diagnostics/` — 2320-2327 rows (2322 rendered as reserved/not-emitted per
   divergence (a)) + 2203 retirement note; sweep EVERY page's
   examples off wrapper syntax (`grep -rn "component \|hook use_\|module " ReactiveUIGodotDocs~/src/pages/ --include="*.ts"`
   and review — GettingStarted, Hooks, Concepts, Components at minimum). `npm run build && npm run lint`.
2. Changelogs (every lane): root `CHANGELOG.md` 0.11.0 (hand-written) → byte-copy to
   `addons/reactive_ui/CHANGELOG.md` (tripwire test); `addons/reactive_ui_editor/CHANGELOG.md`;
   `ide-extensions/changelog.json` + `node ide-extensions/scripts/changelog.mjs verify`;
   `plans/DISCORD_CHANGELOG.md` entry (**≤2000 chars**).
3. Versions (G-11): `addons/reactive_ui/plugin.cfg` 0.10.2→**0.11.0**;
   `addons/reactive_ui_editor/plugin.cfg` 0.8.1→**0.9.0**; `ide-extensions/vscode/package.json` +
   `lsp-server/package.json` 0.10.3→**0.11.0**; VS2022 `.vsixmanifest` 0.10.3→**0.11.0**; docs
   `package.json` per its lane. Skew rule: extensions publish in the SAME release window as the
   addon (old mirrors would red-squiggle the new grammar).
4. **Corpus lockstep (G-12):** the M0-agreed cases are already in `guitkx-scanner-cases.json`;
   re-pin `plans/family-corpus.hash` with `node scripts/corpus-hash.mjs --write` ONLY to the
   family-agreed value; `--check` green here AND (owner-verified) in the sibling repos at
   campaign end. A locally-invented hash value = family drift = STOP.
5. Bookkeeping: `plans/MASTER_PLAN.md` §2.3 is a ROW in the §2 table
   (`| # | Item | Status | Blocker / next action | Source |`, at :34) — update it IN PLACE:
   **Status** → `DECIDED: directive KEPT (escape hatch + module-migration binding tool)`;
   **Blocker / next action** → `removal revisited post-campaign, owner-triggered`;
   **Source** → append `ES_MODULES_EXECUTION_PLAN (archived)` alongside the existing
   CLASSNAME_CLEANUP_PLAN pointer (this plan's G-07 record). Add this leg as a row in §6
   "Closed & archived" once merged. Archive THIS plan to `plans/archive/` with a one-row
   `archive/README.md` entry in the same PR that completes it (archive protocol).
6. CI: `.github/workflows/test.yml` gains a step for every NEW suite/script this leg adds and
   keeps the two-pass class-cache order (it is §10's CI mirror); decide with the owner whether
   the M6 migrate runner's idempotency ("migrated 0") gets a step like `guitkx_migrate.gd`'s
   local run. `ide-extensions.yml` / `publish.yml` need no structural change (changelog verify
   + builds already cover the new work) — verify, don't assume.

---

## 7. Test matrix (add/update; run per milestone)

| Suite | Adds |
|---|---|
| `tests/guitkx_test.gd` | classification: each E-01 rule + cross-guards (2321, 2100-reuse); value extent forms (`=`, `: T =`, `:=`, brace/bracket/paren + end-of-line); wrapper decls still parse + warn 2320 (kind arg, one per decl) + BYTE-identical `.gd` vs pinned; import forms (`as`, `* as`, default, `export {}`, `export default`) parse + lower; 2323-2327 fixtures (2325 alias-collision vs decl AND vs another import; 2322 NEVER fires — assert absence on a `:=` value); namespace 2306 chain; default-component laziness (no preload emitted); rename-import addressing; binding with value-first export; `_binding_name` order cases incl. `export default` before `@class_name`; codemod: each rewrite + module-hoist + `@class_name` insertion + idempotency (second run = 0) |
| `tests/guitkx_build.gd` | adversarial pass-order fixture (M4.1); broken value initializer exits 1 |
| `tests/hmr_test.gd` | `static var` injector skip (M5.2); value-edit → targeted refresh, no state reset; `__RUI_DEFAULT`/new-kind decl tables round-trip `get_script_constant_map()` |
| `tests/demos_test.gd` / `tests/doom_game_test.gd` | unchanged assertions over the MODERNIZED tree (codemod acceptance) |
| `tests/guitkx_editor_test.gd` | rename-ghost scenario (M4.3); outline/completion/hover for new kinds; changelog mirror tripwire still green |
| `tests/guitkx_lsp_test.gd` | go-to-def through `as`/`* as`/default; virtual-doc value consts; live 232x |
| `tests/core_test.gd` | `V.comp` signature regression (must NOT change) |
| `tests/contract` | new plain-decl + import-form fixtures (family-core mirrored + Godot-local) — **FLAG: goldens re-pin via `contract_dump.gd`** |
| `ide-extensions/lsp-server` `node --test` | declScan classification cases, formatter round-trip (all new forms idempotent), workspaceIndex export/default awareness, importNav clause navigation, contract.test.ts vs re-pinned goldens |

## 8. Committed-generated-output flag list

1. `addons/reactive_ui/guitkx/guitkx_vocabulary.gen.gd` — M1 (232x rows; regen via
   `dev/gen_vocabulary.gd`).
2. `ide-extensions/lsp-server/src/vocabulary.json` — M1 (byte-identical sync; test-enforced).
3. `tests/contract/fixtures/*.gd` + `*.guitkx.diags.json` + `tests/contract/golden/*.json` —
   M2 (emission), M3 (diags), M6 (fixture modernization where fixtures adopt plain syntax —
   keep a frozen wrapper-fixture subset for the window, E-12). Regenerate, REVIEW the diff.
4. `ide-extensions/lsp-server/test-fixtures/guitkx-scanner-cases.json` +
   `guitkx-formatter-cases.json` + `plans/family-corpus.hash` — M0/M8 (family-agreed values
   ONLY).
5. `examples/**/*.gd` stay git-ignored (hand-written exceptions untouched); the `.guitkx`
   sources ARE committed and change in M6's codemod sweep — review that diff file-by-file.

## 9. Full sync-surface checklist (G-12 — all are gated milestone items above)

- [ ] parser + all emitters + resolver (M1-M3) — [ ] formatter GD+TS (M1.6)
- [ ] codemod + runner (M6) — [ ] HMR pipeline (M5)
- [ ] TextMate grammar (shared + VS Code `syntaxes/` copy) + schema BOTH copies (grammar/ +
  editor `data/`) + tokenizer/highlighter + semanticTokens/isBodyBrace + declarations.ts +
  guitkx_context.gd (M1.4/M1.5)
- [ ] LSP GD + TS: completions/hover/go-to-def/rename/outline/virtual docs (M7)
- [ ] vocabulary ×2 + .gen.gd (M1.7) — [ ] contract fixtures/goldens (M2/M3/M6)
- [ ] family corpus + hash LOCKSTEP (M0.3/M8.4)
- [ ] changelogs: root + addon mirror + editor addon + changelog.json + Discord ≤2000 (M8.2)
- [ ] MIGRATION-0.11.md (M6.5) — [ ] docs-site pages rewritten (M8.1)
- [ ] versions all four lanes + skew rule (M8.3) — [ ] MASTER_PLAN §2.3 row updated per its
  table columns (M8.5) — [ ] CI workflow steps for new suites (M8.6)

## 10. Verify commands (CI order; run after every milestone — never weaken)

```bash
# Two-pass class-cache order (CLAUDE.md — the law on fresh clones/CI):
godot --headless --path . --editor --quit || true                       # 1. class-name cache
godot --headless --path . --script res://tests/guitkx_build.gd          # 2. compile (two-pass + counted parse gate)
godot --headless --path . --editor --quit || true                       # 3. re-scan generated class_names
godot --headless --path . --script res://tests/core_test.gd
godot --headless --path . --script res://tests/style_test.gd
godot --headless --path . --script res://tests/router_match_test.gd
godot --headless --path . --script res://tests/router_spine_test.gd
godot --headless --path . --script res://tests/update_test.gd
godot --headless --path . --script res://tests/demos_test.gd
godot --headless --path . --script res://tests/doom_game_test.gd
godot --headless --path . --script res://tests/guitkx_test.gd
godot --headless --path . --script res://tests/hmr_test.gd
godot --headless --path . --script res://tests/guitkx_editor_test.gd
godot --headless --path . --script res://tests/guitkx_lsp_test.gd
godot --headless --path . --script res://tests/contract_dump.gd -- --check
godot --headless --path . --script res://tests/guitkx_migrate.gd        # 0.10.0 codemod: still "migrated 0"
node scripts/corpus-hash.mjs --check                                    # family hash (M0-agreed value only)
node ide-extensions/scripts/changelog.mjs verify
cd ide-extensions/lsp-server && npm ci && npm run build && node --test out/test/*.test.js && node scripts/smoke.js
cd ide-extensions/vscode && npm ci && npm run build
cd ReactiveUIGodotDocs~ && npm ci && npm run build && npm run lint
```
- Godot binary on this machine:
  `C:\Yanivs\daniela test\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe`.
- M6 acceptance adds: `godot --headless --path . --script res://addons/reactive_ui/dev/migrate_0_11_0.gd`
  then the FULL list again (and a second migrate run reporting 0).
- The editor-scan steps stay REQUIRED (ambient hand-written classes; M4.4) — do not remove.

## 11. Executor guardrails (what NOT to do) + error signatures

- Do NOT touch `V.comp` laziness, `_comp_cache`, or make ANY component reference eager (G-08).
- Do NOT change `_hook_signature` (`guitkx.gd:2173`) or the `__RUI_HOOK_SIG` key semantics —
  family Fast-Refresh key stability.
- Do NOT remove/alter: `@class_name` machinery (G-07 — parser, binding override, formatter
  canonicalization GD+TS, `_cn_re`, TextMate, schemas), the 2300-2309 rows/messages, the
  2310-2315 reserved block, retired-number rows (0103, 2203-to-be — numbers are never reused).
- Do NOT rename `__RUI_DECLS` keys or restructure the decl-table shape (E-11) — only ADD kinds
  and the `__RUI_DEFAULT` const.
- Do NOT emit deprecation text into generated `.gd` (E-12 — wrapper output stays byte-frozen).
- Do NOT implement re-exports (`export { a } from`), namespace component tags (E-06), or wrapper
  REMOVAL (later minor) — all out of scope.
- Do NOT edit generated `.gd`/`.uid`/sidecars by hand; never edit `tests/contract/golden/` by
  hand (regen only); never `--write` the family hash to a locally-invented value.
- Do NOT weaken `guitkx_build`'s counted parse gate or the two-pass order; do NOT drop the
  editor-scan steps from §10.
- Do NOT commit or push without an explicit owner ask; no Co-Authored-By trailers.

Error signatures → likely cause:

| Symptom | Likely cause |
|---|---|
| pass-2 `res://…gd:N Parse Error: Identifier "V"/"Hooks" not declared` en masse (49/49) | class-cache scan skipped — rerun §10 step 1 |
| `ERR_PARSE_ERROR 43` on ONE generated file referencing another's `.gd` | two-pass regression (pass-1 parse check re-enabled) or a value-import emitted before its target exists — M4.1 |
| reload fails only under HMR with "already declared in this scope" | injector splicing a dup const over `static var` — M5.2 regex |
| `corpus-hash.mjs --check` fails | familyCore corpus touched without family agreement — revert or STOP AND ASK |
| contract `--check` drift in a `t*` WRAPPER case | E-12 violation — wrapper emission moved; STOP |
| demos render blank / `Invalid call … 'render'` cross-file | `render_component`/export-table `func` addressing disagreement — E-10 |
| GUITKX2106 storms after rename tests | ghost `.gd` cleanup failed — M4.3 |

## 12. Risks / watch-list / STOP-AND-ASK

- **Component classification requires `-> RUIVNode` (E-01).** A user's un-annotated PascalCase
  markup function silently becomes a util and its tag stops resolving (2307/2102 at the use
  site, not at the decl). Mitigations: codemod always annotates; docs teach it; the 2307 message
  already points at exports. If field feedback shows this biting hard, a decl-site LINT (body
  peek) is a FAMILY decision — do not add unilaterally (G-03 forbids body inspection for
  classification).
- **Eager-symbol growth** (values + namespace consts) raises load-order pressure — M4 is
  mandatory re-verification, not optional hardening. The 2306 policy error still does NOT
  mitigate fresh-clone ordering; only the two-pass does.
- **`static var` vs `const` (E-05):** `static var` values are mutable from consumers (GDScript
  has no read-only statics). Document "treat as constants"; if the owner wants hard immutability,
  STOP AND ASK (const-foldability analysis is a bigger lift).
- **Binding = first exported decl now includes values** (E-10): a file whose first export is a
  lowercase value gets a lowercase `class_name` — legal but ugly in the flat registry; the
  codemod's `@class_name` insertion covers migrated modules, docs recommend the hatch for this
  case. Watch 2106 arbitration behavior over lowercase bindings in M2 tests, and run M2.1's
  class_name-vs-same-named-member shadowing probe BEFORE building on the §3.2 shape.
- **Family divergence risk:** 232x numbers/wording, corpus cases, and `* as`-tag scope (E-06)
  are pinned by the Unreal reference leg. Anything landed here before the family pin risks the
  26xx→23xx renumber pain again — M0's gates are hard STOPs, not formalities.
- **Ambiguous anywhere = STOP AND ASK.** Specifically pre-identified ask-first items: E-05
  const-vs-static-var; E-06 namespace tags if Unreal ships them; 2101 rewording; any conflict
  between this plan and `ES_MODULES_GENERAL_PLAN.md` (the contract wins); any test that can only
  pass by weakening a gate.
