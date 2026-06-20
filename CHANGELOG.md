# Changelog

All notable changes to **Reactive UI for Godot** are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/), and this
project adheres to [Semantic Versioning](https://semver.org/).

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

### Notes
- A typed/pooled props layer was prototyped and measured against the native `Dictionary`;
  in pure GDScript the native dict wins (it's a C++ type), so the library stays on dicts.
  The experiment lives on the `typed-props` branch for reference.
