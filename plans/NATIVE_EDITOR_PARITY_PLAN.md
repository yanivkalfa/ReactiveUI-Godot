# NATIVE_EDITOR_PARITY_PLAN — `reactive_ui_editor` → parity with the VS Code extension

**Status: PLANNED 2026-07-04.** Evidence: full feature inventories of both surfaces taken this day
(VS Code/LSP `ide-extensions/` at 0.8.6; addon `addons/reactive_ui_editor/` at 0.2.0), diffed
against the mechanism constraints in `GODOT_EDITOR_EXTENSION_PLAN.md` §2/§6 and the deep-tier
design in `GODOT_ANALYZER_INTEGRATION_PLAN.md`. Driver: **submit the editor addon to the Godot
Asset Store ASAP** — so the plan is milestone-ordered: M1 = store-submittable, M2 = full
markup-tier parity, M3 = embedded-GDScript depth (gdext; existing plan, referenced not repeated).

---

## 1. Where each side stands (inventory summary)

**VS Code extension (the parity target), 0.8.6** — LSP capabilities actually registered:
completion (`< @ . _` + space triggers), hover, definition, references, rename+prepare,
signatureHelp, documentSymbol, inlayHint, codeAction, semanticTokens (full), formatting
(doc+range), push diagnostics, `**` file watcher (`lsp-server/src/server.ts:101-121`).
**Deliberately absent there too — so OUT of parity scope:** workspaceSymbol, foldingRange,
on-type formatting, executeCommand, pull diagnostics, semanticTokens `range`, markup-tier code
actions (did-you-mean is message text only).

**Godot addon, 0.2.0** — main-screen editor (single buffer, Open/Save/Format toolbar), theme-aware
9-category highlighter + unreachable dimming, live diagnostics via `RUIGuitkx.compile` on a 0.3 s
debounce (gutter icons + line tint + Problems bottom panel + click-to-jump), context-aware
completion (tagName/markup/attrName/directive; **live ClassDB** — richer source than VS Code's
static dump), hover via 4.4+ `symbol_hovered` (plain-text tooltip), lazy workspace component
index, 6 settings toggles, 39-check headless suite (`tests/guitkx_lsp_test.gd`) — **not wired
into CI**.

**The addon's native advantages to preserve:** live `ClassDB` (no `godot-control.json` dump),
in-engine compiler = the *real* diagnostic catalog on the live buffer (VS Code only approximates
it between saves), theme-integrated colors.

---

## 2. The gap table (feature → status → mechanism → milestone)

Legend: ✅ have · 🟡 partial · ❌ missing. Mechanisms are from `GODOT_EDITOR_EXTENSION_PLAN.md` §6.

| # | Feature (VS Code ref) | Addon today | Gap | Godot mechanism | MS |
|---|---|---|---|---|---|
| G1 | Go-to-definition: component tag → declaring `.guitkx` | ❌ (index stores `offset` **expressly for this**, nothing consumes it; hover text falsely advertises Ctrl-click — `lsp/guitkx_workspace.gd:6,91`, `lsp/guitkx_hover.gd:32`) | wire it | `symbol_lookup_on_click` + `symbol_validate` → `set_symbol_lookup_word_as_valid` + `symbol_lookup` → `open_resource` + caret | **M1** |
| G2 | Find references: component across project | ❌ | port `refs.ts` `scanTagRefs` (boundary-aware, skips `a < Name`) | results list in Problems panel (new "References" tab) + click-to-jump | M2 |
| G3 | Rename: component atomic (usages + decl + `@class_name`), collision-refusing | ❌ | port `server.ts:1332-1368` gate + edit set | toolbar/context action + `EditorFileDialog`-less popup; apply to open buffer + on-disk files via `FileAccess` | M2 |
| G4 | Signature help: `on_<signal>={ func(` param tracking | ❌ | port `signatureHelpAt` (`server.ts:1540-1629`) | no built-in popup — draw a small `PopupPanel` above caret on `(`/`,` | M2 |
| G5 | Completion: `attrValue` context (bool/enum values) | ❌ (classified, returns `[]` — `lsp/guitkx_completion.gd:19-28`) | serve it | same `_request_code_completion` path | M2 |
| G6 | Completion: style-dict keys (50 `STYLE_KEYS` inside `style={ {…} }`) | ❌ | port `inStyleDict` (`server.ts:602-620`) + key table (already in schema JSON? — add if not) | same | M2 |
| G7 | Completion: `Color.` / `Vector2.` builtin member constants | ❌ | trivial natively: live `ClassDB`/`CoreConstants` beats the TS static table | same | M2 |
| G8 | Completion: hook names in setup lines (`useState`…) | ❌ (VS Code serves via analyzer; a cheap vocabulary-driven approximation is possible now) | offer hook names + snippets when the caret is on a setup line | same | M2 |
| G9 | Hooks hover cards (23 curated markdown signatures — `server.ts:652-676`) | ❌ | port `HOOK_HOVER` table into addon data | rich tooltip (G10) | M2 |
| G10 | Rich hover (markdown: bold, fenced code) | 🟡 markdown *stripped* to plain `tooltip_text` | `_make_custom_tooltip` returning a `RichTextLabel` (BBCode; convert our markdown subset) | Control tooltip override | M2 |
| G11 | Embedded `{expr}` GDScript sub-highlighting | 🟡 one flat span (`guitkx_tokenizer.gd:53-59`); setup lines outside markup already tokenize | recurse the existing tokenizer inside `{…}` spans | per-line tokenizer | M2 |
| G12 | Document outline (component/hook/module/member tree) | ❌ | port `scanDeclarations` consumers | side `Tree` panel in the main screen; click-to-jump | M2 |
| G13 | Cross-file unknown-component diagnostics (0105 + did-you-mean) | ❌ in-editor (`compile(text, basename)` is called with **no** `known_components`/`component_paths`, so unknown-tag checks can't arm — `editor/guitkx_editor_view.gd:126`) | pass `Codegen.project_bindings()` output into the live compile, exactly like the watcher does | existing compiler API | **M1** |
| G14 | Project-wide Problems (all files, not just the open buffer) | ❌ (panel is single-buffer) | the sidecars (`*.guitkx.diags.json`) already exist on disk — read them all; group by file; jump opens the file | Problems panel second tab "Project" | M2 |
| G15 | Workspace-index freshness on external create/rename/delete | ❌ (index refreshes only on in-editor Save; `rescan()` exists, never called) | hook `EditorInterface.get_resource_filesystem().filesystem_changed` → debounced `rescan()` | EditorFileSystem signal | **M1** |
| G16 | Multi-file editing (tabs / open-files list) | ❌ single buffer | script-editor-style left `ItemList` of open files + per-file undo/caret state | main-screen layout change | M2 |
| G17 | Editor session state (reopen last file(s), caret) | ❌ (`get_state`/`set_state` unimplemented) | implement `EditorPlugin.get_state/set_state` (+ `get_window_layout`) | EditorPlugin API | M2 |
| G18 | "New .guitkx file" action (+ template content) | ❌ | toolbar + FileSystem-dock friendly flow; template = minimal `component` skeleton | EditorFileDialog save mode | M2 |
| G19 | Gutter-click diagnostic detail | 🟡 `push_warning` to Output (`guitkx_editor_view.gd:187-189`) | proper popup/tooltip at the gutter line | PopupPanel or tooltip | M2 |
| G20 | Snippet-style directive completion (`@if (…):` bodies) | 🟡 plain-text inserts | CodeEdit has no tabstops — insert expanded body, place caret inside parens (best approximation; accepted deviation) | completion insert + caret move | M2 |
| G21 | Embedded-GDScript completion/hover/diagnostics/signature/inlay/code-actions/semantic overlay | ❌ (explicitly deferred) | **gdext analyzer binding** — `GODOT_ANALYZER_INTEGRATION_PLAN.md` Phases 2–5, incl. virtualDoc + sourceMap + LineIndex ports; feature-detect, degrade to markup-only | gdext (native) | M3 |
| G22 | Plain-`.gd` intelligence (the extension's 4th tier) | ❌ — and **out of scope**: Godot's own editor already owns `.gd` | n/a | n/a | — |
| G23 | Format range (selection) | ❌ (VS Code has it; low value in-engine) | non-goal for now; Format is whole-doc + on-save | — | — |

**Store/packaging gaps (submission-blocking):**

| # | Item | Today | Fix | MS |
|---|---|---|---|---|
| S1 | Cross-addon **parse-time preload** `res://addons/reactive_ui/guitkx/guitkx_diag.gd` (`editor/guitkx_diagnostics_renderer.gd:12`) — addon fails to load if `reactive_ui` absent | hard crash path | convert to runtime `load()` + existence check; plugin loads and shows one friendly "requires the Reactive UI addon" warning, disables compile-dependent features | **M1** |
| S2 | `RUIGuitkx` / `RUIGuitkxFormatter` / `RUIGuitkxLexer` global-class references (same failure class) | hard dep | same feature-detect gate (`ClassDB`/`type_exists` check at startup); highlighting w/o lexer needs the lexer — gate the *whole* addon behind the check with the friendly message (dependency stays REQUIRED, but failure becomes graceful + explained) | **M1** |
| S3 | `tests/guitkx_lsp_test.gd` not in CI (`test.yml`, `publish.yml`) | manual-only | add to both suites | **M1** |
| S4 | `publish.yml` has no editor-addon leg | only `reactive_ui` ships | add `release-editor-addon` job: version from `reactive_ui_editor/plugin.cfg`, tag `editor-v<ver>`, zip `addons/reactive_ui_editor` **+ LICENSE**, idempotent skip-if-tag-exists — mirror of `release-addon` | **M1** |
| S5 | Store listing assets + metadata | none | 16:9 thumbnail variant, summary/description (declare the `reactive_ui` dependency prominently!), AI-disclosure line, version zip; manual dashboard add (no API yet) | **M1** |
| S6 | Addon `LICENSE`/README inside the zip; listing docs | root LICENSE only | zip step includes LICENSE (same fix as the main addon's next release); short `addons/reactive_ui_editor/README.md` | **M1** |
| S7 | Stale `README.md` claim: "best-effort line anchoring" — code now does exact offsets | doc drift | refresh addon README (it doubles as listing copy) | **M1** |

---

## 3. Milestones

### M1 — Store-submittable (target: ~2–3 focused days)
The bar: **honest, robust, packaged** — not feature-complete.

1. **S1+S2 graceful dependency**: runtime-load all `reactive_ui` references; single startup check
   (`type_exists("RUIGuitkx")` etc.); absent → EditorToaster/dialog message + addon idles cleanly.
2. **G1 go-to-definition**: `symbol_validate`/`symbol_lookup` → `GuitkxWorkspace.lookup(tag)` →
   open in our main screen + caret to stored offset. Also makes the existing hover text truthful.
   (Small: the index side is already built.)
3. **G13 known-components in live compile**: reuse `Codegen.project_bindings()` (cheap, cached per
   debounce tick) so in-editor buffers get 0105/did-you-mean exactly like the watcher sweep.
4. **G15 index freshness**: `filesystem_changed` → debounced `GuitkxWorkspace.rescan()`.
5. **S3 CI**: `guitkx_lsp_test.gd` into `test.yml` + `publish.yml`; add checks for G1/G13 logic
   (lookup resolution; unknown-component diag with a planted two-file fixture).
6. **S4 publish leg + S6 packaging**: `release-editor-addon` job (tag `editor-v0.3.0`), zip
   includes LICENSE; also fix the main `release-addon` zip to include LICENSE (store guideline:
   license must be inside the download — currently satisfied only by my hand-built zip).
7. **S5+S7 listing prep**: addon README refresh, thumbnail, field sheet; bump `plugin.cfg` →
   **0.3.0** (additive: goto-def). Submit to the new store (manual) as a **second asset** that
   declares the Reactive UI dependency; AL listing optional/later.

### M2 — Markup-tier parity (target: ~2–3 weeks, ship in 2–4 releases)
Order by user value; each lands with headless checks + a changelog entry, versions 0.4.x…:

1. **G10 rich hover** (`_make_custom_tooltip` + BBCode) → then **G9 hooks cards** (port the
   curated table; single data file shared-shape with `server.ts:652-676`).
2. **G5/G6/G7/G8 completion contexts**: attrValue, style-dict keys, builtin members (native
   ClassDB), setup-line hook names + snippets.
3. **G2 references + G3 rename** (port `refs.ts` + the rename gate; References tab in the panel;
   rename applies to disk + open buffer; refuse host-tag/collision exactly like the TS gate).
4. **G12 outline** + **G16 multi-file open list** + **G17 session state** (one UX wave — they
   touch the same main-screen layout).
5. **G14 project-wide Problems** (sidecar aggregation) + **G19 gutter popup**.
6. **G4 signature help** (hand-drawn popup; markup `on_<signal>` tier only until M3).
7. **G11 embedded sub-highlighting** + **G18 new-file** + **G20 snippet caret** (polish wave).

**Parity-verification discipline** (mirrors the HMR/formatter precedent): extend the golden-fixture
corpus so context classification, completion item sets, hover texts, and refs/rename edit sets are
asserted against the same fixtures the TS suite uses (`ide-extensions` `markup-cases`); a drift in
either implementation fails one suite or the other.

### M3 — Embedded-GDScript depth (existing plan; ~4–6 weeks, separate track)
`GODOT_ANALYZER_INTEGRATION_PLAN.md` Phases 2–5 unchanged: gdext crate in the analyzer repo →
per-OS CI → `virtualDoc`/`sourceMap`/`LineIndex` GDScript ports → wire completion/hover/
diagnostics/signature/inlay/code-actions/semantic overlay for `{expr}`/setup — feature-detected,
optional, markup-only degradation. Closes G21 and reaches the §9 parity ceiling of
`GODOT_EDITOR_EXTENSION_PLAN.md` (everything except Script-type/debugger integration, which
requires `ScriptLanguageExtension` and stays rejected).

---

## 4. Non-goals (explicit)
- **workspaceSymbol / folding provider / on-type formatting / pull diagnostics / range semantic
  tokens** — absent in the VS Code extension too; parity does not require them.
- **Plain-`.gd` intelligence** (G22) — Godot's editor owns `.gd`.
- **Format-range** (G23) — whole-doc + on-save only.
- **`ScriptLanguageExtension`** — rejected (60+ virtuals, crash edges); see extension plan §2.2.
- **Tabstop snippets** — CodeEdit has none; caret-placement approximation accepted.

## 5. Risks
- **`symbol_lookup` word granularity**: validate-word hooks give the word, not the tag span —
  PascalCase words are fine, but `@class_name` values need the context classifier at the caret
  (already ported). Low.
- **Two markup implementations drift** (TS ↔ GDScript) — the standing risk; the golden corpus is
  the mitigation and M2 makes it CI-enforced both sides.
- **Rename touching closed files** — disk writes race the `reactive_ui` watcher sweep; do writes
  first, then one `resource_filesystem.scan()`, and let the sweep recompile (same discipline as
  Save).
- **Problems-panel sidecar reads** on large projects — cheap (JSON per file), but debounce reads
  behind `filesystem_changed` like the index.
- **Store review of a dependent addon** — the listing must be unmissable about requiring
  Reactive UI; bundle-vs-depend questions from reviewers are possible (answer: depend; the
  runtime addon is the product, the editor is tooling).

## 6. Decisions for the user
1. **M1 scope OK?** (graceful-dep + goto-def + known-components + freshness + CI + publish leg +
   listing at 0.3.0 — then submit.)
2. **Second listing name** — proposal: **"Reactive UI Editor (.guitkx tooling)"**, publisher
   yaniv-kalfa, slug `reactive-ui-editor`.
3. **M2 ordering** — the list above is my value-ranking; reorder freely.
4. **AL (classic) second listing** — skip (new-store only) or also submit? Recommendation: skip;
   the editor addon targets 4.7 users, who browse the new store in-editor.
