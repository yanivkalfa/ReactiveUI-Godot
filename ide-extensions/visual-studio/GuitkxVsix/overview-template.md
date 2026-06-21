# GUITKX — ReactiveUI for Godot

Editor support for **`.guitkx`**, the JSX-like markup of [ReactiveUI for Godot](https://github.com/yanivkalfa/ReactiveUI-Godot) — a React-style reactive UI library for Godot 4.x.

## Features

- **Syntax highlighting** for the JSX-like markup *and* the embedded GDScript, via a self-contained TextMate grammar.
- **Markup IntelliSense** — completion and hover for host-element tags, structural/common attributes, control-flow directives (`@if`/`@elif`/`@else`/`@for`/`@while`/`@match`/`@case`/`@default`), and per-element event handlers.
- **Embedded-GDScript IntelliSense** — completion and hover inside `{expr}`, setup, and control-flow conditions, forwarded to Godot's own GDScript language server so you get real `V.*` / `Hooks.*` / Godot-API completion.
- **Diagnostics** for structural problems.

## Requirements

- **Node.js** on your PATH (the bundled language server runs on Node).
- For embedded-GDScript intelligence: the **Godot editor running** with your project open and its GDScript language server enabled (Editor Settings → Network → Language Server; engine default port 6005).
