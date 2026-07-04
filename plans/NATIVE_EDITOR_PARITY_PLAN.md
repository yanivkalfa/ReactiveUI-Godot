# NATIVE_EDITOR_PARITY_PLAN — `reactive_ui_editor` → parity with the VS Code extension

**Status: PLANNED 2026-07-04 — four audit passes + a runtime benchmark, all claims in-code
verified.** Pass 1 = feature inventories of both surfaces (language parity → G1–G23). Pass 2 =
host-editor affordances (→ G24–G30). Pass 3 = interaction flows (→ G31–G34). **Pass 4 =
exhaustive four-lens parallel sweep**: editor substrate (→ E-table), file lifecycle (→ L-table),
diagnostic sources (→ D-table), tests/docs/release plumbing (→ F-table), plus a headless
performance benchmark (→ P-table). Driver: **submit the editor addon to the Godot Asset Store
ASAP** — milestone-ordered: M1 store-submittable → M2 markup-tier parity → M3 embedded depth
(gdext; `GODOT_ANALYZER_INTEGRATION_PLAN.md`, referenced not repeated). Mechanism constraints:
`GODOT_EDITOR_EXTENSION_PLAN.md` §2/§6/§9.

**Version note:** the addon is **0.3.0** (in-flight working tree, 2026-07-04; completion+hover
release). M1 ships as **0.4.0**.

---

## 1. Where each side stands

**VS Code extension (parity target), 0.8.6** — registered: completion (`< @ . _` + space),
hover, definition, references, rename+prepare, signatureHelp, documentSymbol, inlayHint,
codeAction, semanticTokens(full), formatting(doc+range), push diagnostics, `**` watcher
(`lsp-server/src/server.ts:101-121`). **Absent there too — OUT of parity scope:**
workspaceSymbol, foldingRange, on-type formatting, executeCommand, pull diagnostics,
semanticTokens range, markup-tier code actions.

**Godot addon, 0.3.0** — main-screen editor (single buffer, Open/Save/Format), theme-aware
9-category highlighter + unreachable dimming, live diagnostics via `RUIGuitkx.compile` on a
0.3 s debounce (gutter + line tint + Problems panel + click-to-jump), context-aware completion
(tagName/markup/attrName/directive; **live ClassDB**), hover provider (see E2 — currently can't
fire), lazy workspace index, 6 settings, 39-check headless suite (not in CI).

**Native advantages to preserve:**
- Live `ClassDB` (no static dump) for props/signals/events.
- The **real compiler on the live buffer**: on eleven codes (0018, 0019, 0026, 0103, 0111,
  0120/0121, 2102, 2210, 2504, 2505) the Godot editor is *ahead* of VS Code, which only sees
  them post-save via sidecar (they're not in `VOCABULARY.live`).
- Rules-of-hooks (0013–0016, `guitkx.gd:473-512`) and did-you-mean texts (0105
  "did you mean <X>?", `guitkx.gd:1686-1708`; decl keyword, `:233`) come free via `compile()`.
- Theme-integrated colors; quick-open lists `.guitkx` and routes correctly into our editor
  (loader classifies it a Resource — hidden but functional entry point).

---

## 2. The gap catalog

### 2A. Feature parity (G-table, passes 1–3)

Legend: ✅ have · 🟡 partial · ❌ missing. Mechanisms per `GODOT_EDITOR_EXTENSION_PLAN.md` §6.

| # | Feature (VS Code ref) | Addon today | Fix / mechanism | MS |
|---|---|---|---|---|
| G1 | Goto-def: component tag → declaring `.guitkx` | ❌ (index stores `offset` expressly for this, unconsumed; hover text falsely advertises Ctrl-click) | `symbol_lookup_on_click`+`symbol_validate`→`symbol_lookup`→open+caret | **M1** |
| G2 | Find references across project | ❌ | port `refs.ts` boundary-aware `scanTagRefs`; References tab | M2 |
| G3 | Rename: component atomic (usages+decl+`@class_name`), collision-refusing | ❌ | port `server.ts:1332-1368`; apply to buffer + disk | M2 |
| G4 | Signature help: `on_<signal>={ func(` param tracking | ❌ | port `signatureHelpAt`; hand-drawn popup on `(`/`,` | M2 |
| G5 | Completion: attrValue (bool/enum values) | ❌ (classified, returns `[]`) | serve it | M2 |
| G6 | Completion: 50 style-dict keys in `style={ {…} }` | ❌ (keys verified NOT in bundled schema) | port `inStyleDict` + add keys to `data/guitkx-schema.json` | M2 |
| G7 | Completion: `Color.`/`Vector2.` builtin members | ❌ | native ClassDB/CoreConstants (beats TS static table) | M2 |
| G8 | Completion: hook names in setup lines | ❌ | vocabulary-driven names + snippets | M2 |
| G9 | Hooks hover cards (23 curated signatures) | ❌ | port `HOOK_HOVER` table into addon data | M2 |
| G10 | Rich hover (markdown/BBCode) | 🟡 markdown stripped to plain tooltip — and see **E2**: hover doesn't fire at all today | `_make_custom_tooltip` + RichTextLabel | M2 (E2 in M1) |
| G11 | Embedded `{expr}` sub-highlighting | 🟡 one flat span | recurse tokenizer inside `{…}` | M2 |
| G12 | Document outline | ❌ | side Tree panel; click-to-jump | M2 |
| G13 | Cross-file unknown-component 0105 (+did-you-mean) in-editor | ❌ (`compile(text, basename)` gets no known/paths) | pass `Codegen.project_bindings()` — **cached until `filesystem_changed`, NOT per tick** (see P2) | **M1** |
| G14 | Project-wide Problems (all files) | ❌ | aggregate sidecars; second panel tab | M2 |
| G15 | Index freshness on external create/rename/delete | ❌ (`rescan()` exists, never called) | `filesystem_changed` → debounced rescan | **M1** |
| G16 | Multi-file editing (open-files list) | ❌ single buffer | script-editor-style left list, per-file state | M2 |
| G17 | Session state (reopen last file, caret) | ❌ | `EditorPlugin.get_state/set_state` + window layout | M2 |
| G18 | "New .guitkx" action + template | ❌ | toolbar + save dialog + skeleton | M2 |
| G19 | Gutter-click detail popup | 🟡 `push_warning` to Output | PopupPanel at line | M2 |
| G20 | Snippet-style directive completion | 🟡 plain inserts | insert body + caret-in-parens (no tabstops in CodeEdit — accepted) | M2 |
| G21 | Embedded-GDScript intelligence (completion/hover/diags/signature/inlay/actions/semantic) | ❌ deferred | **gdext binding** — analyzer plan Phases 2–5; feature-detect, degrade | M3 |
| G22 | Plain-`.gd` intelligence | out of scope (Godot owns `.gd`) | — | — |
| G23 | Format range | non-goal (whole-doc + on-save) | — | — |
| G24 | Find / Replace | ❌ no search UI at all (`TextEdit.search()` is programmatic-only) | find bar: Ctrl+F, F3/⇧F3, count (**M1**); replace (M2) | **M1**/M2 |
| G25 | External-modification guard | ❌ no mtime tracking → silent clobber | mtime at load; compare on save+focus; reload/keep prompt | **M1** |
| G26 | `guitkx.config.json` formatter overrides | ❌ nothing GDScript-side reads it; editor passes `{}` to `format()` | port walk-up loader (~30 lines) into Format + on-save | M2 |
| G27 | Hook goto-def → `core/hooks.gd` | ❌ | name-scan jump (VS Code chains virtual-doc stubs) | M2 |
| G28 | Both event spellings in completion (`onClick` + `on_<signal>`) | 🟡 `godot_signals()` implemented, never wired | call it in attrName completion | M2 |
| G29 | Host-vs-component tag color distinction | 🟡 one flat tag color | highlighter consults schema+workspace | M2 |
| G30 | Tag-aware Enter indentation | 🟡 (see also E5 — even generic auto-indent is off) | Enter interception between tag pairs | M2 |
| G31 | **Ctrl+S saves the file** | ❌ zero input handling — Ctrl+S fires Godot's **Save Scene**; buffer stays unsaved | `shortcut_input()` → Save path | **M1** |
| G32 | Dirty tracking + discard guards | ❌ none; switching files silently discards edits | dirty flag + `*` label + confirm — implemented via **L4's proper hooks** | **M1** |
| G33 | Undo survives Format | ❌ `_set_text_preserving_caret` assigns `.text` (`:201`) → undo history wiped on every format-on-save | one `begin/end_complex_operation` edit | **M1** |
| G34 | Problems rows show diagnostic code | 🟡 marker+message+line only | prepend `[GUITKX####]` + reference-URL tooltip | M2 |

### 2B. Editor-substrate defects (E-table, pass 4 — CodeEdit audit)

What `guitkx_code_edit.gd` sets today: indent tabs/4, `#` + quote delimiters, auto-brace on,
highlighter, diagnostics gutter, completion + prefixes, `symbol_hovered` connect (`:21-54`).
Everything below is **unset/absent** (each verified):

| # | Defect | Consequence | Fix | MS |
|---|---|---|---|---|
| E1 | `gutters_draw_line_numbers` off | **no line numbers at all**; Problems jumps land unanchored | trivial property | **M1** |
| E2 | `symbol_tooltip_on_hover` never set | **hover is dead code** — `symbol_hovered` can never fire; 0.3.0's advertised hover cannot trigger | trivial property (4.4+ guarded) | **M1** |
| E3 | editor types tabs/4; formatter emits spaces/2; view passes no opts | **indentation fights itself** — every format-on-save produces mixed indent + visual jumps; the `:20` rationale comment is factually wrong | `indent_use_spaces=true`, `indent_size=2` | **M1** |
| E4 | no `<>` auto-close pair | typing `<` doesn't close in a markup language | `add_auto_brace_completion_pair("<",">")` | **M1** |
| E5 | `indent_automatic` off | Enter drops toward column 0 — every line re-indented by hand | trivial property + prefixes | **M1** |
| E6 | `highlight_current_line` off | no active-line band | trivial | **M1** |
| E7 | `highlight_all_occurrences` off | selection doesn't reveal other uses | trivial | **M1** |
| E8 | `auto_brace_completion_highlight_matching_brace` off | no matching-bracket highlight | trivial | **M1** |
| E9 | `line_folding` + fold gutter off | can't collapse nested markup/setup | trivial (indent folding works out of the box) | **M1** |
| E10 | `minimap_draw` off | no overview map (script editor has one) | trivial | **M1** |
| E11 | font zoom absent (Ctrl+wheel/±) | can't zoom text (it's a `CodeTextEditor` feature, not CodeEdit) | small `_gui_input` + font-size override | M2 |
| E12 | toggle-comment shortcut absent (Ctrl+/) | no one-key comment toggle | small `_gui_input` using the `#` delimiter | M2 |
| E13 | go-to-line UI absent | programmatic `goto_line()` exists; no user entry | small dialog + shortcut | M2 |
| E14 | line-verbs suite absent (move/duplicate/delete line, bookmarks) | standard editing verbs missing | medium (several small handlers) | M2 |
| E15 | word wrap off, no toggle | long attr lines scroll horizontally only | small + toolbar toggle | M2 |
| E16 | view toggles unset: `draw_tabs/spaces`, `scroll_smooth`, `scroll_past_end_of_file`, `caret_blink`, `line_length_guidelines` | whitespace invisible (worsens E3), static caret, no rulers | trivial batch | **M1** (caret/scroll) + M2 |
| E17 | drives off `text_changed`, full decoration rebuild | no incremental remap (`lines_edited_from` unused) — pairs with P1/P3 | small–medium refactor | M2 |
| E18 | **Find-in-Files can't search `.guitkx`** — not a script ext, not in `textfile_extensions` (verified: only prose mentions repo-wide); Search-in-Files builds filters from those pools | **no project-wide text search over components exists in-editor** | add `"guitkx"` to `docks/filesystem/textfile_extensions` on `_enter_tree` (per-user editor setting — document; Resource route still wins double-click, so routing is unaffected) | **M1** |

Verified fine (defaults already on): multi-caret, drag-drop text, middle-click paste, context
menu, quote auto-close.

### 2C. Lifecycle & data-safety defects (L-table, pass 4 — lifecycle audit)

Root cause shared by L1/L2/L4: the editor never learns about filesystem lifecycle events and
never advertises unsaved state (no `files_moved`/`file_removed` subscription, no
`_get_unsaved_status`/`_save_external_data`/`_apply_changes`, all grep-verified absent).

| # | Defect | Consequence | Fix | MS |
|---|---|---|---|---|
| L1 | Open file renamed/moved in dock → `_current_path` stale → Save **recreates the old filename** | edits silently diverge into a zombie file; content-based class identity → GUITKX2106 duplicate; the swept old `.gd` **resurrects** on the zombie's recompile | `FileSystemDock.files_moved` → `retarget_path()` (~15 lines) | **M1** |
| L2 | Open file deleted in dock → Save resurrects it; folder deleted → write fails, buffer stuck; reopening a cached deleted resource primes another resurrection | deletes silently undone / silent no-op save | `file_removed` → detach buffer, require Save-As (~10 lines, shares L1 wiring) | **M1** |
| L3 | Save failure = `push_error` only | user believes they saved (perms/read-only/locked/deleted dir) | AcceptDialog / label error state (~5 lines) | **M1** |
| L4 | No `_get_unsaved_status`/`_save_external_data` | Godot **quit** and **Save All** neither warn nor flush a dirty buffer | implement both off the G32 dirty flag (~15 lines) — the *correct* Godot-native shape for G32 | **M1** |
| L5 | Watcher error dock entries navigate to `reactive_ui/plugin.gd` (push_error stack), not the `.guitkx`; success prints ARE linkified, errors aren't | misleading navigation asymmetry | mirror errors into Problems panel for the open file; `print_rich` raw path | M2 |
| L6 | `_self_edit` re-entrancy guard declared, read, **never armed** | latent buffer-clobber trap for future programmatic `_edit` | arm around Save→`scan()` or delete (~3 lines) | **M1** |
| L7 | `GuitkxResource.source` not exported | Inspector shows empty resource; exotic `ResourceSaver` paths drop text | `@export_storage var source` (1 line) | **M1** |
| L8 | Save uses full `scan()` (watcher itself uses targeted `update_file`) | heavier; momentarily gates watcher triggers via `is_scanning()` | `update_file(_current_path)` (1 line) | **M1** |
| L9 | Watcher `_last_diags` never cleared for renamed/deleted paths | rare first-error suppression on a recreated same-path file | erase in orphan-removal loop (2 lines, watcher-side) | M2 |
| L10 | Observations (by design, document): plugin-disable makes `.guitkx` un-openable in-editor (loader unregistered, UX cliff — note in README/listing); quick-open works correctly (re-reads disk) | — | docs only | M1 docs |

### 2D. Diagnostic-source gaps (D-table, pass 4 — catalog audit)

Definitive catalog result: of every GUITKX code, exactly **two are sweep-only** and can NEVER
appear in the editor from `compile()` — **GUITKX2106** (duplicate class binding; needs the
project-wide class map, `guitkx_codegen.gd:489`) and **GUITKX2107** (dangling component refs;
needs sidecar refs state, `:529`). Everything else is compile-time and already live in-editor.

| # | Finding | Fix | MS |
|---|---|---|---|
| D1 | 2106 invisible in-editor (the copy-paste flow shows nothing in the code view) | rides D3 | M2 |
| D2 | 2107 invisible in-editor (dangling `<Foo/>` never squiggles) | rides D3 | M2 |
| D3 | **Sidecar overlay**: editor writes sidecars (via watcher) but never READS them | after `compile()`, read own `.diags.json`; `src_hash` match → merge (dedupe by code+line); mismatch → suppress or one file-level info row (mirror `mergeCompilerSidecar`); ~40-60 LOC | M2 (wave 1) |
| D4 | Pathless buffer compiles with literal basename `"Component"` → spurious 0103 on scratch buffers | derive from declared name / skip 0103 when pathless (~5 LOC) | **M1** |
| D5 | Renderer has no HINT tier: 0107 renders as warning + double-decorates dimmed lines | add hint branch; drop 0107 row where dim covers (~10 LOC) | M2 |
| D6 | `_ref_accum` static: **verified SAFE today** (no `await` anywhere in the compile path; timers run sequentially on the main thread) — but the safety is an unstated invariant | fix-forward: make it per-call/threaded context (~10-20 LOC) | M2 |

### 2E. Performance (P-table, pass 4 — headless benchmark, Godot 4.7)

Measured: compile 4 KB = **33.6 ms**; compile 90 KB = **189 ms**; `project_bindings()` over
105 files = **35 ms**.

| # | Finding | Fix | MS |
|---|---|---|---|
| P1 | Live compile runs on the **main thread** each 0.3 s debounce: a 90 KB file (well under the 200 000-char `MAX_LIVE_COMPILE` guard) freezes the editor ~190 ms per typing pause | adaptive gate: track last compile duration; when > ~80 ms, stretch the debounce / drop to compile-on-save with a status hint. Lower the hard guard | **M1** (cheap gate) |
| P2 | `project_bindings()` = 35 ms — calling per debounce tick (G13's first sketch) would double the stall | cache bindings; invalidate ONLY on `filesystem_changed` (G13 wording fixed) | **M1** (with G13) |
| P3 | Full decoration clear+rebuild per tick (with E17) | incremental remap via `lines_edited_from` | M2 |

### 2F. Quality & plumbing (F-table, pass 4 — tests/docs/release audit)

| # | Finding | Fix | MS |
|---|---|---|---|
| F1 | `guitkx_tokenizer.gd` says "headlessly unit-testable" — zero tests; TS twin is pinned | case-table test (~15 cases) | M2 |
| F2 | Golden corpora (scanner/markup/formatter-cases) are GD-consumable and pin the **compiler** — nothing pins the addon's own surfaces | addon-surface fixtures | M2 |
| F3 | Unpinned TS-pinned behaviors: `onChange` polymorphism + OptionButton candidate ORDER; `@class_name` override binding; index eviction; Windows path canonicalization | targeted asserts in the addon suite | M2 |
| F4 | `editor/` + `resources/` layers: 0 tests (several are pure/headless-testable) | `guitkx_editor_test.gd` (~80-120 lines) | M2 |
| F5 | Docs site has no native-editor page (FAQ paragraphs only) — **verify against the in-flight docs rewrite** before authoring | site page | M2/Wave 3 |
| F6 | `KnownIssuesPage.tsx:70-77` says the editor addon is "(on the roadmap)" and only on-save compilation exists — contradicts the same site's FAQ and 0.3.0 reality (page untouched by the in-flight rewrite) | rewrite one paragraph | **M1** |
| F7 | No editor asset template / docs target for the second listing | write it in listing prep (browse target: README `#ide-tooling` until F5) | **M1** |
| F8 | **No schema-drift tripwire**: `data/guitkx-schema.json` ↔ `ide-extensions/grammar/guitkx-schema.json` byte-identical today, nothing keeps them so; hostElements never checked ⊆ vocabulary `host_tags` | byte-identity test + subset test (~30-40 lines, mirrors `vocab.test.ts`) | **M1** |
| F9 | **No min-version handshake**: editor 0.4.0 + old/missing `reactive_ui` = raw unresolved-class crash | startup check: addon present + `plugin.cfg` version ≥ `MIN_REACTIVE_UI` + API probe (`RUIGuitkx.compile`, `RUIGuitkxFormatter.format`) → friendly banner (~20-30 lines; supersedes the S1/S2 sketch) | **M1** |
| F10 | (premise fix) addon CHANGELOG exists + current at 0.3.0 | — | — |
| F11 | No editor release-notes channel (root CHANGELOG + `changelog.json` have no editor leg) | `release-editor-addon` feeds the addon CHANGELOG section into the GitHub-release body | **M1** |
| F12 | The bundled schema is a **fourth vocabulary copy with no sync step** (no generator emits it) | add to the gen ritual + F8 tests | **M1** |
| F13 | Confirmations: `editor-v*` tag collides with nothing; `assetlib-update` can't fire on it; export-ignore means the editor zip MUST be direct-`zip` (never git-archive) — and the **classic AL provider-zip mechanism cannot ship the editor addon at all** | → the editor listing is **new-store only** (decision 4 resolved by fact) | — |

---

## 3. Milestones

### M1 — Store-submittable, ships as **0.4.0** (target: ~5–7 focused days)
The bar: **truthful, safe, packaged**. Grouped into workstreams; each lands with tests where
headless-testable, one commit per workstream.

1. **W1 Substrate flip-ons** (one commit, ~15 properties): E1 line numbers, **E2 hover comes
   alive**, E3 spaces/2 (ends the indent fight), E4 `<>` pair, E5 auto-indent, E6/E7/E8
   highlights, E9 folding + gutter, E10 minimap, caret blink + scroll-past-end (E16 subset).
   Defaults mirror Godot's script editor.
2. **W2 Data safety**: G31 Ctrl+S; G32 dirty flag + `*` + confirms, implemented via **L4**
   `_get_unsaved_status`/`_save_external_data`; G25 mtime guard; **L1/L2** `files_moved`/
   `file_removed` retarget/detach; L3 save-failure dialog; G33 undo-preserving apply; L6 arm
   `_self_edit`; L7 `@export_storage`; L8 `update_file`.
3. **W3 Intelligence wiring**: G1 goto-def; G13 known-components with **P2 caching**; G15 index
   freshness; D4 pathless-basename fix; P1 adaptive live-compile gate.
4. **W4 Search**: G24 find bar (basic); E18 Find-in-Files registration (+README note that it's
   a per-user editor setting).
5. **W5 Dependency handshake**: S1/S2 graceful load + **F9** version/API assert with friendly
   banner.
6. **W6 CI + drift tripwires**: S3 suite into both workflows; **F8/F12** schema byte-identity +
   vocabulary-subset tests + schema copy into the gen ritual; new checks for W2/W3 logic.
7. **W7 Packaging + listing**: S4 `release-editor-addon` (direct zip + LICENSE + **F11**
   release-notes from addon CHANGELOG; tag `editor-v0.4.0` — verified collision-free); fix main
   `release-addon` zip to include LICENSE; S5 thumbnail/field sheet + **F7** template; S7 README
   refresh + **F6** KnownIssues paragraph + L10 disable-cliff note; min Godot 4.7 on the
   listing; **new-store only** (F13). Submit.

### M2 — Markup-tier parity (~3 weeks, 2–4 releases, 0.5.x)
1. **D3 sidecar overlay** (closes D1 2106 + D2 2107 — the field-tested bug classes) + G10 rich
   hover + G9 hooks cards + G26 formatter config.
2. Completion: G5 attrValue, G6 style keys (+schema), G7 builtins, G8 hooks, G28 `on_<signal>`;
   E12 comment toggle; E13 go-to-line.
3. G2 references + G3 rename + G27 hook goto-def; References tab.
4. G12 outline + G16 multi-file + G17 session state; E11 zoom; E15 word wrap.
5. G14 project Problems + G34 codes-in-rows + G19 gutter popup + L5 watcher-error mirror + D5
   hint tier + G24 replace-all.
6. G4 signature help.
7. Polish + hardening: G11 embedded sub-highlight, G29 tag colors, G30 Enter indent, G18
   new-file, G20 snippet caret, E14 line verbs, E16 rest, E17+P3 incremental decorations, D6
   `_ref_accum` per-call, L9 `_last_diags`.
8. **Test-parity wave**: F1 tokenizer corpus, F2/F3 addon-surface fixtures + event/workspace
   pins, F4 editor-layer tests. F5 docs-site page (coordinate with the in-flight docs rewrite).

**Parity discipline** (all waves): extend the shared golden corpus so context/completion/hover/
refs outputs are asserted in BOTH implementations; drift fails one suite or the other.

### M3 — Embedded depth (unchanged; ~4–6 weeks, separate track)
`GODOT_ANALYZER_INTEGRATION_PLAN.md` Phases 2–5 — gdext crate → per-OS CI → virtualDoc/
sourceMap/LineIndex ports → wire `{expr}`/setup intelligence, feature-detected, markup-only
degradation. Closes G21; reaches the §9 parity ceiling (everything except Script-type/debugger).

---

## 4. Non-goals (explicit)
workspaceSymbol / folding provider / on-type formatting / pull diagnostics / range semantic
tokens (absent in VS Code too) · plain-`.gd` intelligence (G22) · format-range (G23) ·
`ScriptLanguageExtension` (rejected; extension plan §2.2) · tabstop snippets (CodeEdit has none).

## 5. Risks
- **Two markup implementations drift** — the standing risk; golden corpus + F8 tripwires are
  the mitigation, M1/M2 make them CI-enforced.
- **Rename/disk writes race the watcher sweep** — writes first, one targeted `update_file`,
  let the sweep recompile (same discipline as Save).
- **`_ref_accum` invariant** — safe only while the compile path stays `await`-free (verified
  today); D6 removes the dependency.
- **Per-user editor settings** (E18) — touching `textfile_extensions` affects the whole editor
  install; must be documented and idempotent.
- **Store review of a dependent addon** — the listing must be unmissable about requiring
  Reactive UI (F9 makes the failure friendly).
- Live-editor-only checks remain (tooltip rendering, completion popup feel, reload prompts) —
  M1 acceptance is a manual pass through: open → type → complete → hover → Ctrl+F → Ctrl+S →
  rename file → delete file → quit-with-dirty; plus in-editor save → watcher regen → HMR push.

## 6. Decisions for the user
1. **M1 scope OK?** (7 workstreams above, ships 0.4.0, ~5–7 days, then submit.)
2. **Second listing name** — proposal: **"Reactive UI Editor (.guitkx tooling)"**, publisher
   yaniv-kalfa, slug `reactive-ui-editor`.
3. **M2 ordering** — value-ranked; reorder freely.
4. ~~AL second listing?~~ **Resolved by fact (F13):** the classic AL's provider-zip mechanism
   cannot ship this addon (export-ignore + no release-asset support) → **new-store only**.
