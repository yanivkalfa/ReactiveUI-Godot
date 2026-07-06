# Reactive UI — Godot (GDScript)

💬 **[Join the Discord][discord-invite]** — questions, feedback, and release announcements.

A **React-style reactive UI library for Godot 4.x**, written in GDScript, authored through
**`.guitkx`** — a JSX-like markup that compiles to GDScript. It's the Godot sibling of
[ReactiveUIToolKit](https://github.com/yanivkalfa/ReactiveUIToolKit) (the C# / Unity UI Toolkit
library) — same mental model, ported to Godot's retained-mode `Control` tree.

You write **function components** in `.guitkx`; a **fiber reconciler** diffs each render against
the last and patches only what changed on the real Godot node tree. State lives in **hooks**, and
saving a `.guitkx` while your game runs under F5 hot-reloads it in place (**Fast Refresh**).

```
component Counter {
	var s = useState(0)
	return (
		<VBox style={ {"separation": 8} }>
			<Label text={ "Count: %d" % s[0] } style={ {"font_size": 28} } />
			<HBox style={ {"separation": 8} }>
				<Button text="−1" onClick={ func(): s[1].call(s[0] - 1) } />
				<Button text="+1" onClick={ func(): s[1].call(func(c): return c + 1) } />
			</HBox>
		</VBox>
	)
}
```

> **Status: runtime feature-complete, verified on Godot 4.7 with a green test suite.**
> A fiber reconciler with bailout + keyed reconciliation, **23 hooks** plus a full
> React-Router-style **router** (with its own **17 hooks**), **signals**, **Suspense**, a
> three-layer **style** system, declarative **item-model** controls, media/animation, a
> custom-drawing hatch, and **~61 `V.*` factories**. `.guitkx` gets you React-parity markup — early
> returns, prop spread, context handles, control-flow directives — plus **Fast Refresh** (hot
> reload with hook state preserved) and editor tooling in three places: natively inside Godot, in
> VS Code, and in Visual Studio 2022.

Everything below is written the way you should actually author UI with this library: in
**`.guitkx`**. The library's underlying GDScript API (`V.*` factories, `Hooks.*`) is what `.guitkx`
compiles to — it's covered too, but as the escape hatch it's meant to be, not the primary path.

---

## Install

**As a project:** open this folder in Godot 4.x and press Play (runs `examples/main.tscn`, the demo
gallery — every demo is `.guitkx`).

**As an addon in your own project:** copy `addons/reactive_ui/` into your project's
`res://addons/`. The runtime is plain GDScript with global `class_name`s (`V`, `Hooks`,
`ReactiveRoot`, ...), so they're available immediately — **no plugin enable required**.

To actually *write* `.guitkx`, enable the plugin (**Project Settings → Plugins → Reactive UI**) —
it watches the filesystem and compiles each `.guitkx` to a sibling `.gd` on save. Then add editor
support for the language itself (pick one, or use both):

- **`addons/reactive_ui_editor/`** — a native in-Godot editor tab: syntax highlighting, live
  diagnostics, completion, and hover, no external tools. Copy it in alongside `reactive_ui` and
  enable it too.
- **VS Code / Visual Studio 2022 extensions** (`ide-extensions/`) — the same, plus embedded-GDScript
  intelligence inside `{expr}`/setup code (completion, hover, go-to-definition, find-references,
  rename), fully offline. See [IDE tooling](#ide-tooling).

Requires **Godot 4.1+** (uses `static var`); verified on **4.7**. Standard build — no C# or `.NET`.

---

## Quick start

1. Put a `Control` in your scene (or use the scene root).
2. Write your first component as a `.guitkx` file, e.g. `res://ui/counter.guitkx`:

```
@class_name Counter

component Counter {
	var s = useState(0)
	return (
		<VBox>
			<Label text={ "Count: %d" % s[0] } />
			<Button text="+1" onClick={ func(): s[1].call(func(c): return c + 1) } />
		</VBox>
	)
}
```

Saving it compiles a sibling `res://ui/counter.gd` (git-ignore this — it's generated). `@class_name`
gives the generated script a real Godot `class_name`, so you can reference it like any other class.

3. Mount it from a plain `.gd` script — this one bootstrap point is the only place raw GDScript is
   unavoidable, the same way a React app still has one `ReactDOM.render` call:

```gdscript
extends Control

var _app: ReactiveRoot   # keep this referenced for the UI's lifetime!

func _ready():
	_app = ReactiveRoot.create(self, V.fc(Counter.render))

func _exit_tree():
	_app.unmount()
```

`ReactiveRoot.create(container, root_vnode)` mounts under `container` and renders. **Hold onto the
returned `ReactiveRoot`** — it owns the reconciler; call `.unmount()` to tear down and run cleanups.
(A `Control`-based `ReactiveRootNode` is also available if you prefer mounting via a scene node.)

From here on, edit `counter.guitkx` while the game runs under F5 and watch it update in place — see
[Fast Refresh](#fast-refresh).

---

## Authoring in `.guitkx`

A `.guitkx` file declares one `component` (or a `hook` / a `module` grouping several — see
[Companion files](#companion-files)), with GDScript **setup code** followed by exactly one markup
`return (...)`. Canonical formatting is **2-space indentation** (Unity-exact); the compiler and
formatter both enforce it.

### Hooks

Call hooks **only** at the top of a component, unconditionally, in a stable order (never in
`if`/loops/lambdas — the compiler rejects this at compile time). The core set:

| Hook | Returns / does |
|---|---|
| `useState(initial)` | `[value, setter]`. `setter.call(v)` or `setter.call(func(old): return new)`. |
| `useReducer(reducer, initial)` | `[state, dispatch]`. |
| `useRef(initial)` | A stable `{ "current": initial }` box (never re-created). |
| `useMemo(factory, deps)` | Cached value; recomputed only when `deps` change. |
| `useCallback(cb, deps)` / `useStableCallback(cb)` | A stable `Callable` while `deps` are unchanged. |
| `useEffect(effect, deps = null)` | Runs after commit when `deps` change (`[]` = once; `null` = every render). `effect` may return a `Callable` cleanup. |
| `useLayoutEffect(effect, deps)` | Like `useEffect` but synchronous, before paint. |
| `useContext(handle)` | The nearest provider's value; re-renders on change. |
| `useSignal(sig, selector)` / `useSignalKey(key)` | Subscribe to a [signal](#signals) store. |
| `useDeferredValue(v)` / `useTransition()` | Defer/triage non-urgent updates (synchronous renderer — see [limitations](#notes--limitations)). |
| `useTween(...)` / `useTweenValue(...)` / `useAnimate(...)` / `useSfx(...)` | Animation + audio helpers. |

…plus `useImperativeHandle`, `useSafeArea`, `createContext`/`provideContext`, and the
stable-callback family — **23 hooks** in all. Bare calls (`useState(...)`) auto-resolve to
`Hooks.useState(...)`. The [router](#router) adds **17 more**, all on `RUIRouter`
(`RUIRouter.useNavigate`, `useLocation`, `useParams`, `useSearchParams`, `useBlocker`, …) — router
hooks stay explicitly qualified.

### Control flow

`@if`/`@elif`/`@else`, `@for`, `@while`, and `@match`/`@case`/`@default` bodies are GDScript **prep
code plus `return ( <markup> )`**, and nest recursively — the same model as ReactiveUIToolKit:

```
@for (it in items) {
	var label = "row %s" % it
	if it == null:
		return null                          # skip this item
	return ( <Label key={ str(it) } text={ label } /> )
}
```

`return null` / a bare `return` are the sanctioned skip-guard forms. A component's markup `return`
can also appear **early**, guarding on a condition, not just as the final statement:

```
component Panel(ready: bool = false) {
	if not ready:
		return ( <Label text="loading" /> )
	return ( <VBox>…</VBox> )
}
```

### Prop spread & context

```
component Card {
	var shared = { "custom_minimum_size": Vector2(140, 0), "text": "shared" }
	return ( <Button {...shared} onClick={ handle } /> )
}
```

Spreads merge left-to-right (later wins), on both host elements and components — just like JSX.
For cross-cutting state, prefer a context **handle** over a bare string key (collision-free, and it
carries a default value):

```gdscript
# accent_context.gd — a module-level handle, shared by every component that imports it
static var HANDLE: RUIContext = preload("res://.../hooks.gd").createContext(Color(0.4, 0.7, 1.0))
```

```
provideContext(AccentContext.HANDLE, accent[0])   # in a provider
useContext(AccentContext.HANDLE)                  # in a consumer
```

### Styling

Godot has no CSS/USS — styling is `Control` properties + `Theme` overrides, and layout is
**container-driven**. `.guitkx`'s `style={ {...} }` prop gives you three layers (see
`core/style.gd` + `core/style_sheet.gd`):

1. **Inline shorthands** — `min_width`/`min_height`, `grow_h`/`grow_v` (size flags),
   `modulate`/`self_modulate`, `font_color`/`font_size`, `bg_color` (a `StyleBoxFlat`),
   `separation`, `margin`, `tooltip`, rotation/scale, and more.
2. **Theme channels** — full `Theme` coverage (colors / constants / fonts / font-sizes / icons /
   styleboxes) plus **per-state `StyleBox` slots** (hover / pressed / focus / disabled / read-only).
3. **`classes={ [...] }`** — named style sets registered with `RUIStyleSheet` (merged left-to-right;
   inline `style` wins). A userland "USS classes" layer.

### Keys

Give each item in a list a `key` so the reconciler tracks identity across re-renders (efficient
add/remove/reorder instead of rebuild):

```
@for (it in items) {
	return ( <Label key={ str(it.id) } text={ it.name } /> )
}
```

### Item models

`<ItemList>` / `<Tree>` / `<TabBar>` / `<OptionButton>` (and `PopupMenu`, via `V.h`) take a
declarative `items={ [...] }` prop and reconcile rows **by item identity** (selection/expansion
preserved across renders). Wire changes with the normal `on*` event props. Register adapters for
your own controls via `RUIHost.register_item_adapter(...)`.

### Custom drawing

Draw directly onto any host element — the Godot analogue of Unity's `OnGenerateVisualContent`:

```
<Control draw_fn={ func(canvas): canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color.DARK_SLATE_GRAY) }
         redraw_key={ frame } />
```

`draw_fn` is a `Callable(canvas_item)` run during the node's `draw`. A register-once trampoline
reads the latest callback, so a fresh closure each render never re-subscribes — it repaints only
when the callback identity **or** `redraw_key` changes.

### Companion files

A `hook use_thing() { ... }` or a `module Name { component A {...} hook use_b() {...} }`
declaration groups reusable logic into its own `.guitkx` file, compiled the same way — this is
still `.guitkx`, not raw GDScript. See the docs site's Companion Files page for the full layout
convention (one `component` per file, sub-components as sibling files, `module` for shared hooks).

### Where `V.*` still shows up

A handful of structural primitives have no markup tag — **`Portal`, `Suspense`, `ErrorBoundary`,
`Memo`, `Audio`/`Video`, and the router's `Router`/`Routes`/`Route`/`Outlet`/`Navigate`/`NavLink`**
aren't in the tag vocabulary (`vocabulary.json`'s `host_tags`), so you reach them via `V.*` inside
an embedded `{ expr }` — still inside your `.guitkx` file, just not as a `<Tag>`:

```
component App {
	return (
		<VBox>
			{ V.suspense({ "fallback": V.fc(Spinner.render), "ready_signal": ready }, [V.fc(Content.render)]) }
		</VBox>
	)
}
```

Everything else — every host `Control`, every hook, every directive — is a real `.guitkx` tag or
keyword. Reaching for the bare `V.*`/`Hooks.*` GDScript API directly (outside a `.guitkx` file) is
possible — it's the same runtime — but treat it as a fallback for one-off scripts or advanced
internals, not how you author application UI.

### Router

A faithful **React-Router-v6-style** component-tree router: nested/layout routes via
`{ V.outlet() }`, ranked first-match, merged `:params`, splat `*`, `basename`, query strings,
`NavLink`-equivalent active styling, and navigation blockers. The route table itself is configured
via `V.routes(...)`/`V.route(...)` (see [above](#where-v-still-shows-up)); drive it from markup with
the router hooks on `RUIRouter`.

### Signals

A reference-aware `RUISignal` store plus a process-wide, string-keyed `RUISignals` registry —
share state across components without prop-drilling. Read it with `useSignal`/`useSignalKey`.

### Fast Refresh

Save a `.guitkx` while your game runs under F5 and the UI updates **in place**, hook state
preserved — no restart:

- A changed **component** re-renders just its own fibers; a changed **hook/module** triggers a
  global re-render (any component may call it).
- If the hook-call shape changed (added/removed/reordered), that component's state is
  **deliberately reset** instead of risking corruption — React Fast Refresh semantics, backed by a
  compiler-embedded hook-order fingerprint.
- A component created *after* F5 (so it has no registered `class_name` yet) still hot-links in,
  by path, the moment you reference it.
- **Dev-only**: gated on an attached debugger session (F5 from the editor); exported builds carry
  zero HMR code. Renaming a component remounts it (fresh state).

---

## Architecture

Mirrors ReactiveUIToolKit; the design (algorithms) is ported, the code is GDScript.

```
addons/reactive_ui/core/
  vnode.gd / v.gd            RUIVNode / V     — UI description + the ~61 factories (incl. V.comp)
  fiber.gd                   RUIFiber         — persistent tree node; current/WIP alternates; hook store
  hooks.gd                   Hooks            — the 23 hooks
  reconciler.gd              RUIReconciler    — render (diff) + two-phase commit; bailout; scheduling
  host_config.gd             RUIHost          — the Godot adapter: nodes, props, signals, items, custom draw
  style.gd / style_sheet.gd  RUIStyle / RUIStyleSheet — declarative style -> Control props / Theme
  signal_store.gd / signal_registry.gd  RUISignal / RUISignals
  suspense.gd                                  — V.suspense boundary
  media.gd                                     — useSfx / useAnimate / V.audio / V.video
  hmr.gd                     RUIHmr           — Fast Refresh runtime (game side)
  router/                    RUIRouter…       — router spine, matcher, ranker, history, location
  reactive_root.gd / reactive_root_node.gd     — mount surfaces
addons/reactive_ui/guitkx/    RUIGuitkx…       — the .guitkx lexer/parser/codegen/formatter
addons/reactive_ui/editor/                     — editor-side watcher + Fast Refresh push (hmr_debugger.gd)
addons/reactive_ui_editor/                     — native in-Godot .guitkx editor tab (separate addon)
ide-extensions/                                — VS Code / VS 2022 extensions + shared language server
```

**Render loop:** a hook setter calls `request_update()`, which **coalesces** to one re-render per
frame. The reconciler builds a work-in-progress fiber tree (running components, dispatching hooks),
diffs it against the committed tree with **component bailout** + keyed child reconciliation, and
commits in two passes — **deletions** then **placements/updates** — then runs **effects**. Hook
state persists via the per-fiber `hooks` array carried to the reused fiber.

**Engine boundary:** only `host_config.gd` + `style.gd` touch concrete Godot APIs — the same seam
that lets React point one reconciler at react-dom or react-native.

**Cross-component references are path-based, not registry-based:** a generated `<Card />` reference
compiles to `V.fc(V.comp("res://ui/card.gd"), …)` — a lazy, cached, path-based resolver — instead of
`Card.render`, so a component created mid-session, an editor rescan lag, or a cyclic component graph
can never break resolution. Hand-written `class_name` components (and your own GDScript expressions)
keep the classic `Foo.render` form.

---

## Diagnostics

The compiler validates as it goes — rules of hooks, duplicate/unstable keys, unknown elements,
directive-header grammar, dangling/duplicate component references, asset paths, and more — **39
`GUITKX####` codes** in total, with "did you mean" hints where it can tell. See the docs site's
Diagnostics reference for the full table; `GUITKX2103` is the one you'll hit migrating pre-0.7
`.guitkx` (directive bodies need `return ( <markup> )` now), and `GUITKX2106`/`GUITKX2107` guard
against a copy-pasted or dangling component reference.

---

## <a id="ide-tooling"></a>IDE tooling

Three ways to get `.guitkx` intelligence, and you can mix them:

| | Native (`reactive_ui_editor`) | VS Code / VS 2022 (`ide-extensions/`) |
|---|---|---|
| Syntax highlighting | ✅ | ✅ (self-contained TextMate grammar) |
| Live diagnostics | ✅ | ✅ |
| Tag / attribute / directive completion + hover | ✅ | ✅ |
| Embedded-GDScript intelligence inside `{expr}`/setup (completion, hover, diagnostics) | — | ✅, via [`@gdscript-analyzer/core`](https://www.npmjs.com/package/@gdscript-analyzer/core), fully offline, no running Godot editor |
| Go-to-definition / find-references / rename / signature help | — | ✅ |
| Formatting | ✅ | ✅ |

The native addon needs nothing but Godot itself — enable `addons/reactive_ui_editor/` alongside
`reactive_ui`. The external extensions need Node bundled in (already handled by the packaged
`.vsix`) — see `ide-extensions/README.md` for building/publishing. The `.guitkx` toolchain and all
IDE support are optional in the sense that the runtime works without them, but writing UI by hand as
raw `V.*`/`Hooks.*` calls is not the intended day-to-day workflow — see
[Authoring in `.guitkx`](#authoring-in-guitkx).

---

## Notes & limitations

- **`V.comp`-addressed structural primitives have no markup tag yet** — `Portal`, `Suspense`,
  `ErrorBoundary`, `Memo`, `Audio`/`Video`, and the router primitives are reached via `V.*` inside an
  embedded expression (see [above](#where-v-still-shows-up)), not a `<Tag>`. Adding tags for these is
  tracked in `plans/`.
- **Removed plain props don't reset to defaults** between renders (style keys, events, refs, and
  custom draw *do* reset). Keep props consistent or set explicit defaults.
- **Error boundaries are structural** — GDScript has no `try`/`catch`, so a boundary can't
  auto-catch a child render crash; it shows its fallback on an imperative toggle / `reset_key`.
- **`useTransition`/`useDeferredValue` are synchronous** (no concurrent renderer) — faithful to the
  Unity reference, but not "true" concurrency.
- **Fast Refresh is dev-only** (gated on an attached debugger session) and does not migrate
  hand-written module `static var`s across a reload (a Godot engine limitation, godot#105667) —
  generated components are statics-free by design.
- Event handler lambdas are re-created each render (events re-wire on change — fine functionally;
  use `useCallback` to stabilize). Custom `draw_fn` uses the register-once trampoline so it does
  **not** re-subscribe.
- **Dependency arrays compare by VALUE, not identity** — `useEffect`/`useMemo`/`useCallback` deps use
  GDScript `==`, which deep-compares `Array`/`Dictionary`, unlike React's per-item `Object.is`. A
  freshly-built but structurally-equal deps array will **not** re-run the effect (a stable behavior
  this library relies on elsewhere), but a large `Array`/`Dictionary` in a deps list is deep-compared
  every render — keep deps small/primitive where you can. (State/signal change-detection is
  identity-based already, matching React; only the deps-array comparison differs.)
- **The VS 2022 extension lags VS Code**: both ship from the same `lsp-server`, but VS 2022 hasn't
  been re-published since 0.5.5 while VS Code/the language server are at 0.8.6 — VS 2022 users are
  missing several releases' worth of fixes (dangling-reference detection, sidecar watching, folder
  deletion handling) until it's repackaged.

## Roadmap

- **Markup tags for the remaining `V.*`-only primitives** (`Portal`, `Suspense`, `Router`/`Routes`/
  `Route`, …) so the "escape hatch" list above gets shorter.
- **Native-editor parity** — go-to-definition, find-references, rename, and embedded-GDScript
  intelligence for `reactive_ui_editor`, closing the gap with the VS Code/VS 2022 extensions (see
  `plans/NATIVE_EDITOR_PARITY_PLAN.md`).
- **Docs site** (`ReactiveUIGodotDocs~/`) — a full guide beyond this README; run it locally with
  `cd ReactiveUIGodotDocs~ && npm ci && npm run dev`.
- **Test parity** — golden codegen corpus, rules-of-hooks matrix.
- **Godot Asset Store / Asset Library distribution** — repo prep (license, icon, export rules) is
  in place; publishing itself is not live yet.

<!--
  Single source of truth for the community Discord invite used in this file — update only here.
  (The docs site has its own single source: ReactiveUIGodotDocs~/src/links.ts.)
-->
[discord-invite]: https://discord.gg/Knedqu4Wyv
