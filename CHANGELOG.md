# Changelog

All notable changes to **Reactive UI for Godot** are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/), and this
project adheres to [Semantic Versioning](https://semver.org/).

## [0.5.0] — 2026-07-03

**The `.uitkx` syntax & diagnostics parity release.** `.guitkx` now matches Unity
ReactiveUIToolKit's grammar feature-for-feature, its diagnostic codes are renumbered onto
Unity's shared numbering (the minor bump), and the embedded-GDScript analysis is upgraded to
gdscript-analyzer 0.6 with Godot's own verbatim messages.

### Changed — **diagnostic codes renumbered** (breaking for anything matching code strings)

| old | new | meaning |
|---|---|---|
| `GUITKX0102` | `GUITKX2101` | missing/unknown declaration (the conditional-markup-return half is `GUITKX2102`) |
| `GUITKX0107` | `GUITKX0109` | moved per the shared table |
| `GUITKX0114` | `GUITKX0107` | unreachable code after the component's return (hint + dimming) |
| `GUITKX0113` | `GUITKX0026` | duplicate key (now an error) |
| `GUITKX0110` | `GUITKX2504` | structure error (shared 25xx Godot-reserved block) |
| `GUITKX0112` | `GUITKX2505` | structure error |
| `GUITKX0306` | `GUITKX2506` | Godot-specific parse error (different meaning than Unity's 0306) |

Kept: `0103 0104 0105 0106 0108 0013 0300–0305`. New (Unity numbers): `0014–0016 0018 0019
0111 0120 0121 0150 2100 2102 2105 2203 2210`; Godot-reserved `2504–2507`. One severity per
code everywhere, driven by `vocabulary.json`'s `severities` table (duplicate keys error;
unreachable code is a dimmed hint).

### Added
- **Unity-parity grammar:** markup comments (`//`, `/* */`, `<!-- -->`, and `{/* */}` in
  attribute lists), `<Fragment key={ ... }>`, the Unity text model (mid-text braces are
  literal; `GUITKX0150` migration warning), rules-of-hooks as errors (conditional / loop /
  match / lambda contexts + hook calls inside markup expressions), PascalCase/`use_` naming
  checks, effect-deps / binder-as-key / unused-param / asset-path checks (`0018 0019 0111
  0120 0121`), and a working `@uss` / `@theme` directive that preloads a Theme onto the root.
- **Live tier:** markup parse errors, unknown lowercase tags with did-you-mean, and unknown
  PascalCase components (checked against the full project universe) all squiggle while typing.
- `examples/demos/directives/` — every directive, all comment forms, `<Fragment key>`, `@uss`,
  spread-with-key; doubles as a grammar contract fixture.

### Changed
- **The compiler is fail-loud:** an error can never coexist with a successful compile; a broken
  `.guitkx` deletes its stale sibling `.gd` instead of letting the editor run code that no
  longer matches the source; the **last top-level markup return** is the component's output
  (Unity `useLastReturn` parity) and early/conditional markup returns are precise errors.
- **Embedded GDScript analysis bundles gdscript-analyzer 0.6:** Godot's verbatim 4.7 message
  texts (probed against the real binary), `Too few/many arguments` + invalid-argument errors on
  resolved calls, unreachable/unused code dims in the editor (LSP DiagnosticTags), diagnostics
  carry a real `code` + a link to the analyzer's Warning Reference, and the warning profile
  matches the engine's defaults (the `UNSAFE_*` family stays opt-in, like Godot itself).
- Names declared in sibling `.guitkx` files now feed the analyzer as **virtual libraries**
  (replacing a suppression hack) — cross-file references resolve on a fresh clone, and a typo
  colliding with a `.guitkx` name is no longer silently forgiven.

### Fixed
- The five filed silent-tooling bugs (G5–G9): unknown-tag pairs, unreachable-after-return
  flagging/dimming, the `fsunc():` typo silently accepted, the false `UNDEFINED_IDENTIFIER`
  cascade on a broken lambda initializer, and the `@for`-only missing-return miss.
- The vocabulary now loads lazily and self-heals; an unreadable vocabulary is an environment
  error (`GUITKX2507`) that **preserves** generated output instead of stale-deleting it (the
  editor's first filesystem scan used to wipe every generated `.gd` on a fresh clone).
- Parser hardening: commented `#elif` ghost branches, digit/dotted tags, unterminated attribute
  strings, directive token boundaries, `or`-fallback markup in expressions.

## [0.4.3] — 2026-07-02

Compiler indentation-anchor fixes and analyzer-ready hook typing.

### Fixed
- **One outlier setup line no longer breaks the whole generated `.gd`.** The depth-based reindenter
  anchored the block to its *shallowest* line, so a single accidentally-shallow line (say, a statement
  pasted at column 0) pushed every other line a level deeper — an over-indented statement with no
  preceding `:`, i.e. "expected an expression" plus the whole cascade of bogus follow-on errors. The
  reindenter (compiler + formatter, byte-identical with the IDE mirrors) now anchors to the **first
  non-blank, non-comment line** and clamps shallower outliers up to the body level.
- **An over-indented leading `#` comment no longer shifts real code.** Comments are legal at any
  indentation in GDScript; anchoring on one could dedent an `if` body out of its block (invalid
  generated `.gd`, and Format Document rewrote the source the same wrong way). Comments are skipped
  when picking the anchor; `_validate_hooks` uses the same anchor rule, so a shallow outlier no longer
  fakes a `GUITKX0013` "hook called conditionally" and commented-out hook calls no longer count.
- **A comment-only hook body now compiles to valid GDScript.** Comments are not statements, so the
  emitted function needed a trailing `pass`; both the top-level and module hook emitters add it.

### Added
- **`## @return-tuple(...)` doc tags on `useState`, `useReducer`, and `useTransition`.** Inert comments
  to Godot; the gdscript-analyzer (0.5.3+) reads them as fixed-shape return types, so `s := useState(0)`
  makes `s[1]` a typed, checkable `Callable` in the IDE extensions and the analyzer CLI.

## [0.4.2] — 2026-07-02

Editor-plugin reliability (shipped with IDE extensions 0.5.3).

### Fixed
- **External `.guitkx` edits recompile without restarting Godot.** The plugin recompiles on editor
  focus-in (a `.guitkx`-only external edit doesn't reliably flip Godot's `filesystem_changed`), with an
  mtime staleness guard keeping the pass cheap.
- **Errors-dock spam.** Diagnostics are de-duplicated (Godot's Errors dock is append-only) and a
  "resolved" line is printed when a previously-failing file compiles clean.

## [0.4.1] — 2026-07-02

Compiler robustness: forgiving indentation and reliable regeneration.

### Fixed
- **Mixed tabs and spaces in a component's `setup` no longer break compilation.** A line indented with,
  say, a tab + two spaces renders identically to two tabs, so the difference is invisible — yet the old
  reindenter compared indentation by raw characters and emitted GDScript with inconsistent indentation
  (an "unindent doesn't match" downstream) plus a spurious `GUITKX0013` "hook in a block". The compiler
  now measures indentation by **depth** (a tab and the inferred space-unit each count as one level), so
  mixed tabs/spaces normalize to consistent, valid GDScript. A genuine hook-in-a-block still warns.
- **Generated `.gd` now regenerate when the compiler itself changes, not only when the `.guitkx` is
  newer.** The staleness check was mtime-only, so after updating the library a sibling `.gd` that was
  newer than its source (but produced by the *old* compiler) was skipped forever — the editor kept
  loading stale output. `compile_all` now fingerprints the compiler pipeline and forces a full
  regeneration when it changes (stored in a machine-local `.godot` marker).

## [0.4.0] — 2026-07-01

Hooks go camelCase (full React parity) plus a round of compiler validation fixes.

### Breaking
- **Hooks are now camelCase, with no snake_case aliases.** `use_state`→`useState`, `use_effect`→`useEffect`,
  `use_ref`→`useRef`, `use_memo`→`useMemo`, `use_callback`→`useCallback`, `use_reducer`→`useReducer`,
  `use_context`→`useContext`, `create_context`→`createContext`, `provide_context`→`provideContext`,
  `use_layout_effect`→`useLayoutEffect`, `use_imperative_handle`→`useImperativeHandle`,
  `use_deferred_value`→`useDeferredValue`, `use_transition`→`useTransition`,
  `use_stable_callback`/`use_stable_func`/`use_stable_action`→`useStableCallback`/`useStableFunc`/`useStableAction`,
  `use_safe_area`→`useSafeArea`, `use_signal`→`useSignal`, `use_signal_key`→`useSignalKey`,
  `use_tween`→`useTween`, `use_tween_value`→`useTweenValue`, `use_animate`→`useAnimate`, `use_sfx`→`useSfx`.

- **Router hooks are camelCase too** (they were missed in the first pass) — **17 hooks on `RUIRouter`**:
  `use_navigate`→`useNavigate`, `use_location`→`useLocation`, `use_params`→`useParams`,
  `use_search_params`→`useSearchParams`, `use_blocker`→`useBlocker`, `use_query`→`useQuery`,
  `use_matches`→`useMatches`, `use_router`→`useRouter`, `use_go`/`use_can_go`→`useGo`/`useCanGo`,
  `use_navigation_state`/`use_navigation_base`→`useNavigationState`/`useNavigationBase`,
  `use_route_match`→`useRouteMatch`, `use_outlet_context`→`useOutletContext`,
  `use_resolved_path`→`useResolvedPath`, `use_location_info`→`useLocationInfo`, `use_prompt`→`usePrompt`.

  **Migration:** rename the **23 core hook tokens** and the **17 `RUIRouter.*` router hooks** (snake→camel)
  across your `.guitkx` and `.gd` files. The compiler auto-prefixes bare calls for **all 23** core hooks
  (previously only 11 auto-prefixed to `Hooks.*`); router hooks stay explicitly qualified as `RUIRouter.*`.

### Compiler
- **`@for`/`@while` bodies must contain a single root element** (`GUITKX0108`) — wrap siblings in a
  fragment `<>…</>`, matching the top-level render-root rule.
- **Duplicate keys are detected for expression keys** (`key={ str(i) }`), not only literal `key="x"`
  (`GUITKX0104`).
- **`@class_name` is validated** as a single identifier (`GUITKX0300`) instead of flowing into a broken
  generated `.gd`.
- **Misspelled declaration keywords** get a "did you mean 'component'?" hint (`GUITKX0102`).
- **`<` followed by whitespace** (e.g. `<  a>`) is reported as an invalid tag name, not silently parsed as
  a fragment.
- **Unreachable code after the markup return** is flagged (`GUITKX0114`), with line ranges so editors can
  dim it.

### Examples
- New **prop spread** and **context handle** demos in the gallery (previously feature-complete but undemoed).

### Docs
- **README refreshed** to match the library — examples and the hooks/router tables now use the camelCase
  hooks + React-style events, the pinned version is dropped, and the counts are corrected
  (**23 core hooks · 17 router hooks · ~60 `V.*` factories**).

## [0.3.0] — 2026-07-01

React-parity event handlers, prop spread, and context handles — the markup gets meaningfully closer to React.

### Runtime
- **React-style event handlers.** Wire events with camelCase names — `onClick` (→ Godot `pressed`),
  `onChange` (polymorphic: binds whichever of `item_selected` / `value_changed` / `text_changed` /
  `tab_changed` / `toggled` the control actually has), `onSubmit` (→ `text_submitted`), `onFocus` /
  `onBlur`, `onPointerDown` / `onPointerUp` / `onPointerEnter` / `onPointerLeave`, `onResize`, and any
  `onXxxYyy` → the `xxx_yyy` signal. The native `on_<signal>` spelling still works as an escape hatch to
  any Godot signal, so nothing breaks.
- **Prop spread `{...obj}`.** Spread a dictionary of props onto any element — `<Button {...cfg}
  onClick={ f } />` — exactly like React. Spreads merge with explicit props left-to-right (later wins),
  order-preserving, on both host elements and components.
- **Context handles.** `Hooks.create_context(default)` returns an `RUIContext` handle; pass it to
  `provide_context` / `use_context` instead of a bare string key to avoid cross-feature key collisions
  (the handle's object identity is the map key) and to receive a default value when no ancestor provides
  it. String keys still work (back-compat).

### IDE extensions
- **GUITKX VS Code 0.4.0 / VS 2022 0.4.0** teach the editor the React event names — completion (offered
  per control), hover showing the bound Godot signal + its arguments, signature help, unknown-attribute
  validation, and semantic highlighting — and recognize prop spread `{...obj}` in markup (highlighted,
  never flagged as unknown, preserved by the formatter).

## [0.2.2] — 2026-06-30

Custom drawing on any element, a README that finally matches the library, and a much smarter IDE.

### Runtime
- **Custom drawing.** A `draw_fn` prop (a `Callable(canvas_item)`) on any host element issues the node's
  `draw_*` calls during its `draw` signal; an optional `redraw_key` forces a repaint without changing the
  callback. A register-once trampoline reads the latest callback, so a fresh closure each render never
  re-subscribes — the Godot analogue of Unity's `OnGenerateVisualContent` / `RedrawKey`.

### Docs
- The README is rewritten to reflect the real surface — 21 hooks, ~14 router hooks, 63 `V.*` factories,
  router / signals / Suspense / item-model adapters / custom drawing / IDE tooling — instead of the old
  "MVP / 10 host elements" framing.

### IDE extensions
- **GUITKX VS Code 0.3.0 / VS 2022 0.3.0** now drive **plain `.gd`** files through gdscript-analyzer —
  diagnostics, completion, hover, navigation, project-wide rename, formatting, and semantic tokens — in
  addition to `.guitkx` markup + embedded GDScript (which gained find-references, rename, signature help,
  inlay hints, and code actions). On by default; bundles `@gdscript-analyzer/core` 0.5.2.

## [0.2.1] — 2026-06-22

A `.guitkx` toolchain fix, plus the demo gallery rewritten in markup.

### Compiler (.guitkx)
- **Hook return-type hints are preserved.** `hook foo(...) -> Array { … }` now emits
  `static func foo(...) -> Array:` instead of dropping the hint, so a caller's `var xs := foo()`
  type-inference compiles (it previously errored with "cannot infer the type of …"). Tuple-style
  `-> (a, b)` is still dropped (GDScript has no tuple type).

### Examples
- The demo gallery (`examples/`) is now authored entirely in `.guitkx` markup — one `component`
  per file (sub-components are sibling files; `module` is used only for hook / registry files),
  mirroring the ReactiveUIToolKit sample layout. The generated sibling `.gd` are git-ignored and
  regenerated by the editor plugin (and by CI before the class-cache scan).

### IDE extensions
- **Shared language server — VS Code 0.2.4 + VS 2022 0.2.4** (both bundle the same Node server, so
  these apply to both): forces tab indentation; **preserves authored blank lines** + **collapses
  embedded-GDScript whitespace** (`==␣␣␣null` → `== null`) when formatting; reports unknown elements
  (GUITKX0105) and unknown attributes (GUITKX0107) as **errors**; offers **style-dict key** +
  **built-in constant** (`Color.WHITE`) completion; forwards **go-to-definition** on GDScript symbols
  to Godot's LSP; and reads a project **`guitkx.config.json`** for formatter options.
- **VS Code only**: the 0.2.2 packaging/activation fix (the VSIX was shipping without
  `vscode-languageclient`, so the extension never activated) + format-on-save defaults + a
  self-closing-tag Enter-indentation fix (0.2.4). See `plans/IDE_EXTENSION_ISSUES.md` for the full list.

### Formatter (`guitkx_formatter.gd`)
- Mirrors the LSP formatter: preserves an authored blank line at setup-block boundaries and collapses
  runs of 2+ spaces in embedded GDScript (outside strings/comments). Byte-identical to the TS formatter.

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
