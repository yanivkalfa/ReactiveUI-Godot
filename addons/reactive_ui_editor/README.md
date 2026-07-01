# Reactive UI Editor

In-editor authoring for `.guitkx` files, right inside the Godot editor: a **main-screen editor** with
**syntax highlighting** and **live compiler diagnostics**.

This is the sibling of the **Reactive UI** runtime addon (`addons/reactive_ui`) and **depends on it** —
it reuses that addon's `.guitkx` compiler (`RUIGuitkx`), formatter (`RUIGuitkxFormatter`) and lexer
primitives (`RUIGuitkxLexer`). Install/enable **Reactive UI first**.

## Install

1. Copy both `addons/reactive_ui/` and `addons/reactive_ui_editor/` into your project's `res://addons/`.
2. Enable both under **Project → Project Settings → Plugins** (Reactive UI, then Reactive UI Editor).
   In this repository both are already enabled in `project.godot`.

Requires **Godot 4.4+**.

## What it does

- A **ReactiveUITK** tab appears in the main-screen bar (next to 2D / 3D / Script / AssetLib).
- **Double-click a `.guitkx`** in the FileSystem dock (or use the **Open** button) to edit it here.
- **Syntax highlighting** for tags, attributes, `{expr}` regions, strings, `#` comments, keywords and
  `@directives`, themed to match your editor's GDScript colors.
- **Live diagnostics**: on each (debounced) edit the file is compiled with `RUIGuitkx.compile`; errors and
  warnings show as **gutter icons + line tints** and in a bottom **Problems** panel (click a row to jump).
- **Save** writes only the `.guitkx`; the Reactive UI addon's own watcher regenerates the sibling `.gd`.
- **Format** runs `RUIGuitkxFormatter` (never corrupts — returns the source verbatim on a parse error).

## Settings (Project → Project Settings → `reactive_ui_editor/`)

All default **on**; toggle any off. Highlighting, completion, diagnostics and format-on-save apply
**live**. `open_guitkx_in_editor` is structural (it registers a resource loader that reroutes the
double-click) and applies after you **re-enable the addon**.

| Setting | Default | Effect |
|---|---|---|
| `highlighting_enabled` | on | `.guitkx` syntax highlighting |
| `diagnostics_enabled` | on | live compile + gutter/Problems diagnostics |
| `completion_enabled` | on | host-tag completion after `<` |
| `open_guitkx_in_editor` | on | double-click a `.guitkx` opens it here (else the built-in editor) |
| `format_on_save` | on | run the formatter when saving |

## Phase-1 scope / known limits

- Diagnostic **line anchoring is best-effort**: the compiler emits diagnostics without source positions,
  so the line is recovered by matching a quoted identifier in the message; file-level codes anchor to the
  top. Precise ranges await positions in the compiler.
- `{expr}` regions are highlighted as one span (embedded GDScript isn't sub-highlighted yet).
- Deep intelligence (hover, go-to-definition, refs/rename, signature help inside `{expr}`) is **not** in
  this phase — see `plans/GODOT_EDITOR_EXTENSION_PLAN.md`.
