# Field-Triage Fix Plan — post-0.6.0/0.5.0 release

> **Origin:** first real-project field test of the published toolchain (vscode ext 0.6.0 + addon
> v0.5.0 + analyzer core 0.6.0, 2026-07-03) surfaced five defect clusters. Every root cause below
> was verified against source (`feat/syntax-parity` tip == master) and the published artifacts —
> file:line anchors are the evidence, not guesses.
>
> **Method:** same as the parity plan — per task: research → fix → test → bug-hunt → commit.
> One branch + one PR per phase. Production-grade fixes, no bandaids. Publish at end of each
> phase, user-gated. Flip ⬜ → ✅ with a one-line summary as tasks land.
>
> **Branches / releases**
> - Phase A + B → `fix/live-tier-field-triage`, one PR. Patch release: lsp/ext **0.6.1**, addon **0.5.1**.
> - Phase C → `feat/early-markup-returns` (after A+B ship), one PR. Minor release: addon **0.6.0**, ext **0.7.0** (language feature = genuinely additive).

---

## Phase A — live tier (`ide-extensions/lsp-server`)

### A1 ✅ 0105 flags PascalCase host tags (`<HBox>`, `<Button>`, `<Label>`) — **S** — landed `1a3be5b`
- **Root cause:** the live PascalCase branch (`liveMarkup.ts:68-77`) checks only the `known`
  component universe and never consults `VOCABULARY.host_tags`; `known` (`server.ts:1564`) is
  built from index bindings + `class_name`s only — host tags are PascalCase too, so every one
  flags the moment `componentUniverseReady` arms (`server.ts:148-156`). NOT a vocab-load failure:
  hover (`server.ts:622`, `findTag`) reads the same loaded singleton (`schema.ts:9`).
- **Fix:** in the PascalCase branch add `&& !(nd.tag in VOCABULARY.host_tags)` (the `known` set
  stays semantically "components"). Audit the lowercase branch (`liveMarkup.ts:60`) for the same
  omission while there.
- **Tests:** regression — `windowStructureDiags` over `<HBox/>`+`<Button/>` with a **non-null**
  `known` lacking them → zero 0105; typo'd `<HBoxx/>` still flags with suggestion. (Existing
  tests never pitted a host tag against an armed universe — `core.test.ts:343-346, 961-980`.)
- **Accept:** examples/demos project shows zero 0105 on vocabulary tags.

### A2 ✅ Early markup return leaks raw markup into the virtual GDScript doc — **M** — landed `bfb12a9`
- **Root cause:** `virtualDoc.ts` splices the setup span verbatim (`emitDeclFunc` → 
  `emitVerbatimBlock:383-426`, no neutralization; only `emitExpr:365` calls `neutralizeMarkup`).
  `splitReturn:497-554` latches the **last** top-level markup return, so an earlier
  `return <s></a>` stays inside "setup" and reaches the analyzer as GDScript garbage →
  GDSCRIPT_SYNTAX / UNDEFINED_IDENTIFIER / STANDALONE_EXPRESSION / UNREACHABLE_CODE noise.
- **Fix:** neutralize markup-shaped spans inside the setup region before the verbatim splice
  (equal-length padding so the 1:1 source map survives) — the Unity analog is the LSP excluding
  `SetupCodeMarkupRanges` from the Roslyn doc (`DiagnosticsPublisher.cs:160`). Have `splitReturn`
  report the extra/early markup returns it demotes (feeds A4).
- **Accept:** `return <s></a>` mid-setup produces **no** embedded-GDScript noise; existing
  embedded-diagnostic offset tests stay green.

### A3 ✅ 2101 masked by any earlier markup-shaped return — **S** — folded into A4 (`af86a25`)
> **Landing note:** deeper analysis dissolved the standalone fix. When the "early" markup return
> is the LAST one, it *is* the window — the live markup diagnostics (0302 mismatched close, 0105
> unknown element) fire on it, which is the correct signal, not 2101. Nested-only markup returns
> already 2101 live, and now pair with live 2102 exactly like the compiler. What actually made
> return-shape problems invisible with Godot closed was 2102 being sidecar-only — A4's fix.
- **Root cause:** live `missingReturnComponents` (`formatGuitkx.ts:628/638`) reports only when
  `splitReturn === null` — i.e. *no markup return anywhere*. An early `return <s></a>` satisfies
  it, so deleting the final return shows nothing.
- **Fix:** 2101 = "no **final top-level** markup return" (the chosen return must be the last
  top-level statement-position markup return; interior ones don't count).
- **Accept:** file with only an early `return <s></a>` and no final `return (...)` → live 2101.

### A4 ✅ 2102 live + honest wording (both sides) — **S** — landed `af86a25`
- **Root cause:** 2102 is compiler-only (in `vocabulary.json` severities, absent from `live`),
  so with the Godot editor closed it never appears, updates, or clears. Its message ("a
  component's setup cannot `return` before the final markup return") overstates the rule —
  `return null` (sanctioned, `guitkx.gd:874-877`, golden t03), bare and value returns are legal;
  only **markup** early-returns are banned.
- **Fix:** emit 2102 live from A2's `splitReturn` extras; add `GUITKX2102` to vocabulary `live`
  (stale-sidecar copies then drop on buffer divergence, `server.ts:744`). Reword the message in
  `guitkx.gd:_bad_return:897-902` + live to say what it means: *"an early `return` cannot return
  markup — return null to guard, or branch with @if/@match in the markup"*. Regen contract
  goldens that pin the old text (t14 etc.). Phase C later relaxes the rule itself.
- **Accept:** early markup return squiggles live with the new wording and clears on fix, Godot
  closed throughout.

### A5 ✅ `@for`/`@if`/`@match`/`@while` header grammar — live — **M** — landed `aa5a98c` (code **GUITKX2508**; t05 promotion skipped — that fixture pins an unrelated declaration-typo divergence)
- **Root cause:** no header validation exists anywhere. Live checks parens only
  (`markup.ts:316-342`); `@for (i in 2: int5)` passes silently.
- **Fix:** live grammar check: `@for` header must be `<ident> [, <ident>] in <expr>`; `@if`/
  `@while` need a non-empty expression; `@match` an expression. Diagnostic code: pick per the
  concordance rules (2504–2507 are the Godot-reserved band; extend with 2508+ if nothing fits).
  Validate the *expr* part via the embedded-analyzer seam where practical, not regex-only.
- **Accept:** `@for (i in 2: int5)` and `@for (garbage)` flag live; all demo headers stay clean.

### A6 ✅ Stale sidecar pile-up — **S/M** — landed `da5ac42`
- **Root cause:** on `src_hash` divergence, `mergeCompilerSidecar` (`server.ts:735-757`)
  re-publishes every compiler-only diag each keystroke with clamped offsets (many collapse to
  EOF), and nothing refreshes the sidecar until a Godot-editor recompile
  (`plugin.gd` triggers only: enter-tree, fs-changed, focus-in).
- **Fix:** on divergence, collapse stale compiler-only diags to **one** file-level Information
  entry ("N compiler diagnostics from the last compile are stale — recompiles when the Godot
  editor next compiles this file"); full set restored when hashes match again.
- **Accept:** editing with Godot closed → no drifting squiggles; reopen Godot + save → real
  sidecar diagnostics return positioned.

### A7 ✅ Packaging hardening: `vscode:prepublish` — **S** — landed `8eb9e15` + `86ac96b` (prepublish VERIFIES rather than rebundles — CI bundles per `--target`, an unconditional rebundle would clobber it; vocabulary compared semantically since tsc re-emits JSON normalized)
- **Root cause:** `vscode/package.json:78` prepublish runs only the extension `tsc`; only
  `npm run package` refreshes `server/`. On-disk `vscode/server/` is stale (missing
  `vocabulary.json`, `liveMarkup.js`, …) — a local `vsce publish`/`package` outside `npm run
  package` would ship a server that dies on `MODULE_NOT_FOUND`. (CI is safe: publish.yml runs
  `bundle-server.js` explicitly.)
- **Fix:** make `vscode:prepublish` run the lsp-server build + `bundle-server.js`; have
  `bundle-server.js` assert `out/vocabulary.json` exists before copying.
- **Accept:** from a clean checkout, `npx vsce package` alone produces a VSIX containing
  `server/vocabulary.json` + `server/liveMarkup.js`.

---

## Phase B — Godot addon side (`addons/reactive_ui`)

### B1 ✅ Vocabulary loader: scan-window read failures are deafening — **S/M** — landed `06ed4e3` + `9d58277`
> **Replay result (pristine-clone cold open):** 2 warning lines total (was ~250 red), 0 "Parse
> JSON failed", outputs kept, clean exit. Both the res:// AND globalized-path reads fail inside
> the 4.7 scan window — the empty-check + once-per-episode hold is the real safety; the absolute-
> path read stays as best-effort. Self-heal on the first post-scan compile (recovery line).
- **Root cause:** during the editor's first filesystem scan, `FileAccess.get_file_as_string`
  on `res://…/vocabulary.json` returns **empty** (file itself is valid — byte-verified);
  `_load_vocabulary` (`guitkx.gd:55-56`) feeds "" straight to `JSON.parse_string` → Godot's own
  "Parse JSON failed at line 0" + our 2 error lines, × every file × every sweep (~250 red lines
  per cold open, user's `errors` capture 2026-07-03). The 751be6a guard correctly preserves
  outputs; the noise and the retry-only strategy remain.
- **Fix:** (1) check emptiness before parsing (kills Godot's noise line); (2) fallback read via
  `FileAccess.open(ProjectSettings.globalize_path(_VOCAB_PATH))` when the res:// read comes back
  empty — likely dodges the scan-window quirk entirely; (3) demote per-file spam to **one**
  warning per `compile_all` sweep (static latch, reset per sweep), keep per-file GUITKX2507
  sidecar behavior as-is.
- **Tests:** extend the `_test_codegen` env-guard case (bogus path → still env_error + outputs
  preserved); pristine-clone cold-open replay (the 751be6a probe method) → expect ≤2 log lines
  and, if the globalize fallback works in-scan, a successful first compile.
- **Accept:** cold editor open of a fresh clone is quiet and self-heals; no `.gd` deletions.

### B2 ✅ Compiler-side `@for` header validation — **S/M** — landed `aa5a98c` (same commit as A5, GD+TS lockstep; golden `t20_bad_for_header` pins it)
- **Root cause:** `_parse_loop` → `_read_paren` (`guitkx_markup.gd:283-292`) captures the header
  raw; statement lowering emits it **verbatim** (`guitkx.gd:1327-1336` → `for i in 2: int5:`),
  so garbage becomes invalid GDScript caught only by Godot at load. `_split_for_header:1398`
  only requires the substring `" in "` and guards nothing in the common top-level path.
- **Fix:** validate the header at parse time (same grammar as A5, same code) so the sidecar and
  live tier agree; expr-mode and statement-mode share the one validated split. Promote the
  known-divergence fixture `t05_typo_header.pending.guitkx` to a real golden.
- **Accept:** `@for (i in 2: int5)` fails compile with a positioned diagnostic; goldens updated.

---

## Phase C — early **markup** returns, the Unity way — **L**

> The one language-semantics item. Unity uitkx supports markup in setup **in place**: the parser
> tracks `SetupCodeMarkupRanges`/`SetupCodeBareJsxRanges` (`DirectiveParser.cs:358-359,428`) and
> the emitter splices them to VirtualNode calls (`CSharpEmitter.SpliceSetupCodeMarkup:2334`), so
> `if (loading) { return (<Spinner/>); }` just works. Unity's 2102 means "malformed render
> return", not "no early returns". guitkx converges to that.

### C1 ✅ `_split_return` → ordered span model — landed `7f7609a`
`guitkx.gd:813-893` currently yields one setup string + one markup window and 2102-flags every
other markup return (5 sites: `:857-858, :860-861, :867-868, :870-871, :878-888`). Rework into an
ordered list of `(gdscript-segment | markup-return)` spans, top-level **and** nested; 2102
narrows to Unity semantics (a return that *should* be the render return but isn't
`return ( <markup> )`-shaped / non-markup content in the final position).

### C2 ✅ `_emit_func` interleaved, scope-correct emission — landed `7f7609a` (per-return fresh line buffer at the return's real indent, shared `__cfN` counter; the t04 indent hazard is the runtime-verified test case)
`guitkx.gd:1052-1074` emits verbatim setup + one final return. New: interleave verbatim GDScript
segments with in-place lowered `return <expr>` at the return's **real indent**. The hazard: 
`_emit_if/_emit_loop/_emit_match` hoist `__cfN` pre-statements to render() top level
(`ctx["lines"]`, flushed at indent 1) — a conditional return's hoists must emit at its own indent
or force inline lowering (`_emit_if_inline`/`_emit_for_inline`; `@while`/`@match` inside early
returns may stay GUITKX0026 initially). The untracked `tests/contract/fixtures/t04_early_return_in_if.gd`
experiment shows exactly this indent bug — it becomes the acceptance fixture, done right.

### C3 ✅ TS/LSP mirror (same-commit invariant) — landed `7f7609a` (early returns = live markup windows; unconditional-early dim in unreachableRegions; A4-era live 2102 removed, 2102 left vocabulary `live`; virtualDoc keeps the A2 neutralization — the analyzer's `return null` view is flow-correct)
`splitReturn`/`markupWindows()` (single-window assumption), `virtualDoc` multi-window stubs,
live structure walk + 0105/keys per window, formatter (`formatGuitkx.ts`), semantic tokens.
A2's neutralization stays as the catch-all for *unrecognized* markup; recognized early returns
become real windows with full markup intelligence.

### C4 ✅ Contract goldens + fixtures — landed `7f7609a` (t04/t14 flip legal; new t21 pins the two-window shape; decision resolved: EVERY early markup return is legal incl. unconditional top-level ones, which dim the rest — full Unity parity, stricter-than-Unity option dropped)
Regen all goldens (`contract_dump.gd` currently assumes one window per component, `:112-114`);
new goldens: early return in `if`, unconditional early markup return (→ unreachable-after hint,
0107 parity), multiple top-level markup returns (now legal? — decide: Unity keeps *one* render
return; recommended: conditional/nested early markup returns legal, **two unconditional
top-level** markup returns stays an error).

### C5 ✅ Docs + changelog + versions — diagnostics page rows (2102/2508), CHANGELOGs, addon 0.6.0 + ext/lsp 0.7.0
Language reference "early returns" section, Unity-differences page row removed, CHANGELOG,
addon 0.6.0 / ext 0.7.0 bumps.

- **Accept (phase):** `if not ready:\n\treturn (<Spinner/>)` compiles to valid GDScript that
  renders Spinner; demos + full test suites + smoke green; live tier gives markup intelligence
  inside the early return.

---

## Phase R — cold-open recovery (round-2 field triage, 2026-07-03 evening) — branch `fix/cold-open-recovery`, addon **0.6.1** + ext **0.7.1**

> Round-2 field test (ext 0.7.0 + addon 0.6.0) surfaced no new language bugs — every symptom
> traced to the COLD-OPEN pipeline. A zombie editor session (pre-Phase-C compiler still in
> memory, empty host-tag table) force-swept all 43 files at 1:13 PM, stamped every sidecar with
> bogus 0105 host-tag storms, consumed the fingerprint marker while compiling nothing, and left
> 38 generated .gd deleted (→ app.gd "DemoGallery not declared"); the editor then held every
> compile behind GUITKX2507 for hours because this repo's node_modules/docs trees keep the
> editor's first scan — during which ALL FileAccess reads return empty, even the fingerprint's
> own source reads — running for minutes, and nothing retried without a user edit.

### R0 ✅ Embed the vocabulary as a generated const (kills the 2507 class) — landed `5edebe7`
`dev/gen_vocabulary.gd` → `guitkx_vocabulary.gen.gd` (`const DATA`), preloaded by `guitkx.gd`:
production never file-reads — if the compiler script loads, its vocabulary exists. The
`_VOCAB_PATH` test seam keeps the historical file-read + env machinery exercisable;
`vocabulary.json` stays the single source of truth (LSP untouched), drift-tested in
`guitkx_test.gd`.

### R1 ✅ Auto-retry while held — landed `5edebe7`
`plugin.gd`: a sweep returning `held` files schedules a 2s one-shot retry (announced once per
episode, bound method so a freed plugin drops the connection) until a sweep runs unheld.

### R2 ✅ Held ≠ errors (the 42-line wall) — landed `5edebe7`
`compile_all` returns `held[]` separate from `errors[]`; `plugin.gd` prints nothing per held
file — the loader's one-per-episode hold warning is the only announcement.

### R3 ✅ Fingerprint marker survives held sweeps AND the scan window — landed `5edebe7`
`_write_fp_marker()` only when `held` is empty, and `compiler_fingerprint()` returns
unknowable ("") on any empty source read — forces the sweep (safe direction) but never
persists garbage. The test run itself caught the second half: the `--editor --quit` process
hashed empty reads and persisted a garbage marker. `.gen.gd` joined `_COMPILER_SOURCES`.

### R4 ✅ `.gdignore` the non-Godot trees — landed `5edebe7`
`ide-extensions/`, `ReactiveUIGodotDocs~/`, `plans/`, `research/` (NOT `tests/` — CI loads
scripts from there). Editor first scan: minutes → seconds; `find_all` already honors
`.gdignore`, so codegen sweeps skip them too.

### R5 ✅ Enter-after-`</Tag>` over-indent (ext 0.7.1) — landed `5edebe7`
`language-configuration.json` increaseIndentPattern branch `([^/]>\s*$)` matched closing tags;
now `(^(?!\s*</).*[^/]>\s*$)` (regex case-table verified; multi-line opening tags and `/>`
self-closers unchanged).

- **Verified NOT bugs this round:** live 2101 fires on every missing-return shape (repro-proven
  on the exact field buffer, on both 0.6.1 and 0.7.0) — it anchors at the `component Name`
  declaration head; live 2508 fires on `@for (i in 2: int5)`. Both were buried under the
  zombie-sidecar noise. The LSP server is untouched this phase (stays 0.7.0).
- **Accept (phase):** cold open of this repo compiles everything with zero red lines (or, if
  the environment is ever held, recovers by itself within seconds); Enter after `</VBox>`
  aligns with the opening tag; full suites green (guitkx_build 42/0, contract 63, core 114,
  style 25, router 18+37, update, demos 30, guitkx incl. `_test_cold_open_recovery`; TS
  173/173).

---

## Phase R2 — scan-window completeness (0.6.2, field follow-up) — branch `fix/scan-window-sweep`

> R landed and the cold open went quiet — but a stale `.guitkx` STILL survived a cold open
> uncompiled (field capture 18:23→18:30): the startup sweep runs inside the first scan, where
> `get_modified_time` returns 0 → `0 > 0` = "fresh" → silent no-op, `held` empty, no retry.
> Separately: an unknown identifier in an expression is legal guitkx, and the generated .gd
> only parses when first LOADED — a typo showed nothing anywhere until play time.

### H1 ⬜ Initial sweep waits out `is_scanning()` (0.5s poll), then runs; headless unchanged.
### H2 ⬜ Empty source read of an existing file = HELD (env), never a compile input — an empty
flake read must never fail a compile and T1.1-delete a healthy sibling .gd.
### H3 ⬜ `is_stale`: a zero mtime on either file counts as stale (compile attempt is safe now
that H2 guards the read).
### H4 ⬜ Parse every freshly generated .gd on a throwaway `GDScript` (class_name stripped, no
resource-cache pollution) — GDScript-level errors land in the dock at compile time
(`gd_parse_ok` on the compile_file result). Unity parity: Roslyn surfaces generated-C# errors
immediately.

- **Accept:** save a stale edit → cold open → file compiles once the scan ends, no user
  interaction; a `slisced` typo produces a dock error at compile time; full suites green.

---

## Phase D — directive-body returns, HARD Unity convergence — branch `feat/directive-body-returns`, addon **0.7.0** + ext/lsp **0.8.0** (breaking pre-1.0)

> USER DECISIONS (2026-07-03, verbatim): (1) "No we dont keep it, we stick to reactiveUIToolkit
> unity. and do it properly even if it mean refactor things" — NO bare-markup shorthand; every
> demo/golden/doc migrates. (2) "except it cannot have hooks" — directive bodies are
> mini-components WITHOUT hooks (diagnostic; Unity HooksValidator scans BodyCode the same way).
> (3) "tab is 2 spaces" — Unity-exact: spaces, width 2, format-on-save.
> Spec-by-example: Unity `Samples/Components/UitkxTestFileDoNotTouch/UitkxTestFileDoNotTouch.uitkx`.

### Unity architecture of record (verified in source 2026-07-03)
- **Parser** (`UitkxParser.ParseControlBlockBody:157`): a directive body is RAW HOST CODE
  (`BodyCode`, brace-matched), with JSX ranges found for splicing (`FindJsxBlockRanges` =
  paren-wrapped, `FindBareJsxRanges` = bare) + `ParseBodyForIde` (first top-level `return (...)`
  content parsed as markup AST for IDE features, nested directives included).
- **Emitter** (`CSharpEmitter.cs:1918-2010`): `@if` → IIFE `((Func<VNode>)(() => { if.. { body
  with REAL returns, JSX lowered in place } .. return null; }))()`; `@for/@while/@foreach` →
  IIFE building `List<VNode> __r` where body top-level returns are REWRITTEN
  (`RewriteReturnsForInline(code, "__r")`) to append-and-continue. Fall-through = null/absent.
- **Hooks rule** (`HooksValidator.cs:60-98`): BodyCode scanned for hook calls → error.
- **GDScript lowering (design v2 — REVISED during D0)**: lambdas are OUT — GD lambdas capture
  by VALUE, so a lambda-wrapped `@while (i < n) { i += 1 ... }` never terminates and body
  mutations silently vanish (Unity C# closures capture by REFERENCE; a lambda strategy would
  diverge observably). Instead, Unity's rewrite technique applied UNIFORMLY: the body's
  directive-level returns are rewritten in place — `return ( <markup> )` → `<target> = /
  .append(<lowered>)` + `continue`; `return null` / bare `return` → `continue` — inside an
  enclosing loop that provides the early-exit: the REAL loop for `@for/@while` (append target),
  a single-iteration `for __rui_once in 1:` wrapper for `@if/@elif/@else/@match` arms (assign
  target). Returns inside nested `func():` scopes are NOT rewritten (indent-tracked scope
  skip); a directive-body `return <value>` that is neither markup nor null → error. Bodies run
  in the real function scope (mutations behave exactly like Unity). Reuses Phase C's ret-span
  scan + in-place lowering + `_reindent_block` geometry.

### Tasks
- **D0 ✅ Formatter/config parity** — landed (this branch). FmtOptions + guitkx_formatter.gd
  defaults → space/2; `[guitkx]` configurationDefaults (defaultFormatter, formatOnSave,
  autoIndent full, tabSize 2, insertSpaces, detectIndentation false); embedded reflow converts
  gdscript-fmt tab depth to the document unit. BONUS FIND: `_indent_unit` (GD + both TS
  mirrors) inferred the unit as the MIN WIDTH — the base offset — folding spaces-2 nesting
  levels together and dedenting a nested `return` out of its guard on reformat; now the min
  positive delta between distinct widths (sample-idempotency sweep caught it). Corpus
  regenerated (14 cases, spaces-2). Repo-wide reformat deferred into D5 (files migrate anyway).
- **D1 ⬜ GD markup grammar:** `_parse_if/_parse_loop/_parse_match` bodies → `body_code` model:
  raw text (parser stays dumb — Unity parity); a new compiler-side splitter (adapt
  `_split_return:963`'s scan) classifies every DIRECTIVE-LEVEL return: markup-paren / bare
  markup / `return null` / bare `return` / VALUE return (`return node_var` — LEGAL, rewritten
  like any other; Unity splices it verbatim). Returns inside nested `func():` scopes are found
  by indent-tracked func-header stack and are NOT body returns (their markup still lowers in
  place, Phase C behavior). Markup content present with NO body return → **GUITKX2103**
  migration error ("a directive body returns its markup — write `return ( <markup> )`");
  code-only bodies with no return are legal (produce nothing, Unity parity). New node shapes
  documented in the mirror header (markup.ts D4). Hooks scan → **GUITKX2104** (D2).
- **D2 ⬜ No-hooks-in-directive-bodies diagnostic** (both sides, live + compiler): scan
  body_code for vocabulary hooks + `use_`-prefixed calls (Unity HooksValidator parity).
- **D3 ⬜ GD lowering:** `_emit_if/_emit_loop/_emit_match` → the lambda-IIFE design above, prep
  code spliced verbatim (re-indent via Phase C `_reindent_block`), markup returns lowered in
  place; expr_mode variants collapse into the same IIFE form (a lambda call IS an expression —
  `@while/@match` inside {expr} become legal, GUITKX0026 narrows/retires).
- **D4 ⬜ TS mirror:** markup.ts grammar; virtualDoc splices body prep code as ANALYZABLE
  GDScript (embedded diagnostics inside directive bodies — new capability); liveMarkup
  structure walk + new diagnostics live; semanticTokens; formatGuitkx emits the new form.
- **D5 ⬜ Migration:** all 43 examples/demos + fixtures + contract goldens (regen via
  contract_dump) + guitkx_test pins flipped to the new grammar.
- **D6 ⬜ Runtime proof:** demos suite + GDScript.new() render tests incl. a 4-deep nested case
  mirroring the Unity kitchen-sink file (prep vars per level, `return null` skip, else-branch).
- **D7 ⬜ Docs + release:** language-reference directive section rewritten, Unity-differences
  page updated, CHANGELOGs, addon 0.7.0 + ext/lsp 0.8.0, migration notes (loud).
- **D8 ⬜ Gates:** full headless suite + TS suite + pristine-clone cold open + field checklist.

- **Accept (phase):** the Unity kitchen-sink patterns (translated to GDScript expressions)
  compile and render in guitkx; old bare-markup bodies error with the migration message; hooks
  in a body error; `.guitkx` files format to spaces-2 on save; suites green.

---

## Non-goals / parked
- **Setup markup as a value** (`var x = <Label/>` — Unity's bare-JSX ranges): natural C-follow-up,
  not in C's acceptance. Track after C lands.
- **Analyzer redeclaration check** (duplicate `var rev` unflagged): gdscript-analyzer repo
  TECH_DEBT item, separate wave there.
- **VS2022 0.6.0**: branch `chore/vs-extension-0.6.0` parked until VS Code ext is stable;
  publish.yml's `publish-vs2022` job ships it automatically once merged.

## Status log
- 2026-07-03 — plan created from the field-triage investigation (root causes verified by two
  code sweeps + byte/API checks). No fixes started.
- 2026-07-03 — **Phases A + B COMPLETE** on `fix/live-tier-field-triage` (per-task commits,
  GD+TS same-commit where both sides changed). Gates: lsp 171/171 unit + contract + e2e smoke;
  full Godot suite in a PRISTINE CLONE (guitkx_build, contract 62 goldens, core/style/router×2/
  update, demos 30/30, guitkx) — the clone also served as the B1 cold-open replay; extension
  build + bundle + verify. Release: addon **0.5.1**, extension + language server **0.6.1**.
  Phase C (early markup returns, the Unity way) remains the next wave on its own branch.
- 2026-07-03 — **Phase C COMPLETE** on `feat/early-markup-returns` (core in one GD+TS commit,
  `7f7609a`, per the parity invariant). Early markup returns are LEGAL and lowered in place at
  their own scope depth; every early return is a live markup window; unconditional early returns
  dim the rest; 2102 narrowed to Unity semantics ("final return isn't markup"). Runtime-proved:
  the compiled guard renders both paths. Gates: lsp 173/173 + smoke, 63 goldens (t04/t14 flipped
  legal, t21 new), GD suite, docs build. Release: addon **0.6.0**, ext/lsp **0.7.0** (minor —
  language capability).
