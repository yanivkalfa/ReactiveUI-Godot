# Changelog

All notable changes to the **Reactive UI Editor** Godot addon are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/); this addon versions independently
of the `reactive_ui` runtime library and the VS Code / Visual Studio extensions.

## [0.4.0] — 2026-07-05

The store-readiness milestone (parity plan M1) plus a hard field-testing round: the editor stops
losing work, stops lying, gains the daily-driver features a code editor is judged by in its first
five minutes — and survived a two-day torture campaign of save-spam, rename storms, deletes, and
git restores.

### Added
- **Go-to-definition** — Ctrl+click a component tag jumps to its declaration, cross-file (the
  hover text has promised this since 0.3.0; now it's true).
- **Find bar** — Ctrl+F (seeded from the selection), all-match highlight, match counter,
  F3/Shift+F3 stepping with wrap in both directions, case toggle, Esc to close.
- **Rich hover** — cards render as formatted text at show time (the old native-tooltip path
  stacked two delays and often needed a second hover pass), and hovering a **diagnosed line puts
  the error message — including its did-you-mean — right in the card**. Clicking a gutter icon
  opens the full diagnostic in a popup at the mouse instead of a line lost in Output.
- **Hook signature cards** — hovering `useState`, `useEffect`, `provideContext`, … in setup code
  shows the real signature (all 23 built-in hooks; previously the editor said nothing there).
- **Scan-tier unknown-component errors** — the compiler's own unknown-tag check lives in its emit
  phase, so the classic typo (open tag changed, close tag now mismatched = parse error) masked the
  one error that explained it. A parse-independent scan now flags unknown tags with a did-you-mean
  even while the file doesn't parse.
- **Ctrl+S saves the file** while the editor tab is visible (it used to fall through to Godot's
  Save Scene, leaving the buffer silently unsaved). Godot's **Save All**, **quit confirmation**,
  and **Play** now also see the buffer: unsaved `.guitkx` changes join the quit dialog, and
  pressing Play flushes first so the game runs what's on screen.
- **Dirty tracking + guards** — `*` in the file label; switching files with unsaved edits prompts
  Save/Discard/Cancel; double-clicking the file already being edited no longer clobbers the buffer.
- **External-change safety** — a clean buffer auto-reloads when the file changes on disk (window
  focus); a dirty buffer gets an explicit Overwrite/Reload choice at Save. Renaming/moving the open
  file in the dock retargets the buffer (Save no longer resurrects the old filename); deleting it
  marks the buffer detached and Save asks before recreating. Failed writes raise a dialog.
- **Cross-file diagnostics** — the live compile now receives the project's component universe, so
  unknown `<Component />` tags error with a did-you-mean exactly like the watcher build; the index
  and bindings follow external file changes automatically.
- **Editor substrate** — line numbers, code folding + fold gutter, minimap, current-line /
  occurrence / matching-bracket highlights, `<` auto-closes to `>`, automatic indent on Enter,
  caret blink, smooth scroll, scroll-past-end, print-width ruler.

### Fixed
- **The one that explained everything: the `.guitkx` resource loader now survives script reloads.**
  Godot removes all custom format loaders on every script-reload cycle (which the Reactive UI
  watcher triggers on each save, by regenerating a `.gd`) and re-adds only global-class ones — the
  old manually-registered loader silently died minutes into every session. Everything downstream
  followed: failed loads got cached (permanent red ✕ in the dock, "no file opens anymore"), and
  routing fell through to the built-in Script editor, which session-restored `.guitkx` ghosts as
  boot errors forever. The loader is now a global class the engine owns and re-adds itself.
- **Dock renames clean up after themselves** — renaming a `.guitkx` left its generated `.gd`
  under the old name until the watcher's next sweep, long enough for rapid renames to stack
  duplicate `class_name` declarations. The old outputs are now removed synchronously in the
  rename event (hand-written `.gd` files are untouchable, as in the watcher's own sweep).
- **A deleted-then-restored file heals** — `git restore` (or un-deleting) used to leave the buffer
  stuck on "(deleted on disk)"; a clean buffer now reloads automatically the moment the file is
  back, and detach no longer falsely marks the buffer as edited.
- **A momentarily-unreadable file can no longer poison the session** — the loader never returns a
  load error (failures get cached as a permanent red ✕); reloads update the cached resource in
  place so every holder keeps one coherent object.
- **`.guitkx` is deliberately NOT in Godot's Search-in-Files extensions** — that registration let
  the built-in Script editor adopt the files and endlessly session-restore them; an addon-native
  project search replaces it in an upcoming release.
- **Hover never fired** — `symbol_tooltip_on_hover` was never enabled, so the 0.3.0 hover feature
  was unreachable. It works now.
- **An untouched empty tab no longer greets you with a red "missing declaration" icon.**
- **Undo survived nothing** — Format (and format-on-save, which is default-on) replaced the buffer
  via `text =`, wiping the undo history on every save. Formatting is now a single undoable edit
  with the caret preserved.
- **The editor typed tabs/4 while the formatter wrote spaces/2**, mixing indentation on every
  format cycle. The editor now types exactly what the formatter emits (spaces, 2), and tab glyphs
  are drawn so any legacy mix is visible.
- **Unsaved scratch buffers self-reported a name mismatch** (GUITKX0103) against the placeholder
  basename; a pathless buffer now derives its identity from its own declaration.
- Big files no longer freeze the editor on every typing pause — the compile debounce stretches
  with measured compile time (0.3s floor, 2s cap), and the live-compile guard tightened.

### Dependencies
- Requires **Reactive UI 0.8.1+**; the plugin now checks on enable and shows a friendly dialog
  (instead of a raw script error) when the runtime addon is missing, incomplete, or too old.

## [0.3.0] — 2026-07-04

- **Native markup intelligence — completion and hover, right inside the Godot editor, no VS Code
  required.** Five new pure-logic modules (`lsp/guitkx_schema.gd`, `guitkx_context.gd`,
  `guitkx_completion.gd`, `guitkx_hover.gd`, `guitkx_workspace.gd`), headlessly tested (39 checks,
  `tests/guitkx_lsp_test.gd`), wired into `GuitkxCodeEdit`:
  - **Completion** on `<` (host tags + your own project's components), inside an attribute list
    (structural attributes, React-style event names resolved to the real Godot signal via
    `ClassDB`, plain properties), and after `@` (directives) — driven by
    `data/guitkx-schema.json` plus **live `ClassDB`** lookups, so it always matches the running
    engine version rather than a bundled snapshot.
  - **Hover** for tags, attributes, and directives, plus your own components (resolved against a
    project-wide index that's re-scanned on save) — shown as a native `CodeEdit` tooltip
    (Godot 4.4+).
  - Both are independently toggleable (`completion_enabled` / `hover_enabled` under
    **Project Settings → `reactive_ui_editor/`**), default **on**, apply live.
- Embedded-GDScript intelligence inside `{expr}`/setup code is still **not** covered — that layer
  stays VS Code / VS 2022-only (`ide-extensions/`, via `@gdscript-analyzer/core`). See
  `plans/GODOT_ANALYZER_INTEGRATION_PLAN.md` and `plans/NATIVE_EDITOR_PARITY_PLAN.md` for the
  remaining gap (go-to-definition, find-references, rename, signature help, semantic tokens).

## [0.2.0] — 2026-07-01

- **Unreachable code is dimmed.** Code after a component's markup `return (...)` is faded in the editor
  (parity with the compiler's `GUITKX0114` and Unity's `UITKX0107`).
- **Richer live diagnostics for free.** The editor renders `RUIGuitkx.compile()` diagnostics, so it now
  surfaces the new compiler validations live: single-root `@for`/`@while` bodies (`GUITKX0108`), duplicate
  expression keys (`GUITKX0104`), `@class_name` validation, invalid tag names, misspelled-keyword hints,
  and unreachable-code warnings.
- **Fix:** stop re-adding `CodeEdit`'s built-in `{ } ( ) [ ] " "` auto-brace pairs — they threw four
  "auto brace completion open key already exists" errors on editor load.

## [0.1.0] — 2026-07-01

- Initial release: a main-screen `.guitkx` editor (`@tool` `EditorPlugin`) with lexer-driven syntax
  highlighting, live compiler diagnostics (gutter icons + a bottom **Problems** panel), Open / Save /
  Format, double-click routing via a toggle-able `ResourceFormatLoader`, and default-on settings under
  `reactive_ui_editor/`. Depends on the `reactive_ui` addon for the `.guitkx` compiler/formatter.
