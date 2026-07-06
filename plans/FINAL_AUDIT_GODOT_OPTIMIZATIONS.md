# ReactiveUI-Godot — Final Audit: OPTIMIZATIONS & PERFORMANCE (v4 split)

**Date:** 2026-07-06. Companion to `FINAL_AUDIT_GODOT_FINDINGS.md` (correctness bugs live there). IDs are stable across both docs — G-08, G-10, G-11, G-15 moved here unchanged; GO-## items are perf observations promoted from earlier findings text.

**Ground rules:** measure before/after (numbers in the PR); behavior-preserving only — the `scanner-cases.json` / `tests/contract` suites pin behavior, so any contract diff during a perf change is a bug in the change. Mirror discipline still applies where an optimization touches mirrored code paths (but TS mirrors usually need no port — `charCodeAt` is already cheap; the contracts pin behavior, not implementation).

**Runtime verdict up front:** `addons/reactive_ui/core` needed no perf findings — the reconciler is time-slice-capable (`RUIConfig.time_slicing` + frame budget), hooks store `deps.duplicate()` (no aliasing), and the editor pipeline is debounced/adaptive/size-capped with cached cross-file bindings. The work below is tooling-side.

---

## 1. P1 — Scanner character access (the big one)

### G-10 — All GDScript scanners use `src[i]` single-char-String indexing
- **Anchors:** `guitkx_lexer.gd` (0 uses of `unicode_at`), `guitkx_markup.gd` (0), most of `guitkx.gd`, `guitkx_tokenizer.gd`/highlighter. In GDScript 4, `s[i]` allocates a fresh 1-char String per access and comparisons are string-compares. These loops run per keystroke (highlighter, live diagnostics), per save (compiler), and per poll tick (watch sweeps).
- **RECIPE:**
  1. Convert the LEXER first (`skip_noncode`, `_skip_string`, `find_matching`, `keyword_at`, `_is_ident`): `var c := src.unicode_at(i)` + int-constant comparisons (named `const` ints at the top: `const C_HASH := 35`, `C_QUOTE := 34`, …).
  2. Run the scanner contract tests after EACH function conversion.
  3. Then `guitkx_markup.gd` inner loops (`_parse_nodes`/`_parse_element`/`_parse_attribute`), `guitkx.gd` hot scanners (`_find_decl`, `_split_return`, `_split_body`, `_validate_*`, `_hook_signature`), and the editor tokenizer/highlighter.
  4. Measure with the method noted at `guitkx_editor_view.gd:13` (~2.1 ms/KB baseline) and update that comment with the new number. Expect an order-of-magnitude reduction in scanner cost.
- **Coordination:** the findings-doc G-01 fix adds `skip_noncode_markup` — write that new function in the `unicode_at` style from day one so it doesn't need a second pass.

## 2. P2 — Parser/compiler algorithmic costs

### G-08 — `_line_of` is O(n²)-with-allocation on element-heavy files
- **Anchors:** `guitkx_markup.gd _line_of` (l.396): `_src.substr(0, idx).count("\n")` — a full prefix COPY per element node.
- **RECIPE:** build `_line_starts: PackedInt32Array` once in `parse()` (single pass over `[start,end)`); `_line_of` = binary search. Mirror check: grep `markup.ts` for the equivalent (`slice(0, …).split("\n")`-style) and fix if present. Contract behavior unchanged (line numbers identical).

### GO-01 — `guitkx.gd compile()` re-scans per tier
- `_split_return`, `FindJsx`-style walks, `_validate_hooks`, `_validate_effect_deps`, and `_hook_signature` each walk setup/body text independently per compile. Compile cadence is per-save (not per keystroke), so this is acceptable today; if profiling after G-10 still shows compile > ~50 ms on large files, share one pass that produces (line starts, hook-call offsets, jsx spans) consumed by all tiers. Do NOT restructure preemptively.

## 3. P2 — Editor addon / sweeps

### G-11 — Poll sweep rewalks the tree per tick (bounded; optional)
- **Anchors:** `guitkx_codegen.gd has_stale()` — dir walk + 1-2 mtime reads per file per tick, early-exiting; plus one small sidecar JSON read per tracked file for the 2107 dangling-refs check (cost documented in-code at l.171-180).
- **RECIPE (only if projects grow into hundreds of components):** cache the walk list; invalidate from the plugin's existing `filesystem_changed` debounce (`plugin.gd _on_fs_settled`). Keep the early-exit ordering (compiler_changed → mtimes → sidecars).

### GO-02 — Editor live pipeline — verified good, keep the invariants
- Debounced (`_debounce` Timer, adaptive from `_last_compile_ms` — P1), live compile size-capped (`MAX_LIVE_COMPILE = 150_000`), `project_bindings()` cached against filesystem shape (~35 ms / 100 files, never per tick). No action; when touching `guitkx_editor_view.gd`, preserve these three properties — they are the addon's responsiveness contract.

## 4. P2 — LSP server startup

### G-15 — Synchronous workspace scan + library load inside `onInitialize`
- **Anchors:** `ide-extensions/lsp-server/src/server.ts:95-100` — `scanWorkspace` + `loadLibraries` + `syncAllGuitkxLibraries` run before the initialize response returns → cold-open LSP latency on big projects; **also the direct enabler of the VS2022 save-hang (findings G-18)** — a save issued during the scan window blocks on the busy server.
- **RECIPE:** move the three calls into `connection.onInitialized(...)` behind a `workspaceReady` promise; handlers await it or degrade gracefully (they already tolerate empty indices). Measure: time-to-first-hover on a large project before/after. Do together with findings G-18 (its timeout is the belt, this is the suspenders).

## 5. Suggested order & measurement
1. **G-10** lexer conversion (contract-pinned, mechanical, biggest win) — before/after ms/KB in the PR.
2. **G-15** (with findings G-18) — cold-open time-to-first-hover.
3. **G-08** — parse timing on an element-heavy file (generate one with `dev/gen_markup_fixtures.gd`).
4. **G-11 / GO-01** — only with measurements showing need.
