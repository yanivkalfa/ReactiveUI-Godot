# ReactiveUI for Godot — Master Porting Plan

> ℹ️ **This is the aspirational "map" — checkboxes here are NOT a status report** (the doc is intentionally not
> updated as code lands). For LIVE status see **`PARITY_PLAN.md`** (refreshed 2026-06-30). Quick reconciliation:
> the markup is **`.guitkx`** (this doc's older `.gitkx`/`.uitkx` spellings = the same language); codegen ships
> as **sibling-`.gd` via a `@tool EditorPlugin`**, *not* the Phase 2.3 EditorImportPlugin; the core runtime is
> **~Unity parity** (PHASE_7 COMPLETE, not the Part-1 `[ ]` state shown here); and the IDE LSP uses
> **`@gdscript-analyzer/core`**, not a standalone-vs-skip decision.

> Porting **ReactiveUIToolKit** (C# / Unity UI Toolkit) to **Godot 4.x (GDScript)**.
> This is the authoritative plan; we execute against it phase by phase. No code is
> written from this document directly — it is the map.

## How to read this

- `[ ]` = not started · `[~]` = in progress · `[x]` = done.
- **Port-from:** points at the Unity source to mine for *design/algorithm* (the code is
  C#; we re-implement in GDScript — only the design transfers).
- **Divergence:** where the Godot version intentionally differs from Unity (kept in the
  [Divergence Ledger](#divergence-ledger) too).
- Unity repo root referenced as `UNITY/` = `…/UnityComponents/Assets/ReactiveUIToolKit`.
- This Godot repo root = `…/ReactiveUI/ReactiveUI-Gadot`.

## Guiding principles

1. **Parity of concepts and public API, not of code.** A developer who knows
   ReactiveUIToolKit should feel at home: `V.fc`, hooks, the same render/commit mental
   model, the same router/component ideas. The *implementation* is idiomatic GDScript.
2. **Godot-idiomatic where it matters.** Layout is container-driven; styling is
   Theme/StyleBox; there is no USS/CSS; tooling is editor-centric. We adapt, we don't
   force Unity's model onto Godot.
3. **Reach over runtime tricks.** GDScript so the whole Godot community can use it, on
   every export platform (web/mobile included). No C#.
4. **HMR is free.** Godot hot-reloads GDScript natively — we *delete* the entire HMR
   subsystem rather than port it.
5. **Small, correct, layered.** Keep the engine seam (`RUIHost` + `RUIStyle`) clean so
   the reconciler never grows Godot-specific knowledge. Every phase ships behind tests.
6. **Track divergence explicitly.** Anything that isn't a faithful port is logged so the
   two libraries can be reasoned about together (a shared *conceptual* spec, not code).

---

## Current state (the MVP — our Part 1 starting point)

Already built and **verified running in Godot 4.7** (`tests/update_test.gd` passes):

- `core/vnode.gd` (RUIVNode), `core/v.gd` (V: `fc` + 10 host elements), `core/fiber.gd` (RUIFiber).
- `core/reconciler.gd` — synchronous render + 2-phase commit, current/WIP alternates, keyed +
  positional child reconciliation, host-sibling placement (components/fragments own no node),
  child-order enforcement, deletion cleanup, **update coalescing** (1 render/frame), and
  explicit **cycle GC** (RefCounted fibers).
- `core/hooks.gd` — `use_state`, `use_reducer`, `use_ref`, `use_memo`, `use_callback`, `use_effect`.
- `core/host_config.gd` (RUIHost) — create nodes, prop diffing, `on_*` signal wiring, `ref`.
- `core/style.gd` (RUIStyle) — small declarative style → Control/Theme mapping.
- `core/reactive_root.gd` (ReactiveRoot) — mount + own the reconciler + `unmount()`.
- `examples/app.gd` + `examples/main.tscn`, `plugin.cfg`/`plugin.gd`, `README.md`.

**Known MVP simplifications to revisit in Part 1:** re-render starts from the root (no
targeted updates / bailout); effects run inline (not two-pass cleanup→setup); no context /
portals / suspense / error boundaries; ~10 elements only; minimal style vocabulary; no
router/animation/signals/diagnostics; no markup.

---

# PART 1 — Core runtime to full parity

Goal: bring the reconciler + hooks + elements + styling to feature-complete, scalable
parity with ReactiveUIToolKit's runtime (everything that makes sense on Godot).

## Phase 1.0 — Refactor the MVP for scale  (Foundation)
- [ ] Split `reconciler.gd` into focused units mirroring Unity's structure:
      `fiber_reconciler.gd`, `fiber_child_reconciliation.gd`, `fiber_function_component.gd`,
      `fiber_factory.gd`, `fiber_intrinsic_components.gd`, `commit.gd`. **Port-from:**
      `UNITY/Shared/Core/Fiber/*`.
- [ ] Introduce an explicit `HostContext` (env slots: scheduler, diagnostics, isEditor) and a
      `FiberRoot` object (container, current, WIP, pending effects). **Port-from:**
      `Shared/Core/HostContext.cs`, `Shared/Core/Fiber/FiberRoot.cs`.
- [ ] Formalize effect-tag flags (Placement/Update/Deletion/LayoutEffect/PassiveEffect/Ref).
- [ ] Test harness: build a small GDScript test runner (extend `tests/`), with snapshot-style
      assertions on the committed node tree. **Port-from:** `Shared/Core/Util/VNodeSnapshot.cs`,
      `SnapshotAssert.cs`.

## Phase 1.1 — Reconciler completeness  (Core)
- [ ] **Targeted updates + bailout.** Update from the specific fiber that changed (not the
      root); skip subtrees whose props/state/context are unchanged. Track `has_pending_state`
      + `subtree_has_updates`. **Port-from:** `FiberReconciler.ScheduleUpdateOnFiber`,
      `FiberFunctionComponent` bailout path. *Biggest perf win; the MVP's root re-render is the
      main thing to replace.*
- [ ] **Two-pass passive effects** (all cleanups, then all setups) + **layout effects**
      (`use_layout_effect`, synchronous post-commit, pre-paint). **Port-from:**
      `FiberFunctionComponent.RunPassiveEffect*`, `CommitLayoutEffects`.
- [ ] **Deferred updates during commit** (queue + replay) — guard against setState-in-commit
      corrupting the tree. **Port-from:** `FiberReconciler._deferredUpdates`. *(This is the
      family of the bug we fixed in the Unity lib — design it in from the start here.)*
- [ ] **Context**: `use_context` / a `Provider` component; change propagation marks only
      consumers dirty. **Port-from:** `Hooks.UseContext/ProvideContext`, `HostContext`.
- [ ] **Portals**: render a subtree under a different host node. **Port-from:**
      `Shared/Core/PortalContextKeys.cs`, portal handling in the reconciler.
- [ ] **Error boundaries**: catch a child render error, show a fallback, reset key.
      **Port-from:** ErrorBoundary fiber tag + `Shared/Props/Typed/ErrorBoundaryProps.cs`.
- [ ] **Suspense** (optional / lower priority): boundary that shows a fallback while an async
      child is pending. **Port-from:** `FiberIntrinsicComponents`, `FiberSuspenseSuspendException`.
      *Godot async = signals / `await`; redesign the suspension primitive.*
- [ ] **Fragments** as a first-class node (beyond "component returns Array").
- [ ] **Keyed reconciliation hardening** — mixed keyed/unkeyed lists, move detection,
      stable-vs-index edge cases. **Port-from:** `FiberChildReconciliation.cs`.

## Phase 1.2 — Full hook set  (Core)
Port all 21 hooks. **Port-from:** `Shared/Core/Hooks.cs` (2,151 lines) + `HookRegistry.cs`.
- [ ] `use_layout_effect` (1.1 dependency).
- [ ] `use_context` (1.1).
- [ ] `use_imperative_handle`, `use_deferred_value`, `use_transition` (the last two can be
      synchronous no-ops on Godot, matching Unity's behavior — no concurrent renderer).
- [ ] `use_signal` (depends on Phase 1.5 Signals).
- [ ] `use_safe_area` (Godot: `DisplayServer.get_display_safe_area()` / `get_safe_area`).
- [ ] `use_sfx` / `use_tween` (depends on Phase 1.7 Animation; Godot has native `Tween`).
- [ ] `use_ui_document_root` → Godot equivalent: resolve the mount container / viewport.
- [ ] Stable hooks family: `use_stable_func/action/callback`.
- [ ] A `HookRegistry`-style single source of truth for hook metadata (names/validation) — also
      feeds Part 2 tooling. **Port-from:** `HookRegistry.cs`.

## Phase 1.3 — Element / host-adapter system  (Core)
Replace the MVP's flat `RUIHost` with a registry + per-element adapters, like Unity.
**Port-from:** `Shared/Elements/*` (`IElementAdapter`, `BaseElementAdapter`,
`ElementRegistry`, `StatefulElementAdapter`).
- [ ] **Adapter interface + registry** — create/apply-diff/resolve-child-host per element type.
- [ ] **Simple controls** (props pass-through is mostly enough): Label, Button, LineEdit,
      TextEdit, RichTextLabel, CheckBox, CheckButton, OptionButton, LinkButton, ColorRect,
      TextureRect, NinePatchRect, ProgressBar, HSlider/VSlider, SpinBox, HSeparator/VSeparator,
      TextureProgressBar, TextureButton, TabBar.
- [ ] **Containers** (layout-aware): VBoxContainer, HBoxContainer, GridContainer,
      MarginContainer, PanelContainer, CenterContainer, ScrollContainer, TabContainer,
      HSplitContainer/VSplitContainer, FlowContainer, AspectRatioContainer, SubViewportContainer.
- [ ] **Complex / stateful controls** (need a `StatefulElementAdapter` with per-instance state,
      like Unity's ListView/TreeView/MultiColumn adapters): **ItemList**, **Tree**,
      **GraphEdit/GraphNode**, **MenuBar/PopupMenu**. These are the Godot analogues of the
      hardest Unity adapters. **Port-from:** `ListViewElementAdapter.cs`, `TreeViewElementAdapter.cs`,
      `MultiColumn*ElementAdapter.cs`, `Trackers/*` (scroll/selection/expansion preservation).
- [ ] **Drop / skip (Unity-Editor-only):** ObjectField, EnumField, Bounds/Rect/Hash128/MinMaxSlider
      inspector fields, IMGUIContainer, Foldout, HelpBox, Toolbar, PropertyInspector,
      TwoPaneSplitView, GroupBox — these are Unity-Editor IMGUI/inspector concepts. Provide Godot
      equivalents only where one exists (e.g. Foldout→a custom collapsible; SplitView→HSplitContainer).
      *Log each in the Divergence Ledger.*
- [ ] **Custom-draw escape hatch** (Unity's `onGenerateVisualContent`): map to Godot's
      `_draw()` / `RenderingServer` via a `CanvasItem` draw callback prop + a `redraw_key`.
      **Port-from:** `CUSTOM_RENDERING_PLAN.md` / `PropsApplier` GVC trampoline (Unity).

## Phase 1.4 — Styles & theming  (Core — the big redesign)
There is no USS/CSS in Godot. Build a typed, declarative style layer over Control properties,
size-flags/anchors, and Theme/StyleBox. **Port-from (design only):** `Shared/Props/Typed/Style.cs`,
`TypedPropsApplier.cs`, `BaseProps.cs`, `StyleValue.cs`.
- [ ] **Layout vocabulary** (the Godot-specific part): anchors/offsets presets, size flags
      (grow/expand/fill/shrink), min/custom size, container child overrides (h/v expand), margins.
      *This replaces flexbox — design it deliberately.*
- [ ] **Appearance vocabulary**: modulate/self-modulate, theme color/constant/font/font-size
      overrides, `StyleBox` builders (flat/texture: bg, border, corner radius, content margins),
      per-control theme-item awareness (the theme vocabulary differs per control type).
- [ ] **Named themes / variations**: support assigning a `Theme` resource + theme type variations
      (Godot's cascade analogue) for reuse beyond inline styles.
- [ ] **Typed style object + diffing infrastructure**: bitmask/dirty-set tracking so style
      diffs are cheap (port the *infrastructure* idea from Unity's 92-bit Style; the *vocabulary*
      is new). Reset-on-remove for every key.
- [ ] **Style helpers / presets** library (analogue of Unity `CssHelpers`).

## Phase 1.5 — Signals  (Core)
Reactive global state outside the component tree. **Port-from:** `Shared/Core/Signals/Signal.cs`,
`SignalsRuntime.cs`, `Hooks.UseSignal`.
- [ ] `Signal` value holder with subscribe/notify + equality gate. *(Note: name collides with
      Godot's own "signal" concept — pick a distinct public name, e.g. `Store`/`Atom`/`RUISignal`.)*
- [ ] `use_signal(store, selector, comparer)` hook → re-renders the consuming component.
- [ ] A lazy global registry (no Unity `DontDestroyOnLoad` needed; an autoload or a plain object).

## Phase 1.6 — Router  (Core)
React-Router-style routing — largely engine-agnostic, so a high-fidelity port.
**Port-from:** `Shared/Core/Router/*` (Router/Routes/Route/Outlet/NavLink/Navigate components,
RouteMatcher, RouteRanker, MemoryHistory, RouterHooks, RouterPath).
- [ ] History (memory) + `use_navigate`/`use_location`/`use_params`/`use_search_params`.
- [ ] `<Router>/<Routes>/<Route>/<Outlet>/<NavLink>/<Navigate>` (as `V.*` factories).
- [ ] Route matching + ranking (port directly — it's pure logic).
- [ ] (Carry over the *fixes* the Unity router already shipped: `<Routes>` atomicity, throwing
      on nested routers, basename, useMatches/useOutletContext.)

## Phase 1.7 — Animation  (Core)
- [ ] `use_tween` over Godot's native `Tween` (a big simplification vs Unity's custom ticker).
      **Port-from (API only):** `Shared/Core/Animation/AnimateFunc.cs`, `Easing.cs` (Godot has
      built-in easing/transition curves).
- [ ] `V.Animate`-style declarative animation node, if warranted.

## Phase 1.8 — Diagnostics & dev-experience  (Core)
- [ ] `WhyDidYouRender`-style render tracing (opt-in). **Port-from:** `Shared/Diagnostics/WhyDidYouRender.cs`.
- [ ] Render metrics (commit count, nodes touched) surfaced for debugging.
- [ ] A diagnostics config flag set. **Port-from:** `Shared/Core/Diagnostics/*`, `FiberConfig.cs`.

## Phase 1.9 — Scheduler, root, lifecycle hardening  (Core)
- [ ] Frame-budgeted scheduler with priority queues + optional time-slicing for very large
      trees (the MVP defers one render/frame). **Port-from:** `Runtime/Core/RenderScheduler.cs`,
      `IScheduler`. *Time-slicing is optional for v1 — keep the seam.*
- [ ] `ReactiveRoot` as a Node-based root option (in-scene lifecycle) in addition to the
      RefCounted one; handle viewport/container re-parenting. **Port-from:** `RootRenderer.cs`.
- [ ] Multiple independent roots in one scene.

**Part 1 exit criteria:** a counter/list/router/themed sample renders and updates correctly;
all hooks covered; ≥30 host elements; the style layer expresses real layouts; bailout works;
no per-render leaks; a green GDScript test suite.

---

# PART 2 — Markup language + IDE/editor tooling

> Strategic divergence: ReactiveUITK's tooling targets external IDEs (VS Code/VS2022/Rider)
> with a Roslyn LSP because Unity C# devs live in those editors. **Godot devs live in the
> built-in Godot script editor**, and there is no Roslyn. So Part 2 is *reconceived*, not
> ported 1:1: the primary deliverable is a Godot-native authoring path; external-IDE support
> is secondary.

## Phase 2.1 — `.gitkx` markup language spec  (Tooling)
- [ ] Define the `.gitkx` grammar (the Godot analogue of `.uitkx`): JSX-like elements,
      `{expr}` interpolation, directives (`@if/@for/@foreach` etc.), event/style attributes,
      component declaration, embedded **GDScript** (not C#) in setup/expression blocks.
      **Port-from:** the `.uitkx` grammar + `UNITY/ide-extensions~/grammar/uitkx.tmLanguage.json`,
      `uitkx-schema.json`, and the language semantics in `UNITY/ide-extensions~/language-lib/`.
- [ ] Decide embedded-language host: GDScript expressions/statements inside markup.
- [ ] Spec doc in `plans/` before implementation.

## Phase 2.2 — The compiler: `.gitkx` → GDScript  (Tooling — the core lift)
No Roslyn. Write the transpiler in **GDScript** so it is self-contained and runs inside the
Godot editor (no external toolchain). **Port-from (design):** `UNITY/SourceGenerator~/` (the
emit pipeline) and `UNITY/ide-extensions~/language-lib/` (parser/AST/formatter).
- [ ] **Lexer + parser → AST** (the front-end design transfers from language-lib; reimplement in GDScript).
- [ ] **Emitter: AST → `.gd`** (the new back-end — emit GDScript instead of C#; simpler because
      GDScript is dynamically typed, no typed-emission/overload-resolution burden).
- [ ] **Directive lowering** (`@for`/`@if`/etc. → GDScript loops/conditionals building child arrays).
- [ ] **Component model mapping** (a `.gitkx` component → a render `func(props, children)` + the
      `V.fc` wiring).
- [ ] Golden-file tests: `.gitkx` input → expected `.gd` output (mirror the Unity SG snapshot suite).

## Phase 2.3 — Godot editor integration  (Tooling — primary)
- [ ] **`EditorImportPlugin`** that compiles `.gitkx` → a generated GDScript resource on import
      (rides Godot's free hot-reload — edit `.gitkx`, save, see it update). This is the headline
      DX feature and the *reason* HMR isn't needed.
- [ ] **Syntax highlighting** for `.gitkx` in the Godot script editor (`EditorSyntaxHighlighter`).
- [ ] (Stretch) completion / go-to-component in the Godot editor via an `EditorPlugin`.
- [ ] Error surfacing: compiler diagnostics shown at import + in the editor.

## Phase 2.4 — External-editor support  (Tooling — secondary)
- [ ] **VS Code extension** for `.gitkx` (TextMate grammar + a light language server) for devs
      who edit GDScript in VS Code (godot-tools). **Port-from:** `UNITY/ide-extensions~/vscode/`,
      `grammar/`. *Reuse the grammar design; target GDScript semantics.*
- [ ] Decide whether a standalone LSP is worth it for Godot (likely lighter than the Unity
      Roslyn LSP, or skipped initially). VS2022/Rider ports are **out of scope** (Unity-IDE
      audience; not Godot's).

## Phase 2.5 — Formatter & diagnostics for `.gitkx`  (Tooling)
- [ ] A `.gitkx` formatter (idempotent). **Port-from (design):** `language-lib/Formatter/AstFormatter.cs`
      (note the idempotency lessons from the Unity formatter bugs).
- [ ] Static diagnostics (rules-of-hooks, unknown elements/attrs, prop mismatches) — reuse the
      `HookRegistry` from Phase 1.2.

**Part 2 exit criteria:** author a component in `.gitkx`, it imports to GDScript, runs, and
hot-reloads in Godot; basic editor highlighting + import error reporting work.

---

# PART 3 — Documentation

> Mirror the Unity docs site's structure where it transfers; rewrite all engine-specific content.
> **Port-from:** the Unity docs site + `UNITY/Plans~/MIGRATION_GUIDE.md`.

## Phase 3.1 — Reference docs
- [ ] API reference: `V` factories, all hooks, `RUIHost`/element list, the style vocabulary,
      router, signals, animation.
- [ ] `.gitkx` language reference (after Part 2).

## Phase 3.2 — Guides & tutorials
- [ ] Quick start (mount under a Control, first component).
- [ ] Core concepts: components/props/children, state & effects, the render/commit model.
- [ ] **Styling & layout in Godot** (the most novel guide — containers vs flex, themes, StyleBox).
- [ ] Lists & keys, context, router, signals.
- [ ] "For React / ReactiveUIToolKit devs" — concept mapping + naming differences (`V.fc`, snake_case hooks).

## Phase 3.3 — Docs site
- [ ] Stand up a docs site (reuse the Unity site's framework/structure if practical).
- [ ] Cross-link to the Unity library + the shared conceptual model.

---

# PART 4 — Samples, distribution, quality

## Phase 4.1 — Samples
- [ ] A showcase app (forms, lists, router, themed UI) — the Godot analogue of the Unity samples.
- [ ] Small focused demos per feature (counter, todo, router, signals, custom-draw).

## Phase 4.2 — Distribution & packaging
- [ ] Clean addon packaging under `addons/reactive_ui/` (no example/test code in the shipped addon).
- [ ] **Godot Asset Library** submission metadata + a GitHub release flow.
- [ ] Versioning + a CHANGELOG + a Discord-changelog mirror (reuse the Unity process). **Port-from:**
      `UNITY/Plans~/VERSIONING_PROCESS.md`, `DISCORD_CHANGELOG.md` conventions.

## Phase 4.3 — Quality & CI
- [ ] A headless GDScript test runner in CI (`godot --headless --script …`) — the pattern we
      already used for `tests/update_test.gd`.
- [ ] Reconciler/hook/style/router test suites; golden-file tests for the `.gitkx` compiler.
- [ ] A performance baseline (large list render/update) + a regression guard.

---

# Cross-cutting

## Parity & the shared conceptual model
The deep-research feasibility study concluded a **shared C# core is not viable** (GDScript).
So "shared core" lives at the **design/spec level**, not code:
- [ ] Maintain a **parity matrix** mapping each ReactiveUIToolKit feature → Godot status
      (ported / redesigned / dropped / new). Keep it current as both libraries evolve.
- [ ] Keep public API + behavior aligned so concepts transfer 1:1; document every intentional
      naming/semantic difference.

## <a id="divergence-ledger"></a>Divergence Ledger (living list)
Things that are NOT a faithful port (expand as we go):
- **HMR removed** — Godot hot-reloads GDScript natively (Part 1/2 simplification, not a gap).
- **Styling redesigned** — no USS/CSS; container layout + Theme/StyleBox vocabulary (Phase 1.4).
- **Source-gen retooled** — no Roslyn; GDScript transpiler + `EditorImportPlugin` (Part 2).
- **IDE tooling reconceived** — Godot-editor-first; VS2022/Rider dropped; LSP likely lighter/optional.
- **Unity-Editor-only adapters dropped** — ObjectField/IMGUI/inspector fields/etc. (Phase 1.3).
- **`func` reserved** — function-component factory is `V.fc`, not `V.func`.
- **Hook naming** — snake_case (`use_state`) per Godot convention vs C# `UseState`.
- **`Signal` name clash** — Godot already uses "signal"; pick a distinct public name (Phase 1.5).
- **Concurrent features no-op** — `use_transition`/`use_deferred_value` synchronous (as in Unity).

## Sequencing / dependency notes
- Part 1 is mostly linear by phase, but **1.4 (styles)** and **1.3 (elements)** can proceed in
  parallel; **1.5 (signals)** gates `use_signal`; **1.7 (animation)** gates `use_tween`.
- Part 2 depends on a stable Part-1 component API; **2.2 (compiler)** is the critical path; ship
  **API-first** (no markup) at the end of Part 1 so the runtime is usable before 2.x lands.
- Part 3/4 trail the features they document/package; start the **"styling in Godot"** guide
  early since it's the biggest conceptual delta.

## Risk register
| Risk | Phase | Severity | Mitigation |
|---|---|---|---|
| Reconciler perf over Godot Node tree at scale | 1.1/4.3 | Med | bailout + targeted updates + a perf baseline early |
| Style/layout model fights Godot containers | 1.4 | Med-High | design the layout vocabulary deliberately; lots of real-layout tests |
| `.gitkx` GDScript transpiler scope creep | 2.2 | Med-High | API-first runtime first; transpiler is additive, golden-file driven |
| Complex stateful adapters (Tree/ItemList) state loss on re-render | 1.3 | Med | port Unity's tracker pattern (scroll/selection/expansion preservation) |
| Godot editor-plugin API churn across 4.x | 2.3 | Low-Med | target current stable; isolate plugin code |
| Adoption / scope (one person, large surface) | all | Med | ship Part 1 (runtime) as a usable 0.x before Part 2/3 |

---

## Milestones (suggested)
- **0.1 (done):** MVP POC — runs in Godot 4.7.
- **0.2:** Part 1.0–1.3 — refactor + reconciler completeness + full hooks + element registry.
- **0.3:** Part 1.4–1.6 — styling, signals, router. *(Runtime feature-complete, API-first, usable.)*
- **0.4:** Part 1.7–1.9 + Part 3.2 core guides. *(Polished runtime + first docs.)*
- **0.5:** Part 2.1–2.3 — `.gitkx` compiler + Godot import plugin. *(Markup authoring.)*
- **1.0:** Part 2.4–2.5, Part 3 docs site, Part 4 samples + AssetLib + CI.
