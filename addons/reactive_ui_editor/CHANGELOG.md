# Changelog

All notable changes to the **Reactive UI Editor** Godot addon are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/); this addon versions independently
of the `reactive_ui` runtime library and the VS Code / Visual Studio extensions.

## [0.4.0] — 2026-07-04

The store-readiness milestone (parity plan M1): the editor stops losing work, stops lying, and
gains the daily-driver features a code editor is judged by in its first five minutes.

### Added
- **Go-to-definition** — Ctrl+click a component tag jumps to its declaration, cross-file (the
  hover text has promised this since 0.3.0; now it's true).
- **Find bar** — Ctrl+F (seeded from the selection), all-match highlight, match counter,
  F3/Shift+F3 stepping with wrap in both directions, case toggle, Esc to close. `.guitkx` is also
  registered into Godot's project-wide **Search in Files**, which previously could not see the
  format at all (per-user editor setting, set once).
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
- **Hover never fired** — `symbol_tooltip_on_hover` was never enabled, so the 0.3.0 hover feature
  was unreachable. It works now.
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
