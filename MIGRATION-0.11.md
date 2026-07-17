# Migrating to 0.11.0 — ES modules: a file IS a module

0.11.0 completes the family's transition to true ES-module semantics (the layer the 0.10.0
imports leg started): **plain, signature-classified declarations** replace the `component` /
`hook` / `module` wrapper keywords, **value exports** land, and the **full ES import surface**
(rename, namespace, default, deferred export lists) opens up. One command migrates a whole
project; the old syntax keeps compiling for this minor with a deprecation warning
(`GUITKX2320`) and is removed in a later minor.

## The one command

```bash
godot --headless --path . --script res://addons/reactive_ui/dev/migrate_0_11_0.gd
```

Idempotent and re-runnable (a second run reports `modernized 0`). Always whole-project —
reference resolution needs every declaration in its universe. Commit before running; review the
diff after.

## Classification — the signature IS the declaration

There are no wrapper keywords. What a declaration *is* is read from its signature alone:

| You write | It is | Because |
|---|---|---|
| `Name(params) -> RUIVNode { … }` | **component** | the `-> RUIVNode` return annotation (PascalCase name enforced — GUITKX2100) |
| `use_name(params) [-> T] { … }` | **hook** | the `use_` prefix |
| `name(params) [-> T] { … }` | **util** | any other callable |
| `name := expr` / `name: T = expr` / `name = expr` | **value** | the `=` after the name |

Consequences to know:

- **A component MUST annotate `-> RUIVNode`.** A PascalCase callable without it is a util and
  its `<Tag>` stops resolving (the error appears at the use site — GUITKX2307/2102). The
  codemod always adds the annotation; write it by hand in new files.
- A `use_`-prefixed callable that returns `RUIVNode` is the cross-guard error **GUITKX2321**
  ("did you mean a component?").
- `GUITKX2203` (hook naming warning) is retired: without wrappers the `use_` prefix *is* the
  classification — a helper without it is simply a util, no warning. (The code number is
  reserved forever; it still fires on deprecated `hook` wrapper decls during the window.)
- Values compile to `static var` on the generated class (GDScript cannot verify
  constant-foldability at parse time, so `const` is not an option). **Treat them as
  constants** — mutating an imported value is undefined behavior across hot-reloads.

## Before / after

```guitkx
# 0.10.x                                   # 0.11.0
export component ScoreRow(label) {         export ScoreRow(label) -> RUIVNode {
  return ( <Label text={label}/> )           return ( <Label text={label}/> )
}                                          }

export hook use_countdown(start) -> int {  export use_countdown(start) -> int {
  ...                                        ...
}                                          }

export module HudUtils {                   @class_name HudUtils
  hook fmt(x) -> String { ... }            export fmt(x) -> String { ... }
  hook use_tick() -> int { ... }           export use_tick() -> int { ... }
}
```

**Modules hoist.** A `module M { … }` becomes its members at top level (each member's export =
the module's export flag) plus `@class_name M`, so the file's binding and global identity stay
`M` — hand-written `M.member(...)` callers keep working unchanged. This is exactly what the
`@class_name` escape hatch is for (it stays, permanently).

**Importers of a module flip to `* as`.** `import { HudUtils } from "./hud_utils"` consumed as
`HudUtils.fmt(...)` becomes `import * as HudUtils from "./hud_utils"` — the codemod does this
for you.

## Value exports (new)

```guitkx
export MAX_ITEMS: int = 5
export accent := { "modulate": Color(1, 0, 0) }
theme = { "panel": "PanelDark" }        # un-exported -> file-private
```

Value (and util/hook) references are **eager** `preload` edges: a value-import cycle is still
the hard error `GUITKX2306` with the chain printed. Component references stay **lazy**
(`V.comp` path-keyed) — component cycles stay legal. Nothing changed there (G-08).

## The full import surface (supersedes 0.10.0's named-only rule)

```guitkx
import { fmt, Chip as Badge } from "./hud"    # named + rename-on-import
import * as Hud from "./hud"                  # namespace (values/utils/hooks via Hud.x; no <Hud.Tag/> yet)
import Panel from "./score_panel"             # default import
export { container, MAX_ITEMS }               # deferred export list (top-level line)
export default ScorePanel                     # at most one per file
```

- A rename binds the LOCAL name; diagnostics on the clause validate the REMOTE name (2301/2302).
- A default import resolves **at compile time** to the target's `export default` decl and
  lowers per its kind (a default component stays lazy). No default in the target → `GUITKX2326`
  (with the named-import fix suggested).
- `export { a, b }` / `export default X` may name only in-file top-level decls (`GUITKX2323`);
  double-exporting is `GUITKX2324`; a second `export default` is `GUITKX2327`; an import alias
  colliding with a declaration or another import is `GUITKX2325`.
- Re-exports (`export { a } from "./x"`) remain deferred — not in 0.11.0.

## File = module: renames are semantic

A file's exports are its entire public surface and its **identity is its path**. Renaming a
file changes module identity (importers' specifiers must update — the editor addon cleans up
the old outputs and the next sweep flags stale specifiers with `GUITKX2300`) and the
hot-reload identity of its private members (their state resets on the next reload). Accepted,
documented semantics.

## Deprecation timeline

| Release | Wrapper keywords (`component`/`hook`/`module`) |
|---|---|
| 0.10.x | the only syntax |
| **0.11.0** | still compile, byte-identical output, one `GUITKX2320` warning per decl |
| a later minor (owner-announced) | removed — parse error |

Run the codemod once and none of this touches you.
