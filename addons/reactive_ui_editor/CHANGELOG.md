# Changelog

All notable changes to the **Reactive UI Editor** Godot addon are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/); this addon versions independently
of the `reactive_ui` runtime library and the VS Code / Visual Studio extensions.

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
