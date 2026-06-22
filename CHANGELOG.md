# Changelog

All notable changes to **Reactive UI for Godot** are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/), and this
project adheres to [Semantic Versioning](https://semver.org/).

## [0.2.0] — 2026-06-22

A breadth + correctness release: the router is rewritten into a full React-Router-style
component-tree spine, several runtime features land (Suspense, a signal registry, item-model
adapters, a styling `classes` layer, media + animation hooks), the `.guitkx` compiler gains inline
control-flow lowering, and a project-wide review fixed 20 confirmed bugs.

### Added
- **Component-tree router** (faithful port of ReactiveUIToolKit's router): `V.route`, `V.routes`
  (a ranked first-match switch that ALSO accepts the legacy `routes` table), `V.outlet` (nested /
  layout routes), `V.navigate` (declarative redirect), and `V.nav_link` (active-aware styling).
  Nested routes with merged `:params`, leaf-exactness (a leaf route consumes the whole path; a
  layout matches a prefix), splat `*`, `basename`, query strings, and navigation blockers. New
  hooks: `use_navigate`/`use_location`/`use_query`/`use_params`/`use_matches`/`use_resolved_path`/
  `use_search_params`/`use_go`/`use_can_go`/`use_blocker`/`use_prompt`, plus a nested-`<Router>`
  guard. The legacy `routes`-table API and the navigate-only context-split optimization are preserved.
- **Location model** — `RUIRouterLocation {path, query, state}`; history stores full locations and
  supports `go`/`can_go` + blockers; `use_location()` is basename-relative.
- **Suspense** — `V.suspense` (signal-await / frame-poll readiness; GDScript has no throw-to-suspend).
- **Signal registry** — `RUISignals` (process-wide string-keyed shared signals) + `use_signal_key`.
- **Text** — `V.text` + raw-String children auto-wrap to Labels; text-bearing hosts fold all-text
  children into the `text` prop.
- **`V.memo`** + an optional `props.__memo_eq` comparer.
- **Item-model adapter registry** — declarative `items` generalized to `ItemList`/`Tree`/`TabBar`/
  `OptionButton`/`PopupMenu`, selection/expansion preserved by item identity; `register_item_adapter`
  for custom controls.
- **Styling** — per-state StyleBox slots (`hover`/`pressed`/`focus`/`disabled`/`read_only`); a
  userland `classes: [...]` layer (`RUIStyleSheet`, ordered dict merge, inline `style` wins).
- **Hooks** — a real `use_deferred_value` (next-frame deferral); `use_animate` (Tween multi-track);
  `use_sfx` + `RUIMedia` one-shot audio; `V.audio` / `V.video` host elements.
- **Dev diagnostics** — hook-order validation + a state-update-during-render guard (debug-gated).

### Compiler (.guitkx)
- **Inline control-flow in expressions** — `@if`/`@elif`/`@else` and `@for` inside an embedded
  `{expression}` / lambda return now lower to a ternary / `.map` instead of hoisting render-level
  statements that couldn't see lambda locals (which produced invalid GDScript). `@while`/`@match`
  in an expression report `GUITKX0113`.
- Fixed: a member call on a non-Hooks receiver (`obj.use_state(...)`) is no longer auto-prefixed
  with `Hooks.`; a `module` declaring a component and a hook of the SAME name is now rejected; a
  conditional `return null` guard before the real markup return no longer fails the compile.

### Fixed (project-wide review)
- `classes`-only elements (no inline `style`) no longer error on re-render and now re-apply the
  resolved class style.
- `use_signal` re-binds its signal/selector/comparer every render (no longer frozen at mount).
- `<Outlet/>` falls back to its own children when a nested route stops matching (no stale slot).
- `ReactiveRoot.render()` / scheduling after `unmount()` no longer null-dereferences.
- `use_state`/`use_reducer` and `RUISignal` change-detection use reference equality for collections
  (Object.is), so a freshly-built equal Array/Dictionary still re-renders / notifies.
- Item adapters re-select at most the original number of duplicate-text items (and the right one).
- `use_can_go` re-renders on navigation; Suspense re-subscribes when its readiness source changes;
  `RUIMedia` one-shots no longer leak for looping streams; `use_query`/`use_params` return copies.

### Notes
Verified on Godot 4.7. Full suite green: core 91 / style 25 / guitkx / router (18 + 37) / demos 28 /
update / LSP 31. IDE extensions bump to VS Code 0.2.0 / VS 2022 0.2.0 (LSP + formatter fixes).

## [0.1.0] — 2026-06-20

First public version of the GDScript port of ReactiveUIToolKit — a React-style reactive
UI library for Godot 4.x (function components, hooks, a fiber reconciler, and a typed
style layer). Verified on Godot 4.7 (106 headless asserts green).

### Added
- **Core runtime** — virtual node tree (`RUIVNode`/`V`), fiber reconciler with
  current/work-in-progress alternates, two-phase begin/complete + post-order effect list,
  component **bailout**, **two-pass passive effects**, sync **layout effects**, **context**,
  **fragments**, **portals**, **keyed reconciliation**, deferred-updates-in-commit, and a
  structural **error boundary** (GDScript has no try/catch, so auto-catch is a documented limit).
- **19 hooks** — `use_state`, `use_reducer`, `use_ref`, `use_memo`, `use_callback`,
  `use_effect`, `use_layout_effect`, `use_context`, `use_signal`, `use_tween`/`use_tween_value`, …
- **Host layer** — ~50 `V.*` element factories; a generic adapter instantiates any of Godot's
  Control classes via `ClassDB`; declarative item-model adapters for `ItemList`/`Tree`
  (rebuild on change, preserve selection/expansion); controlled-input caret preservation.
- **Style layer** (`RUIStyle`) — friendly shorthands + a `StyleBoxFlat` builder + generic theme
  channels (colors/constants/fonts/font_sizes/icons/styleboxes = full Theme coverage).
- **Reactive store** (`RUISignal`), **router** (history/matcher/`V.router`/`routes`/`link`),
  **diagnostics** counters, **time-slicing**, and a `ReactiveRootNode` mount node.
- **Demo gallery** (`examples/`) — 24 demos incl. a **library stress test** and a **native
  stress test** (raw `ColorRect`s, no reconciler) for an in-game A/B of the reconcile cost.
- **CI/tests** — headless test suites (`tests/`), throughput + native-vs-library benchmarks
  (`tests/bench.gd`, `tests/bench_native.gd`, `tests/bench_compare.gd`, `tests/microbench.gd`).

### Performance
Three optimization rounds against an N-bouncing-boxes stress test (all general, not
stress-test-specific; correctness-neutral, all suites green):
- **Round 1 — fiber double-buffering.** The reconciler reuses each fiber's `alternate`
  instead of allocating a fresh fiber per element per frame, and drops the per-frame
  whole-tree sever (subtrees are released only on real deletion/unmount). In-game 1500 boxes:
  **~21 → ~33 fps**.
- **Round 2 — reconciler hot-path.** Eliminated the per-frame child-list array (walk the
  sibling chain), added a keyed positional fast-path for stable lists, an `is_same()` identity
  short-circuit before the prop deep-compare, inlined tag checks, and a shared empty children
  array. ~12% further.
- **Round 3 — call-inlining (GDScript is function-call-overhead bound).** Inlined the vnode
  factory and the hot reconcile/commit call chain (leaf fast-path, effect append, key-compare,
  begin-work). 1500-box reconcile **~23 → ~18 ms** (overhead vs native −22%).
- **Round 4 — fast-list path (the big structural win).** A stable list of host *leaves* (same
  count/keys/order, every child a childless host element) now bypasses the entire per-child
  fiber traversal: child fibers are reused in place and only the *changed* rows are diffed +
  committed (per-row bail-out, à la `React.memo` + Solid/Svelte fine-grained updates). Cuts
  reconcile-traversal **8.5 → 3.3 ms** and 1500-box reconcile **~18 → ~12.7 ms** (−31%);
  throughput roughly doubled (1500 boxes ~38 → ~69 fps headless). Mostly-static lists become
  nearly free. Backed by deep research into the GDScript interpreter — the remaining gap to
  native is GDScript interpretation itself; true native parity would need a small batched
  GDExtension (a documented, optional future step), not a rendering-path change.

### Notes
- A typed/pooled props layer was prototyped and measured against the native `Dictionary`;
  in pure GDScript the native dict wins (it's a C++ type), so the library stays on dicts.
  The experiment lives on the `typed-props` branch for reference.
