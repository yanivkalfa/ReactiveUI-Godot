# Phase 7 — Core library breadth (parity push)

> ✅ **Done — what's next (2026-06-30):** the runtime is at ~Unity parity. The remaining library work (G2) lives
> in `PARITY_PLAN.md`'s Forward Roadmap: port the **custom-draw escape hatch**
> (`onGenerateVisualContent`/`_draw` + `redraw_key`) from the Unity 0.6.3 sibling, refresh the **stale README**,
> and decide the niche adapters (SubViewport / GraphEdit / GraphNode).

> **STATUS (2026-06-22): COMPLETE.** All 12 sub-phases (7.0–7.11) done + tested. Full regression
> green: core 86 · style 25 · guitkx ALL · router_match 18 · router_spine 30 · demos 28 · update ·
> LSP 30. Router rewritten as a faithful component-tree spine (V.route/routes-children/outlet/
> navigate/nav_link + RouterState/RouteContextEntry owner-stamp), location model (RUIRouterLocation +
> basename + blockers), real use_deferred_value + use_sfx/use_animate + V.audio/V.video, item-model
> adapter registry (TabBar/OptionButton/PopupMenu) + RUIStyleSheet `classes` userland layer. Legacy
> table API + context-split optimization preserved.

Source: a 5-agent research+critique workflow (2026-06-22), critique verdict **needs-work → endorsed**
after dropping one false premise. 12 sub-phases, foundation-ordered. User chose **all 12** (one
milestone), not a router-second split.

## Locked decisions (user, 2026-06-22)
1. **Router API:** ONE canonical `V.routes` that auto-detects a Dictionary `routes` prop (legacy table,
   kept working for `examples/demos/router` + `core_test`) vs JSX children (new ranked switch).
   Component-tree routing matching ReactiveUIToolKit + React-Router-dom semantics.
2. **Failure mode:** `push_error` + degrade (loud in dev, returns `[]`/continues in release). GDScript
   can't throw catchable exceptions — never hard-crash a shipped game. Use `assert` only debug-side.
3. **Style scope:** reduced-scope userland merge — `classes:[...]` resolved against a registered
   stylesheet dict at render time (NO CSS specificity/cascade) + `theme_type_variation` escape hatch +
   native per-state StyleBoxes (hover/pressed/focus). No USS cascade-engine emulation.
4. **Suspense:** drop throw-to-suspend (impossible in GDScript); declarative `<Suspense>` boundary driven
   by an awaited Godot Signal/completion token, with a Callable-poll opt-in escape hatch.
5. **Signal registry:** static-var-on-class_name (process-global, lazy-init, manual `clear()`), matching Unity.

## Architecture note (from the bug-class audit)
The port is scannerless by design and so is Unity (its `MarkupTokenizer` is a cursor, not a token stream).
Likewise the runtime mirrors ReactiveUIToolKit's fiber/hooks. Keep porting 1:1, not re-platforming.

## Sub-phases (ordered; ✅ = done + tested)
- **✅ 7.0** Dev diagnostics + `RUIConfig` strict flags: `enable_hook_validation` /
  `enable_strict_diagnostics` (default `OS.is_debug_build()`); hook-order validation (`_record`/
  `_check_hook_order` in hooks.gd, push_error on divergence); state-update-in-render guard (reads the
  already-set `is_rendering` in the setters). Captured via `RUIDiagnostics.messages` for tests.
  *(Dropped: the "use_signal unmount leak" — it does NOT exist, `_dispose_fiber_state:783` already calls
  unsub; and the missing-deps heuristic — too noisy, GDScript can't tell forgotten-vs-intentional deps.)*
- **✅ 7.1** `core/signal_registry.gd` (`RUISignals` static registry) + `Hooks.use_signal_key`.
- **✅ 7.2** `V.text` + raw-String child auto-wrap (v.gd `_norm`/`_flatten_into` + reconciler
  `_flatten_into`/`_to_vnode_array`) + compile-time text-merge (text-bearing host with all-text/expr
  children → `.text` prop, no nested Labels). *(A dedicated `Kind.TEXT` was deemed unnecessary: Godot
  renders text via Label nodes anyway, so auto-wrap-to-Label is functionally equivalent with zero
  reconciler surgery and already gets the fast-leaf-list path.)*
- **7.3** `V.memo` (thin alias of `V.fc`; optional `props.__memo_eq` comparer) + pseudo-state StyleBox
  slots in style.gd (`style={bg:.., hover:{..}, pressed:{..}, focus:{..}, disabled:{..}}` — Godot retains
  per-state StyleBoxes natively, NO event wiring; warn when a state slot is unavailable on the class) +
  `resolve_child_host` (small node-class → inner-content match; default self).
- **7.4** Suspense: `SUSPENSE` Kind+Tag; `_begin_suspense` cloned from `_begin_error_boundary`
  (reconcile `[fallback]` vs `children`); await-token readiness via `state.on_state_updated`.
  **Critique notes:** add SUSPENSE to `fiber.matches`/`tag_for_vnode` AND the `_perform_unit` dispatch arm.
- **✅ 7.5** Router foundation (pure GDScript port, Unity-faithful, 18 value-tests in
  `tests/router_match_test.gd`): `core/router/router_path.gd` (`RUIRouterPath`),
  `route_match.gd` (`RUIRouteMatch`), `route_ranker.gd` (`RUIRouteRanker` — exact Unity scores incl.
  index cost-cancellation), + `match`/`_merge` added to `matcher.gd` (legacy table API kept). Below =
  the original plan for this + the remaining sub-phases.
- **7.5 (orig)** Router foundation (pure GDScript port): `rui_router_path.gd` (combine/normalize/split/parse/
  parse_query/build_query/strip_basename/with_basename via String.split/uri_(de)code), `RUIRouteMatch`
  RefCounted, rewrite matcher (`match` + `merge_params`), port `RouteRanker` **verbatim**: score
  static+10/:param+3/index+2/empty+1/splat-2, **incl. the `if isIndex: score -= segments.size()`
  cancellation** (the old `rank()` numbers differ — must replace, not keep). Highest-fidelity, most testable.
- **7.6** Router spine: context-key constants (RouteMatch/RoutePattern/RouteContextEntry/MatchChain/
  OutletElement/OutletContext/RouterOwner); `V.route` + `route_fn` (resolve parent entry, `combine`
  resolved path, use_memo match, provide chain); RouteContextEntry owner-stamp via `Hooks._cur`;
  CollectRouteCandidates (walk FUNCTION props, descend FRAGMENT); nested-router guard (ROUTER_OWNER +
  push_error). Relies on `_propagate_context_change` shadowing (already correct).
- **7.7** Router composition: `V.outlet` (read OUTLET_ELEMENT, children fallback) + ranked `<Routes>`
  switch (auto-detect table vs children, per decision #1) + `V.navigate` (use_effect → navigate, replace
  defaults true).
- **7.8** Location model: `RUIRouterLocation {path,query,state}`; history stores full location (parse on
  push/replace); `use_location()` keeps returning a path String, add `use_query()`; `basename` strip/with.
- **7.9** Router ergonomics: `V.nav_link` (is_active end/exact/prefix-on-boundary + active style), `use_go`/
  `use_matches`/`use_resolved_path`/`use_search_params`, blockers (`register_blocker`+`_allow_transition`
  veto, `use_blocker`/`use_prompt`).
- **7.10** Remaining hooks: `RUIScheduler` (reuse reconciler frame machinery, route through
  `schedule_update_on_fiber`), real `use_deferred_value`/`use_transition`; `use_animate` (Tween),
  `use_sfx` + `V.audio`/`V.video` (media autoload). **Highest-risk item: scheduler re-entrancy vs the
  25-restart abort guard.**
- **7.11** Item-model adapter registry (generalize ItemList/Tree dispatch → TabBar/OptionButton/
  MenuBar/PopupMenu, tracker state in node meta) + USS-class userland layer (`classes:[...]` →
  `RUIStyleSheet` dict merge, per decision #3).

## Test strategy
Mirror `tests/*.gd` SceneTree-script discipline + the byte-identity corpus pattern. Per area: diagnostics
(captured messages), router foundation (value-assert score numbers + merge_params vs Unity fixtures),
router composition (mount-and-walk the real node tree at depth ≥3, navigate, assert no stale nodes +
legacy-table back-compat), Text (re-bless markup/codegen corpora), Suspense (fallback→children over
process_frame), style/item-model (state-slot override + selection-survives-rerender). New `class_name`
scripts need a `--editor --quit` cache refresh before `--script` runs.
