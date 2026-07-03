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

### A1 ⬜ 0105 flags PascalCase host tags (`<HBox>`, `<Button>`, `<Label>`) — **S**
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

### A2 ⬜ Early markup return leaks raw markup into the virtual GDScript doc — **M**
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

### A3 ⬜ 2101 masked by any earlier markup-shaped return — **S**
- **Root cause:** live `missingReturnComponents` (`formatGuitkx.ts:628/638`) reports only when
  `splitReturn === null` — i.e. *no markup return anywhere*. An early `return <s></a>` satisfies
  it, so deleting the final return shows nothing.
- **Fix:** 2101 = "no **final top-level** markup return" (the chosen return must be the last
  top-level statement-position markup return; interior ones don't count).
- **Accept:** file with only an early `return <s></a>` and no final `return (...)` → live 2101.

### A4 ⬜ 2102 live + honest wording (both sides) — **S**
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

### A5 ⬜ `@for`/`@if`/`@match`/`@while` header grammar — live — **M**
- **Root cause:** no header validation exists anywhere. Live checks parens only
  (`markup.ts:316-342`); `@for (i in 2: int5)` passes silently.
- **Fix:** live grammar check: `@for` header must be `<ident> [, <ident>] in <expr>`; `@if`/
  `@while` need a non-empty expression; `@match` an expression. Diagnostic code: pick per the
  concordance rules (2504–2507 are the Godot-reserved band; extend with 2508+ if nothing fits).
  Validate the *expr* part via the embedded-analyzer seam where practical, not regex-only.
- **Accept:** `@for (i in 2: int5)` and `@for (garbage)` flag live; all demo headers stay clean.

### A6 ⬜ Stale sidecar pile-up — **S/M**
- **Root cause:** on `src_hash` divergence, `mergeCompilerSidecar` (`server.ts:735-757`)
  re-publishes every compiler-only diag each keystroke with clamped offsets (many collapse to
  EOF), and nothing refreshes the sidecar until a Godot-editor recompile
  (`plugin.gd` triggers only: enter-tree, fs-changed, focus-in).
- **Fix:** on divergence, collapse stale compiler-only diags to **one** file-level Information
  entry ("N compiler diagnostics from the last compile are stale — recompiles when the Godot
  editor next compiles this file"); full set restored when hashes match again.
- **Accept:** editing with Godot closed → no drifting squiggles; reopen Godot + save → real
  sidecar diagnostics return positioned.

### A7 ⬜ Packaging hardening: `vscode:prepublish` — **S**
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

### B1 ⬜ Vocabulary loader: scan-window read failures are deafening — **S/M**
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

### B2 ⬜ Compiler-side `@for` header validation — **S/M**
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

### C1 ⬜ `_split_return` → ordered span model
`guitkx.gd:813-893` currently yields one setup string + one markup window and 2102-flags every
other markup return (5 sites: `:857-858, :860-861, :867-868, :870-871, :878-888`). Rework into an
ordered list of `(gdscript-segment | markup-return)` spans, top-level **and** nested; 2102
narrows to Unity semantics (a return that *should* be the render return but isn't
`return ( <markup> )`-shaped / non-markup content in the final position).

### C2 ⬜ `_emit_func` interleaved, scope-correct emission
`guitkx.gd:1052-1074` emits verbatim setup + one final return. New: interleave verbatim GDScript
segments with in-place lowered `return <expr>` at the return's **real indent**. The hazard: 
`_emit_if/_emit_loop/_emit_match` hoist `__cfN` pre-statements to render() top level
(`ctx["lines"]`, flushed at indent 1) — a conditional return's hoists must emit at its own indent
or force inline lowering (`_emit_if_inline`/`_emit_for_inline`; `@while`/`@match` inside early
returns may stay GUITKX0026 initially). The untracked `tests/contract/fixtures/t04_early_return_in_if.gd`
experiment shows exactly this indent bug — it becomes the acceptance fixture, done right.

### C3 ⬜ TS/LSP mirror (same-commit invariant)
`splitReturn`/`markupWindows()` (single-window assumption), `virtualDoc` multi-window stubs,
live structure walk + 0105/keys per window, formatter (`formatGuitkx.ts`), semantic tokens.
A2's neutralization stays as the catch-all for *unrecognized* markup; recognized early returns
become real windows with full markup intelligence.

### C4 ⬜ Contract goldens + fixtures
Regen all goldens (`contract_dump.gd` currently assumes one window per component, `:112-114`);
new goldens: early return in `if`, unconditional early markup return (→ unreachable-after hint,
0107 parity), multiple top-level markup returns (now legal? — decide: Unity keeps *one* render
return; recommended: conditional/nested early markup returns legal, **two unconditional
top-level** markup returns stays an error).

### C5 ⬜ Docs + changelog + versions
Language reference "early returns" section, Unity-differences page row removed, CHANGELOG,
addon 0.6.0 / ext 0.7.0 bumps.

- **Accept (phase):** `if not ready:\n\treturn (<Spinner/>)` compiles to valid GDScript that
  renders Spinner; demos + full test suites + smoke green; live tier gives markup intelligence
  inside the early return.

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
