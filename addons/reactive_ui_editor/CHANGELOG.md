# Changelog

All notable changes to the **Reactive UI Editor** Godot addon are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/); this addon versions independently
of the `reactive_ui` runtime library and the VS Code / Visual Studio extensions.

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
