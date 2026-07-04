# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A **React-style reactive UI library for Godot 4.x, written in plain GDScript** — the Godot sibling of
the C#/Unity [ReactiveUIToolKit](https://github.com/yanivkalfa/ReactiveUIToolKit). Function components
return a virtual tree; a fiber reconciler diffs each render and patches only what changed on the real
Godot `Control` tree. State lives in hooks.

The repo actually holds **four independently-versioned deliverables**, each with its own version and
release gate (see `.github/workflows/publish.yml`):

| Deliverable | Location | Language | Version source |
|---|---|---|---|
| The runtime addon | `addons/reactive_ui/` | GDScript | `plugin.cfg` |
| The in-Godot-editor `.guitkx` plugin | `addons/reactive_ui_editor/` | GDScript | `plugin.cfg` |
| VS Code + VS2022 `.guitkx` extensions | `ide-extensions/` | TypeScript / C# | `package.json` / `.vsixmanifest` |
| Docs site | `ReactiveUIGodotDocs~/` | React + Vite | `package.json` |

`ReactiveUIGodotDocs~` is named with a trailing `~` so the Godot importer skips it (it's a Node/Vite
project, not Godot content).

## Commands

### Runtime tests (headless GDScript — the primary test loop)

Godot has no compile step; "tests" are `tests/*.gd` scripts run under `--headless`, each `quit()`ing
non-zero on failure. Run them exactly like CI (`.github/workflows/test.yml`), **in this order** — the
guitkx compile and the class-cache scan must happen before the suites:

```bash
# 1. Compile every examples/**/*.guitkx to its sibling .gd (the generated .gd is git-ignored)
godot --headless --path . --script res://tests/guitkx_build.gd
# 2. Build the class-name cache so global class_names resolve headlessly
godot --headless --path . --editor --quit || true
# 3. Run a suite (this is also how you run a SINGLE test file)
godot --headless --path . --script res://tests/core_test.gd
```

The suites: `core_test.gd` (reconciler/hooks/effects/bailout/context/keyed), `style_test.gd`,
`router_match_test.gd` + `router_spine_test.gd`, `update_test.gd` (diff), `demos_test.gd` (renders
every demo — the real check that generated `.gd` render without error), `guitkx_test.gd` (compiler +
codegen). `bench*.gd` / `microbench.gd` are benchmarks, not pass/fail tests.

### IDE tooling (TypeScript language server + VS Code extension)

```bash
cd ide-extensions/lsp-server && npm ci && npm run build && node --test out/test/*.test.js && node scripts/smoke.js
cd ide-extensions/vscode     && npm ci && npm run build          # F5 in VS Code to debug
```

`@vscode/vsce` and `ovsx` are invoked via `npx` (not deps) to keep `npm install` small. The bundled
language server embeds a native napi addon (`@gdscript-analyzer/core`), so a packaged `.vsix` is
**platform-specific**. See `ide-extensions/README.md` for packaging, the VS2022 build, and publishing.

### Docs site

```bash
cd ReactiveUIGodotDocs~ && npm ci && npm run dev     # or: npm run build / npm run lint
```

## Architecture

### Runtime (`addons/reactive_ui/core/`)

The library exposes global `class_name`s — **no autoload or plugin-enable is required to use the
runtime**; the classes are available as soon as the files exist. Enabling the plugin only adds the
`.guitkx` compile-on-save integration.

- **`v.gd` (`V`) / `vnode.gd` (`RUIVNode`)** — the ~60 `V.*` factories and the immutable UI
  description. `V.fc` is the function-component factory (GDScript reserves `func`, so it's not `V.func`).
- **`hooks.gd` (`Hooks`)** — the 23 hooks. Call only at the top of a render, in a stable order.
- **`reconciler.gd` (`RUIReconciler`)** — the fiber reconciler. Synchronous (non-time-sliced) work
  loop: **render phase** (`begin_work` reconciles children + runs components descending, `complete_work`
  diffs/creates host nodes + builds the post-order effect list ascending) → **commit phase** (deletions
  → placement/update/layout effects → enforce child order → swap current↔wip → passive effects). A hook
  setter calls `request_update()`, which **coalesces to one re-render per frame**. Bailout skips
  re-running a component whose props/state/context/children are unchanged.
- **`fiber.gd` (`RUIFiber`)** — persistent tree node carrying the per-fiber `hooks` array (how hook
  state survives across renders). Fresh fibers are built each pass (no C#-style double-buffer reuse);
  cycles are severed explicitly for GC.
- **`host_config.gd` (`RUIHost`) + `style.gd`/`style_sheet.gd`** — **the only files that touch concrete
  Godot APIs.** This is the engine-boundary seam (the same one that lets React point a reconciler at
  react-dom vs react-native). `RUIHost` maps props→node properties, React-style `onXxx`→Godot signals,
  declarative `items`→item-model controls, and `draw_fn`→a register-once custom-draw trampoline.
- **Subsystems:** `router/` (React-Router-v6-style, +17 hooks on `RUIRouter`), `signal_store.gd` +
  `signal_registry.gd` (`RUISignal`/`RUISignals` cross-component state), `suspense.gd`, `media.gd`
  (`useSfx`/`useAnimate`/`V.audio`/`V.video`), `context.gd`, `diagnostics.gd`.
- **Mount surfaces:** `reactive_root.gd` (`ReactiveRoot.create(container, root_vnode)` — hold the
  returned object for the UI's lifetime; `.unmount()` runs cleanups) and `reactive_root_node.gd`.

**Known runtime constraints** (see README "Notes & limitations"): removed *plain* props don't reset to
defaults between renders (style/events/refs/draw *do* reset); error boundaries are structural (no
try/catch in GDScript, so they can't auto-catch a child render crash); `useTransition`/`useDeferredValue`
are synchronous. Preserve these behaviors — they're faithful-to-reference, not bugs.

### `.guitkx` toolchain

`.guitkx` is a JSX-like markup: **two languages in one file** — markup plus embedded GDScript (setup,
`{expr}`, `@if`/`@for`). It compiles to a sibling `.gd`.

- **Compiler (`addons/reactive_ui/guitkx/`)** — pure GDScript: `guitkx_lexer.gd` → `guitkx_markup.gd` /
  `guitkx_jsx_scan.gd` → `guitkx_codegen.gd` (`RUIGuitkxCodegen`, the entry point:
  `compile_file` / `compile_all` / `find_all`) → `guitkx_formatter.gd`.
- **In-Godot-editor plugin (`addons/reactive_ui_editor/`)** — watches the filesystem and recompiles
  each `.guitkx`→`.gd`. It recompiles on **editor focus-in** (not just `filesystem_changed`) because a
  `.guitkx`-only external edit doesn't reliably flip Godot's changed flag; an mtime staleness guard
  keeps that cheap, and diagnostics are de-duplicated (Godot's Errors dock is append-only). Also hosts
  the in-editor `.guitkx` view, tokenizer/highlighter, and a headless LSP layer (`lsp/`).
- **External IDE extensions (`ide-extensions/`)** — a shared TypeScript language server + a TextMate
  grammar, driven by both VS Code and VS2022. Markup intelligence is answered locally from the schema;
  embedded-GDScript intelligence builds a synthetic `.gd` virtual document with a length-preserving
  source map and analyzes it **in-process via `@gdscript-analyzer/core`** — no running Godot editor,
  no TCP, fully offline.

**Generated `.gd` files are git-ignored** (`examples/**/*.gd`, minus a few hand-written exceptions
listed in `.gitignore`). Always edit the `.guitkx` source, never the generated `.gd`. `.guitkx` is
**tab-indented** (the embedded GDScript and the compiler both require tabs); override the formatter via
a `guitkx.config.json` walk-up file.

### Examples

`examples/` is **not shipped** — the addon in `addons/reactive_ui/` is self-contained. `examples/app.gd`
(→ `examples/main.tscn`, the project's main scene) mounts the demo gallery. Open the project in Godot 4.x
and press Play to explore.

## Conventions

- **Faithful port.** Algorithms/behavior mirror ReactiveUIToolKit (the C#/Unity library); the code is
  GDScript. When in doubt about intended semantics, that library is the reference. GDScript divergences
  (no exceptions, fresh fibers per pass) are documented at the top of the relevant core file.
- Requires Godot **4.1+** (uses `static var`); verified on **4.7**. Standard build — no C#/.NET.
- `plans/` holds design/porting docs; `research/` holds background notes. `CHANGELOG.md` (runtime) and
  `ide-extensions/changelog.json` (the source of truth for extension changelogs) track releases.
