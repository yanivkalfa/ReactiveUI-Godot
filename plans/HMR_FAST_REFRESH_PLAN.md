# Phase H — Runtime Fast Refresh (HMR) for running games

**Status: PLANNED — research complete, feasibility CONFIRMED, implementation awaiting go.**
Field capture 2026-07-04: edit a `.guitkx` while the demos run under F5 → expectation is the
running UI updates ("not much of a hot reload"). Today RG has zero runtime-reload machinery —
the watcher keeps generated `.gd` fresh for the editor and the *next* run only.

**Goal (Unity parity):** save a `.guitkx` → the running game re-renders the changed components
with **hook state preserved** (a counter keeps its count while its label changes), within
~poll+compile+push latency (≈2–3 s today, dominated by the 2 s watch poll), with changed hook
*shapes* resetting state deliberately, and errors keeping the last good UI. Exported builds
carry zero HMR behavior.

---

## 1. Research findings

### 1.1 Godot facts (web-verified, 4.2–4.5 era)

- **Godot's own "Synchronize Script Changes" cannot drive this**: it only pushes reloads to the
  running game for saves made in the *built-in* script editor. Externally written files — our
  generated `.gd` — never trigger it ([godot#72825](https://github.com/godotengine/godot/issues/72825)).
  → We must own the push.
- **The debugger protocol has custom bidirectional channels**: editor side
  `EditorPlugin.add_debugger_plugin(EditorDebuggerPlugin)`, sessions via `get_sessions()` /
  `EditorDebuggerSession.is_active()`, send with `session.send_message("prefix:name", data)`
  (colon format mandatory); game side `EngineDebugger.register_message_capture("prefix", cb)`
  (receives `"name"` without the prefix) and `EngineDebugger.send_message()` for replies
  ([EditorDebuggerPlugin docs](https://docs.godotengine.org/en/stable/classes/class_editordebuggerplugin.html)).
- **In-place reload is state-friendly**: `script.reload(keep_state = true)` updates the live
  GDScript resource in place — `reload(false)` actually *errors* when instances exist. Callables
  bound to a script + method **name** (`DemoBox.render`) dispatch the **new** code after reload
  ([godot#85704](https://github.com/godotengine/godot/issues/85704) — method refs survive;
  the script resource object is unchanged, so Callable equality survives too).
- **Sharp edges**: *lambda* Callables created by the old script version can go null/stale on
  reload ([godot#85704](https://github.com/godotengine/godot/issues/85704),
  [godot#84046](https://github.com/godotengine/godot/issues/84046) — the crash there involves
  threads+deferred; we are main-thread only). Static **vars** misbehave under hot-reload
  ([godot#105667](https://github.com/godotengine/godot/issues/105667)) — our generated
  components use static **funcs** + `const` only, so this is a documented limitation, not a
  blocker. There is no engine signal for "scripts reloaded"
  ([godot-proposals#9620](https://github.com/godotengine/godot-proposals/issues/9620)) — moot,
  since we initiate the reload ourselves.

### 1.2 How Unity RUI does it (mapped from source, `Editor/HMR/` + `Shared/Core/Refresh/`)

The Unity implementation is a C# port of React Fast Refresh. Its essence:

| Concern | Unity mechanism |
|---|---|
| Code swap | In-editor Roslyn compile → new DLL → `Assembly.LoadFrom`; **Family indirection**: a stable mutable cell per component (`Family.Current`) is re-pointed by the new DLL's `[ModuleInitializer]` calling `RefreshRuntime.Register` — every consumer redirects atomically (`Family.cs:90-118`, `RefreshRuntime.cs:177-226`). |
| Identity | Family keyed by **simple type name**; reconciler compares `ReferenceEquals(fiber.Family, vnode._family)` instead of delegate equality (`FiberChildReconciliation.cs:261-298`). Rename ⇒ new family ⇒ remount. |
| State preservation | Fiber reuse ⇒ `ComponentState` is **shared, not cloned** (`FiberFactory.cs:183`). |
| State reset rule | Compile-time **hook-signature fingerprint** (`[HookSignature]`) compared on Register; changed ⇒ family queued for force-remount: effect cleanups + full hook-state clear *before* re-render (`RefreshRuntime.cs:213-224, 656-737`). Hook-file edits propagate transitively via reverse edges and trigger a **global** re-render. |
| Re-render kick | Registry of live roots (`RootRenderer.AllInstances`) → `PerformRefresh` walks trees once, refreshes each dirty fiber's render delegate, invokes its normal `OnStateUpdated` scheduling (`RefreshRuntime.cs:607-692`). |
| Errors | Failed compile ⇒ never registers ⇒ last-good body stays. Render crash after swap ⇒ **one-shot rollback** to `Family.Previous` (`FiberReconciler.cs:504-548`), else nearest ErrorBoundary. Rude edits (new static fields, renamed types) ⇒ full domain reload. |
| Gating | Everything `#if UNITY_EDITOR`; player builds carry zero refresh code. |

### 1.3 The RG runtime today (mapped from source) — what exists, what's missing

- **Identity is already Callable equality**: `RUIFiber.matches` → `component == vnode.component`
  (`fiber.gd:88-89`). With in-place reload, `DemoBox.render` Callables stay equal ⇒ fibers
  match ⇒ `fiber.state` carries over (`reconciler.gd:360`). **Unity's whole Family layer is
  unnecessary in Godot — the engine's in-place reload IS the indirection.**
- **THE BAILOUT CRUX**: matching identity + unchanged props ⇒ `_begin_function` bails to the
  cached `state.last_output` (`reconciler.gd:240-268`) — *new code would never run*.
  `request_update()` (`reconciler.gd:95-96`) marks only the ROOT fiber; pending flags don't
  propagate to children. **There is no "re-run everything" primitive — must be added.**
- **No live-root registry** (grep-verified: no static list, no groups): roots are held only by
  their owners (`app.gd:9`, `ReactiveRootNode._app`). **Must be added.**
- **No debugger channel, no autoload** (`project.godot` has no `[autoload]`). Game-side
  statics that always exist once UI mounts: `RUIConfig`, `RUIDiagnostics`, `Hooks`, etc. —
  registration can ride the first reconciler's `_init`.
- **Hook-order guard exists at runtime**: `hooks.gd` records a positional hook log, primes
  `hook_signatures` on first render, and `push_error`s on later mismatch (`hooks.gd:34-65`),
  debug-gated by `RUIConfig.enable_hook_validation`. There is **no compile-time signature** —
  but we own the compiler, so we can emit one (Unity parity).
- **The frozen root vnode is harmless**: `reconciler._root_vnode` keeps the mount-time Callable,
  which dispatches new code after in-place reload; only the bailout blocks re-execution.
- **What actually goes stale on reload**: lambdas minted by old component code (onClick
  handlers connected to live buttons) — recreated by the re-render; the reload→commit window
  must be atomic (§2.4).

**Feasibility verdict: YES.** Every Unity mechanism has a cheaper Godot counterpart; the only
new reconciler surface is a bailout-bypass + targeted dirty-marking, and the only new
infrastructure is a debugger message channel + a root registry. No engine forks, no C++.

---

## 2. Design

### 2.1 Mechanism map (Unity → Godot)

| Unity | Godot RG |
|---|---|
| Roslyn → new DLL → LoadFrom | already have: watcher compiles `.guitkx` → sibling `.gd` on disk |
| `[ModuleInitializer]` → `Family.Current` swap | `scr.source_code = FileAccess…; scr.reload(true)` — in-place, same resource |
| Family identity in reconciler | native: Callable(script, "render") equality survives reload |
| `RootRenderer.AllInstances` | **new**: static weakref registry in `RUIReconciler` |
| `PerformRefresh` dirty walk | **new**: `RUIReconciler.hmr_refresh(scripts, reset_scripts)` |
| `[HookSignature]` fingerprint | **new**: emitter writes `static func __rui_hook_sig() -> String` |
| `FullResetComponentState` | **new**: fiber state reset (cleanups + fresh `RUIComponentState`) |
| FSW + debounce (editor-side) | already have: 2 s watch poll + focus/fs triggers |
| editor→runtime: same process | **new**: `EditorDebuggerPlugin` channel `"rui_hmr:reload"` |
| `#if UNITY_EDITOR` | runtime gate: `EngineDebugger.is_active()` (+ `OS.is_debug_build()`) |

### 2.2 Editor side (plugin.gd + new `editor/hmr_debugger.gd`)

1. `RUIHmrDebuggerPlugin extends EditorDebuggerPlugin` — registered in `_enter_tree` via
   `add_debugger_plugin`, removed in `_exit_tree`. `_has_capture("rui_hmr")` handles replies
   (status lines from the game → print into the editor Output alongside the sweep lines).
2. After every sweep (`_compile_all`), collect `gd_path` of each *successfully compiled* entry
   (`res["compiled"]`), and for each `get_sessions()` session with `is_active()`:
   `session.send_message("rui_hmr:reload", [gd_paths])`. No session ⇒ no-op (zero cost).
3. Include module-hook files (`*.hooks.gd`) in the list — the game side treats them as
   global-invalidation (2.3, step 4).

### 2.3 Game side (new `core/hmr.gd` — `RUIHmr`, static; ~150 lines)

1. **Registration**: `RUIHmr.ensure_registered()` called from `RUIReconciler._init` — once per
   process, only when `EngineDebugger.is_active()`:
   `EngineDebugger.register_message_capture("rui_hmr", RUIHmr._on_message)`.
2. **Root registry**: `RUIReconciler` gains `static var _live: Array[WeakRef]`; `_init` appends,
   `unmount()` removes; `RUIHmr` prunes dead refs on use. (Core scripts are never reloaded, so
   the static is safe from the reload path.)
3. **Reload-in-place** (`_on_message("reload", [paths])`): for each path —
   - not in `ResourceLoader` cache ⇒ skip (never loaded; next `load()` reads the new file);
   - `var scr: GDScript = load(path)`; capture `old_sig` (`scr.__rui_hook_sig()` if present);
   - `var src := FileAccess.get_file_as_string(path)`; empty ⇒ skip + warn (editor race);
   - `scr.source_code = src`; `scr.reload(true)`; on error ⇒ keep old code, report back to the
     editor channel, continue with other files;
   - `sig_changed := old_sig != new_sig` → collect `(scr, sig_changed)`.
4. **Refresh**: for every live reconciler, call `hmr_refresh(changed, resets)`:
   - walk the current fiber tree once; for each FUNCTION fiber whose
     `component.get_object()` is one of the reloaded scripts: set `has_pending_update = true`
     (defeats the bailout at `reconciler.gd:256`) and, when its script's signature changed,
     **reset state first**: run effect cleanups + signal unsubscribes (the `_dispose_fiber_state`
     moves), then attach a fresh `RUIComponentState` (hook log re-primes on next render —
     `hooks.gd` needs one small addition: allow re-priming after an HMR reset).
   - a reloaded `.hooks.gd` module (no fiber references it) ⇒ mark **all** FUNCTION fibers
     pending (Unity's `TriggerGlobalReRender` parity).
   - then **flush synchronously** (schedule + immediate tick): reload and re-commit happen
     inside one debugger-message callback, so no input event can fire a stale/nulled lambda in
     between (the #85704 window). New render passes recreate every handler.
5. **Status back-channel**: after the pass, `EngineDebugger.send_message("rui_hmr:status",
   [n_reloaded, n_reset, ms])` → editor prints
   `[guitkx] hot-reloaded 2 component(s) in 14 ms (1 state reset)`.

### 2.4 Compiler addition — the hook signature (H4)

The GD emitter already validates hook calls in setup; it additionally emits:
```gdscript
static func __rui_hook_sig() -> String:
	return "useState|useState|useEffect"   # call-shape fingerprint, order-sensitive
```
- Components AND hook modules get one (module: per-hook concatenation).
- Contract goldens regenerate (mechanical, one sweep); HMR-emitter isn't a thing here (single
  GD emitter) — but `Hmr*ContractTests`-style parity is N/A (no TS emitter of `.gd`).
- v0 fallback while H4 lands: treat every reload as *non*-reset (preserve state always) and
  rely on the runtime hook-order guard to loudly `push_error` on shape changes; H4 upgrades
  that error into the deliberate Fast-Refresh reset.

### 2.5 Explicit non-goals / accepted limits (documented in the docs page)

- **Exported builds**: `EngineDebugger.is_active()` is false ⇒ HMR never registers. Zero cost.
- **Renamed components**: new class_name ⇒ different script/Callable ⇒ unmount/remount
  (state loss) — same as Unity.
- **`static var` in user modules**: values are not migrated (Godot #105667 territory);
  generated code has none today.
- **Non-component `.gd` edits** (hand-written game scripts): out of scope — this pipeline
  reloads only what the guitkx compiler emitted.
- **Runtime render-crash rollback** (Unity's one-shot `Family.Previous`): parked; the
  editor-side `gd_parse_ok` gate already blocks unparseable scripts, logic errors fall to the
  existing ERROR_BOUNDARY path. Revisit after field experience.

---

## 3. Phases

**H0 — spike (de-risk, throwaway):** scratch EditorScript + temporary autoload: prove
(a) `send_message("rui_hmr:x")` arrives in a running F5 game, (b) `source_code`+`reload(true)`
on a mounted demo component swaps behavior, (c) Callable equality + hook state survive, and
(d) a manual `has_pending_update = true` + tick re-runs the new body. *Gate: all four printed
proofs. Everything after this is plumbing.*

**H1 — editor push:** `RUIHmrDebuggerPlugin`, registration lifecycle, sweep wiring (compiled
paths only), reply printing. *Gate: running game logs receipt of the exact path list after a
save; no session ⇒ silent.*

**H2 — game runtime:** `core/hmr.gd`, root registry in `RUIReconciler`, reload-in-place with
per-file error isolation, gating. *Gate: headless unit — mount kitchen-sink, rewrite a
component `.gd` on disk, call `RUIHmr._apply` directly (no debugger), assert the label changed
and a sibling counter's state survived.*

**H3 — reconciler refresh:** `hmr_refresh(scripts, resets)` — targeted pending-marking,
bailout bypass, module-hook global path, synchronous flush. *Gate: headless — (a) targeted:
only the touched component re-renders (diagnostics counters), (b) untouched siblings bail as
usual, (c) hooks-module edit re-renders everything.*

**H4 — signature reset:** emitter `__rui_hook_sig()` (+ goldens regen), old/new comparison in
the reload step, state-reset path incl. hooks.gd re-prime. *Gate: headless — changing a
component's hook shape resets ITS state (counter back to 0) while a sibling keeps state;
unchanged shape preserves state.*

**H5 — field polish + release:** status back-channel + editor Output line, timings, docs page
("Hot reload" — capabilities + limits table), CHANGELOG; **addon 0.8.0** (minor — new
capability), demos field script. *Gate: THE acceptance — F5 the gallery, counter at 5, edit
label text in `counter.guitkx`, save: UI updates ≤ ~3 s, count still 5; break the file: last
good UI stays + dock error; fix: green resolved + refresh.*

**H6 — hardening pass:** multi-root, router demo (navigation state across refresh), rapid
successive saves (coalescing), reload while a deferred update is pending, `.hooks.gd` +
component changed in one sweep, editor restart mid-session. Bughunt then close.

Estimated shape: H0 an evening; H1–H3 the core wave; H4 emitter + goldens; H5–H6 polish.
Same methodology as every wave: one branch, one PR, research→develop→test→bughunt→fix→commit.

## 4. Risk table

| Risk | Exposure | Mitigation |
|---|---|---|
| Lambda-null window on reload (#85704) | clicks during swap | reload+re-render atomically in one message callback (no frame boundary) |
| `reload(true)` fails on weird content | broken UI | per-file isolation; editor already gd_parse_ok-gates; report + keep old code |
| Bailout bypass misses a cache | stale UI after save | H3 gate asserts re-run via diagnostics counters; `last_output` nulled on marked fibers |
| Hook-order guard fires on legit reset | error spam | H4 re-prime path; v0 documents the error as the reset signal |
| Debugger channel absent (run outside editor) | none | `is_active()` gate — feature simply off |
| Static-var user modules | silent stale values | documented limit (Godot #105667); generated code has none |
| Root registry leaks | RefCounted cycles | WeakRefs + prune on use + unregister on unmount |

## 5. Sources

- [godot#72825 — external-editor saves don't hot-reload](https://github.com/godotengine/godot/issues/72825)
- [EditorDebuggerPlugin — custom editor↔game messages](https://docs.godotengine.org/en/stable/classes/class_editordebuggerplugin.html)
- [godot#85704 — lambdas die on reload; method refs survive](https://github.com/godotengine/godot/issues/85704)
- [godot#84046 — threaded deferred lambda + hot reload crash](https://github.com/godotengine/godot/issues/84046)
- [godot#105667 — static vars under hot-reload](https://github.com/godotengine/godot/issues/105667)
- [godot-proposals#9620 — no scripts-reloaded signal](https://github.com/godotengine/godot-proposals/issues/9620)
- Unity implementation anchors: `Editor/HMR/UitkxHmrController.cs`, `UitkxHmrCompiler.cs`,
  `Shared/Core/Refresh/{RefreshRuntime,Family}.cs`, `FiberChildReconciliation.cs:261-298`,
  `FiberFactory.cs:183` (state sharing), `RefreshRuntime.cs:607-737` (refresh + reset).
- RG anchors: `fiber.gd:84-96` (identity), `reconciler.gd:240-268` (bailout), `:77-102`
  (scheduling), `:311-394` (reuse), `hooks.gd:34-65` (order guard), `component_state.gd`.
