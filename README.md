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

> **Status: 0.2.x — runtime feature-complete, at ~parity with the Unity library.**
> A fiber reconciler with bailout + keyed reconciliation, **21 hooks** plus a full
> React-Router-style **router** (with its own ~14 hooks), **signals**, **Suspense**,
> a three-layer **style** system, declarative **item-model** controls, media/animation,
> a custom-drawing hatch, and **63 `V.*` factories**. Verified on Godot 4.7 with a green
> test suite. There is also an optional **`.guitkx` markup** authoring format + VS Code /
> VS 2022 extensions (see [IDE tooling](#ide-tooling)).

---

## Install

**As a project:** open this folder in Godot 4.x and press Play (runs `examples/main.tscn`).

**As an addon in your own project:** copy `addons/reactive_ui/` into your project's
`res://addons/`. The library is plain GDScript with global `class_name`s (`V`, `Hooks`,
`ReactiveRoot`, ...), so they're available immediately — **no plugin enable required** to
use the runtime. Enabling the plugin under *Project Settings > Plugins* adds the optional
**`.guitkx` compile-on-save** editor integration (it watches the filesystem and generates a
sibling `.gd` for each `.guitkx`); skip it if you only write GDScript components.

Requires **Godot 4.1+** (uses `static var`); verified on **4.7**. Works in the **standard**
build — no C# or `.NET` needed.

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
reconciler. Call `_app.unmount()` to tear down and run cleanups. (A `Control`-based
`ReactiveRootNode` is also available if you prefer mounting via a node in the scene.)

---

## API

### `V` — building the tree

> GDScript reserves the keyword `func`, so the function-component factory is **`V.fc`**
> (not `V.func`).

| Call | Meaning |
|---|---|
| `V.fc(render_fn, props := {}, children := [], key = null)` | A function component. `render_fn` is `func(props, children) -> RUIVNode \| Array \| String`. |
| `V.h(type, props, children, key)` | A host element by Godot class name — the escape hatch for **any** `Control`. |

**~63 host factories** cover Godot's control surface, including:

- **Containers** — `V.control` · `V.vbox` · `V.hbox` · `V.grid` · `V.margin` · `V.panel` ·
  `V.center` · `V.scroll` · `V.flow_h`/`V.flow_v` · `V.tabs` · `V.split_h`/`V.split_v` ·
  `V.aspect` · `V.foldable`
- **Text & display** — `V.label` · `V.rich_text` · `V.texture_rect` · `V.progress_bar` · ...
- **Buttons** — `V.button` · `V.check_box` · `V.check_button` · `V.option_button` · ...
- **Inputs** — `V.line_edit` · `V.text_edit` · `V.code_edit` · `V.spin_box` ·
  `V.h_slider`/`V.v_slider` · `V.color_picker` · ...
- **Item-model controls** — `V.item_list` · `V.tree` · `V.tab_bar` · `V.option_button` (see [Item models](#item-models))
- **Menus** — `V.menu_bar` · `V.menu_button` (a `PopupMenu` takes declarative items too)
- **Media** — `V.audio` · `V.video`
- **Structural** — `V.fragment` · `V.portal` · `V.suspense` · `V.error_boundary` · `V.memo`
- **Router** — `V.router` · `V.routes` · `V.route` · `V.outlet` · `V.navigate` · `V.nav_link` · `V.link`

Anything not covered is one `V.h("SomeControl", props)` away.

**Props** on a host element:
- Any Godot property of the node — `"text"`, `"editable"`, `"disabled"`, etc. — is set directly.
- `"style"` / `"classes"` — a [style dictionary](#style) and/or stylesheet class names.
- `"on_<signal>"` — an event: a `Callable` connected to the node's `<signal>`
  (e.g. `"on_pressed"` → `pressed`, `"on_text_changed"` → `text_changed(new_text)`).
- `"ref"` — a `Callable(node)` or a `{ "current": ... }` box that receives the live node.
- `"items"` — declarative data for [item-model controls](#item-models).
- `"draw_fn"` / `"redraw_key"` — a [custom-drawing](#custom-drawing) callback.
- `"key"` — stable identity for [keyed reconciliation](#keys) (or pass `key` positionally).

### Hooks

Call **only** at the top of a component render, in a stable order (never in `if`/loops).
The core set:

| Hook | Returns / does |
|---|---|
| `Hooks.use_state(initial)` | `[value, setter]`. `setter.call(v)` or `setter.call(func(old): return new)`. |
| `Hooks.use_reducer(reducer, initial)` | `[state, dispatch]`. |
| `Hooks.use_ref(initial)` | A stable `{ "current": initial }` box (never re-created). |
| `Hooks.use_memo(factory, deps)` | Cached value; recomputed only when `deps` change. |
| `Hooks.use_callback(cb, deps)` / `use_stable_callback(cb, deps)` | A stable `Callable` while `deps` are unchanged. |
| `Hooks.use_effect(effect, deps = null)` | Runs after commit when `deps` change (`[]` = once; `null` = every render). `effect` may return a `Callable` cleanup. |
| `Hooks.use_layout_effect(effect, deps)` | Like `use_effect` but synchronous, before paint. |
| `Hooks.use_context(ctx)` | The nearest provider value; re-renders on change. |
| `Hooks.use_signal(selector)` / `use_signal_key(key)` | Subscribe to a [signal](#signals) store. |
| `Hooks.use_deferred_value(v)` / `use_transition()` | Defer/triage non-urgent updates. |
| `Hooks.use_tween(...)` / `use_tween_value(...)` / `use_animate(...)` / `use_sfx(...)` | Animation + audio helpers. |

…plus `use_imperative_handle`, `use_safe_area`, and the stable-`func`/`action` family — **21 hooks** in all.
The [router](#router) adds ~14 more (`use_navigate`, `use_location`, `use_params`, `use_search_params`,
`use_blocker`, …).

### <a id="style"></a>Style

Godot has no CSS/USS — styling is `Control` properties + `Theme` overrides, and layout is
**container-driven**. The library gives you three layers (see `core/style.gd` + `core/style_sheet.gd`):

1. **Inline `"style"` shorthands** — `min_width`/`min_height`, `grow_h`/`grow_v` (size flags),
   `modulate`/`self_modulate`, `font_color`/`font_size`, `bg_color` (a `StyleBoxFlat`),
   `separation`, `margin`, `tooltip`, rotation/scale, and more.
2. **Theme channels** — full `Theme` coverage (colors / constants / fonts / font-sizes / icons /
   styleboxes) plus **per-state `StyleBox` slots** (hover / pressed / focus / disabled / read-only).
3. **`classes`** — named style sets registered with `RUIStyleSheet` (merged left-to-right;
   inline `style` wins). A userland "USS classes" layer.

### <a id="router"></a>Router

A faithful **React-Router-v6-style** component-tree router: nested / layout routes via
`V.outlet()`, ranked first-match, merged `:params`, splat `*`, `basename`, query strings,
`V.nav_link` active styling, `V.navigate`, and navigation blockers. Drive it with the router
hooks (`use_navigate`, `use_location`, `use_params`, `use_search_params`, `use_blocker`, …).

### <a id="signals"></a>Signals

A reference-aware `RUISignal` store plus a process-wide, string-keyed `RUISignals` registry —
share state across components without prop-drilling. Read it with `use_signal` / `use_signal_key`.

### <a id="items"></a>Item models

`V.item_list` / `V.tree` / `V.tab_bar` / `V.option_button` (and `PopupMenu`) take a declarative
`"items"` array and reconcile rows **by item identity** (selection/expansion preserved across
renders). Wire changes with the normal `on_*` event props. Register adapters for your own
controls via `RUIHost.register_item_adapter(...)`.

### <a id="custom-drawing"></a>Custom drawing

Draw directly onto any host element — the Godot analogue of Unity's `OnGenerateVisualContent`:

```gdscript
V.control({
    "draw_fn": func(canvas):                       # runs during the node's `draw`
        canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color.DARK_SLATE_GRAY)
        canvas.draw_line(Vector2(0, 0), canvas.size, Color.CYAN, 2.0),
    "redraw_key": frame,                            # optional: bump to repaint without changing draw_fn
})
```

`draw_fn` is a `Callable(canvas_item)` that issues the node's `draw_*` calls. A register-once
trampoline reads the latest callback, so a fresh closure each render never re-subscribes — it
repaints only when the callback identity **or** `redraw_key` changes. Pair `redraw_key` with
`use_stable_callback` to repaint on a counter alone. (Per-frame repaint without re-rendering: use
a `ref` + `queue_redraw()`, or `use_animate`.)

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
  vnode.gd / v.gd            RUIVNode / V     — UI description + the ~63 factories
  fiber.gd                   RUIFiber         — persistent tree node; current/WIP alternates; hook store
  hooks.gd                   Hooks            — the 21 hooks
  reconciler.gd              RUIReconciler    — render (diff) + two-phase commit; bailout; scheduling
  host_config.gd             RUIHost          — the Godot adapter: nodes, props, signals, items, custom draw
  style.gd / style_sheet.gd  RUIStyle / RUIStyleSheet — declarative style -> Control props / Theme
  signal_store.gd / signal_registry.gd  RUISignal / RUISignals
  suspense.gd                                  — V.suspense boundary
  media.gd                                     — use_sfx / use_animate / V.audio / V.video
  router/                    RUIRouter…       — router spine, matcher, ranker, history, location
  reactive_root.gd / reactive_root_node.gd     — mount surfaces
```

**Render loop:** a hook setter calls `request_update()`, which **coalesces** to one re-render
per frame. The reconciler builds a work-in-progress fiber tree (running components, dispatching
hooks), diffs it against the committed tree with **component bailout** + keyed child
reconciliation, and commits in two passes — **deletions** then **placements / updates** — then
runs **effects**. Hook state persists via the per-fiber `hooks` array carried to the reused fiber.

**Engine boundary:** only `host_config.gd` + `style.gd` touch concrete Godot APIs — the same seam
that lets React point one reconciler at react-dom or react-native.

---

## <a id="ide-tooling"></a>IDE tooling (optional)

A JSX-like **`.guitkx` markup** format compiles to GDScript (a sibling `.gd`, generated by the
editor plugin on save). The **VS Code** and **VS 2022** extensions give it highlighting,
completion, diagnostics, hover, formatting, go-to-definition, find-references, and rename — with
the embedded GDScript analyzed **headlessly** (no running Godot editor) by
[`@gdscript-analyzer/core`](https://www.npmjs.com/package/@gdscript-analyzer/core). The same
extension can optionally drive plain `.gd` files too (`guitkx.enableGdscriptAnalysis`). See
`ide-extensions/`. The `.guitkx` toolchain is entirely optional — the function-component API
above works fully without it.

---

## Notes & limitations

- **Removed plain props don't reset to defaults** between renders (style keys, events, refs, and
  custom draw *do* reset). Keep props consistent or set explicit defaults.
- **Error boundaries are structural** — GDScript has no `try`/`catch`, so a boundary can't
  auto-catch a child render crash; it shows its fallback on an imperative toggle / `reset_key`.
- **`use_transition` / `use_deferred_value` are synchronous** (no concurrent renderer) — faithful
  to the Unity reference, but not "true" concurrency.
- Event handler lambdas are re-created each render (events re-wire on change — fine functionally;
  use `use_callback` to stabilize). Custom `draw_fn` uses the register-once trampoline so it does
  **not** re-subscribe.

## Roadmap

- **Docs site + more samples** — a proper guide beyond this README.
- **Test parity** — golden codegen corpus, rules-of-hooks matrix.
- **`.guitkx` + IDE depth** — analyzer-driven formatting + semantic tokens for embedded GDScript.
- **Native Godot-editor support** — syntax highlighting for `.guitkx` inside Godot's own script editor.
