# Reactive UI — Godot (GDScript)

A **React-style reactive UI library for Godot 4.x**, written in GDScript. It's the
Godot sibling of [ReactiveUIToolKit](https://github.com/yanivkalfa/ReactiveUIToolKit)
(the C# / Unity UI Toolkit library) — same mental model, ported to Godot's
retained-mode `Control` tree.

You write **function components** that return a virtual tree; a **fiber reconciler**
diffs each render against the last and patches only what changed on the real Godot
node tree. State lives in **hooks**.

```gdscript
func _counter(props, children):
    var s = Hooks.use_state(0)
    var count = s[0]
    var set_count = s[1]
    return V.hbox({ "style": { "separation": 8 } }, [
        V.button({ "text": "-", "on_pressed": func(): set_count.call(count - 1) }),
        V.label({ "text": "Count: %d" % count }),
        V.button({ "text": "+", "on_pressed": func(): set_count.call(func(c): return c + 1) }),
    ])
```

> **Status: MVP / 0.1.** Core + hooks + styling + 10 host elements. Built to grow —
> see [Roadmap](#roadmap).

---

## Install

**As a project:** open this folder in Godot 4.x and press Play (runs `examples/main.tscn`).

**As an addon in your own project:** copy `addons/reactive_ui/` into your project's
`res://addons/`. That's it — the library is plain GDScript with global `class_name`s
(`V`, `Hooks`, `ReactiveRoot`, ...), so they're available immediately. (Enabling the
plugin under *Project Settings > Plugins* is optional; it's only a hook for future
editor tooling.)

Requires **Godot 4.1+** (uses `static var`). Works in the **standard** build — no C#
or `.NET` needed.

---

## Quick start

1. Put a `Control` in your scene (or use the scene root).
2. Attach a script and mount an app under it:

```gdscript
extends Control

var _app: ReactiveRoot   # keep this referenced for the UI's lifetime!

func _ready():
    _app = ReactiveRoot.create(self, V.fc(_my_app))

func _my_app(props, children):
    return V.vbox({}, [
        V.label({ "text": "Hello, Godot!" }),
    ])
```

`ReactiveRoot.create(container, root_vnode)` mounts under `container` and renders.
**Hold onto the returned `ReactiveRoot`** (e.g. in a member variable) — it owns the
reconciler. Call `_app.unmount()` to tear down and run cleanups.

---

## API

### `V` — building the tree

> GDScript reserves the keyword `func`, so the function-component factory is **`V.fc`**
> (not `V.func`).

| Call | Meaning |
|---|---|
| `V.fc(render_fn, props := {}, children := [], key = null)` | A function component. `render_fn` is `func(props, children) -> RUIVNode \| Array`. |
| `V.h(type, props, children, key)` | A host element by Godot class name (escape hatch for any `Control`). |

**The 10 MVP host elements** (`props`, `children`, `key` all optional):

`V.control` · `V.label` · `V.button` · `V.line_edit` · `V.vbox` · `V.hbox` ·
`V.panel` · `V.margin` · `V.texture_rect` · `V.check_box`

**Props** on a host element:
- Any Godot property of the node — `"text"`, `"editable"`, `"disabled"`, `"placeholder_text"`, `"horizontal_alignment"`, etc. — is set directly.
- `"style"` — a [style dictionary](#style) (layout + appearance).
- `"on_<signal>"` — an event: a `Callable` connected to the node's `<signal>`.
  e.g. `"on_pressed"` → `pressed`, `"on_text_changed"` → `text_changed(new_text)`,
  `"on_toggled"` → `toggled(pressed)`. The handler's arguments must match the signal.
- `"ref"` — a `Callable(node)` or a `{ "current": ... }` box that receives the live node.
- `"key"` — stable identity for [keyed reconciliation](#keys) (or pass `key` positionally).

### Hooks

Call **only** at the top of a component render, in a stable order (never in `if`/loops).

| Hook | Returns |
|---|---|
| `Hooks.use_state(initial)` | `[value, setter]`. `setter.call(v)` or `setter.call(func(old): return new)`. |
| `Hooks.use_reducer(reducer, initial)` | `[state, dispatch]`. `dispatch.call(action)`. |
| `Hooks.use_ref(initial)` | A stable `{ "current": initial }` box (never re-created). |
| `Hooks.use_memo(factory, deps)` | Cached value; recomputed only when `deps` change. |
| `Hooks.use_callback(cb, deps)` | A stable `Callable` while `deps` are unchanged. |
| `Hooks.use_effect(effect, deps = null)` | Runs `effect` after commit when `deps` change (`[]` = once; `null` = every render). `effect` may return a `Callable` cleanup. |

### <a id="style"></a>Style

Godot has no CSS/USS — styling is `Control` properties + `Theme` overrides, and layout
is **container-driven**. The `"style"` dict maps a small declarative vocabulary onto
that (see `addons/reactive_ui/core/style.gd` to extend it):

| Key | Effect |
|---|---|
| `min_width` / `min_height` | `custom_minimum_size` |
| `grow_h` / `grow_v` | size flags: `"fill"`, `"expand"`, `"expand_fill"`, `"center"`, `"begin"`, `"end"` |
| `modulate` / `self_modulate` | `Color` tint |
| `font_color` | text color override |
| `font_size` | font-size override |
| `bg_color` | a `StyleBoxFlat` background (Panel / PanelContainer / Button) |
| `separation` | child spacing on box containers |
| `margin` | `MarginContainer` insets (all sides) |
| `tooltip` | `tooltip_text` |

### <a id="keys"></a>Keys

When rendering a list, give each item a `key` so the reconciler tracks identity across
re-renders (efficient add / remove / reorder instead of rebuild):

```gdscript
var rows = []
for it in items:
    rows.append(V.fc(_row, { "key": it.id, "item": it }))
return V.vbox({}, rows)
```

---

## Architecture

Mirrors ReactiveUIToolKit; the design (algorithms) is ported, the code is GDScript.

```
addons/reactive_ui/core/
  vnode.gd        RUIVNode   — immutable description of UI (host | component | fragment)
  v.gd            V          — factory: V.fc, V.label, V.button, ...
  fiber.gd        RUIFiber   — persistent tree node; current/WIP alternates; hook store
  hooks.gd        Hooks      — use_state / use_effect / use_ref / use_memo / ...
  reconciler.gd   RUIReconciler — render (diff) + two-phase commit; update scheduling
  host_config.gd  RUIHost    — the Godot adapter: create nodes, apply props, wire signals
  style.gd        RUIStyle   — declarative style -> Control props / Theme overrides
  reactive_root.gd ReactiveRoot — mount + own the reconciler (like RootRenderer)
```

**Render loop:** a hook setter calls `request_update()`, which **coalesces** to one
full re-render at end of frame. The reconciler builds a new work-in-progress fiber
tree (running components, dispatching hooks), diffs it against the committed tree, and
commits in two passes — **deletions** (run cleanups, free nodes) then **placements /
updates** (create nodes, apply prop deltas, fix child order) — then runs **effects**.
Hook state persists because the per-fiber `hooks` array is carried over to the reused
fiber each render. Components and fragments own no node, so placement walks up to the
nearest host parent and orders siblings by tree position.

**Engine boundary:** only `host_config.gd` + `style.gd` touch concrete Godot APIs. The
rest (`vnode`/`fiber`/`reconciler`/`hooks`) is engine-agnostic in spirit — the same
seam that lets React point one reconciler at react-dom or react-native.

---

## Roadmap

This MVP is deliberately the small, correct core. Planned next (in rough order):

- **More host elements** (the rest of Godot's controls) + better default prop handling.
- **Richer style layer** — anchors/offsets, more theme items, `StyleBox` builders, named themes.
- **Bailout / targeted updates** — skip unchanged subtrees; update from a specific fiber instead of the root (the structure already supports adding this).
- **Time-sliced work loop** — for very large trees.
- **Context** (`use_context` / providers) and a **router**.
- **`.gitkx` markup + an import plugin** — a JSX-like authoring format compiled to GDScript at import time (the function-component API works fully without it).

## Notes & limitations (MVP)

- Re-render starts from the root each update; the diff keeps actual node mutations minimal, but every component's render function re-runs (normal for React-style libraries).
- Event handler lambdas are re-created each render, so events are re-wired on change — fine functionally; use `use_callback` to stabilize if needed.
- Removing a *plain* prop between renders doesn't reset it to its default (style keys do reset). Keep props consistent or set explicit defaults.
- No compile-checking was done in this environment — open it in Godot and report any syntax nits; they're quick to fix.
