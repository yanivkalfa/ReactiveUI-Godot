# Reactive UI Editor

In-editor authoring for `.guitkx` files, right inside the Godot editor: a **main-screen editor** with
syntax highlighting, live compiler diagnostics, completion, hover, go-to-definition, find, and the
data-safety guardrails you'd expect from a real editor (dirty tracking, external-change detection,
rename/delete follow-up, undo-surviving format).

This is the sibling of the **Reactive UI** runtime addon (`addons/reactive_ui`) and **depends on it** —
it reuses that addon's `.guitkx` compiler (`RUIGuitkx`), formatter (`RUIGuitkxFormatter`) and lexer
primitives (`RUIGuitkxLexer`). Install/enable **Reactive UI first** (0.8.1 or newer — the plugin
checks and tells you politely instead of erroring if it's missing or too old).

## Install

1. Copy both `addons/reactive_ui/` and `addons/reactive_ui_editor/` into your project's `res://addons/`.
2. Enable both under **Project → Project Settings → Plugins** (Reactive UI, then Reactive UI Editor).
   In this repository both are already enabled in `project.godot`.

Requires **Godot 4.4+**.

## What it does

- A **ReactiveUITK** tab appears in the main-screen bar (next to 2D / 3D / Script / AssetLib).
- **Double-click a `.guitkx`** in the FileSystem dock (or use the **Open** button) to edit it here.
- **Syntax highlighting** for tags, attributes, `{expr}` regions, strings, `#` comments, keywords and
  `@directives`, themed to match your editor's GDScript colors — plus line numbers, code folding,
  minimap, current-line/occurrence/bracket highlights, and a ruler at the formatter's print width.
- **Live diagnostics**: on each (debounced) edit the file is compiled with `RUIGuitkx.compile` — with
  the full project's component universe, so an unknown `<Component />` errors (with a did-you-mean)
  exactly like the build. Errors/warnings show as **gutter icons + line tints** and in a bottom
  **Problems** panel (click a row to jump). Diagnostic lines are **exact** (character offsets from
  the compiler). Big files automatically stretch the compile debounce instead of stuttering.
- **Completion** on `<` (host tags + your own project's components, from a project-wide index that
  follows external file changes), inside an attribute list (structural attributes, React-style event
  names resolved to the real Godot signal via live `ClassDB`, plain properties), and after `@`
  (directives).
- **Hover** for tags, attributes, directives, and your own components (Godot 4.4+ tooltip).
- **Go-to-definition**: Ctrl+click a component tag to jump to its declaration (cross-file).
- **Find**: Ctrl+F opens a find bar (all-match highlight, match count, F3/Shift+F3 with wrap, case
  toggle). `.guitkx` is deliberately NOT registered into Godot's Search in Files — that route lets
  the built-in Script editor adopt (and endlessly session-restore) `.guitkx` files; an addon-native
  project-wide search is planned instead.
- **Ctrl+S saves the `.guitkx`** while the tab is visible; Godot's own Save All / quit-confirmation /
  Play flows also flush the buffer (unsaved changes join the quit dialog; pressing Play saves first
  so the game runs what's on screen).
- **Your work is protected**: switching files with unsaved edits prompts; if the file changed on disk
  a clean buffer auto-reloads on focus while a dirty one gets an explicit Overwrite/Reload choice at
  Save; renaming or moving the open file in the FileSystem dock retargets the buffer (Save never
  resurrects the old filename); deleting it marks the buffer detached and Save asks before
  recreating; failed writes raise a dialog, not just a console line.
- **Save** writes only the `.guitkx`; the Reactive UI addon's own watcher regenerates the sibling `.gd`
  (and, if a game is running under F5, hot-reloads it in place — see Fast Refresh in the root README).
- **Format** (button or format-on-save) runs `RUIGuitkxFormatter` — never corrupts (verbatim on parse
  error), applies as **one undoable edit** (Ctrl+Z survives), honours the formatter's spaces-2 style,
  which the editor also types.

## Settings (Project → Project Settings → `reactive_ui_editor/`)

All default **on**; toggle any off. Highlighting, completion, hover, diagnostics and format-on-save
apply **live**. `open_guitkx_in_editor` is structural (it registers a resource loader that reroutes the
double-click) and applies after you **re-enable the addon**.

| Setting | Default | Effect |
|---|---|---|
| `highlighting_enabled` | on | `.guitkx` syntax highlighting |
| `diagnostics_enabled` | on | live compile + gutter/Problems diagnostics |
| `completion_enabled` | on | tag / attribute / directive completion |
| `hover_enabled` | on | tag / attribute / directive / component hover |
| `open_guitkx_in_editor` | on | double-click a `.guitkx` opens it here (off: it opens in the Inspector) |
| `format_on_save` | on | run the formatter when saving |

Note: `.guitkx` files stay visible in the FileSystem dock even while this addon is disabled — the
format's resource loader is a global class the engine registers on its own (that is also what keeps
it alive across Godot's script-reload cycles).

## Known limits (vs. the VS Code / VS 2022 extensions)

- `{expr}` regions are highlighted as one span (embedded GDScript isn't sub-highlighted yet), and
  embedded-GDScript intelligence (completion/hover/diagnostics *inside* `{expr}`/setup code) isn't
  analyzed natively — that layer is VS Code / VS 2022-only for now, via `ide-extensions/`'s
  `@gdscript-analyzer/core`.
- No find-references, rename, signature help, or document outline yet; find has no replace yet — see
  `plans/NATIVE_EDITOR_PARITY_PLAN.md` (milestone M2) for the remaining gap and order of arrival.
- Single file at a time (no tabs yet — also M2).
