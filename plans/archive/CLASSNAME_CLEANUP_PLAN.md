# `@class_name` cleanup (Option A) — demos become pure imports/exports — EXECUTION PLAN

> **Status:** APPROVED direction (owner, 2026-07-16 discussion). Researched against the live tree
> the same day — every anchor below was verified by grep/read; re-verify only if the tree moved.
> **Branch:** one branch (`feat/classname-cleanup`), one PR into `dev`, master fast-forward after.
> **House rules apply** (dev-process skill): research → develop → test → bughunt → fix → commit per
> milestone; production-grade only; never weaken a gate; do NOT commit without running the verify
> list; changelog + version bump before release.

---

## 0. What this is (and is NOT)

Since 0.10.0, a file's binding (`class_name` of the generated `.gd`) is **inferred**: `@class_name`
override → else first **exported** declaration's name → else first declaration. The directive is
already optional. Yet **45 of 49** demo `.guitkx` files carry `@class_name X` where `X` is exactly
the declaration name — pure redundancy (verified: zero files use it to *differ*). They exist only
to silence **GUITKX0103** ("component `DemoBailoutChild` differs from file name `bailout_child`"),
a pre-imports convention warning whose purpose (predictable global names under *name-based*
resolution) died when resolution became specifier-based.

**This leg:** (1) retire the 0103 warning, (2) delete the 45 redundant directives so the demos
model the pure import/export style, (3) sweep the docs/README examples to the same style.

**This leg does NOT:** remove `@class_name` from the grammar. It stays a documented, rare escape
hatch (GDScript has no namespaces; the override is the only tool that decouples a decl's import
identity from its flat-global-registry identity on a collision). Grammar removal is a FAMILY
decision, tabled in `MASTER_PLAN.md` §2 alongside re-exports — do not touch it here.

### Locked decisions (do not re-litigate)

1. **0103 is retired from EMISSION, not from the registry.** The `vocabulary.json` severities row
   stays in BOTH copies (number can never be reused; old sidecars still render); its docs table row
   becomes a "retired" note. Rationale recorded as a per-repo divergence note (the Unity-shared
   numbering keeps 0103 alive on other legs — same policy precedent as the imports plan §4).
2. **The directive's machinery is untouched.** Compiler parse, binding override, formatter
   canonicalization (both GD + TS), LSP rename-lockstep, tokenizers, TextMate, schemas, the
   `directives` list in vocabulary — ALL stay. Only the warning and the redundant usages go.
3. **Contract fixtures are untouched.** 39/66 fixtures carry `@class_name` — they pin the
   escape-hatch grammar we're keeping. Only their GOLDENS re-pin (0103 rows vanish).
4. **No editor-addon or IDE-extension version bumps** — no code changes land in them (verified:
   the LSP has no live 0103; only a comment in `workspaceIndex.ts:4`, which stays).
5. Runtime addon ships this as **0.10.2** (patch; a compiler behavior change).

---

## 1. Verified facts / anchors (2026-07-16)

| Fact | Evidence |
|---|---|
| 45/49 demo `.guitkx` have `@class_name`; **all 45 equal their decl name** | scripted audit over `examples/`; the 4 without: `doom_game_screen.hooks`, `gallery_table`, `stress_native.hooks`, `stress_test.hooks` (hook/module companions) |
| 0103 has exactly ONE emission site | `addons/reactive_ui/guitkx/guitkx.gd:721` — inside `_compile_component` (single-decl path). **Mixed-decl files, hooks, and modules never emitted it** — an existing inconsistency; retirement also fixes that asymmetry |
| No test asserts 0103 presence | only hit across `tests/*.gd` is a COMMENT in `guitkx_editor_test.gd:559` (a fixture uses `@class_name` to keep 0103 noise out — fixture keeps working; update the comment) |
| 15 contract goldens contain 0103 entries | `grep -rln "GUITKX0103" tests/contract/golden/` → 15 files (t02, t03, t04, t06, t10, t12, t14, t15, t17, t18, …) — they drift the moment emission stops → re-pin |
| TS contract test ignores diagnostics | `contract.test.ts` `goldenComparable` compares only `windows` + `markup` → re-pinning is TS-safe, no lsp-server changes |
| Binding is unchanged by directive removal | binding = override else first-exported-decl; all 45 overrides equal the decl name → generated `.gd` stays **byte-identical** (verify with hashes, §M2) |
| Codemods never write `@class_name` | 0 hits in `migrate_0_9_0.gd` and `guitkx_migrate.gd` — no codemod work |
| `vocabulary.json` state | `severities["GUITKX0103"]="warning"` in both copies + `guitkx_vocabulary.gen.gd`; 0103 is NOT in the `live` array |
| Docs surfaces teaching the old style | Diagnostics page `structuralRows` 0103 row (`UitkxDiagnosticsPage.tsx:74`); GettingStarted prose (`UitkxGettingStartedPage.tsx:53`) + example (`.example.ts:3` `@class_name HelloWorld`) + `docs.tsx:85` searchContent ("one component per file filename must match component name @class_name HelloWorld"); README quick start (`README.md:80` directive + `:93` prose); ~12 docs `*.example.ts` files carry `@class_name` (list: grep `-rln "@class_name" ReactiveUIGodotDocs~/src/pages/`) |
| Reference page | `@class_name` row exists and STAYS (reword to "optional override, rarely needed") |

---

## 2. Milestones

Run the FULL verify list (§4) at the end of every milestone; commit per milestone.

### M0 — baseline

1. Branch `feat/classname-cleanup` off `origin/dev` (fetch first).
2. Run the §4 verify list once untouched — record the build line (expect
   `49 file(s), 0 error(s), 5 warning(s)`) and hash the generated demo `.gd` for the M2 comparison:
   ```bash
   godot --headless --path . --editor --quit || true
   godot --headless --path . --script res://tests/guitkx_build.gd
   find examples -name "*.gd" | grep -vE "app.gd|signals_store|styling.style|accent_context|doom_types|doom_textures|doom_maps|raycast|doom_bsp|doom_bootstrap|doom_input_state|doom_game_screen_logic|game_logic" | sort | xargs md5sum > /tmp/gd_before.txt
   ```
   (The excluded names are the hand-written `.gd` under `examples/` per `.gitignore`'s re-includes —
   confirm the exclusion list against `.gitignore` before trusting it.)

### M1 — retire GUITKX0103 (emission only)

1. Delete the emission at `guitkx.gd:721` (the `if class_name_override == "" and pc["name"] != basename:` block —
   remove the whole conditional, not just the append; verify no other 0103 site: `grep -rn 0103 addons/ | grep -v vocabulary`).
2. `vocabulary.json` (BOTH copies — `addons/reactive_ui/guitkx/` and `ide-extensions/lsp-server/src/`,
   byte-identical, a test enforces the sync): keep the severities row; append to the top-level
   `__comment`: a one-line divergence note — 0103 registered but retired on the Godot leg since
   0.10.2 (imports made filename identity moot; the number is reserved, never reuse). Regenerate the
   embedded projection: `godot --headless --path . --script res://addons/reactive_ui/dev/gen_vocabulary.gd`
   (**FLAG: commits `guitkx_vocabulary.gen.gd`**).
3. Re-pin the 15 goldens: `godot --headless --path . --script res://tests/contract_dump.gd` then
   review the diff — ONLY 0103 rows may vanish; any `windows`/`markup` change is a bug in your edit.
   (**FLAG: commits `tests/contract/golden/*.json`**.)
4. Docs Diagnostics page: move the 0103 row out of `structuralRows` into a short "Retired" note
   under the table (code, old meaning, "retired 0.10.2 — imports made filename identity
   meaningless; the number stays reserved"). Update `docs.tsx` Diagnostics searchContent if it
   names 0103.
5. Update the stale comment at `tests/guitkx_editor_test.gd:559` (the fixture no longer needs the
   0103 excuse; the `@class_name` in that fixture can stay — it also pins the kept grammar).
6. Add a regression test in `tests/guitkx_test.gd` (`_test_bughunt_fixes` block or a new
   `_test_0103_retired`): compiling `component DemoThing() { return ( <Label /> ) }` with basename
   `some_file` produces **ok = true and NO GUITKX0103** in diagnostics; and (grammar keep-alive)
   `@class_name Custom` still overrides the binding (`gd` contains `class_name Custom`).
7. Verify list. Expected deltas: contract 66 still matches AFTER re-pin; build still
   `0 error(s), 5 warning(s)` (0103 never fired on the demos — the directives silenced it).

### M2 — strip the 45 redundant directives from `examples/`

1. Enumerate: `grep -rln "@class_name" examples --include="*.guitkx"` → expect exactly 45.
2. For each file remove the `@class_name <Name>` line AND the single blank line directly after it
   (every demo follows `@class_name X\n\n<rest>`; verify per-file — if any file has the directive
   elsewhere or no trailing blank, handle it manually, do not blind-sed). A small throwaway script
   is fine; do NOT touch `tests/contract/fixtures/`.
3. Sanity: `grep -rln "@class_name" examples --include="*.guitkx"` → 0.
4. Recompile + byte-identity proof:
   ```bash
   godot --headless --path . --script res://tests/guitkx_build.gd
   find examples -name "*.gd" | <same filter as M0> | sort | xargs md5sum > /tmp/gd_after.txt
   diff /tmp/gd_before.txt /tmp/gd_after.txt   # MUST be empty — binding unchanged by construction
   ```
   If any hash differs, STOP — the directive was not redundant in that file; investigate before
   proceeding (the M0 audit says this cannot happen; trust the audit only after the diff agrees).
5. Codemod idempotency still holds: `godot --headless --path . --script res://tests/guitkx_migrate.gd`
   → `migrated 0`.
6. Note: demo sidecars (`*.guitkx.diags.json`, gitignored) regenerate with shifted offsets (doom's
   0106 rows) — expected, nothing asserts them.
7. Verify list (full — demos, doom, editor, lsp all exercise these files).

### M3 — docs / README style sweep (teach the new style)

1. `README.md`: drop the `@class_name Counter` line from the quick start (`:80`); rewrite the `:93`
   prose — the generated script automatically gets a real Godot `class_name` equal to the (first
   exported) declaration's name, so `Counter.render` mounting still works; mention `@class_name`
   only as an optional override. Check the imports section (`:170`) stays accurate (it is — binding
   text already says "override, else first exported declaration").
2. Docs site — remove `@class_name` from every teaching example that uses it redundantly
   (`grep -rln "@class_name" ReactiveUIGodotDocs~/src/pages/` — GettingStarted, CompanionFiles,
   Hooks, Context, Events, Assets, AdvancedAPI, CustomRendering, Differences, Components, …).
   Rules: examples where the directive equals the decl name → delete the line (+ its blank line);
   the Reference page's directive-table row STAYS, reworded "optional — overrides the inferred
   `class_name`; rarely needed (name collisions with hand-written classes)". GettingStarted prose
   (`:53`) and `docs.tsx:85` searchContent lose the "filename must match" teaching.
3. `MIGRATION-0.10.md` / Migrations page: check whether any example carries a redundant directive;
   align.
4. `cd ReactiveUIGodotDocs~ && npm run build && npm run lint` must both pass.
5. Verify list.

### M4 — release plumbing + plans bookkeeping

1. `addons/reactive_ui/plugin.cfg`: `0.10.1` → `0.10.2`.
2. Root `CHANGELOG.md`: hand-written 0.10.2 entry (retired GUITKX0103 + demos/docs modeled on pure
   imports; `@class_name` unchanged as an optional override). Copy byte-identically to
   `addons/reactive_ui/CHANGELOG.md` (a test enforces the mirror). Short
   `plans/DISCORD_CHANGELOG.md` entry.
3. NO other version bumps (editor addon, extensions untouched — verify `git status` shows no
   changes under `addons/reactive_ui_editor/` beyond the test comment, none under `ide-extensions/`
   beyond the synced vocabulary copy).
4. `plans/MASTER_PLAN.md`: add to §2 (family campaign) a row — "**`@class_name` grammar removal +
   generated-registry privacy end-state** — family decision (GDScript's flat registry is the one
   leg where the override is a namespace substitute); decide with Unity leg 3, alongside
   re-exports". Add this plan to §6 as executed once merged.
5. Verify list one final time; then archive THIS plan to `plans/archive/` with a one-row entry in
   `archive/README.md` (same PR).

---

## 3. What NOT to do (executor guardrails)

- Do NOT remove `@class_name` from: the compiler grammar, `_find_decl`/preamble parsing, binding
  logic, `guitkx_formatter.gd` / `formatGuitkx.ts` canonicalization, `declScan.ts` /
  `workspaceIndex.ts` (`readClassName`, rename-lockstep `classNameStart/End`), editor tokenizer /
  `_cn_re` / references panel, TextMate grammars, `guitkx-schema.json` (×2), or the vocabulary
  `directives` array. The directive is a KEPT feature.
- Do NOT touch `tests/contract/fixtures/*.guitkx` (goldens re-pin only, in M1).
- Do NOT delete the 0103 severities row from vocabulary (number reservation).
- Do NOT "fix" the four companion files that never had the directive — they're already correct.
- Do NOT edit generated `.gd`, `.uid`, or sidecar files by hand.
- Keep tests that USE `@class_name` in inline sources (binding tests, BH-17 parity, imports tests,
  the editor sidecar-overlay fixture) — they pin the kept grammar.

## 4. Verify commands (run after every milestone; all must pass)

```bash
godot --headless --path . --editor --quit || true
godot --headless --path . --script res://tests/guitkx_build.gd          # 49 files, 0 errors, 5 warnings
godot --headless --path . --editor --quit || true
godot --headless --path . --script res://tests/core_test.gd
godot --headless --path . --script res://tests/style_test.gd
godot --headless --path . --script res://tests/router_match_test.gd
godot --headless --path . --script res://tests/router_spine_test.gd
godot --headless --path . --script res://tests/update_test.gd
godot --headless --path . --script res://tests/demos_test.gd
godot --headless --path . --script res://tests/doom_game_test.gd
godot --headless --path . --script res://tests/guitkx_test.gd
godot --headless --path . --script res://tests/hmr_test.gd
godot --headless --path . --script res://tests/guitkx_lsp_test.gd
godot --headless --path . --script res://tests/guitkx_editor_test.gd
godot --headless --path . --script res://tests/contract_dump.gd -- --check
godot --headless --path . --script res://tests/guitkx_migrate.gd        # idempotent: migrated 0
node scripts/corpus-hash.mjs --check                                    # family corpus must NOT drift
node ide-extensions/scripts/changelog.mjs verify
cd ide-extensions/lsp-server && npm run build && node --test out/test/*.test.js && node scripts/smoke.js
cd ReactiveUIGodotDocs~ && npm run build && npm run lint
```

(Godot binary on this machine: `C:\Yanivs\daniela test\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe`.)

## 5. Committed-generated-output flag list

1. `addons/reactive_ui/guitkx/guitkx_vocabulary.gen.gd` — M1 (regenerated after the `__comment` note).
2. `tests/contract/golden/*.json` — M1 (15 goldens lose their 0103 rows; NOTHING else may move).
3. `ide-extensions/lsp-server/src/vocabulary.json` — M1 (byte-identical sync of the addon copy).

## 6. Risks / watch-list

- **The byte-identity diff in M2 is the safety net** — if it's non-empty, an audit assumption broke;
  stop and investigate rather than accepting the new output.
- The 15-golden re-pin must show ONLY diagnostics-row deletions; a windows/markup delta means the
  compiler edit leaked beyond the warning.
- The family corpus hash must not move (nothing here touches familyCore grammar; if
  `corpus-hash.mjs --check` fails, revert — you edited the wrong thing).
- Old sidecars in USER projects may still carry 0103 entries; the LSP renders them from the
  embedded severity — no reader changes needed (verified: severity is per-entry in the sidecar).
- The demos' 0106/2203 warnings (5 total) are pre-existing and out of scope — do not "fix" them here.
