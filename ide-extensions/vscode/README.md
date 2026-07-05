# GUITKX — ReactiveUI for Godot tooling

Language support for **`.guitkx`**, the JSX-like markup of
[ReactiveUI for Godot](https://github.com/yanivkalfa/ReactiveUI-Godot) — plus a full,
headless GDScript language service for your plain `.gd` files. Everything runs
**in-process via [gdscript-analyzer](https://github.com/yanivkalfa/gdscript-analyzer)**:
no running Godot editor, no TCP connection, works fully offline.

## `.guitkx` markup

- **Syntax highlighting** — hand-tuned TextMate grammar; embedded GDScript inside
  `{expr}`, setup blocks, and `@if`/`@for` conditions gets real GDScript colouring.
- **Completion & hover** for tags, attributes, attribute values, directives, hooks, and
  events (React-style aliases like `onClick` plus the verbatim `on_<signal>` escape hatch).
- **Live diagnostics** — structural markup errors and dangling component references as you type.
- **Formatting** — the same formatter the in-Godot editor uses, configured by a
  Prettier-style `guitkx.config.json` walk-up (`printWidth`, `indentStyle`, `indentSize`,
  `singleAttributePerLine`, `insertSpaceBeforeSelfClose`). Format-on-save is on by default
  for `.guitkx`.

## Embedded GDScript — type-aware

The GDScript *inside* your markup is projected into a synthetic virtual document with a
length-preserving source map and analyzed by gdscript-analyzer, so `{expr}` and setup code
get **typed completion, hover, and go-to-definition** at the exact right positions. Toggle
with `guitkx.enableEmbeddedAnalysis`.

## Plain `.gd` files — full language service

With `guitkx.enableGdscriptAnalysis` (on by default) your `.gd` files get the analyzer's
whole surface, headless: **diagnostics, completion, hover, navigation, project-wide rename,
formatting, semantic highlighting, inlay hints, code actions, and document symbols**. It
runs alongside the godot-tools extension — to avoid duplicate diagnostics, disable
godot-tools' language server, or turn this setting off to keep godot-tools as your `.gd` LSP.

When [gdformat](https://github.com/Scony/godot-gdscript-toolkit) is installed,
`guitkx.useGdformat` also reflows embedded GDScript during `.guitkx` formatting — guarded:
any change beyond whitespace/quote style is rejected, so semantics never change.

## Settings

| Setting | Default | Meaning |
|---|---|---|
| `guitkx.enableEmbeddedAnalysis` | `true` | Type-aware completion/hover/go-to-definition for embedded GDScript |
| `guitkx.enableGdscriptAnalysis` | `true` | Full analyzer language service for plain `.gd` files |
| `guitkx.useGdformat` | `true` | Reflow embedded GDScript via gdformat when formatting (semantics-guarded) |

Command palette: **GUITKX: Restart Language Server**.

## How it relates to the rest of ReactiveUI for Godot

- The **runtime addon** (`reactive_ui`) compiles `.guitkx` to plain `.gd` on save and
  hot-reloads running games (Fast Refresh). This extension edits the markup; the addon owns
  compilation.
- Prefer staying inside Godot? The **Reactive UI Editor** addon is a native in-Godot
  `.guitkx` editor with the same language features (and the analyzer bundled as a
  GDExtension). Both editors share the same compiler, formatter, and diagnostic codes.

MIT — [repository](https://github.com/yanivkalfa/ReactiveUI-Godot) ·
[issues](https://github.com/yanivkalfa/ReactiveUI-Godot/issues)
