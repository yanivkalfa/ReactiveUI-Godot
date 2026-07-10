# ReactiveUI-Godot — Final Audit: FINDINGS & BUGS (v5, + VS2022 extension audit)

**VERIFICATION PASS (v6, 2026-07-10) — most findings below are now FIXED; this doc is the record,
not the work-list.** Code-verified against the current tree (grep for each entry's fix marker):
**FIXED** — G-01 (`skip_noncode_markup` + `find_matching_markup` shipped; G-23 later refined the
mode model to per-level), G-02/G-03 (`_string_line_mask` in both formatter mirrors), G-04
(close-tag guard), G-05/G-06 (`fell_back` threaded; unsafe str-attr verbatim), G-07 (`uid://`
short-circuit), G-12 (`onDidChangeConfiguration` in server.ts), G-13 (client restart listener),
G-16 (`__RUI_KIND` emitted + read by hmr), G-17 (comment tokens in reflowEmbedded), G-18 (2s
CancellationTokenSource on VS2022 format-on-save), G-19 (spaces/2 canon in VS Code
configurationDefaults + VS2022 editor defaults), G-20 (`enableGdscriptAnalysis` gating), G-21
(OnApply text), G-22 (`RedirectStandardError` + restart messaging), G-23 (per-level content modes +
line classification, 2026-07-10 — see §10). The VS2022 pkgdef packaging bug also shipped its fix
(`vs2022-v0.8.7` tagged). **STILL OPEN:** G-09 (hooks deps deep-compare — document + optional
`same_ref` hatch; design/doc-level) and, in `FINAL_AUDIT_GODOT_OPTIMIZATIONS.md`, the tail of G-10
(stages 1–2 — lexer + markup loops — landed 2026-07-10 with measurements; `guitkx.gd` hot scanners
+ the editor tokenizer remain; G-08 is DONE in both mirrors). The v5 text below (incl. §0's "what
remains") predates these fixes — read it as the audit record.

**VERIFICATION PASS (v5, 2026-07-06):** the node probe suite re-ran against the current compiled TS formatter — **all confirmed findings still reproduce**: G-02 (triple-quoted interior re-indented AND interior double-space collapsed), G-03 (blank line in body segment deleted), and the G-01 failure modes G3/G4 (both parse-fail into verbatim fallback). The trivia guards still pass (G2 leading comment, G5 `{expr}` child preserved). Additionally verified clean in the v5 sweep (do not re-audit): `liveMarkup.ts` (mirrors `_validate_node`/`_validate_body` faithfully; its `findHookCall` has the correct token-boundary + noncode-skipping semantics), `sourceMap.ts` (length-preserving span model, correct bidirectional lookup), `server.ts` `onDidClose` (re-indexes from disk — one LOW gap added to §4 smalls), the diagnostics sidecar staleness gate (`srcHash` FNV-1a pinned to `RUIGuitkxCodegen.src_hash`). The v5 sweep found no new substantive issues in this repo.

**Date:** 2026-07-06 (v4 = v3 split into two documents; this file = correctness findings/bugs with fix recipes. Performance items live in `FINAL_AUDIT_GODOT_OPTIMIZATIONS.md` — IDs G-08, G-10, G-11, G-15 moved there unchanged.)
**Trees audited:** compiler/formatter/editor/LSP/runtime at `dev @ 3d0ac6e`; **VS2022 extension at `dev @ 68f44c6`** (the parity campaign PR #65 — Phases 0–4 — landed between audit passes and touched ONLY `ide-extensions/visual-studio/**` + scripts/CI/plans, so all other findings remain valid against current dev).
**Method:** full reads of the guitkx compiler stack (incl. the emit half), both formatter mirrors, editor addon, LSP server entry points, `hmr.gd`, and **all ten VS2022 extension sources**; plus empirical probes with node against the compiled TS formatter (`out/formatGuitkx.js`, probes G1–G6). GDScript/TS mirrors are contract-tested (`scanner-cases.json`, `tests/contract`), so TS-confirmed findings are *confirmed-on-mirror* — re-verify with one headless run while fixing.

**Audited and found CLEAN (do not re-audit):** `guitkx.gd` emit layer (`_emit`/`_emit_func` interleaving, splice-before-alias ordering, per-scope line buffers, `__cfN` hoisting), `_hook_signature` (conservative by design), `virtual_doc.gd` structure, `hooks.gd` effect bookkeeping (`[audit C3]` late-call guard, two-pass cleanup), `reconciler.gd` context/deletion paths and the interrupted-render `_restart` machinery (cap 25 — the Unity 0.6.4 fix counterpart), `guitkx_codegen.gd` staleness ladder + sidecars, `plugin.gd` lifecycle, the editor live-compile cadence (debounced, adaptive, 150k-char cap, cached bindings), `reflowEmbedded.ts` (multi-line-string bail + token-equivalence — the model safety net; one hardening gap = G-17), VS2022 `GuitkxSettings` store design (deliberate, race-proof), `GuitkxPackage` dispose pattern.

---

## HOW TO USE THIS DOCUMENT (read first, executor)

- Findings are `G-##` with severity, anchors, failure scenario, and a **FIX RECIPE**. Write the named failing test/contract case FIRST.
- **Mirror discipline:** `guitkx_markup.gd` ↔ `markup.ts`, `guitkx_formatter.gd` ↔ `formatGuitkx.ts`, `guitkx_lexer.gd` ↔ `scanner.ts` are line-for-line mirrors. Every fix lands in BOTH plus a `scanner-cases.json` / `tests/contract` case. Change both or neither.
- Tests: GDScript `godot --headless --path . --script tests/guitkx_test.gd`; TS `cd ide-extensions/lsp-server && npm test`. VS2022 builds via `ide-extensions/visual-studio/build-local.ps1` / `publish-vsix.ps1 -LocalOnly`.
- Versioning: patch bumps per artifact; changelog per artifact; publish only via the workflow_dispatch Publish button. No commit/push without the user's go.
- **Probe harness:** `node` + `require(".../out/formatGuitkx.js").formatGuitkx(src)`; every confirmed finding quotes its repro. Rebuild `out/` (tsc) after TS fixes before re-probing.

---

## 0. Executive summary

Better shape than the Unity tooling: formatter trivia guards already work (probes G2/G5 pass), one consolidated lexer with cross-impl contract tests, token-boundary comment-aware validators, clean HMR. What remains:

1. **G-01 (P0):** every directive/return brace- and paren-matching pass runs the **GDScript lexer over MARKUP content** — `#` in markup text swallows same-line delimiters; `{}()` inside markup `//`, `/* */`, `<!-- -->` comments are miscounted. Fix surface: `_read_brace_body`, `_parse_match`, `_split_return`, `_split_body`, `_parse_component_at`.
2. **G-02/G-03 (P0):** formatter re-anchor corrupts triple-quoted string interiors (confirmed, both mirrors) and deletes blank lines in body code segments.
3. **VS2022 (new, post-parity-campaign):** format-on-save can hang the UI thread with no timeout (G-18); **both editors' typing defaults (tabs/4) contradict the formatter's canonical output (spaces/2)** → whole-file indent churn on every save (G-19, cross-editor); the plain-.gd toggle is an honestly-labeled no-op pending a server-side gate (G-20).
4. LSP/config: no `onDidChangeConfiguration` (G-12), selector rebuild needs reload (G-13). **G-14 is OBSOLETE** — the parity campaign executed (PR #65); its plan-staleness correction no longer applies.

---

## 1. P0 — Compiler correctness

### G-01 — GDScript-lexis brace/paren matching over markup content (CONFIRMED failure modes)
- **Root cause:** `guitkx_lexer.gd skip_noncode()` implements GDScript lexis (`#` = comment; `//`,`/* */`,`<!-- -->` are not comments). Every balanced-region scan that spans MARKUP uses it via `L.find_matching`.
- **Fix surface (all verified):**
  1. `guitkx_markup.gd _read_brace_body()` (l.294) — directive bodies.
  2. `guitkx_markup.gd _read_paren()` (l.283) — headers are GDScript expressions — LEAVE as GDScript lexis.
  3. `guitkx_markup.gd _parse_match()` (l.354) — the `@match` body brace.
  4. `guitkx.gd _split_return()` (l.1054) — the `return ( … )` window: `// smiley :)` in markup text miscounts parens; `#` in text swallows same-line `)`.
  5. `guitkx.gd _split_body()` — same pattern.
  6. `guitkx.gd _parse_component_at()` (l.384) — the component body brace (`<Label>Score #3</Label>` + `}` on one line closes the COMPONENT early).
- **Confirmed repros (probe G3/G4 — parse failures; formatter falls back verbatim, compiler errors on valid-looking input):**
  - `@if (true) { <Label text="x"/> # }` → unclosed (the `#` eats the `}`).
  - Body containing `// TODO: revisit }` → the `}` inside the markup comment closes the body early.
  - Constructible worse case: a `#` line whose tail contains a rebalancing `{` shifts the span SILENTLY → miscompiles. That is why this is P0.
- **FIX RECIPE:**
  1. Add `skip_noncode_markup(src, i)` to `guitkx_lexer.gd`: skips `//`-to-EOL, `/* … */`, `<!-- … -->`, quoted strings (`"`/`'`, no prefixes); does NOT treat `#` as a comment. Mirror as `skipNoncodeMarkup` in `scanner.ts`.
  2. Add a mode-aware matcher: line-classified — a line whose first non-ws char is `<`, `@`(directive), `{`, `//`, `/*`, `<!--` is markup-mode; GDScript statement forms are code-mode. This is the SAME classification `_split_body` already applies to parts — reuse it rather than inventing a second.
  3. Invert the current order where needed: today the SPAN is found before the split; find the span WITH the mode-aware scanner (skip_noncode on code lines, skip_noncode_markup on markup lines).
  4. Replace calls at surface items 1, 3, 4, 5, 6 (leave 2).
  5. Mirror in `markup.ts` (`readBraceBody`, `parseMatch`) and the TS ports of `_split_return`/`_split_body` (grep `findMatching(` in `formatGuitkx.ts`/`virtualDoc.ts`).
  6. Contract cases: G3 + G4 inputs; `<Label>Score #3</Label>` + same-line `}`; `<!-- } -->` in a body; `#FF0000` text + same-line `)` inside `return ( … )`; a component-body case.
  7. Anything consciously left unsupported → a targeted diagnostic (GUITKX0150-style), never a bare unclosed error.

---

## 2. P0 — Formatter (both mirrors)

### G-02 — Triple-quoted string interiors corrupted by re-anchor  *(CONFIRMED, probe G1)*
- **Anchors:** `guitkx_formatter.gd _reanchor()` (l.410-442) / `_reanchor_rel()` (l.386) / `_collapse_spaces()`; TS mirror `formatGuitkx.ts reanchor()` (l.602) / `reanchorRel()` (l.573) / `collapseSpaces`.
- **Repro:** setup `var msg := """\nline1\n  keep  two  spaces\n\t\ttabbed line\n"""` → interior re-indented AND interior double-space collapsed → **runtime string value changed**.
- **FIX RECIPE:**
  1. Per-line "starts inside an open multi-line string" mask helper in both mirrors (one scan with the existing `_skip_string`/`skipString`, recording line starts).
  2. `_reanchor`/`reanchor` AND `_reanchor_rel`/`reanchorRel`: masked lines emit **byte-verbatim** (no strip/collapse/depth math; excluded from anchor + `_indent_unit` inference).
  3. Contract/golden cases: G1 input byte-identical; masked `}`-leading line inert; `'''` variant; `r"""` variant.

### G-03 — Blank lines inside directive-body GDScript segments deleted  *(CONFIRMED, probe G6)*
- **Anchors:** `_reanchor_rel` l.390-391 (`if t == "": continue`) / `reanchorRel` (TS l.576). Plain `_reanchor` PRESERVES blanks — the two disagree.
- **FIX RECIPE:** emit a bare `"\n"` for blank lines in both mirrors' `_reanchor_rel` (like `_reanchor`'s `depths[i] == -1` branch). Golden: `var a := 1\n\nvar b := 2` in an `@if` body keeps its blank, idempotent.

### Verified GOOD (do not "fix")
Leading comments preserved (G2); `{expr}` children + markup comments preserved (G5); parse error → byte-verbatim; paren-wrapped `@match` case values; Allman `@else`/`@elif` accepted; module member doc-comments re-emitted.

---

## 3. P1 — Compiler / tooling correctness (smaller)

| ID | Anchor | Finding + RECIPE |
|---|---|---|
| G-04 | `guitkx_markup.gd _parse_element` l.167 | close-tag guard passes when `<` is the last char before `end` → less precise error. `if j >= end or _src[j] != "<" or j + 1 >= end or _src[j + 1] != "/":` + mirror + contract case (`<Box><` at EOF). |
| G-05 | `_fmt_attr` "str" l.284 | unescaped `name="value"` re-emit; parser can't produce an embedded `"` today, a future escape would corrupt silently. Guard: value contains `"` → verbatim fallback (uses G-06's flag) + comment. |
| G-06 | `format()` l.24-29 | always `ok:true` — callers can't tell "formatted" from "verbatim fallback". Thread `fell_back: bool` through `_format_or_verbatim`; surface in `guitkx_editor_view.gd` ("file has syntax errors — format skipped") and mirror in TS (`fellBack`) + a once-per-file VS Code message. |
| G-07 | `guitkx.gd` `@uss` checks l.199-202 | `FileAccess.file_exists` doesn't accept `uid://`; short-circuit when the path begins with `uid://` and rely on `ResourceLoader.exists(path, "Theme")`. |
| G-09 | `hooks.gd _deps_changed/_equal` l.565 | GDScript `==` deep-compares Arrays/Dictionaries — differs from React identity (recreated-but-equal dict does NOT re-run; large structures deep-compare per render). Design decision: DOCUMENT in hooks docs + perf note; optional `same_ref` escape hatch later. |
| G-16 | `hmr.gd _is_module` l.156 | source-text heuristic (`contains("static func render(")`) misclassifies a module whose comment/string contains that text → misses the global re-render. Emit `const __RUI_KIND := "component"` in generated components, read via `get_script_constant_map()` like `__RUI_HOOK_SIG`; text-check fallback for old outputs. LOW. |
| G-17 | `reflowEmbedded.ts normalizeGd` l.118-121 | the token-equivalence safety net STRIPS comments — a gdscript-fmt bug that deleted/mangled a comment would pass the guard. Emit comment tokens into the normal form (order-preserving, trailing-ws-trimmed); adjust the two comment-insensitive reflow tests; add a dropped-comment case → region stays untouched. LOW likelihood, cheap hardening on a data-integrity path. |

---

## 4. P2 — LSP / VS Code extension

### G-12 — TS server reads config only at initialize; no `onDidChangeConfiguration`
- **Anchors:** `ide-extensions/vscode/src/extension.ts:45-49` (initializationOptions); `server.ts:70-90`; no config-change handler (grep verified, still true at 68f44c6).
- **FIX RECIPE:** add `connection.onDidChangeConfiguration` in `server.ts` re-reading `settings.guitkx.{enableEmbeddedAnalysis,useGdformat}` (+ `enableGdscriptAnalysis` for G-20); extract the legacy-alias resolution into one helper shared with `onInitialize`. The VS Code client already synchronizes the `guitkx` section. Manual test: toggle → embedded hover flips without restart. **This is also the prerequisite for G-20 (VS2022 .gd gating), so do it first in this batch.**

### G-13 — `enableGdscriptAnalysis` toggle needs a window reload in VS Code (client-side selector)
- `extension.ts:40-42` builds the selector once. RECIPE: `workspace.onDidChangeConfiguration` listener that offers `client.restart()` on change; mention in the setting description.

### LSP smalls (v5)
- `server.ts` `onDidClose` (l.896-904) re-indexes from disk (correct) but never publishes empty diagnostics for the closed URI — closed-file squiggles linger in the Problems panel until reopen. RECIPE: `connection.sendDiagnostics({ uri: e.document.uri, diagnostics: [] })` in the handler. (Mirror of the Unity LSP's same small.)

### G-14 — ~~parity-plan §P1 staleness correction~~ **OBSOLETE**
- The VS2022 parity campaign executed in full (PR #65, Phases 0–4, merged to dev @ 68f44c6). No action. (Historical note: §P1's "client hardcodes options" description had already been fixed in the VS Code client before the campaign ran.)

---

## 5. P2 — VS2022 extension (NEW section — audited at 68f44c6, post-parity-campaign)

*All ten sources read (`ide-extensions/visual-studio/GuitkxVsix/*.cs`). Overall: a careful, honestly-documented port — the settings-store race analysis, the MEF/package-ordering rationale, and the restart-command tradeoff write-ups are exemplary. Four findings:*

### G-18 — **MED-HIGH** — format-on-save blocks the UI thread with NO timeout
- **Anchors:** `GuitkxFormatOnSave.cs:84-91` — `ThreadHelper.JoinableTaskFactory.Run(() => Rpc.InvokeWithParameterObjectAsync<JToken>("textDocument/formatting", …))` inside `IVsRunningDocTableEvents3.OnBeforeSave` (UI thread). The catch swallows FAILURES, but a server that is merely SLOW (e.g. mid workspace-scan — the server's `onInitialize` does its scan synchronously, see the optimization doc's G-15) never throws — the save just hangs VS.
- **Failure:** open a big project, Ctrl+S a `.guitkx` in the first seconds → VS freezes until the server responds. Also reachable any time the Node process is CPU-pinned.
- **FIX RECIPE:**
  1. Create `var cts = new CancellationTokenSource(TimeSpan.FromSeconds(2));` and pass `cts.Token` to `InvokeWithParameterObjectAsync` (the StreamJsonRpc overload accepts one); on `OperationCanceledException` return `S_OK` (skip formatting — never block a save).
  2. Optional: log skips to an output pane so silent non-formatting is diagnosable.
  3. Manual test: kill-suspend the node process (Process Explorer), save — VS stays responsive, file saves unformatted.

### G-19 — **MED-HIGH / CROSS-EDITOR** — typing defaults (tabs/4) contradict the formatter's canonical output (spaces/2)
- **Anchors (all three layers):**
  - Formatter canon: `guitkx_formatter.gd DEFAULTS` / `formatGuitkx.ts` = `indentStyle "space", indentSize 2` ("Phase D: Unity-exact"); `server.ts formatOptsFor` (l.421-433) **ignores the LSP request's options entirely** and formats spaces/2 (+config-file override). Its comment even claims "the [guitkx] configurationDefaults mirror [uitkx]'s" — they don't:
  - VS Code: `package.json configurationDefaults` → `"editor.insertSpaces": false, "editor.tabSize": 4`.
  - VS2022: `GuitkxEditorDefaults.cs` pins ConvertTabsToSpaces=false, TabSize=4, IndentSize=4 (faithfully mirroring the stale VS Code values; its comment repeats the outdated "the compiler emits tabs" claim); `GuitkxSmartIndent` indents in the editor's (tab) unit; `GuitkxFormatOnSave` hardcodes `{tabSize: 2, insertSpaces: true}` (a third opinion, though the server ignores it).
- **Failure (both editors):** every hand-typed line is tabs/4; every save reformats the file to spaces/2 → whole-file indent churn per save, mixed tabs+spaces between saves, tab-width rendering jumps 4→2, smart-indent keeps inserting tabs into a spaces file.
- **FIX RECIPE (one decision, three syncs — pick spaces/2, the formatter's documented canon):**
  1. VS Code `package.json` configurationDefaults → `"editor.insertSpaces": true, "editor.tabSize": 2`.
  2. VS2022 `GuitkxEditorDefaults` → ConvertTabsToSpaces=true, TabSize=2, IndentSize=2; fix its stale comment; `GuitkxFormatOnSave`'s options object is then consistent (leave, but comment that the server ignores it anyway).
  3. Fix the wrong comment in `server.ts formatOptsFor`.
  4. If a project's `guitkx.config.json` overrides indent (the server honors it), editors will still churn — OPTIONAL follow-up: read the config in the clients too (VS Code already has the uitkx-style tabSize-sync pattern to copy from the Unity repo). Ship steps 1-3 first.
  5. Golden test: format a tabs/4-authored file → spaces/2 (already true); manual: type-Enter-save in both editors → no indent churn on the typed lines.

### G-20 — **LOW-MED** — "Analyze plain .gd files" option is a no-op in VS2022 (documented, but still a dead switch)
- **Anchors:** `GuitkxContentDefinition.cs` (static MEF exports — cannot gate on a runtime setting; the doc-comment explains this correctly); `GuitkxLanguageClient.InitializationOptions` sends only `enableEmbeddedAnalysis` + `useGdformat`; `GuitkxOptionsPage` labels the option "(not yet enforced)".
- **FIX RECIPE (the comment already names it):** (1) send `enableGdscriptAnalysis` in `InitializationOptions`; (2) server-side: in `server.ts`, when `enableGdscriptAnalysis === false`, early-return empty results for `.gd` URIs in diagnostics/completion/hover/etc. (one `isGdAnalysisEnabled(uri)` guard at the `isGd(...)` branches — grep `isGd(` for the ~8 sites); (3) wire it into the G-12 `onDidChangeConfiguration` handler; (4) update the option's "(not yet enforced)" label. VS Code keeps its client-side selector gating (harmless overlap).

### G-21 — **LOW** — stale UI text: OnApply says the restart command is "planned"; it shipped in Phase 4
- **Anchors:** `GuitkxOptionsPage.OnApply` message ("A \"GUITKX: Restart Language Server\" command is planned…") vs `GuitkxPackage.OnRestartLanguageServer` (exists). RECIPE: point the message at the command ("run GUITKX: Restart Language Server, or reload the solution"); while there, note the restart command's own known limit (below).

### G-22 — **LOW** — restart = crash-recovery-once semantics + invisible server stderr
- `GuitkxLanguageClient.RequestRestart` kills the child and relies on VS's documented ONE automatic restart — a second restart in the same session silently does nothing (the message box half-explains). Also `ProcessStartInfo` doesn't redirect stderr, so server-side logs are invisible in VS. RECIPE: (a) after a second kill in one session, extend the message ("restart budget used — reload the solution"; track a static counter); (b) `RedirectStandardError = true` + pump to an Output-window pane ("GUITKX Language Server") — also makes G-18 diagnosable. Both small; bundle with G-21.

---

## 6. Cross-repo parity ledger

| Topic | Godot | Unity | Action |
|---|---|---|---|
| Formatter: leading comments / `{expr}` children | ✅ | ❌ (U-01/U-02 confirmed) | Port Godot's guards to Unity. |
| Formatter: multi-line string interiors | ❌ G-02 | ❌ U-03 | Same mask fix + SHARED test corpus. |
| Formatter: splice-index desync | n/a (single-detector) | ❌ U-36 confirmed data loss | Unity adopts range-driven single-detector. |
| `@else` newline placement | ✅ | ❌ U-05 | Fix Unity. |
| `@case` value delimiting | ✅ paren-wrapped | ❌ U-04 confirmed corruption | Fix Unity; Godot form is the reference. |
| Comment-aware region scanning | ❌ G-01 (markup side) | ❌ U-07 (block comments) | Same lesson: scan with the CONTENT'S lexis. |
| Hook-call detection | ✅ token-boundary (`_find_hook_call`) | ❌ U-10 confirmed FPs | Unity ports Godot's semantics. |
| HMR parse-error gating | ✅ (T1.1 invariant) | ❌ H-01 | Fix Unity HMR; Godot is the model. |
| Lexer consolidation + contract tests | ✅ | ❌ U-20 | Unity adopts the scanner-cases mechanism. |
| **Editor indent defaults vs formatter canon** | ❌ **G-19 (both its editors)** | ✅ (uitkx pins spaces/2 consistently) | Fix Godot's two clients; Unity is the reference here. |

## 7. Repo hygiene
- Add `tests/__*_tmp/` to `.gitignore` (untracked dirs exist: `__dangling_tmp`, `__dupe_tmp`, `__has_stale_tmp`, `__orphan_tmp`).
- Consider excluding `out/test/**` from extension bundles.
- (Unity-repo item, resolved there: the 1.45 MB `tscn_stable.html` GitHub-language-stats anomaly — deleted + pushed. This repo's GDScript/TS split is accurate; the 0.2% "Harbour" is a linguist misclassification, ignorable.)

## 8. Execution order
1. **G-01** (mode-aware matching; contract cases first).
2. **G-02 + G-03** (formatter string mask + blank lines; share the corpus with Unity U-03).
3. **VS2022/editor batch:** G-18 (timeout — smallest, highest safety value), G-19 (indent canon — coordinate the VS Code + VS2022 + server comment changes in one PR), G-12 → G-20 (config handler then .gd gating), G-21+G-22.
4. G-13; section 3 smalls (G-04…G-09, G-16, G-17) + hygiene (§7).
5. Performance items per `FINAL_AUDIT_GODOT_OPTIMIZATIONS.md` (G-10 unicode_at conversion is the big one).

## 9. Probe artifacts
`rg_probe.js` (session scratchpad) drives G1–G6 via node against `out/formatGuitkx.js`. For GDScript confirmation of G-01/G-02 add the same inputs to `tests/guitkx_test.gd` / the golden corpus and run headless.

---

## 10. Post-audit finding — NOT part of the fixed v5 batch above (found 2026-07-06, during unrelated `.guitkx` authoring)

### G-23 — **P1** — a parenthetical comment split across two `#`/`//` lines desyncs paren-balance tracking, surfaces as a spurious "unclosed component body" far downstream

**Status: FIXED 2026-07-10 (same day the root cause was confirmed — see below for the trace).**
The fix is the per-level-mode redesign this entry called for, landed in BOTH mirrors
(`guitkx_lexer.gd find_matching_markup` + `scanner.ts findMatchingMarkup`): content mode is now
tracked **per delimiter-stack level** — `{` opens a BODY level (component/directive body), `(`
after `return` opens a MARKUP window, headers/`{expr}` holes open CODE levels — and within a BODY
level the lexis is **line-classified** (`_is_markup_line`/`isMarkupLine`: a line whose first
non-ws char is `<`, `{`, `//`, `/*`, or a directive `@keyword` scans as markup; any other line is
GDScript prelude and scans with code lexis, so its `#`/`##` comments are comments). MARKUP windows
ignore line shape (a prelude-line `return ( <Label>Score #3</Label> )` keeps `#3` literal); `[`
inherits its level's mode (prelude array literals get code lexis — fixing a sibling latent bug
where a `#` comment inside a multi-line array desynced the stack). **Verified:** 7 new shared
contract cases (`scanner-cases.json` — the G-23 repro, `##` docstring, keyword-bait, unbalanced
brace, array-comment, plus 2 regression pins) run by both `tests/guitkx_test.gd` and the lsp-server
suite (180/180); a compile-level regression test (`_test_g23_prelude_comments`, the exact doom
comment shape incl. a directive-body variant); all 49 example `.guitkx` recompiled **byte-identical**
to pre-fix outputs; live-fire: the real `doom_game_screen.guitkx` with the original split-paren
comments injected compiles `ok:true`. The workaround comments in the doom file can be rephrased
naturally at leisure — they are no longer load-bearing. Original confirmed-trace + repro kept below
for the record.

**CONFIRMED mechanism (2026-07-10).** Direct call of `RUIGuitkxLexer.find_matching_markup` on a component-body `{…}` reproduces it exactly: the body `{ # a (open⏎ # b) close⏎ var x=1⏎ return ( X ) }` returns **-1**; the same body with the paren balanced on one comment line, or with no comment, returns the correct `}` index. Trace: the prelude scans in MARKUP mode (default), where `skip_noncode_markup` keeps `#` literal, so the `(` inside the first comment line opens CODE mode (`code_depth++`); once in CODE mode, `skip_noncode` on the *next* line treats its leading `#` as a real comment and skips its `)` to EOL, so the `(` never closes; a later `}` then pops against the stray `(` → mismatch → -1. So the defect is precisely: **a body's code prelude (everything before its `return (`) is scanned as markup, not code.**

**Why it's a redesign, not a patch (both cheap fixes just move the bug):** (a) making markup-mode skip `#`-to-EOL breaks `@if (x) { <Label>#hot</Label> }` — it would skip the directive-body-closing `}`; (b) scanning the whole body in code-mode breaks a literal `#3`/`#FF0000` in the `return (…)` markup window. The correct fix tracks, **per delimiter-stack level**, whether that level is a *code prelude* or *markup content*, transitioning prelude→markup at `return (` — and it nests (component-body prelude, directive-body prelude). Load-bearing (every `.guitkx` body/return/window goes through `find_matching_markup`; a mistake breaks all compilation) and gated by the repo's byte-identical `scanner.ts findMatchingMarkup` mirror + `tests/contract` cases. A focused own-PR task; the minimal repro above is the first contract fixture. Workaround (keep parenthetical phrases on one comment line) is cheap and already applied throughout `doom_game_screen.guitkx`.

- **Repro:** a component whose setup code (or a directive body) contains a doc-comment where one open paren `(` is on one `#`/`//` comment line and its matching `)` is on the *next* comment line, e.g.:
  ```
  # Faithful port of Foo's per-column texture windowing (BackgroundSize +
  # BackgroundPositionX/Y in the original): select the texel column...
  ```
  Both lines are individually valid, ordinary GDScript/markup comments — the paren only "closes" when read across the line break, which a human reads fine but the compiler apparently doesn't. Confirmed via bisection: with all doc-comments stripped from the file it compiles clean (`ok:true`, zero diagnostics); reintroducing just this style of split-parenthetical comment reproduces `GUITKX0304 "unclosed component body"`, anchored at the component's own opening `{` — i.e. the reported location is nowhere near the actual defect, which is what made this slow to isolate.
- **Root-cause hypothesis (not fully confirmed):** `guitkx_lexer.gd`'s `find_matching_markup` (the mode-aware scanner added by the G-01 fix above) documents itself as starting in **MARKUP mode** from the component's opening `{` — including over the setup code that precedes any actual markup/`return`. In markup mode, `skip_noncode_markup` does not treat a bare `#` as a comment-starter at all (correct for markup *content*, where `#` is literal text, e.g. a hex color or `Score #3`) — so a `#`-prefixed GDScript comment sitting in genuine setup/prep code, scanned under markup-mode rules, has its `#` treated as literal text rather than "skip to end of line," and any `(`/`)` inside that comment gets counted as real delimiters. This would explain the setup-code case precisely. **Not independently re-verified**: whether the same failure also reproduces from a `//`-style comment sitting in an actual markup position (where `skip_noncode_markup` *does* special-case `//` and should skip the whole line in one jump) — several such comments were fixed in the same batch as the setup-code one before re-testing, so it's not yet confirmed whether those were independently required or incidental. A follow-up audit should isolate each case with its own minimal repro before writing a fix recipe.
- **Impact:** LOW-frequency (needs a specific split-comment style most authors won't naturally write) but confusing when hit — the reported diagnostic location is the component's opening brace, arbitrarily far from the actual malformed comment, making it hard to spot without bisection.
- **Workaround (not a fix):** keep every parenthetical phrase inside a single comment line; rephrase with em-dashes/semicolons instead of parens if a comment must wrap. Applied throughout `doom_game_screen.guitkx`.
- **Suggested fix surface for a follow-up session:** `guitkx_lexer.gd find_matching_markup`'s initial mode (should setup/prep code scan in CODE mode, switching to MARKUP only once the `return (` window is entered?), and/or wherever `guitkx_markup.gd _parse_component_at`'s outer body-bclose scan invokes it. Write minimal per-case repros (setup-code `#` comment; markup-position `//` comment) as new `tests/contract` fixtures before touching the scanner, per this document's own "write the failing test first" convention.
