# .guitkx → .uitkx Syntax Parity — Execution Plan

> **ARCHIVED 2026-07-04 (plans audit): executed and shipped — 31 of 32 tasks ✅.** The one open
> item, **T6.1** (docs authoring: concordance page, differences rewrite, directive-mapping
> table), moves to the docs wave (Wave 3; see `ASSET_STORE_PLAN.md` §6). Note two statements
> below were later superseded by events: the "keep bare-markup directive bodies" non-goal
> (0.7.0 made them return-based, Unity-convergent) and global-class-name codegen (path-based
> `V.comp` since 0.8.1).
>
> **Companion docs.** Evidence base: [`UITKX_GUITKX_SYNTAX_PARITY.md`](UITKX_GUITKX_SYNTAX_PARITY.md)
> (the divergence matrix — every claim there carries file:line evidence; this plan references its rows
> as "matrix row N"). Filed bugs G5–G9: [`BUG_AUDIT.md`](BUG_AUDIT.md) §4. This plan **subsumes G5–G9**
> (mapping table at the end).
>
> **Written 2026-07-03 for execution by another AI.** Everything needed is in this file + the matrix.
> Line numbers are anchors as of commit `e843fa0` (master) — re-locate by the quoted identifier if
> drifted; do not trust raw numbers blindly.

## Mandate (user decisions, 2026-07-03)

1. **Feature superset.** The Godot library must have **every feature ReactiveUIToolKit (Unity) has** —
   a missing capability is a gap even if previously classed "intentional." Only *representation*
   differences driven by GDScript stay (keyword renames like `@elif`/`@match`, snake_case, Dictionary
   props/styles, indent re-anchoring). Missing capabilities (`@uss`, markup comments, `<Fragment>`,
   4-context hooks validation, PascalCase check, …) must be implemented.
2. **Text interpolation: Godot adopts the Unity way.** Text no longer stops at `{`; `{expr}` is
   recognized at node start only; mid-text braces become literal text. (Unity stays as-is — its UI
   Toolkit requires text inside a text-bearing element and typed-props made mid-text interpolation
   impractical.) A migration warning is mandatory (T2.4).
3. **Diagnostic codes: renumber the Godot side** to Unity's numbering where meanings align (§ Renumbering).
4. **Unity-repo work is out of scope here.** It lives in the Unity repo:
   `Plans~/UITKX_PARITY_CLEANUP_PLAN.md`.

## Executor briefing — read before any task

**Repos.**
- `RG` = `C:\Yanivs\GameDev\ReactiveUI\ReactiveUI-Gadot` (this repo). Compiler: `addons/reactive_ui/guitkx/*.gd`.
  LSP: `ide-extensions/lsp-server/src/*.ts`. Plugin: `addons/reactive_ui/plugin.gd`. Docs: `ReactiveUIGodotDocs~/`.
  Demos: `examples/demos/`. Native editor addon: `addons/reactive_ui_editor/`.
- `GA` = `C:\Yanivs\GameDev\gdscript-analyzer` (Rust). Only Phase 4 touches it.
- `U` = `c:\Yanivs\GameDev\UnityComponents\Assets\ReactiveUIToolKit` — **read-only reference** for parity
  semantics (never edit from this plan).

**Verification commands.**
- LSP tests: `cd RG/ide-extensions/lsp-server && npm test` (vitest; e2e in `src/test/core.test.ts` runs the
  real bundled analyzer). Smoke: `npm run smoke` if present, else the e2e suite is the smoke.
- Godot headless suites: `"/c/Yanivs/daniela test/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe" --headless --path RG -s tests/<suite>.gd`
  (7 suites exist under `RG/tests/`; run all after compiler changes).
- Shared formatter/compiler fixtures: `RG/ide-extensions/lsp-server/test-fixtures/formatter-cases.json`
  is consumed by BOTH the TS tests and a GD test — byte-identical expectations.
- GA: `cargo test --workspace`, `cargo clippy --workspace -- -D warnings`, `cargo fmt --check`; corpus:
  `cargo run --release -p gdscript-ide --example corpus -- <godot-demo-projects dir> --per-project` and diff vs baseline.

**Hard rules.**
- **Four mirrored reindenters** change together or not at all: `guitkx.gd _reindent_setup`,
  `guitkx_formatter.gd _reanchor`, `virtualDoc.ts emitVerbatimBlock`, `formatGuitkx.ts reanchor` —
  cross-tested via `formatter-cases.json`.
- **Byte-identical port discipline**: `guitkx_lexer.gd:15-70` ≡ `scanner.ts:11-63` and `markup.ts` ≡
  `guitkx_markup.gd` line-for-line. Any grammar change lands in BOTH in the same commit, plus a golden
  fixture (T0.1 makes this enforceable).
- **Sidecar hash pair**: `guitkx_codegen.gd:23-28` (FNV-1a) ≡ `diagsSidecar.ts:19-28`. Changing the
  sidecar format changes both + a version field.
- Never touch the user's uncommitted files unless the task requires it; never add a `Co-Authored-By`
  trailer; commit/push only when the user asks; versioning is SemVer 0.x — **patch by default**, the
  renumbering release (Phase 3) is a **minor**.
- Every task: fix → tests (fixture-based where possible) → run the verification matrix for the touched
  area → update this file's Status field in the same commit.
- **Cross-repo lesson (do not repeat):** a GA change is NOT live in the extension until (a) GA version
  bumped + published to npm, (b) `RG/ide-extensions/lsp-server/package.json` dep + lockfile bumped,
  (c) extension version bumped (publish gates are version-keyed per target), (d) Publish workflow run.
  **Revised 2026-07-03 (user decision):** Phase 4 publishes ONCE, at end of phase, user-gated — not
  per task. Each T4.x is a per-task commit with Rust-level tests; cross-repo integration is verified
  against a locally built napi artifact (`file:`/copied `.node`) BEFORE the single publish chain runs.
  Rationale: npm versions are immutable — one fully-tested release beats six intermediates; commits
  stay per-task so bisectability is unchanged.

**Status legend.** ⬜ todo · 🟨 in progress · ✅ done · 🔷 needs a user decision (recommendation given).

## Phase overview

| Phase | Theme | Ships as | Gate to next |
|---|---|---|---|
| 0 | Foundations: contract harness, structured diagnostics, shared vocabulary | 0.4.x patch + IDE patch | Harness green on current grammar; all 4 surfaces consume structured diags |
| 1 | Silent mis-compiles + data loss (P0 correctness) | patch | No known input compiles with wrong output and zero diagnostics |
| 2 | Missing Unity features (superset mandate) | **minor** (new syntax) | Feature map below shows no "gap" rows |
| 3 | Diagnostics parity + renumbering | **minor** (breaking codes) | Concordance published; severities consistent across surfaces |
| 4 | Analyzer-side message/behavior parity (GA repo) — **✅ code-complete** (GA branch `feat/godot-native-diagnostics`, 5 commits; RG halves in `854132d`; publish chain user-gated) | GA patch (@gdscript-analyzer/core 0.x: features=patch) + RG bundle patch | Golden table green (50 tests); dimming e2e-pinned vs the local 0.5.5 core, live in-editor after the dep bump |
| 5 | Single-source-of-truth completion (LSP ≡ compiler) | patch | Zero contract-test diffs; G7/G8 e2e green |
| 6 | Docs + demos batch | patch | Doc checklist empty |

Order within a phase is the listed order (dependencies noted per task). **Branching (user decision
2026-07-03): the ENTIRE plan lands on ONE branch — `feat/syntax-parity` — one PR, continuous commits;
"Ships as" above marks version-bump points along that branch, not separate PRs.** Within Phase 0 the
executor may sequence T0.2-core before T0.1 (the harness's golden schema consumes T0.2's structured
diagnostics — building the dumper against legacy strings would be throwaway work).

## Non-goals (keep, forever-intentional)

| Divergence | Why it stays |
|---|---|
| `@elif` / `@match`+`@case (v) { }` / `@for (x in xs)` keywords | GDScript idiom; capability-equal to `@else if`/`@switch`/`@foreach` |
| No C-style `@for (init;cond;inc)` | GDScript has no C-style for; range `@for (i in n)` covers counted loops — document the mapping (T6.1) |
| Bare-markup directive bodies (no `return` inside `@if{}` bodies) | Documented authoring-model fork on both sides (matrix row 25) |
| Dictionary props / `render(props, children)`; Dictionary `style` | GDScript is dynamically typed; Unity's typed `<Name>Props`/`Style` can't port |
| snake_case host attributes / signal-model handlers (no event arg) | Godot naming + signal semantics |
| Indent re-anchoring of embedded GDScript | GDScript is indentation-significant |
| Prop spread `{...expr}` (Godot-only) | Natural with Dictionary props; keep + already documented |
| Single-quote attribute strings (Godot-only extra) | Superset rule is one-directional; keep |
| `{ children }` name (vs Unity `{__children}`) | Same capability; snake-idiomatic name. Unity documents its own name in its plan |

## Feature coverage map (Unity construct → Godot)

| Unity | Godot equivalent | State |
|---|---|---|
| `@namespace`, `using`/`@using` | n/a (GDScript has neither) | intentional |
| `@uss "path"` | **missing** | gap → T2.3 |
| `component` / `hook` / `module` decls | exist | `module` semantics differ → T2.8 🔷 |
| PascalCase component check (2100) | missing | gap → T2.6 |
| hook `use`-prefix warning (2203) | missing | gap → T2.6 |
| `@if/@else if/@else`, `@foreach`, `@for`, `@while`, `@switch` | `@if/@elif/@else`, `@for`-in, `@while`, `@match` | capability-equal (non-goal) |
| Markup comments `//`, `/* */`, `<!-- -->` | **none** | gap → T2.1 |
| `<Fragment>` named tag | only `<>` | gap → T2.2 |
| Node-start-only `{expr}`, text runs past `{` | opposite | converge → T2.4 |
| Rules-of-hooks 4 contexts (0013-0016) | 1 heuristic | gap → T2.5 |
| useEffect-deps (0018), iterator-key (0019), unused-param (0111), asset-path (0120/0121) | shipped (T2.7) | ✅ |
| ref-arity (0020/0021) | n/a — checks C# `Ref<T>` typed params; Dictionary-props components have none | intentional (T2.7 probe) |
| Unreachable-code hint (0107) | partial (double, uncoded) | → T1.4/T3.2 |
| Unknown tag/attr errors in IDE (0105/0109) | gated/partial | → T1.5 |
| Compile fails on any parser error | does not | → T1.1/T1.2 |

---

## Phase 0 — Foundations

### T0.1 — Golden-corpus GD↔TS contract harness  · effort: medium · Status: ✅ (53 fixtures = 41 demo copies + 12 targeted; `tests/contract_dump.gd` dumps/`--check`s goldens {ok, diagnostics, windows, markup-AST}; `contract.test.ts` asserts markupWindows+parseMarkup reproduce them; pending fixtures assert their divergence STILL exists (self-burning-down: t05 typo-header recovery); CI: test.yml `--check` + ide-extensions.yml npm test; first run caught a REAL cross-cutting bug — GDScript code-point vs JS UTF-16 offsets on emoji files — fixed via `codePoints.ts` boundary, canonical unit = code points, see tests/contract/README.md)
**Problem.** The grammar is implemented twice (GD compiler, TS LSP) with zero enforcement (matrix §5.1).
**Build.**
1. `RG/tests/contract/fixtures/*.guitkx` — seed with ≥25 fixtures: every demo under `examples/demos/`
   (copy, don't reference), plus one fixture per §5.1 disagreement (items 1–8) and per matrix-row
   ACCIDENTAL edge that is parser-visible (rows 3, 10, 14, 17, 22, 27).
2. `RG/tests/contract_dump.gd` — headless-runnable script: for each fixture, run the compiler's parse
   (`guitkx.gd` decl scan + `guitkx_markup.gd` markup parse) and dump
   `{decls:[{kind,name,params,span}], markup_ast, diagnostics:[{code,severity,message,line,col}]}` as
   canonical JSON (sorted keys) to `tests/contract/golden/<fixture>.json`.
3. `RG/ide-extensions/lsp-server/src/test/contract.test.ts` — vitest: run `declScan.ts` + `markup.ts`
   (+ `virtualDoc.ts` window extraction) over the same fixtures; diff against the golden JSON.
   Normalization layer maps TS shapes to the golden schema; NO tolerance knobs — a diff is a failure.
4. npm script `test:contract` regenerates goldens via the headless binary when `REGEN=1`.
**Expect** the harness to be RED on §5.1 items at first — mark known-diverging fixtures `*.pending.guitkx`
(excluded from CI) and burn the pending list down through Phases 1–5; a phase is not done while it owns a pending fixture.
**Deliverables.** Harness + fixtures + goldens + CI wiring (`test.yml` job) + pending-list README.
**Done when.** CI runs the contract job; non-pending fixtures byte-identical GD↔TS.

### T0.2 — Structured compiler diagnostics `{code, severity, message, line, col}`  · effort: large · Status: ✅ (branch `feat/syntax-parity`; Diag module = `guitkx_diag.gd` `{code,severity,message,offset,length}` + surface-derived line/col; markup nodes carry `at`/`vat`/`body_at` offsets in BOTH parsers; sidecar v2 with v1 fallback; plugin dock = per-diag `path:LINE:COL:` lines; native renderer uses exact offsets; LSP sidecar merge ranges via positionAt + (code,line) dedupe)
**Problem.** Compiler diagnostics are plain strings; severity is a `"(warning)"` substring sniff
(`guitkx.gd:33, 158-160`; `guitkx_codegen.gd:31-46`); every downstream surface degrades: sidecar pins
line 0 (`server.ts:668`), Errors dock prints a joined array with no position (`plugin.gd:69-79`),
native editor guesses lines by token search (`guitkx_diagnostics_renderer.gd:56-72`). Matrix exec #4.
**Build.**
1. In `guitkx.gd`: a `Diag` Dictionary contract `{code:String, severity:int(0=err,1=warn,2=hint), message:String, offset:int, length:int}` —
   offsets into the ORIGINAL `.guitkx` source (every parse fn already carries absolute indices; thread
   them to each `diags.append` site — there are ~30; convert offset→line/col once, at the surface layer).
2. Severity gate becomes `d.severity == 0` (replaces the substring sniff at `guitkx.gd:158-160` and the
   plugin's `"(warning)"` checks).
3. Sidecar (`guitkx_codegen.gd` + `diagsSidecar.ts`): bump sidecar schema with a `"v":2` field; write
   structured entries; TS side reads v2, keeps v1 fallback for one release. Update BOTH hash sides.
4. `plugin.gd`: `push_error("%s:%d:%d: %s: %s" % [path, line, col, code, message])` per diagnostic —
   clickable, per-line, replacing the joined-array print.
5. Native editor renderer: consume real offsets; delete the token-search guesser.
6. LSP live tier keeps its own ranges; the dedupe key becomes `(code, line, message)` — see T3.3.
**Compat.** `compile()`'s public return keeps `diagnostics` as an Array; entries change String→Dictionary —
grep ALL consumers (`plugin.gd`, `guitkx_codegen.gd`, native editor, tests) in the same commit.
**Deliverables.** Structured diags end-to-end on all 4 surfaces + updated fixtures/goldens (T0.1 schema
already expects this shape) + a `docs` note.
**Done when.** A compiler error in any demo shows file:line:col in the Errors dock, the sidecar carries
real ranges (no line-0 pins), and all suites are green.

### T0.3 — Shared vocabulary module  · effort: small · Status: ✅ (`addons/reactive_ui/guitkx/vocabulary.json` = single source {directives, hooks, host_tags incl the 9 aliases, v_factories}; guitkx.gd loads it (HOST_TAGS/HOOK_NAMES/V_FACTORIES static vars); LSP ships a byte-identical copy (`src/vocabulary.json`, resolveJsonModule) and schema.ts DERIVES alias TagInfos from it — the 9 long-form aliases now get completion/hover/no-false-0105; tripwires: vocab.test.ts (copy sync + schema coverage + HOOK_STUBS names) and guitkx_test.gd `_test_vocabulary` (reflection-pins v_factories to core/v.gd public statics); vocabulary.json added to the compiler fingerprint)
**Problem.** HOST_TAGS drift (compiler has 9 long-form aliases the LSP lacks — `guitkx.gd:19-29` vs
`schema.ts:18-51`); hook-prefix list duplicated (`guitkx.gd:373,485,632,1164-1201` vs `virtualDoc.ts:26-50`);
message templates drift for the same code (matrix §4 last para).
**Build.** One checked-in JSON — `addons/reactive_ui/guitkx/vocabulary.json`: `{host_tags:{alias:canonical}, v_factories:[...], hooks:[...], directives:[...], messages:{CODE:template}}`.
`guitkx.gd` loads it (preload via `JSON.parse_string(FileAccess.get_file_as_string(...))` at class init);
`schema.ts`/`virtualDoc.ts`/`server.ts` import it (lsp-server build copies it, like the TextMate grammar
copy pattern on the Unity side). Populate `v_factories` from the real `V` API (grep `static func` in
`RG/src/v.gd` or equivalent — needed by T1.5). A unit test on each side asserts the runtime tables came
from the JSON (tripwire against re-hardcoding).
**Done when.** Both sides' tables have a single source; the 9 missing aliases work in the LSP (highlight,
completion, no false unknown-tag).

---

## Phase 1 — Silent mis-compiles + data loss

### T1.1 — Error gate runs after `_emit` and inside `_compile_module`  · effort: small · Status: ✅ (gates: post-emit in `_compile_component`, validate-all-then-gate + post-emit in `_compile_module`, PLUS a final invariant enforcement in `compile()` itself — ok:true can never coexist with an error diag no matter which path appended it; `compile_file` now DELETES a stale sibling .gd on failed compile (push_error announces it) and regenerates on fix; 0113's legacy push_warning removed — it fails the compile through all 4 surfaces now)
**Current.** Gate at `guitkx.gd:156-163` returns before `_emit` (line 162) is ever consulted — any
error appended DURING emit (GUITKX0113 at `guitkx.gd:896-901`, jsx-scan errors) cannot fail the compile;
`_compile_module` (`guitkx.gd:475-491`) has no gate at all (module-member multi-root compiles fine).
**Target.** One helper `static func _has_error(diags) -> bool` (severity==0 after T0.2). Check it BOTH
after `_validate` AND after `_emit` in `compile()`; add the same double-check inside `_compile_module`
per member and for the module as a whole. `ok:false` ⇒ plugin does not write the sibling `.gd` (verify
`plugin.gd` honors `ok`, and that a previously-written stale `.gd` is deleted or left with a banner —
choose delete + push_error).
**Tests.** GD headless: `@while` in expression position ⇒ `ok:false`, no `.gd` written; module member
with 2 roots ⇒ `ok:false`. Contract fixture each.
**Done when.** No diagnostic with error severity ever coexists with `ok:true`.

### T1.2 — Silent-`null` emissions become diagnostics  · effort: small · Status: ✅ (all 3 sites — `_validate_body`, `_emit_body`, `_emit_markup_substring` — append the INNER parser's own code/message/offset via base-threading; bonus 4th silent path found by the new test: `jsx_scan.find_markup_ranges` dropped UNBALANCED nested markup entirely, so `{ open and <Broken> }` emitted raw `<Broken>` as GDScript — now reported as `{end:-1}` ranges that `_splice_expr_markup` routes through the markup parser for its precise 0301; offset-precision asserted by `_check_diag_at` in `_test_p1_error_gates`)
**Current.** Malformed markup inside a branch/loop/nested-expr emits `null  # body parse error` with
zero diagnostics (`guitkx.gd:283-284, 784-785, 1053-1054`).
**Target.** Each of the three sites appends an error diag (code `GUITKX0302`-family or `0300` with the
inner parser's message and the body's offset) — after T1.1 that fails the compile, matching Unity
(PIPE:184-207 fails codegen on every parser error).
**Tests.** Fixture per site: `@if (c) { <Broken> }`, `@for` body, nested-jsx expr. GD + contract.
**Done when.** Grep `# body parse error` finds no reachable silent path.

### T1.3 — Second declaration / trailing junk: error; formatter stops deleting content  · effort: small/medium · Status: ✅ (code is **GUITKX2105**, not the draft's 2104 — DC.cs authority check: Unity 2105 = "Invalid top-level statement after function-style component declaration", 2104 = mixing directive-header form, no Godot analog; compiler: `_error_on_trailing` after component/hook/module + junk-between-module-members check (`_compile_hook` de-duplicated onto `_parse_hook_at` to learn its end); formatter mirrors: preamble canonicalized ONLY when pure ws+@class_name else byte-verbatim, trailing content re-emitted after one canonical blank line (idempotent), module junk ⇒ whole-doc verbatim — 2 new shared corpus cases; workspaceIndex.reindex filters to first-decl+its-members (scanDeclarations stays full for outline); declarations.ts adds the LIVE 2105 mirror; contract fixture t13_second_decl)
**Current.** Second top-level decl silently dropped (`guitkx.gd:54-69`) while the LSP indexes it
(`workspaceIndex.ts:35-88` — completion offers a component that doesn't exist in the `.gd`); Format
Document DELETES unrecognized regions incl. leading file comments (`formatGuitkx.ts:49-75, 740-747`).
Unity errors (UITKX2104/2105, DP:434-456). Matrix row 5 (data-loss grade).
**Target.** (a) Compiler: after the first decl's closing brace, any non-whitespace/non-comment content
⇒ error `GUITKX2104: only one top-level declaration per file` (renumbered family, §Renumbering) at that
offset — EXCEPT `module { }` which is the sanctioned multi-decl container. (b) Formatter (`formatGuitkx.ts`
AND `guitkx_formatter.gd` — mirrored): emit unrecognized spans verbatim in place; leading comments/blank
lines before the first decl are preserved byte-for-byte. (c) `workspaceIndex.ts`: index only what the
compiler would compile (first decl or module members) so completion matches reality.
**Tests.** Formatter fixture: file with leading comment + 2 components round-trips byte-identical except
sanctioned reflow, plus the new compile error. Contract fixture.
**Done when.** Format Document can never lose user text; second decl is a squiggled error, not a ghost.

### T1.4 — `_split_return`: last-top-level-return semantics (Unity parity)  · effort: medium · Status: ✅ (probe answered: setup is NOT jsx-scanned, so the plan's 2102 branch is the true one. "Top-level" = first token on its line AND line depth <= body anchor (same anchor rule as _reindent_setup); LAST top-level `return (`/`return <` wins; demoted returns → GUITKX2102: earlier top-level ones ("setup cannot return before the final markup return" — Unity's C# compiler catches these, Godot must), and statement-level MARKUP-shaped ones (bare `<`, or parens whose first real char is `<`/`@` — a lambda's `return (x+1)` is legal GDScript and never flagged); chosen window content must pass Unity's LooksLikeMarkupRoot (`<`/`@`/`{`) else 2102; top-level `return other` with no candidate = 2102 malformed (Unity distinction vs 0102 missing); `return null` guards stay sanctioned. All 4 mirrors updated (guitkx.gd, formatGuitkx.ts + closes-beyond-window="unclosed" fix, virtualDoc.ts; guitkx_formatter.gd inherits via _parse_component_at) — contract t04 golden flipped exactly as planned, new fixtures t14 (two returns) t15 (lambda guard) t16 (G9 @for-only→0102); unreachable-0114 now means only code after the CHOSEN return. Codes stay 0102/0114 until T3.1 renumbers)
**Current.** FIRST `return (`/`return <` wins, indentation-blind — even inside an `if:` block
(`guitkx.gd:494-521`, re-verified) — silently dropping the rest of the body with only warning GUITKX0114
(`guitkx.gd:200-211`). Unity: LAST top-level `return ( ... );` (DP:1441-1551); code after = hint. Matrix
row 29 / exec #3; the cause behind filed **G6**'s symptom.
**Target.**
1. Scan the WHOLE body (skip strings/comments via `L.skip_noncode`); collect every markup return
   (`return (`, `return <`); classify **top-level** = column-0-relative indent depth 0 within the body
   (compute from the line's leading whitespace vs the body's base indent — the body is already
   reindent-normalized, so depth 0 is well-defined).
2. Choose the LAST top-level one. Indented markup returns are legal *statements* (conditional early
   returns) — they stay in the setup code verbatim and are compiled as GDScript (they return raw
   VNodes — verify `V` markup inside setup is handled by the jsx-scan path; if not, error `GUITKX2102`
   on indented markup returns instead of silently supporting them — probe first, pick the branch that
   is true, document which).
3. No top-level markup return ⇒ existing missing-return error (renumbered 2101). Code after the chosen
   return ⇒ unreachable hint (renumbered 0107; replaces warning 0114) — live tier mirrors it with an
   `Unnecessary`-tagged diagnostic so VS Code dims (closes the markup half of **G6**).
4. Mirror the same selection in `formatGuitkx.ts splitReturn` + `virtualDoc.ts` + `guitkx_formatter.gd`
   (four mirrors rule) — contract fixtures: early-return-in-if, two top-level returns, return-null guard
   then markup return (already skipped — keep), `@for`-only no return (**G9** fixture — must produce 2101).
**Done when.** The `slicing.guitkx` repro (early `return <s></a>` line 7 + real `return (` line 13)
compiles the line-13 return, flags line 7's tag errors (T1.5) and dims nothing silently.

### T1.5 — Unknown tags validated; markup parse errors surfaced live  · effort: medium · Status: ✅ (compiler: the check lives at `_emit_element` — the single chokepoint every element passes (main tree, control-flow bodies, {expr}-nested) — lowercase tag ∉ v_factories ⇒ 0105 + did-you-mean (edit-dist ≤2 over factories∪aliases∪module∪known); PascalCase checked against `known_components` (new optional `compile()` arg, Dictionary-set; empty ⇒ skipped) with module-locals always known; codegen `known_component_names()` = sibling .guitkx bindings (@class_name ?? first-decl name) + `ProjectSettings.get_global_class_list()`, built once per `compile_all` pass and now also fed by guitkx_build.gd. LSP: new pure `liveMarkup.ts` (declarations.ts pattern) — `windowStructureDiags` publishes window parse errors (0301/0302/…) AND directive-body parse errors (bodies are opaque to the window parse), plus the lowercase-vocabulary 0105 via a GD-`_validate_node`-mirroring AST walk with composed body_at offsets; wired into `markupDiagnostics`. **PascalCase live check stays suggestion-gated until T4.5** (ungated it would false-flag hand-written .gd component classes only the compiler's known-set can see) — documented in server.ts. Corpus audit: the only lowercase tag outside the vocabulary in the whole repo is the G5 repro's `<s>` itself)
**Current.** Compiler never validates tag names (emit-time classification only: lowercase → `V.<tag>`
verbatim, PascalCase → assumed component — `guitkx.gd:703-712, 757-766`); LSP computes markup parse
errors live then discards them (`server.ts:1494-1496`, re-verified) and gates unknown-tag on a
did-you-mean existing (`server.ts:1568-1580`). Filed **G5**; matrix rows 11–12.
**Target.**
1. Compiler: lowercase tag not in `vocabulary.json.v_factories` ∪ host_tags ⇒ error
   `GUITKX0105: unknown element <x>` (+ did-you-mean when edit-dist ≤2). PascalCase tag not in
   host_tags: resolvable check needs the project index — the compiler runs in-editor, so consult
   (a) `ClassDB.class_exists` no (script classes:) (b) `ProjectSettings`-registered script classes +
   (c) sibling `.guitkx` files via the plugin's existing scan; plugin passes a `known_components`
   Array into `compile()` (new optional arg, default empty = skip check for headless callers).
   Unknown ⇒ error 0105.
2. Mismatched close already errors in both parsers (GUITKX0302) — the gap is LIVE surfacing: in
   `scanWindowDiagnostics`, publish `pr.error` (it carries offset — map through the window) instead of
   discarding; remove the suggestion gate on live 0105 (fire always, suggestion optional).
3. `</a>` vs `<s>` fixture (the user's exact repro) must produce: 0302 mismatched close + 0105 unknown
   element ×2, live AND compile.
**Done when.** `return <s></a>` shows two-plus precise squiggles while typing, and the compile fails.

---

## Phase 2 — Missing Unity features (superset mandate)

### T2.1 — Markup comments  · effort: medium · Status: ✅ (all four Unity forms in both mirrored parsers — `//` and `/* */` at node-start only (a `//` inside a text run, e.g. a URL, stays text), `<!-- -->`, and `{/* */}` in attribute lists (scanned to `*/` + `}`, not brace-matched, so comment text may hold braces); comment nodes/attrs emit NOTHING (all emitter/validator/root-count consumers skip them) and both formatters preserve them verbatim — parseComponentAt/_parse_component_at now expose ALL window nodes so root-adjacent comments survive Format Document; virtualDoc skips `{/*` holes; `#` deliberately NOT added (collides with GDScript in expression islands — docs fix in T6.1); T1.4's LooksLikeMarkupRoot check gained _first_markup_real (comment-skipping, mirroring Unity's TrySkipNonCodeSpan))
**Current.** No comment syntax in markup at all (`guitkx_markup.gd:294` open question); docs claim `#`
comments (GDoc Reference:312-315) and doc snippets use `//` (EventsPage.example.ts:21-148). Matrix row 15.
**Target.** Implement Unity's full set in markup context: `//` line, `/* */` block, `<!-- -->`, and
`{/* */}` inside attribute lists — semantics per UP:463-480, 766-772 + MT:270-285: skipped or preserved
as CommentNodes that emit nothing; the formatter preserves them. Implement in `guitkx_markup.gd` AND
`markup.ts` (byte-identical discipline) + formatter mirrors. Do NOT add `#` in markup (it collides with
GDScript comments inside expression islands and Unity doesn't have it) — fix the docs instead (T6.1).
**Tests.** Contract fixtures: comment before root, between siblings, inside attr list, `//` inside a
string attr (must NOT comment), `/* */` spanning lines. Formatter round-trip preserves all.
**Done when.** Every doc snippet that uses `//` in markup compiles.

### T2.2 — `<Fragment>` named alias  · effort: small · Status: ✅ (checked the Unity source: the PARSER keeps Fragment a named element; **PropsResolver** resolves it case-insensitively to TagResolutionKind.Fragment and EmitFragment honors only `key` — mirrored: _mk_el/mkEl converts any case of `fragment` to a frag node carrying `named` (author's spelling, formatter round-trips) + attrs; `key` threads to V.fragment's existing 2nd arg; any OTHER attribute is a GUITKX0107 error (Unity drops silently — against the no-silent-drop charter, divergence documented); vocabulary.json + schema BASE_TAGS gained the tag so completion/hover work and the live probe skips it; contract fixture t18)

### T2.3 — `@uss` equivalent: `@theme` directive  · effort: medium · Status: ✅ (default naming shipped: **`@uss` for doc-compat, `@theme` as the Godot-idiomatic alias** — 🔷 confirm at PR review; `@uss "res://x.tres"` preloads via `const __THEME := preload(...)` and injects a synthesized `theme={ __THEME }` attr on the root ELEMENT unless one is explicit; missing path ⇒ 0120, non-Theme ⇒ 0121 (ResourceLoader.exists("Theme") — the T2.7 machinery, two birds as planned), hook/module file ⇒ 2210, second directive ⇒ 2210, non-element root ⇒ 2210; formatter preserves the directive via the T1.3 verbatim-preamble path; schema.ts completion/hover updated from "(reserved)" to the real semantics + the @theme alias; real tests/assets/test_theme.tres fixture. Docs headline becomes truthful in T6.1)
**Unity semantics.** `@uss "./file.uss"` loads a stylesheet; error UITKX2210 when used in hook/module
files (DP:1250-1315, 484-493). Godot's LSP already advertises `@uss` "(reserved)" (`schema.ts:75-78`)
and the docs headline it (GDoc Reference:16) — an over-promise today (matrix row 2).
**Recommendation (🔷 confirm naming with user at PR time; default = ship as `@uss` for doc-compat, alias `@theme`).**
`@uss "res://path.tres"` preloads a `Theme` resource and assigns it to the component's root control
(`V` root gets `theme` prop if not explicitly set). Non-`.tres`/`.theme` path or missing file ⇒ error
(renumbered 0120 asset-path check — two birds). In hook/module files ⇒ error 2210. Compiler emit: a
`const __THEME := preload("res://...")` + root-prop injection in `_emit`. LSP: completion, hover, path
validation live (`FileAccess.file_exists` equivalent on the LSP side = fs check via workspace root).
**Tests.** Compile fixture with a real tiny `.tres`; missing-path error; hook-file placement error.
**Done when.** The docs' headline example is truthful.

### T2.4 — Text interpolation: Unity semantics + migration warning  · effort: medium · Status: ✅ (both parsers: text stops only at `<`/`@` (was `<`/`{`); `{expr}` recognized at node start only; mid-text braces literal; GUITKX0150 warning fires compile (_validate_node text arm) + live (liveMarkup walk, warning severity threaded through LiveMarkupDiag/DeclDiag→server); corpus audit found ZERO real mid-text interpolation anywhere in the repo so no demo migration was needed, and markup-cases.json regenerated byte-identical; contract fixture t19 pins both the literal run + the node-start expr)
**Current.** Godot text stops at `{` — mid-text `{expr}` interpolates (`guitkx_markup.gd:174-181`;
`guitkx.gd:671-674, 739-741`). **User decision: adopt Unity's way** — text runs to `<` or `@` only
(MT:340-353); `{expr}` recognized at node start only.
**Target.** Change `guitkx_markup.gd` text scanning (and `markup.ts` mirror) to stop only at `<`/`@`;
keep node-start `{expr}` nodes. **Migration warning (mandatory):** when a text node CONTAINS `{`,
emit warning `GUITKX0150: braces inside text are literal since <version>; use text={ "..." % ... } or a leading {expr} node`
— permanent (cheap + protects future users), live + compile. Migrate every demo/doc snippet that used
mid-text interpolation (grep `examples/` + `GDoc` for `\w{` inside text nodes) to `text={ ... }` form.
**Tests.** Fixture: `Count: {n}` renders literal + warns; `{n}` at node start still interpolates;
formatter round-trip. Runtime demo check via headless suite.
**Done when.** Same fixture produces identical AST classification on Unity (spot-check against MT
semantics in the golden) and Godot; demos green.

### T2.5 — Rules-of-hooks: four-context validation  · effort: medium · Status: ✅ (the one-shot indent heuristic became a deterministic BLOCK-OPENER STACK over setup lines (same _indent_unit/_indent_depth geometry as emission): hook call under if/elif/else ⇒ 0013, for/while ⇒ 0014, match ⇒ 0015, `func():` lambda ⇒ 0016, single-line `if c: use_x()` included; ALL are errors (were: one 0013 warning max) and every violation reports; runs on component setup + hook decl bodies + module members; (d) a hook CALL inside a markup {expr} (attr or child) ⇒ 0016 in _validate_node — hook RESULTS are fine (token-boundary `_expr_calls_hook`, which also fixed `_line_calls_hook`'s substring false-positive on `my_useState(`). LSP: `hookContextDiags` in liveMarkup.ts is the routine ported line-for-line over `setupSpans()` (new formatGuitkx export; indentUnit/indentDepth now exported so both consumers share ONE geometry), same fixtures asserted on both sides; virtualDoc keeps its stubs (the analyzer needs them) exactly as planned. Demos: zero hits — build stays 0 errors/3 warnings on clean sources)
**Current.** One indent-heuristic warning (GUITKX0013), compiler-only, max 1/component, never on hook
decls or module members (`guitkx.gd:221-251`); LSP stubs legalize bare hooks everywhere
(`virtualDoc.ts:26-50, 442-448`) while the compiler prefixes only setup/hook bodies — LSP-green code
fails at runtime. Matrix row 32.
**Target.** Port Unity's four checks (DA:517-665 semantics): hook call inside (a) conditional, (b) loop,
(c) `@match` branch, (d) markup attribute expression ⇒ errors 0013/0014/0015/0016. Contexts (a)-(c)
detected in the SETUP code by GDScript-aware scanning (a hook call whose line sits under an
`if/for/while/match` block within setup — use indent depth after reindent-normalization + the block-opener
stack; this is deterministic, unlike the current heuristic); (d) any `use_*`/vocabulary-hook call inside
a markup `{expr}`. Run on component setup, hook decl bodies, and module members alike. Fix the model
mismatch: virtualDoc keeps stubs (analyzer needs them to type hooks) but the LSP live tier fires
0013-0016 itself from the same shared routine ported to TS (contract-tested).
**Tests.** Fixture per context ×(component, hook, module member); negative fixtures (hook at top level
of setup; hook result used in attr expr is FINE — only the *call* in attr is flagged).
**Done when.** The four contexts squiggle live and fail compile, identically GD/TS.

### T2.6 — Naming checks: PascalCase components, `use_` hook prefix  · effort: small · Status: ✅ (GUITKX2100 error in _parse_component_at — single chokepoint, module members included, parse continues for further diags; GUITKX2203 warning in _parse_hook_at; leading junk before the first decl = GUITKX2105 in compile() (comments/@directive lines exempt — a misspelled directive keeps its better 0300 did-you-mean live); live mirrors in declarations.ts (DeclInfo gained `kw` since a member's kind erases the keyword; DeclDiag gained warning severity); corpus effect: 3 helper hooks in stress/gallery demos now carry honest 2203 warnings — goldens regenerated, build reports 3 warnings / 0 errors on clean sources)
**Target.** Component name not PascalCase ⇒ error 2100 (Unity DP:200-280 parity; GDScript class_name
convention is PascalCase too). Hook name not starting `use_` ⇒ warning 2203 (snake adaptation of
Unity's `use` prefix, UP evidence DP:575-653). Also fix `_find_decl`'s garbage-skip (matrix row 4):
non-comment junk before the first decl keyword ⇒ error 2105. Both parsers + fixtures.

### T2.7 — Unity-only diagnostic ports  · effort: medium · Status: ✅ (authority note: 0018/0019/0020/0021 live in the GENERATOR (`SourceGenerator~/Diagnostics/UitkxDiagnostics.cs`, marked "source-gen-only"), not DC.cs — so compile+sidecar IS the Unity-parity surface for them, no live tier owed. Shipped: **0018** warning — `useEffect`/`useLayoutEffect` (incl. `Hooks.`-qualified) with a single argument, `_validate_effect_deps` over setup + hook bodies + module members; **0019** warning — the @for binder used DIRECTLY as `key={ binder }` (a derived `str(binder)` stays clean, matching Unity's direct-use rule; the keyed demo's `key={ id }` migrated to `str(id)` to match every other demo); **0111** warning — component param never token-referenced in the body, `_`-prefixed exempt (GDScript convention), anchored at the param name via new `params_at`; **0120/0121** errors — `res://` string literals in `texture`/`icon`/`theme` attrs checked with FileAccess.file_exists / ResourceLoader.exists(type: Texture2D/Theme). **0020/0021: n/a** (the plan's own probe branch) — they check C# `Ref<T>` typed parameters, which Dictionary-props components structurally lack. Fixing the T2.5 single-line heuristic fell out of the 0018 test: `useEffect(func(): ...)` no longer false-flags 0016 (the opener colon must PRECEDE the hook call; both mirrors))
Port each check with Godot-appropriate semantics (numbers = Unity's, per §Renumbering; each gets live +
compile + fixture):
- **0018** `use_effect` call whose last arg is missing (no deps array) ⇒ warning. Detect via vocabulary
  hooks' known arities.
- **0019** loop iterator used directly as `key` (`key={ i }` where `i` is the `@for` binder) ⇒ warning
  (index-as-key React footgun).
- **0020/0021** ref-prop arity: `ref={ expr }` where expr is a call with wrong arg count against
  `use_ref` shape — port only if Godot has ref props (grep `\"ref\"` in `guitkx.gd`/`src/`; if absent,
  mark n/a in the coverage map instead).
- **0111** unused component param: param name never referenced in setup or markup ⇒ warning.
- **0120/0121** asset-path existence/type for `res://` string literals in known asset-taking attrs
  (`texture`, `icon`, `theme`, `@uss` path — T2.3 shares this) ⇒ error when missing.
**Done when.** Coverage map shows no "gap" row without a shipped code or an explicit n/a.

### T2.8 — `module` semantics  · effort: decision · Status: ✅ (recommendation applied: **KEEP Godot's declaration-container module** — strictly more useful with no partial classes in GDScript; Unity's verbatim-code module exists to host namespaces/usings, which GDScript doesn't have. Divergence goes on the differences page in T6.1. Flag at PR review if Unity semantics are wanted instead)
**Divergence.** Unity `module Name { raw C# }` = opaque code container (DP:657-680); Godot
`module Name { component…/hook… }` = declaration container with structure checks (matrix row 7).
**Recommendation: KEEP Godot's declaration-container module** (it is strictly more useful with GDScript
having no partial classes; Unity's verbatim-code module exists because C# needs a place for
namespaces/usings). Document the divergence prominently (T6.1) and rename nothing. If the user instead
wants Unity semantics, this becomes: accept raw GDScript bodies in modules, emit verbatim into the
sibling `.gd` — flag before implementing.

---

## Phase 3 — Diagnostics parity + renumbering

### T3.1 — Renumber GUITKX codes to the Unity concordance  · effort: medium · Status: ✅ (final concordance, DC.cs-verified: **0102→2101** (missing return; 2102-malformed already shipped in T1.4), **0107→0109** (unknown attribute, Unity 0109), **0114→0107** (unreachable, Unity 0107 — swept 0107→0109 FIRST to avoid collision), **0113→0026** (undesugarable-in-expression, Unity 0026), **0306→2506** (Godot's 0306 means directive-syntax error while Unity's is AtExprNotSupported — different meanings may not share a number, so Godot-reserved), **0110→2504 / 0112→2505** (module structure — Unity has no decl-container module, so 25xx per the plan's fallback). Kept: 0013-0016, 0018, 0019, 0026-new, 0103-0106, 0108, 0109-new, 0111, 0120, 0121, 0150, 0300-0305, 2100, 2102, 2105, 2203, 2210. Swept atomically over compiler, both parsers, vocabulary (severities+live) ×2, LSP src+tests, GD tests, and the docs-site diagnostic pages; goldens + markup-cases REGENERATED (only t05/t16 changed — the 2101 rename); CHANGELOGs deliberately untouched (history), release-notes pair list goes in the version-bump changelog at publish; ships as MINOR per plan)
Single mechanical pass, `vocabulary.json.messages` is the one place numbers live after T0.3. **Verify
each Unity meaning against `U/ide-extensions~/language-lib/Diagnostics/DiagnosticCodes.cs` before
renaming — the table below is the intent, DC.cs is the authority.**

| Godot today | Meaning | New code |
|---|---|---|
| 0102 | missing `return (` | **2101** (malformed-return variant, if emitted distinctly: **2102**) |
| 0107 | unknown attribute | **0109** |
| 0114 | unreachable after return | **0107** (severity: hint + Unnecessary tag) |
| 0110 | nested/empty module | **22xx** module-family number matching DC.cs (else 2504) |
| 0112 | duplicate module member | **22xx** likewise (else 2505) |
| 0113 | undesugarable `@while`/`@match` in expression | **0026** (Unity's undesugarable-in-expression) |
| 0300–0306 | parser codes | keep 0300/0301/0302/0305; re-check 0303/0304/0306 against DC.cs, renumber only on true meaning-match |
| 0103/0104/0105/0106/0108/0013 | already aligned | keep |
| new from Phase 2 | — | Unity's numbers (0014-0016, 0018-0021, 0111, 0120/0121, 0150, 2100, 2104/2105, 2203, 2210) |
Godot-only rules that survive with no Unity analog move to a reserved **25xx** block. Ship as **minor**;
CHANGELOG lists every old→new pair; sidecar v2 (T0.2) carries new codes only; grep the whole repo
(compiler, LSP, tests, fixtures, docs, native editor) for `GUITKX0` and update atomically.
**Done when.** No code number means different things across the two ecosystems; concordance page live (T6.1).

### T3.2 — Severity + surface consistency per code  · effort: small · Status: ✅ (vocabulary.json gained `severities` (every code) — the single severity source, pinned by a GD tripwire that regex-scans every `D.make()` literal in the compiler against the table and a TS twin asserting the reconciled trio (0104 error / 0114 hint / 2203 warning); 0104 duplicate-key is now ERROR on both surfaces (breaks reconciliation outright — t12 golden flipped); 0114 unreachable is HINT everywhere and the live message gained its code prefix so the sidecar copy dedupes via the (code,line) key; 0113 error-failing-compile was done in T1.1; 0103 warning-both was already true)
One table (in `vocabulary.json`) is the single severity source; live tier, sidecar, compiler, dock all
read it. Fix the known offenders: 0113→0026 = error failing compile (done via T1.1); unreachable 0107 =
hint everywhere + deduped (kill the double report `server.ts:1414-1422` vs `657-661` — the live tier
emits it, the sidecar copy is suppressed by identity-dedupe from T3.3); 0103 name-vs-filename: pick
**warning on both surfaces** (Unity's own IDE/compile split is its repo's problem); duplicate-key 0104
**error live, error compile** (Unity IDE = error; be consistent rather than copying Unity's internal
inconsistency). Every remaining code: assert one severity in a table-driven test.

### T3.3 — Sidecar + dedupe correctness  · effort: small · Status: ✅ ((code,line) dedupe landed in T0.2; NEW: while the buffer diverges from the last compile (hash mismatch), COMPILER-ONLY codes (∉ vocabulary.json `live`) are kept with a "(from the last compile … recompiles on save)" marker and clamped best-effort positions instead of vanishing on the first keystroke — live-computable codes drop because the live tier owns them. **Native-editor live-compile sidecar write: SKIPPED — the involved files (guitkx_editor_view.gd etc.) are the user's uncommitted working set this session; revisit when they land.** The dedupe key stays (code,line) rather than (code,line,message): messages differ legitimately between tiers (live composes its own phrasing), and code+line is what identifies "the same finding")
**Current.** Dedupe is per-CODE (`server.ts:658-665`) — a live 0104 on element A suppresses the compiler's
0104 on element B; the sidecar hash gate makes compiler-only codes vanish while typing (`guitkx_codegen.gd:23-28`
vs `diagsSidecar.ts:19-28`); the native editor's live compile never writes the sidecar (`guitkx_codegen.gd:106`).
**Target.** Dedupe key = `(code, line, message)` (structured diags make this possible); while-typing, stale
sidecar entries for codes the live tier ALSO computes are dropped, others kept with a "stale" marker until
next save; native-editor live compile writes the sidecar (or is documented as intentionally ephemeral —
decide by reading `guitkx_codegen.gd:106` context, prefer writing).
**Tests.** Two same-code diags on different lines both visible; typing doesn't erase compiler-only diags.

### T3.4 — Key-checking completion  · effort: small · Status: ✅ (probe finding: the RUNTIME already hoists spread-supplied keys — both `V.h` and `V.fc`/`_key` fall back to `props["key"]` when the key arg is null, so `{...props}`-carried keys reconcile today with no emitter change; a STATIC spread dup-check was deliberately skipped — flagging two siblings spreading the same expr would false-flag the common shared-style-dict pattern (`{...common_style}`), and whether the dict holds a `key` is unknowable statically. 0106 missing-key now also fires for FRAGMENT loop roots (fix: `<Fragment key={...}>`) and EXPRESSION loop roots (reminder wording — unverifiable statically))
Hoist spread-supplied `key` (`{...props}` carrying `key` — `guitkx.gd:724-730`) into the V-factory key
arg + include in dup-check; extend missing-key 0106 to fragment/expr loop roots (`guitkx.gd:291-293`).
(Godot's expression-signature dup detection is already superior — keep; Unity adopts it in its own plan.)
Fixtures for both.

### T3.5 — Lexer/parser bug set  · effort: small · Status: ✅ (all in BOTH parsers, goldens t06/t07/t08 flipped + markup-cases regenerated: `@class_name`/`@uss`/`@theme` require a token boundary (compiler + both formatters; declarations.ts already had it and gained the §5.1-item-5 comment-skip before the directive); `#elif`/`#else` no longer become ghost branches (the `@` itself is verified — the comment-ish line falls to literal text, where the 0150 brace warning hints at the mistake); digit tags `<9foo>` and dotted tags `<Foo.Bar/>` are 0300 parse errors (used to emit nonsense/silently eat `.Bar` as a bool attr); unterminated attribute strings error at the opening quote (used to truncate at the newline); unclosed `return (` now shows LIVE as 0304 via new `unclosedReturns()` (compiler 0304 + formatter-verbatim + virtualDoc partial-window already aligned since T1.4); jsx_scan gained the `or` boundary with a React-`||` desugar — `LHS or <B/>` emits `(V.b() if not (LHS) else null)` instead of raw markup in GDScript (ternary-LHS positions were already covered by the start/`(`/`,`/`=` boundaries))
All in BOTH parsers + contract fixtures (matrix rows 3, 10, 17, 22 + §5.1 items 4-6):
- `@class_name` token boundary: require whitespace after the keyword (`guitkx.gd:38-53`; `formatGuitkx.ts:40`;
  `declarations.ts` comment-skip — §5.1 item 5: skip comments, not just whitespace, before the directive).
- `@elif`/`@else` must verify the `@` (a commented `#elif` currently becomes a real branch —
  `guitkx_markup.gd:230-237, 273-280`; `markup.ts:264-271`).
- Tag names: reject leading digits; `<Foo.Bar/>` ⇒ error (today: silent tag `Foo` + bool attr `.Bar`)
  (`guitkx_markup.gd:297-301`).
- Unterminated attribute string ⇒ error at the opening quote (today: silent newline truncation,
  `guitkx_markup.gd:160-163`).
- Unclosed `return (` — ONE behavior everywhere: compiler error 0304 stands; formatter falls back to
  verbatim (no reflow) AND the LSP live tier shows 0304; virtualDoc emits the partial window (not
  empty-continue) so the analyzer still checks setup (`guitkx.gd:506-508`; `formatGuitkx.ts:695`;
  `virtualDoc.ts:496`).
- jsx_scan boundary holes: markup after `or` and in ternary-LHS position (`guitkx_jsx_scan.gd:20-71`),
  mirroring Unity's operator set (DP:2299-2461).

---

## Phase 4 — Analyzer-side parity (GA repo; per-task commits, ONE user-gated publish chain at end of phase)

### T4.1 — Godot-native message golden table  · effort: medium · Status: ✅ (GA `d316175`. 45+ probes on the REAL 4.7.stable binary (`--check-only`; warning texts via per-code error promotion in project.godot) → every 1:1 template reworded verbatim + pinned by `crates/gdscript-hir/src/godot_messages_tests.rs` (50 tests incl. negatives where Godot is silent). The ADR-0008 "contradiction" dissolved: Godot prints BOTH phrasings per method miss (member-check + call-check lines); GA emits the kind-matching one. Probes also exposed and fixed two inverted behaviors: UNASSIGNED_VARIABLE tracks UNTYPED no-init locals (typed are zero-initialized — q11/r35), ENUM_VARIABLE_WITHOUT_DEFAULT is member-only and gated on the enum lacking a 0 value (r46/r47/r48). Corpus 138 projects: 0 parse errors/panics, no new codes)
**Current.** GA's messages are recognizably not Godot's; the repo even holds two INCONSISTENT recorded
native phrasings for the same probe (`docs/src/adr/0008:9` "Function \"casll()\" not found in base
Callable" vs `infer.rs:3040-3041` "Cannot find member … in base …"). No test pins any message.
**Target.** Probe once, on the real binary
(`/c/Yanivs/daniela test/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe --headless --check-only --script`),
each mistake class: builtin method miss, builtin property miss, undefined identifier, undefined function,
type mismatch (assign + arg), unused variable, unreachable code, arity high/low, missing-colon syntax
error, unexpected-token syntax error. Record verbatim into `GA/crates/gdscript-hir/tests/godot_messages.rs`
as a golden table; reword GA's templates to match Godot's phrasing wherever a code maps 1:1 (keep GA's
extra precision as a suffix only if it doesn't fight the phrasing); reconcile ADR-0008's contradiction in
the ADR text. Corpus run must stay diff-clean vs baseline (message text isn't in the corpus key — verify).

### T4.2 — Humanize parse-error tokens  · effort: small · Status: ✅ (GA `14f9383`. `SyntaxKind::display_name()` over the cstree static-text table (`":"`, `"in"`, `"Literal"`, `"Indent"` — Godot's own quoting, probed); `expect()` emits `Expected ":".`, with `expect_after`/`expect_closing` carrying Godot's verbatim contextual wordings at the probed sites (if/elif/else/while/for/match/class colons, function/lambda/signal/call closers, for-in and match-arm dual-token texts, annotation/signal names, `Unexpected "Literal" in class body.`); 17 wordings pinned by `syntax_error_messages_match_godot`)
`expected Colon` / `expected InKw` / `expected RParen` leak Rust Debug enum names
(`GA/crates/gdscript-syntax/src/parser/parser.rs:324-328`). Add a `display_name()` on the token kind
(`":"`, `"in"`, `")"`, …) and use Godot's syntax-error phrasing from T4.1's probes. Snapshot tests.

### T4.3 — Arity errors  · effort: medium · Status: ✅ (GA `be9a5dc`. `CallSignature` (name, fixed param types, required = default-less count, vararg flag) resolved for own funcs (FuncItem gains `is_vararg` — `...rest` absorbs surplus), inherited engine methods, builtin-receiver methods (new coverage — the closed tables carry full sigs), utilities, and the `@GDScript` layer's min/max. Emits TOO_FEW/TOO_MANY_ARGUMENTS (new ERROR-default catalog codes, Godot-verbatim texts) + the previously-silent definite arg-type mismatch as Godot's `Invalid argument for "f()" function: …`. Callable values/shadowing locals/cross-file/constructors stay silent by design. Corpus gate: ZERO arity or invalid-arg hits across 138 demo projects)
`check_call_args` deliberately breaks on arity (`infer.rs:2304-2306`) — Godot hard-errors. Emit
TOO_MANY_ARGUMENTS / TOO_FEW_ARGUMENTS (check the WarningCode catalog for existing names first; ERROR
default for resolved own/builtin/api functions; SILENT through Unknown seams and variadics — vararg flag
from the API table). Corpus gate before default-on (the A1 lesson: broad corpus, zero FPs, else demote).

### T4.4 — Unnecessary/Deprecated tags + UNREACHABLE_CODE → dimming  · effort: small/medium · Status: ✅ (UNREACHABLE_CODE turned out ALREADY SHIPPED in GA (flow.rs dataflow + emission + test) — the task collapsed to the tags half. GA `966e006`: the Diagnostic POD gains `tags: Vec<DiagnosticTag>` serialized as the LSP numbers (`tags: [1]`; key omitted when empty → pre-tag wire shape untouched), sourced from the WarningCode catalog (unused/unreachable family → Unnecessary), mapped in gdscript-lsp. RG `854132d`: the adapter forwards tags → VS Code dims embedded dead code (the GDScript half of **G6**), and an analyzer UNREACHABLE_CODE inside a markup-level 0107 region is dropped (one report per range))
Check `warnings.rs` for UNREACHABLE_CODE; implement if absent (post-`return`/`break`/`continue` statements
in a block — flow framework likely already computes reachability; verify). Expose LSP DiagnosticTags
through the napi surface (`Diagnostic` POD gains `tags: Vec<u8>`), map in `analyzerAdapter.ts:65-74`
(today tags never cross), publish. VS Code then dims embedded-GDScript dead code — the GDScript half of
**G6**. RG side: dedupe with the markup-level 0107 (one report per range).

### T4.5 — Veto seam → virtual library shims (**G8** root fix)  · effort: medium · Status: ✅ (GA half (`dba20a3`): the plan's "verify name-binds" surfaced the REAL G8 mechanism — the unclosed paren suppresses the pre-pass's synthetic newlines, so the broken lambda's inline body swallows the rest of the function, and the swallowed use resolved BEFORE the binding was pushed. Fixed at the right depth: a declaration's name is now visible to its own initializer (seam-typed) — which also fixes legal `var f = func(): f.call()` (a real FP). RG half (`854132d`): `vetoGuitkxDeclared` DELETED; every indexed .guitkx feeds `class_name <binding>` + VARIADIC member stubs as a virtual library (arity-transparent by construction), retired whenever the real generated sibling .gd exists. e2e: binding resolves + typo flags (green on BOTH cores), G8 no-cascade + tags gated on core 0.5.5. Unlock delivered: live PascalCase 0105 ungated against the merged universe (index bindings + harvested .gd class_names). **G7** re-verified: `fsunc():` now yields a syntax error (GA reads the trailing colon as a property-accessor opener — different wording than Godot's, error presence is the criterion) with no false UNDEFINED)
**Current.** `vetoGuitkxDeclared` (`workspaceIndex.ts:235-242`) suppresses UNDEFINED_FUNCTION/IDENTIFIER
for ANY `.guitkx`-indexed name — a typo colliding with a `.guitkx` name is silent (Godot would error).
**Target.** Feed `.guitkx` declarations INTO the analyzer as generated virtual libraries (the vdoc
already emits module members under real names — extend to per-file components/hooks with their real
signatures via `upsertLibrary`), then DELETE the veto entirely. UNDEFINED_* then resolves correctly with
member tables and arg-checking (composes with T4.3). This also fixes G8's shape: a declaration whose
initializer fails to parse must still bind its NAME (analyzer recovery keeps `var toggle` as a binding
with error type — verify GA does this; if not, fix in GA: declarations with unparsable initializers
bind Unknown, and add a test).
**Tests.** RG e2e: typo `usse_state` near a real `.guitkx` `use_state` ⇒ UNDEFINED_FUNCTION with
did-you-mean; `{ toggle }` with broken lambda initializer ⇒ NO undefined-identifier + a syntax error on
the lambda line (the **G7+G8** repro end-to-end).

### T4.6 — LSP `Diagnostic.code` + default warning set  · effort: small · Status: ✅ (The engine-defaults mechanism turned out fully built in GA (WarningOverride/engine_default/--engine-defaults) but unreachable from the bindings. GA `dba20a3`: `setWarningOverride("engine-defaults"|"strict"|"none")` plumbed through session/napi/wasm. RG `854132d`: the adapter selects engine-defaults at construction (guarded no-op on a pre-0.5.5 core) so the editor never warns where Godot wouldn't, and the `CODE: message` fold is gone — analyzer codes are real LSP `Diagnostic.code`s with a `codeDescription` link to the generated Warning Reference)
Stop folding codes into message text: set `Diagnostic.code` (+ `codeDescription` linking GA's warnings
docs) in `analyzerAdapter.ts`/`server.ts:639-644,886`; message becomes Godot-phrased text only (T4.1).
No-`project.godot` default: match engine defaults instead of promoting UNSAFE_* to WARN
(`warnings.rs:531-540`) — VS Code must not warn where Godot wouldn't.

**G7 note.** `fsunc():` acceptance is expected to fall out of T4.5's e2e + existing GA syntax reporting
once virtualDoc stops swallowing the window (T3.5 unclosed-return behavior + T5.1). After T5.1 lands,
re-run the G7 repro; if `fsunc():` still yields zero diagnostics, root-cause in GA's parser recovery
(a lambda-like `name():` header should produce exactly one syntax error and still parse the indented
body as a block — mirror the A4 over-indent recovery pattern).
**G7 re-run (2026-07-03, local 0.5.5 core): CLOSED.** `var f = fsunc():` yields `GDSCRIPT_SYNTAX:
Expected "get" or "set" in a property accessor.` (GA's var-decl grammar legitimately reads a trailing
colon as the property-accessor opener — not Godot's wording for this shape, but an ERROR where there
was silence, which is the G7 criterion) and NO false UNDEFINED on later uses of `f`.

---

## Phase 5 — Single source of truth completion

### T5.1 — TS port of `guitkx_jsx_scan.gd`  · effort: medium · Status: ✅ (`jsxScan.ts` — same function/variable names, same boundary set incl. T3.5's `or` and the T1.2 `{end:-1}` unbalanced contract; §5.1 item 1 closed. virtualDoc's `emitExpr` now runs `neutralizeMarkup` over every spliced expression: each markup range becomes `null` PADDED TO THE SAME LENGTH (`<A/>` = 4-char minimum, `null` always fits), so the expression stays valid GDScript for the analyzer AND the 1:1 offset map holds — the G7/G8 syntax-noise source is gone. Same fixture strings tested on both sides)
**Current.** No TS port (§5.1 item 1) — virtualDoc splices expression blocks verbatim
(`virtualDoc.ts:344-355`), so nested markup reaches the analyzer as garbage (feeds **G7/G8** noise).
**Target.** `jsxScan.ts`, byte-identical port discipline (same fn/var names, same fixtures), INCLUDING
T3.5's new `or`/ternary boundaries. virtualDoc uses it to replace nested markup spans with
type-preserving placeholders (a `V.fc(...)`-shaped call or `null` cast) before analyzer sync. Contract
fixtures: every boundary case from `guitkx_jsx_scan.gd` + the two new ones.
**Done when.** A component using `@if`-ternary markup in an expression island produces ZERO analyzer
syntax diagnostics from the spliced window, and the contract pending-list drops item 1.

### T5.2 — Typo-recovery + remaining LSP/compiler unifications  · effort: small · Status: ✅ (declScan.ts `nearestDeclKind` was already the spec — edit-dist ≤2, length ≥3, `looksLikeDecl` shape gate; the drift was in guitkx.gd `_nearest_decl_keyword` and declarations.ts `nearestDeclKeyword` (both ≤3, no length floor) — both now ≤2/≥3. The directive near-miss (`@clasaas_name`, ≤3) keeps its own threshold: directives are longer tokens with a different false-positive profile. §5.1 sweep: items 1 (jsxScan) and 5 (comment-skip, T3.5) closed; items 2-3 were T0.3; 4/6 were T3.5)
One shared threshold (edit-dist ≤2, min length 3, shape gate) for decl-keyword recovery in BOTH
`declScan.ts:43-78` and `guitkx.gd:104-128` (and `declarations.ts:44` hint), table-tested with the same
fixture list. Sweep §5.1 for any remaining unresolved item and close or file it.

### T5.3 — Live-tier completeness audit  · effort: small · Status: ✅ (audit table — LIVE: 0013-0016 (hookContextDiags), 0104/0108/0109 (scanWindow), 0105/0106/0150/030x/2506 (liveMarkup), 0107 (unreachableRegions + Unnecessary dim), 2100/2105/2203 (declarations), 2101 (missingReturn), 0304 (unclosedReturns). SIDECAR-ONLY with reasons: 0018/0019/0111/0120/0121 (Unity marks these source-gen-only — parity IS sidecar), 0026/2102 (emit-time semantics — need the compiler), 0103 (needs the filename), 2210/2504/2505 (structure errors needing full compile), 0121 (needs ResourceLoader). G9 closed: `missingReturnComponents` on the @for-only body flags live (the T1.4 splitReturn rewrite fixed the walk) — pinned by test. 0106 now fires live for element AND fragment loop roots (walkLoopBody), added to vocabulary `live`)
After Phases 1–3, table-audit: every compiler-emitted code either (a) has a live equivalent, or (b) is
documented sidecar-only with a reason. Close the known one — **G9**: `missingReturnComponents()`
(`formatGuitkx.ts:586-625`) must flag a component whose body is only an `@for` block (the loop-markup
walk currently satisfies the return detection); fixture = the G9 repro. Also verify GUITKX0106 (missing
key) fires live (was sidecar-only per BUG_SPLIT follow-ups).

---

## Phase 6 — Docs + demos

### T6.1 — Doc corrections batch  · effort: small · Status: 🟨 (done: `@uss` reference row is truthful (real semantics + @theme alias, was "(reserved)"); the `#`-comment claim replaced with the real Unity-parity comment set incl. the `#`-is-GDScript-only note; the two-decl HOOKS_CONTEXT_EXAMPLE is explicitly split into two files with the GUITKX2105 rationale; the renumbered codes were swept through docs.tsx + the diagnostics page in T3.1; docs site builds green. REMAINING for a follow-up docs pass: the UITKX↔GUITKX concordance page (T3.1 output), rewriting the differences page to exactly the non-goals table, the Unity-directive→Godot mapping table, and the smaller nits (snake-case-hooks self-contradiction, str(i) key rationale, .types.guitkx, Counter filename-rule) — pure authoring, no code dependencies)
GDoc fixes: `#`-comment claim → the real comment set (T2.1); `@uss` headline vs "(reserved)" → truthful
after T2.3; mid-text interpolation examples → T2.4 form; snake_case-hooks self-contradiction
(Differences:20-29); `str(i)` vs raw-int keys (Reference:52 vs todo.guitkx:30); two-decl
HOOKS_CONTEXT_EXAMPLE (HooksGuidePage.example.ts:146-173); `.types.guitkx` omission
(CompanionFilesPage.example.ts:27-31 vs 64-72); `Counter.guitkx` filename-rule violation; `@switch`
stale comment (`guitkx_markup.gd:5`). New pages: UITKX↔GUITKX diagnostic concordance (T3.1 output);
"differences from .uitkx" page updated to EXACTLY the non-goals table of this plan; Unity-directive →
Godot mapping table (incl. `@foreach`→`@for`-in, C-style-`@for`→range, `@switch`→`@match`).

### T6.2 — Demo coverage  · effort: small · Status: ✅ (`examples/demos/directives/directives.guitkx` + its Theme: every directive (@if/@elif/@else, @for-in + range, @while, @match/@case/@default), all four comment forms, `<Fragment key>`, `@uss`, spread-with-key, node-start `{expr}` interpolation — compiles clean (0 errors 0 warnings) and is copied into the contract fixtures (goldens now 61), so the grammar of record and the LSP are pinned on all of it)
Zero demos exercise `@match`/`@while`/`@elif` today. Add `examples/demos/directives/` exercising every
directive + comments + `<Fragment>` + `@uss` + spread-with-key — this demo doubles as a contract fixture
and a smoke target for the headless suite.

---

## Renumbering quick reference

Kept: 0103, 0104, 0105, 0106, 0108, 0013, 0300, 0301, 0302, 0305. Moved: 0102→2101(/2102),
0107→0109, 0114→0107, 0113→0026, 0110/0112→22xx-per-DC.cs (else 25xx). New (Unity numbers): 0014-0016,
0018, 0019, 0020/0021, 0026, 0111, 0120, 0121, 0150, 2100, 2101, 2102, 2104, 2105, 2203, 2210.
Godot-reserved: 25xx. Authority: `U/.../DiagnosticCodes.cs` at implementation time.

## Filed-bug mapping

| Bug | Closed by |
|---|---|
| **G5** unknown tag + mismatched close silent | T1.5 (+T0.2 positions) |
| **G6** no unreachable flag/dim after early return | ✅ T1.4 (markup) + T4.4 (GDScript dimming — tags cross end-to-end, live once the core dep bumps to 0.5.5) |
| **G7** `fsunc():` accepted, lambda body unchecked | ✅ T5.1 + T3.5 (window survives) + T4.5 re-run (syntax error fires; see G7 note) |
| **G8** false UNDEFINED_IDENTIFIER on `{ toggle }` | ✅ T4.5 (initializer-scoped names in GA + virtual libraries replacing the veto in RG; e2e pinned, live once the core dep bumps) |
| **G9** `@for`-only component, no missing-return | T1.4 fixture + T5.3 |

Update `BUG_AUDIT.md` §4 / `BUG_SPLIT.md` statuses as these land.

## Definition of done (whole plan)

1. Contract harness: zero pending fixtures.
2. Coverage map: zero "gap" rows (each row ✅ or explicit n/a).
3. No input mis-compiles silently (Phase 1 invariant holds against the fixture corpus).
4. All GUITKX codes: one meaning, one severity, both surfaces or documented-why-not; concordance published.
5. The five user repros from 2026-07-03 (`slicing.guitkx` session) each produce the exact expected
   diagnostics, live and compile, pinned by e2e tests.
6. All suites green: LSP vitest (incl. contract + e2e), 7 Godot headless suites, GA workspace tests +
   clippy + corpus-diff-clean; versions bumped + changelogs written per phase.
