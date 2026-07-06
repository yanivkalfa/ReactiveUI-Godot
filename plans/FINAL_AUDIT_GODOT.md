# ReactiveUI-Godot — Final Audit v3 (Runtime, .guitkx Compiler, Formatter, Editor Addon, LSP/Extensions)

**Date:** 2026-07-06 (v3 — third pass added the full emit half of `guitkx.gd`, `virtual_doc.gd`, `reflowEmbedded.ts`, and runtime hooks/reconciler internals) · **Auditor:** Claude (read-only; no fixes applied in this repo).
**Tree audited:** `dev` @ `3d0ac6e`.

**v3 coverage note (audited and found CLEAN — do not re-audit):** `guitkx.gd` emit layer (`_emit`/`_emit_func`/`_split_return` interleaving, splice-before-alias ordering with its field-capture rationale, per-scope line buffers, `__cfN` hoisting), `_hook_signature` (conservative-by-design), `virtual_doc.gd` structure, `hooks.gd` effect bookkeeping (`[audit C3]` late-call guard, two-pass cleanup) and `reconciler.gd` context duplication/deletion paths, `_stmt_end`/`_first_real` helpers, `unreachable_line_ranges`. `reflowEmbedded.ts` is the safety-net model for formatter work: it BAILS on multi-line strings and enforces token-equivalence — which also confirms the G-02 fix targets the base-indent path that reflow deliberately leaves behind (see G-17 for the one hardening gap found).
**Method (v2):** deep read of the full `guitkx.gd` compiler (validators, `_split_return`/`_split_body`, emit gates), `hmr.gd`, the markup parser, both formatter mirrors, editor addon lifecycle + live-compile cadence, LSP init path — plus **empirical probes** run with node against the compiled TS formatter (`ide-extensions/lsp-server/out/formatGuitkx.js`; probe IDs G1–G6). GDScript-side mirrors are declared line-for-line and contract-tested (`scanner-cases.json`, `tests/contract`), so TS-confirmed findings are *confirmed-on-mirror* for GDScript — re-verify with one headless run while fixing.

---

## HOW TO USE THIS DOCUMENT (read first, executor)

- Findings are `G-##` with severity, anchors, failure scenario, and a **FIX RECIPE** (numbered steps: file → function → change). Write the failing test/contract case FIRST where the recipe names one.
- **Mirror discipline:** `guitkx_markup.gd` ↔ `markup.ts`, `guitkx_formatter.gd` ↔ `formatGuitkx.ts`, `guitkx_lexer.gd` ↔ `scanner.ts` are line-for-line mirrors. Every fix lands in BOTH, plus a `scanner-cases.json` / `tests/contract` case pinning the behavior. Change both or neither.
- Test commands: GDScript side `godot --headless --path . --script tests/guitkx_test.gd` (see tests/README); TS side `cd ide-extensions/lsp-server && npm test`.
- Versioning: patch bumps per artifact (runtime 0.8.x / editor 0.6.x / extensions independent); changelog per artifact per the dev-process skill; publish only via the workflow_dispatch Publish button. Do not commit/push without the user's go.
- **Probe harness:** `node` + `require(".../out/formatGuitkx.js").formatGuitkx(src)` — every confirmed finding quotes its repro input. After a TS fix, `npm run build` (or tsc) before re-probing `out/`.

---

## 0. Executive summary (v2)

This repo is in better shape than the Unity tooling: the formatter already guards the Unity audit's worst class (leading comments, `{expr}` children — probes G2/G5 pass), the lexer is consolidated with cross-impl contract tests, validators are token-boundary and comment-aware (Unity's are not — its plan references THIS repo as the model), and `hmr.gd` + `plugin.gd` + the editor live-compile pipeline audited clean in v2 (debounced, size-capped, cached bindings).

What remains, in priority order:

1. **G-01 (P0):** every directive/return **brace- and paren-matching pass runs the GDScript lexer over MARKUP content** — `#` in markup text swallows same-line delimiters; `{`/`}`/`(`/`)` inside markup `//`, `/* */`, `<!-- -->` comments are miscounted. v2 confirmed the fix surface is wider than v1 stated: it includes `_split_return` and `_split_body`, not just `_read_brace_body`.
2. **G-02/G-03 (P0):** formatter re-anchor corrupts triple-quoted string interiors (confirmed, both mirrors) and deletes blank lines in body code segments.
3. **G-10 (P1 perf):** all GDScript scanners use `src[i]` per-char String allocation instead of `unicode_at()`.
4. LSP/config items (G-12…G-15) — fold into the VS2022 parity campaign; note the parity plan's §P1 is partially stale (G-14).

---

## 1. P0 — Compiler correctness

### G-01 — GDScript-lexis brace/paren matching over markup content (CONFIRMED failure modes; fix surface EXPANDED in v2)
- **Root cause:** `guitkx_lexer.gd skip_noncode()` implements GDScript lexis (`#` = comment; `//`,`/* */`,`<!-- -->` are not comments; markup attr strings happen to share quote syntax). Every balanced-region scan that spans MARKUP uses it via `L.find_matching`.
- **Fix surface (all confirmed by reading; G3/G4 confirmed by probe as parse failures):**
  1. `guitkx_markup.gd _read_brace_body()` (l.294) — `@if/@for/@while` bodies.
  2. `guitkx_markup.gd _read_paren()` (l.283) — directive headers (safe-ish: headers are GDScript expressions — LEAVE as GDScript lexis).
  3. `guitkx_markup.gd _parse_match()` (l.354) — the `@match` body brace.
  4. `guitkx.gd _split_return()` (l.1054) — the `return ( … )` markup window: `// smiley :)` in markup text miscounts parens; `#` in text swallows same-line `)`.
  5. `guitkx.gd _split_body()` — same pattern for directive bodies (verify each `find_matching` call inside it).
  6. `guitkx.gd _parse_component_at()` (l.384) — the component body brace: markup inside the body has the same exposure (e.g. `<Label>Score #3</Label>` followed by `}` on the same line closes the COMPONENT early).
- **Confirmed repros (via TS formatter falling back to verbatim = parse failure; same parse feeds the compiler → user-facing errors on valid-looking input):**
  - G3: `@if (true) { <Label text="x"/> # }` → unclosed-body error (the `#` eats the `}`).
  - G4: body containing `// TODO: revisit }` → the `}` inside the markup comment closes the body early → mismatched/unclosed errors.
  - Constructible worse case: a `#` line whose tail contains a rebalancing `{` shifts the body span SILENTLY → miscompiled output. This is why it's P0, not P2.
- **FIX RECIPE:**
  1. Add to `guitkx_lexer.gd` a second scanner: `static func skip_noncode_markup(src: String, i: int) -> int` that skips: `//`-to-EOL, `/* … */`, `<!-- … -->`, and quoted strings (`"`/`'`, no prefixes) — and does NOT treat `#` as a comment. Mirror in `scanner.ts` as `skipNoncodeMarkup`.
  2. Add `static func find_matching_mixed(src: String, open_i: int) -> int`: like `find_matching`, but tracks a **mode**: starts in `code` mode (GDScript lexis); switches to `markup` mode when at depth ≥ 1 it encounters `<` followed by a letter or `<>` at a node-start position, and back at the matching close-tag/self-close (simplest robust approximation: once inside the body braces, classify per LINE — a line whose first non-ws char is `<`, `@`(directive), `{`, `//`, `/*`, or `<!--` is markup-mode; lines starting with GDScript statement forms (`var `, `if `, `return`, identifiers…) are code-mode. Line-mode classification is exactly what `_split_body` already does for its parts — REUSE that classification rather than inventing a new one).
  3. Concretely: directive/return bodies are already split into `gd` and `ret/markup` parts by `_split_body`/`_split_return` — the ordering problem is that today the SPAN is found before the split. Invert: find the span with a scanner that uses `skip_noncode` on code-classified lines and `skip_noncode_markup` on markup-classified lines (classification by first-non-ws char per line as above; a line's trailing content after markup close on the same line is rare and covered by tests).
  4. Replace the calls at fix-surface items 1, 3, 4, 5, 6 with the mode-aware matcher. Item 2 (headers) stays GDScript.
  5. Mirror everything in `markup.ts` (`readBraceBody`, `parseMatch`) and the TS ports of `_split_return`/`_split_body` in `formatGuitkx.ts`/`virtualDoc.ts` (grep `findMatching(` there).
  6. Contract cases (`scanner-cases.json` + `tests/contract` golden): the G3 and G4 inputs; `<Label>Score #3</Label>` + same-line `}`; `<!-- } -->` in a body; `#FF0000` color text in a label followed by `)` on the same line inside `return ( … )`; and a *component-body* case (`<Label>#x</Label> }` on one line).
  7. If any pattern remains unsupported after this (decide consciously), emit a targeted diagnostic (GUITKX0150-style guidance), never a bare unclosed error.

---

## 2. P0 — Formatter (both mirrors)

### G-02 — Triple-quoted string interiors corrupted by re-anchor  *(CONFIRMED, probe G1)*
- **Anchors:** `guitkx_formatter.gd _reanchor()` (l.410-442), `_reanchor_rel()` (l.386), `_collapse_spaces()`; TS mirror `formatGuitkx.ts reanchor()` (l.602), `reanchorRel()` (l.573), `collapseSpaces`.
- **Repro:** setup `var msg := """\nline1\n  keep  two  spaces\n\t\ttabbed line\n"""` → interior lines re-indented AND `keep  two  spaces` → `keep two spaces` (interior run collapsed) → **runtime string value changed**.
- **FIX RECIPE:**
  1. In both mirrors, add a helper that walks the block ONCE with the existing string scanner and returns a per-line boolean "starts inside an open multi-line string" mask (`_skip_string` already understands `"""`/`'''`; record line starts while scanning). GDScript: `static func _multiline_string_mask(code: String) -> Array[bool]` in the formatter (or lexer, shared with G-01 work); TS: `multilineStringMask(code: string): boolean[]`.
  2. In `_reanchor`/`reanchor` AND `_reanchor_rel`/`reanchorRel`: for masked lines, emit **byte-verbatim** (no strip, no `_collapse_spaces`, no depth math, and `depths[i]` recorded as -1-like "opaque" so they don't affect the anchor); also exclude them from `_indent_unit` inference.
  3. Contract/golden cases: the G1 input round-trips byte-identical inside the literal; a masked line starting with `}` doesn't affect anything; `'''` variant; a raw-prefix `r"""` variant.

### G-03 — Blank lines inside directive-body GDScript segments deleted  *(CONFIRMED, probe G6)*
- **Anchors:** `_reanchor_rel` (l.390-391: `if t == "": continue`) / `reanchorRel` (l.576). Plain `_reanchor` PRESERVES blanks — the two disagree.
- **FIX RECIPE:** in both mirrors' `_reanchor_rel`, replace the `continue` with emitting a bare `"\n"` (exactly like `_reanchor`'s `depths[i] == -1` branch). Golden case: `var a := 1\n\nvar b := 2` inside an `@if` body keeps its blank line, idempotent.

### Verified GOOD in v2 (do not "fix")
Leading comments preserved (G2); `{expr}` children + markup comments preserved (G5); parse error → byte-verbatim; `@match` paren-wrapped case values; Allman `@else`/`@elif` accepted (`_skip_ws` includes newlines); module member doc-comments re-emitted (`_member_comments`).

---

## 3. P1 — Compiler / tooling correctness (smaller)

| ID | Anchor | Finding + RECIPE |
|---|---|---|
| G-04 | `guitkx_markup.gd _parse_element` l.167 | close-tag guard passes when `<` is the last char before `end` (third clause false at boundary) → less precise error. Recipe: change to `if j >= end or _src[j] != "<" or j + 1 >= end or _src[j + 1] != "/":` + mirror markup.ts + one contract case (`<Box><` at EOF). |
| G-05 | `_fmt_attr` "str" l.284 | re-emits `name="value"` unescaped; parser can't currently produce an embedded `"` but a future escape would corrupt silently. Recipe: `if "\"" in value: return source-verbatim fallback` (set a `fell_back` flag per G-06) + comment. |
| G-06 | `format()` l.24-29 | always `ok:true`; callers can't distinguish "formatted" from "verbatim fallback". Recipe: thread a `fell_back: bool` through `_format_or_verbatim` (return `{text, fell_back}`), include in `format()`'s dict, and show a status-bar hint in `guitkx_editor_view.gd`'s format action ("file has syntax errors — format skipped"). Mirror TS: return `{ text, changed, fellBack }` and surface in the VS Code handler as a window message (once per file per session). |
| G-07 | `guitkx.gd` `@uss` checks l.199-202 | `FileAccess.file_exists` doesn't accept `uid://`; verify `ResourceLoader.exists(uss_path,"Theme")` covers uid form and short-circuit the file_exists check when path begins with `uid://`. |
| G-08 | `guitkx_markup.gd _line_of` l.396 | `substr(0, idx).count("\n")` = O(n) copy PER ELEMENT (O(n²) + allocation on big files). Recipe: precompute line starts once in `parse()` (`_line_starts: PackedInt32Array` built with one pass), `_line_of` = binary search. Mirror markup.ts if it shares the pattern (grep `countLines`/`substr(0`). |
| G-09 | `hooks.gd _deps_changed/_equal` l.565 | GDScript `==` deep-compares Arrays/Dictionaries → deps semantics differ from React identity (recreated-but-equal dict does NOT re-run; big structures deep-compare per render). Design decision, not a bug: DOCUMENT in the hooks docs page + add a perf note; optionally support an explicit `same_ref` escape hatch later. |
| G-16 | `hmr.gd _is_module` l.156 | source-text heuristic (`contains("static func render(")`) misclassifies a module whose comment/string contains that text → misses the global re-render. Recipe: emit a dedicated const in generated components (`const __RUI_KIND := "component"`) and read it via `get_script_constant_map()` like `__RUI_HOOK_SIG`; fall back to the text check for pre-existing outputs. LOW severity. |
| G-17 | **NEW (v3)** `reflowEmbedded.ts normalizeGd` l.118-121 | the token-equivalence safety net STRIPS comments before comparing — a gdscript-fmt bug that deleted or mangled a comment would pass the guard and ship the corruption. Recipe: emit comment tokens into the normal form instead of skipping them (`out += "" + commentText.trimEnd()` per comment, order-preserving); adjust the two existing reflow tests that rely on comment-insensitive equivalence, add one where the formatter output drops a comment → region must stay untouched. LOW likelihood, cheap hardening on a data-integrity path. |

## 4. P1 — Performance (editor tooling)

### G-10 — Scanners use `src[i]` single-char String indexing
- **Anchors:** `guitkx_lexer.gd` (0 `unicode_at` uses), `guitkx_markup.gd` (0), most of `guitkx.gd`, `guitkx_tokenizer.gd`. In GDScript 4, `s[i]` allocates a 1-char String per access; comparisons are string-compares. These run per keystroke (highlighter/live diagnostics), per save (compiler), and per poll tick.
- **FIX RECIPE:**
  1. Convert the LEXER first (`skip_noncode`, `_skip_string`, `find_matching`, `keyword_at`, `_is_ident`): take `var c := src.unicode_at(i)` and compare against int constants (`35` = `#`, `34` = `"`, …). Add named `const` ints at the top for readability.
  2. The behavior is pinned by `scanner-cases.json` contract tests — run them after each function conversion (this is a pure-perf change; any contract diff = bug in the conversion).
  3. Then convert `guitkx_markup.gd` `_parse_nodes`/`_parse_element`/`_parse_attribute` inner loops and `guitkx.gd`'s hot scanners (`_find_decl`, `_split_return`, `_split_body`, `_validate_*`), and the editor tokenizer/highlighter.
  4. Measure before/after with the existing `MAX_LIVE_COMPILE` comment's benchmark method (~2.1 ms/KB baseline noted at `guitkx_editor_view.gd:13`) and update that comment.
- **Verified good in v2 (leave alone):** the editor pipeline is debounced (`_debounce` Timer + adaptive from `_last_compile_ms`), live compile is size-capped (150 k chars), and `project_bindings()` is cached against filesystem changes.

### G-11 — Poll-sweep rewalk (bounded; optional)
`guitkx_codegen.gd has_stale()` rewalks the tree per tick with early exit + per-file sidecar JSON reads for the 2107 check. Fine at current scale; if projects grow: cache the walk list, invalidate from the plugin's existing `filesystem_changed` debounce. No action now.

## 5. P2 — LSP / extensions

### G-12 — Config read only at initialize; no `onDidChangeConfiguration`
- **Anchors:** `extension.ts:45-49` (initializationOptions), `server.ts:70-90`; no config-change handler in server.ts (grep verified).
- **FIX RECIPE:** in `server.ts`, add `connection.onDidChangeConfiguration(...)` that re-reads `settings.guitkx.{enableEmbeddedAnalysis,useGdformat}` and updates `embeddedEnabled`/`embeddedReflow`; extract the alias-resolution into one helper shared with `onInitialize`. The client already has `synchronize: { configurationSection: "guitkx" }` so notifications flow. Manual test: toggle the setting; hover in embedded code turns on/off without restart.

### G-13 — `enableGdscriptAnalysis` needs window reload
- `extension.ts:40-42` builds the selector once. RECIPE: cheapest correct fix — `workspace.onDidChangeConfiguration` listener that, when `guitkx.enableGdscriptAnalysis` changes, calls `client.restart()` after an information prompt. Mention in the setting description.

### G-14 — Parity-plan staleness correction (do BEFORE the VS2022 campaign)
`plans/VSCODE_VS2022_PARITY_PLAN.md` §P1 says the VS Code client hardcodes `enableEmbeddedAnalysis` / never sends `useGdformat`. **Stale as of `dev@3d0ac6e`** — `extension.ts:45-49` sends both from config. The initializationOptions CONTRACT section remains accurate. Update §P1's current-state wording so the executor spends effort on the VS2022 client (which still needs to send them), not on re-fixing VS Code.

### G-15 — Synchronous workspace scan in `onInitialize`
- **Anchors:** `server.ts:95-100` — `scanWorkspace` + `loadLibraries` + `syncAllGuitkxLibraries` before the initialize response.
- **FIX RECIPE:** move the three calls into `connection.onInitialized(...)` (the watcher registration already lives there per the l.104 comment), guarded by a `workspaceReady` promise that completion/hover/definition handlers await (or degrade gracefully before it resolves — they already tolerate empty indices). Test: cold-open latency of the first hover in a big project drops; no handler throws pre-scan.

## 6. Cross-repo parity ledger (updated v2)

| Topic | Godot | Unity | Action |
|---|---|---|---|
| Formatter: leading comments / `{expr}` children | ✅ | ❌ (U-01/U-02, confirmed) | Port Godot's guards to Unity (Unity plan has recipes). |
| Formatter: multi-line string interiors | ❌ G-02 (confirmed) | ❌ U-03 (confirmed) | Same mask-based fix + SHARED test corpus (write the corpus once, port inputs). |
| Formatter: splice-index desync | n/a (single-detector design) | ❌ **U-36 confirmed data loss** | Unity adopts the range-driven single-detector approach (its recipe says so). |
| `@else` newline placement | ✅ | ❌ U-05 | Fix Unity. |
| `@case` value delimiting | ✅ paren-wrapped | ❌ U-04 (confirmed corruption) | Fix Unity; Godot form is the reference. |
| Comment-aware region scanning | ❌ G-01 (markup side) | ❌ U-07 (block comments) | Same lesson both ways: scan with the CONTENT'S lexis. |
| Hook-call detection | ✅ token-boundary + noncode-skipping (`_find_hook_call`) | ❌ U-10 confirmed false positives | Unity ports Godot's semantics (named in Unity recipe). |
| HMR parse-error gating | ✅ (`ok`/error invariant T1.1, `D.has_error` gates at compile l.235-239 & emit) | ❌ **H-01: HMR ignores diagList entirely** | Fix Unity HMR; Godot's T1.1 invariant is the model. |
| HMR runtime | ✅ `hmr.gd` clean (ack-first, per-file isolation, sig-reset) | ✅ controller solid; queue-drain freeze H-02 | Fix Unity drain. |
| Lexer consolidation + contract tests | ✅ | ❌ U-20 | Unity adopts; port `scanner-cases.json` mechanism. |

## 7. Runtime & addon notes (v2 verified — no action)
- `reconciler.gd`: `_restart` machinery (cap 25) present = Unity 0.6.4 interrupted-render fix counterpart; time-slicing togglable.
- `hmr.gd`: ack-before-apply, per-file failure isolation, `__RUI_HOOK_SIG` reset semantics, binding injection for post-launch components — audited clean (one LOW: G-16).
- `plugin.gd`: dependency handshake, engine-registered loader rationale, full `_exit_tree` teardown, fs-debounce — clean.
- `guitkx_codegen.gd`: mtime+hash staleness ladder, error-verdict sidecars, orphan/dangling sweeps — exemplary; no changes.

## 8. Repo hygiene
- Add `tests/__*_tmp/` to `.gitignore` (dirs exist on disk untracked: `__dangling_tmp`, `__dupe_tmp`, `__has_stale_tmp`, `__orphan_tmp`).
- Consider excluding `out/test/**` from extension bundles (committed build output is intentional for the bundle-server flow; test files aren't needed).
- FYI resolved in the UNITY repo (affects GitHub language stats there, not here): the 1.45 MB `tscn_stable.html` (a saved Godot-docs page) was the "20% HTML"; deleted, pending user commit. This repo's language bar (GDScript ~50% / TS ~47%) is accurate; the 0.2% "Harbour" is linguist misclassifying some `.prg`-like or generated file — harmless, ignorable.

## 9. Execution order (v2)
1. **G-01** (mode-aware matching; biggest correctness item; contract cases first).
2. **G-02 + G-03** (formatter string mask + blank lines; shared corpus with Unity U-03).
3. **G-10** (unicode_at conversion, lexer first, contract-pinned).
4. **G-12/G-13/G-15** + apply the **G-14** parity-plan correction, then hand the VS2022 campaign to its executor.
5. Section 3 smalls (G-04…G-09, G-16, G-17) + hygiene (§8).

## 10. Probe artifacts
`rg_probe.js` (session scratchpad) drives G1–G6 via node against `out/formatGuitkx.js`. For GDScript confirmation of G-01/G-02 add the same inputs to `tests/guitkx_test.gd` (or the golden corpus) and run headless.
