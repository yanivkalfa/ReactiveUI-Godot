# DoomGame → `.guitkx` Port Plan

> **Goal:** port `ReactiveUIToolKit`'s Unity/C# `DoomGame` sample
> (`C:\Yanivs\GameDev\UnityComponents\Assets\ReactiveUIToolKit\Samples\Components\DoomGame`) — a
> full software-rendered, sector/portal-raycast Doom-style FPS with a HUD, minimap, menu, and
> in-game overlays — into a new `.guitkx` example in this repo (`examples/demos/doom/`, working
> name). **Status: research complete, nothing implemented yet.** This document is the plan; no
> code has been written. It is the single largest single feature ever proposed for this repo (the
> Unity original's simulation/render core alone — `GameLogic` + `Raycast` + `DoomMaps` + `DoomTypes`
> + `DoomTextures` — is ~4,700 lines, before any UI).
>
> Research basis: a full read of every `.guitkx` file under `examples/`, a full read of the
> `.guitkx` language surface (`hooks.gd`, `v.gd`, `router/`, `signal_store.gd`, `context.gd`,
> `media.gd`, `style.gd`, the compiler, `README.md`), and a full read of every file in the Unity
> `DoomGame` sample. See §9 for exactly what was and wasn't verified.

## 0. The one fact that shapes everything

The Unity original's "3D viewport" is not a 3D scene — it's **hundreds of absolutely-positioned
`VisualElement`s per frame**, each one a rect whose `BackgroundImage`/`BackgroundSize`/
`BackgroundPositionX`/`BackgroundPositionY` fake a texture-mapped wall/floor/ceiling strip (a
software raycaster whose "framebuffer" is the UI Toolkit retained-mode tree), all rebuilt and
diffed by the reconciler every tick.

**This is the point of porting this specific demo, not an incidental cost to engineer around.**
The explicit purpose of this port is to stress-test this library's fiber reconciler against a
real, complete game rendering several hundred live, individually keyed host elements per frame —
strictly *more* elements, and under real gameplay conditions, than the existing synthetic
benchmark in `examples/demos/stress_test/` (whose own comment calls it "a worst-case
keyed-list-churn benchmark"). **This plan does not use `draw_fn`/custom drawing for the viewport,
minimap, or anything else the original renders as real elements.** Every wall strip, floor band,
ceiling band, sprite billboard, and hitscan tracer is ported as a real, keyed host element
(`<TextureRect>`/`<ColorRect>`), reconciled through the full fiber diff every tick, exactly
mirroring the Unity original's per-`VisualElement`, `@foreach`-driven approach — see §1.1 for the
concrete host-element mapping. If this turns out to be slow, that is itself a real, valuable
finding about the library to report back, not something to quietly design around mid-port.

## 1. Key architectural decisions

These are the calls this plan makes up front, each with its reasoning, so implementation doesn't
re-litigate them mid-port.

### 1.1 Rendering: one real host element per strip/sprite/tracer, exactly like the original

Every dynamic visual in the Unity version is a real `VisualElement`, built fresh and diffed every
tick inside a keyed `@foreach`-equivalent loop. Port each one to a real Godot host element, keyed
identically, going through the full reconciler every tick — no custom drawing anywhere in the
viewport or minimap:

| Unity mechanism | Godot port (real host element, no custom draw) |
|---|---|
| `BackgroundImage` + `BackgroundSize` + `BackgroundPositionX/Y` (UV-window a texture into a rect) | `<TextureRect texture={ region_tex } position=... size=... />`, where `region_tex` is an `AtlasTexture` (`atlas` = the shared wall/floor/sky texture, `region` = the sampled sub-rect) constructed fresh per strip per tick — the direct Godot analogue of windowing a shared texture, expressed as a real resource-typed prop on a real node, not a draw call. |
| `TransformOrigin` + `Rotate` (rotated-rect hack for tracer streaks) | `<ColorRect style={ {rotation: deg, pivot: [px, py], position: [...], min_size: [...]} } />` — `style.gd` already supports `rotation`/`pivot` as inline shorthand props, so this is a direct 1:1 port of the same rotated-rect technique, not a replacement for it. |
| Flat-color rects (floor backstop, flash overlays) | `<ColorRect style={ {bg_color: ...} } />` (or the plain `color` prop) |
| Weapon sprite / muzzle flash / crosshair / pickup message | `<TextureRect>`/`<Label>` — single elements in the original too, ported as-is |

Every wall column (160 of them), every merged floor/ceiling band, every extra wall seg, every
riser-rim line, every sprite billboard, and every hitscan tracer becomes one keyed host element per
tick inside a `@for` loop, exactly mirroring `DoomGameScreen.uitkx`'s paint-order list
(`examples/demos/stress_test/`'s own keyed-`@for`-per-frame idiom is the closest existing in-repo
precedent for this technique, just at a smaller scale). `DoomGameScreenLogic` ports to
`doom_game_screen_logic.gd`, a plain-function module that builds the same per-tick lists of plain
data (position/size/texture-region/rotation per element) the original built — those lists then map
1:1 into `@for`-emitted `<TextureRect>`/`<ColorRect>` elements in `doom_game_screen.guitkx`'s
markup, not into a draw routine.

**Apply the same treatment to the minimap** (`DoomMinimap`): port its two `@foreach` loops over
cell/mobj lists as real, individually keyed small `<ColorRect>`/`<TextureRect>` elements — exactly
as many host elements as the original creates, not a custom-draw redraw.

**Open question to verify empirically in Phase 1, not decide here**: whether constructing a fresh
`AtlasTexture` resource per strip per tick (rather than Unity's approach of reusing the same shared
`Texture2D` asset and only changing position/size numbers on it) introduces a different kind of
per-frame cost in this library/Godot than the original has. Measure it during Phase 1; don't
preemptively design around it, and don't silently swap in a cheaper mechanism if it turns out
expensive — report back and decide together, since the whole point of this demo is to see how the
library actually performs under this exact load.

### 1.2 Game loop cadence: mirror the `stress_test` idiom, not the Unity scheduler

`examples/demos/stress_test/stress_test.hooks.guitkx` already establishes the house pattern for a
per-frame simulation loop inside a hook: connect to `get_tree().process_frame` inside a
`useEffect`, tick the simulation, call the state setter, and disconnect in the effect's cleanup.
This repo's own reconciler **already coalesces multiple `setState` calls to one re-render per
frame** (per this repo's `CLAUDE.md`) — which is exactly the batching problem the Unity original
had to hand-roll (`el.schedule.Execute(...).Every(16)`, chosen specifically to decouple 60Hz
simulation writes from React-style renders). **We get that for free here; do not port the manual
scheduler.** Use `get_tree().physics_frame` (fixed-timestep-ish, closer to the original's 16ms
cadence) rather than `process_frame` (variable-timestep), to keep simulation behavior
frame-rate-independent the same way the original computed `dt` from wall-clock time regardless.

Concretely, `use_doom_game(...)` (the `.guitkx` `hook` equivalent of `useDoomGame`) does:
- `useRef` for the mutable `GameState` (the "live" copy mutated every tick, mirroring the Unity
  version's `stateRef`/`inputRef` scratch-refs-not-state pattern — ref mutation doesn't trigger
  re-renders, only the periodic setter call does).
- `useState<GameState>` (or a `RUISignal`, see §1.3) for the "committed" copy the render reads.
- `useEffect(effect, [])` connecting `get_tree().physics_frame`, calling `GameLogic.tick(state,
  dt, input_cmd)` (mutating in place — see §1.6), then calling the setter with the same reference
  (since GDScript objects are reference types, no need for the Unity version's defensive
  `.Clone()`-then-replace dance — see §1.6) to trigger the coalesced re-render.

### 1.3 State shape: a shared mutable `GameState` object, no `RUISignal` needed

The Unity original uses **no cross-component store at all** — 100% prop-drilling of one
monolithic `GameState` value, held inside the `useDoomGame` hook and passed down explicitly.
That's a deliberate, working pattern already, and this port keeps it: `DoomGameScreen` calls
`use_doom_game(...)`, gets back `state` + a `restart` callable + input-forwarding callables, and
passes `state` (whole object) into `<DoomMinimap state={state}/>`, and destructured fields into
`<DoomHud .../>` — exactly mirroring the original's prop shape. **`RUISignal`/`RUISignals` (the
house pattern for cross-tree state seen in `examples/demos/signals/`) is not needed here** because
there's no "gameplay code outside the UI tree" in this port — the entire simulation lives inside
the hook, same as the Unity reference. Don't introduce a signal store speculatively; it would add
indirection with no benefit over passing `state` down, and would diverge from the reference
architecture for no reason.

### 1.4 Struct → class, `ref` → plain reference semantics

C# `struct GameState`/`PlayerState`/`Mobj`/`Cell`/`Sector`/etc., passed by `ref` through
`GameLogic.Tick(ref GameState, ...)`, become plain GDScript classes (`extends RefCounted`) with
typed fields, living in a plain-script module `doom_types.gd` (not `.guitkx` — pure data, same
"plain-script escape hatch" convention already used for `signals_store.gd`/`accent_context.gd`/
`styling.style.gd`). Since GDScript objects are already reference types, `GameLogic.tick(state:
GameState, dt: float, cmd: InputCmd) -> void` mutating `state` in place needs **no `ref` keyword
and no defensive `.duplicate()`/`.Clone()` dance** the C# version needed to avoid struct-copy
aliasing bugs — this is a straightforward simplification, not just a mechanical rename. Keep the
same nested shape (`state.player.health`, `state.frame.columns[i].main`, `state.map.cells[...]`)
rather than introducing accessor methods, so the port stays a faithful line-by-line reference
against the original during implementation and review.

`Mobj` pool: port the fixed-capacity array + `id == 0` sentinel-for-free-slot pattern verbatim —
it's engine-agnostic and already correct.

### 1.5 Input: simpler than the original, not just "ported"

Two Unity-specific workarounds disappear entirely rather than needing a Godot equivalent:

- **Raw mouse deltas**: the original bypasses UI Toolkit's `PointerMoveEvent` (which zeroes under
  cursor lock) via `UnityEngine.InputSystem.Mouse.current.delta` / `InputSystem.onAfterUpdate`,
  with a long documented justification. **Godot delivers real relative motion through
  `InputEventMouseMotion.relative` even while `Input.mouse_mode == Input.MOUSE_MODE_CAPTURED`** —
  the workaround's entire reason to exist goes away. Read mouse look directly from
  `InputEventMouseMotion` in the input handler below.
- **Cursor lock/hide**: the original hand-builds a 32×32 near-transparent `Texture2D` because
  `style.cursor` is a documented no-op through the JSX `style=` prop, plus separate OS-specific
  alpha/size/readback quirks. **`Input.mouse_mode = Input.MOUSE_MODE_CAPTURED` both locks and hides
  the OS cursor natively** in Godot — the entire hack is unnecessary. Preserve the *behavior*
  (captured+hidden while playing; released on Escape/death/victory; re-captured on click), not the
  mechanism.

**Where does input get read?** `.guitkx` components/hooks are plain functions, not Node subclasses
— they can't override `_input`/`_unhandled_input`. The bootstrap script that mounts the tree
(§1.7) is a real `Control` script and *can* override it. Recommended split, mirroring the Unity
version's own separation of "raw event capture" from "per-tick consumption":
- The bootstrap script's `_unhandled_input(event)` (or `_input`, if the viewport needs first
  crack before any other UI) accumulates held-keys, mouse delta, and click/use edges into a
  shared, plain `RefCounted` `DoomInputState` object (not a `RUISignal` — same reasoning the
  original used `useRef` for input accumulation: this must not itself trigger re-renders on every
  mouse-delta write, only the tick's periodic setter call should).
- `use_doom_game`'s tick callback reads-and-consumes that shared object once per physics frame,
  exactly mirroring the original's `inputRef`/`pendingYaw`/`pendingPitch` ref-scratch pattern.
- Mouse mode (`Input.mouse_mode`) is toggled from the same bootstrap script (on game-start,
  Escape, death, victory) — the hook can request this via a callback passed down or a tiny shared
  flag on the same `DoomInputState` object, whichever proves simpler at implementation time.

### 1.6 RNG: one deterministic source, fixing a pre-existing inconsistency

The Unity original uses a deterministic seeded LCG (`Frand`, seeded from `GameState.RngSeed`) for
gameplay-affecting randomness (AI pain-chance, hitscan spread) but **also** one stray
`UnityEngine.Random.value` call (face-timer jitter) — a real, if minor, existing inconsistency.
Port `Frand` verbatim (it's simple, engine-agnostic, and already deterministic) and use it
**everywhere**, including face-timer jitter — this both ports faithfully and fixes a
pre-existing bug, worth calling out as an intentional deviation in the eventual PR description.

### 1.7 Screens: `useState` switch, no router needed for MVP

Two top-level screens (`menu`/`game`), switched by a `useState` in a `DoomGame`-equivalent root
component via `@if`/`@else` — exactly the Unity original, and directly analogous to this repo's
own `gallery.guitkx` sidebar-switch pattern. `RUIRouter` (17 hooks, full React-Router-v6 parity —
see `examples/demos/router/`) is available and would work, but the Unity reference doesn't use
one either (no router-equivalent exists in ReactiveUIToolKit's C# API surface used here), and two
screens plus two same-screen overlays (`GameOver`/`Victory`, both just `@if` blocks inside the
game screen) is proportionate to a plain `useState` switch. **Not a rejection of `RUIRouter`** —
if a later milestone wants a real Options/Settings flow (video/audio/controls tabs), adopting the
router then is a reasonable, isolated follow-up; don't pull it in speculatively now.

### 1.8 Mounting: its own scene, not a gallery pane

The gallery shell (`gallery.guitkx`) assumes an embedded, non-fullscreen, non-mouse-capturing pane
alongside a sidebar. This port needs full-bleed rendering and exclusive mouse capture — a poor fit
for that shell. Recommended: a **dedicated example scene**, `examples/demos/doom/doom.tscn` +
`doom_bootstrap.gd` (mirrors `examples/app.gd`'s `ReactiveRoot.create(self, V.fc(DoomGame.render))`
/ `.unmount()` pattern exactly), run standalone rather than through the gallery's sidebar
navigation — the same relationship `examples/guitkx/Counter.guitkx` already has to the main
gallery (present in the repo, not routed through it). Optionally add a gallery-table entry
(`gallery_table.guitkx`) that's just a launcher button/description pointing at running the
dedicated scene, if discoverability from the gallery matters — this is a nice-to-have, not a
blocker, and is an open question for the repo owner (§10).

## 2. File-by-file port map

| Unity file | Port target | Kind | Notes |
|---|---|---|---|
| `DoomGameRuntimeBootstrap.cs` | `examples/demos/doom/doom_bootstrap.gd` + `doom.tscn` | plain `Control` script | Mount (`ReactiveRoot.create`), raw input capture (`_unhandled_input`), `Input.mouse_mode` toggling. See §1.5, §1.8. |
| `DoomGame.uitkx` | `doom_game.guitkx` | `component` | Screen switch (`menu`/`game`), `level`/`difficulty`/`session_version` state — 1:1 port. |
| `DoomMainMenu.uitkx` | `doom_main_menu.guitkx` | `component` | Fully controlled/presentational — 1:1 port, no local state. |
| `DoomGameScreen.uitkx` | `doom_game_screen.guitkx` | `component` | Restart-on-prop-change via `useRef` compare (1:1 idiom, GDScript supports it identically); hosts the real per-strip/sprite/tracer `@for`-emitted viewport elements (§1.1) plus declarative overlays/HUD/minimap. |
| `DoomGameScreen.hooks.uitkx` | `doom_game_screen.hooks.guitkx` | `module` + `hook` | Direct analogue of `stress_test.hooks.guitkx`'s `module { hook use_x(...) -> T { Hooks.useX(...) } }` pattern — this is the one file in the port with a proven house-idiom template to copy almost verbatim in structure. See §1.2, §1.5. |
| `DoomGameScreenLogic.uitkx` | `doom_game_screen_logic.gd` | plain `.gd` (not `.guitkx`) | Pure geometry/list-building functions, no hook calls — doesn't need the `module`/`hook` grammar; a plain script is simpler and compiles faster. Feeds the `@for`-emitted real host elements in `doom_game_screen.guitkx` (§1.1), exactly as the original fed its `@foreach` markup. |
| `DoomHUD.uitkx` | `doom_hud.guitkx` | `component` | 1:1 port — stays declarative markup (§1.1). The `KeyDot(...)`-returns-a-`VirtualNode` local-helper idiom ports directly (GDScript closures/local funcs can return `RUIVNode`s the same way). |
| `DoomFace.uitkx` | `doom_face.guitkx` | `component` | 1:1 port, single element. |
| `DoomMinimap.uitkx` | `doom_minimap.guitkx` | `component` | Port the two `@foreach` loops as real, individually keyed small `<ColorRect>`/`<TextureRect>` elements (§1.1) — same component boundary/props (`state`), same element count as the original. |
| `DoomTypes.uitkx` | `doom_types.gd` | plain `.gd` | Enums → GDScript `enum`; structs → `class X extends RefCounted` with typed fields (§1.4); `static class C` constants → `class C: extends RefCounted` (or a plain top-level `const`/`static var` block) of the same ~70 tunables. |
| `DoomTextures.uitkx` | `doom_textures.gd` | plain `.gd` | `Texture2D`/`SetPixels32`/`Apply` → `Image.create(...)`/`image.set_pixel(...)`/`ImageTexture.create_from_image(image)`; `FilterMode.Point` → `texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST` set as a style prop on each `<TextureRect>` element (or once via a project default — verify exact Godot 4.7 API name/mechanism at implementation time, this plan is not a substitute for reading the engine docs live). Vertical pixel-buffer flip may or may not be needed — `AtlasTexture`'s region coordinate convention should be checked empirically rather than assumed identical to Unity's. |
| `DoomMaps.uitkx` | `doom_maps.gd` | plain `.gd` | `MapBuilder` fluent DSL + the 6 levels (`E1M1`–`E1M6`) — porting is mechanical (no Unity API dependency in the level data itself). |
| `GameLogic.uitkx` | `game_logic.gd` | plain `.gd` | The simulation + raycasting-renderer core (~1,944 lines in the original — expect similar scale here). Pure math/state-machine logic, `Vector2`/`Mathf` → Godot `Vector2`/`@GlobalScope` math functions — mechanically portable, high line-count, low conceptual risk. `ref GameState` → plain mutation (§1.4/§1.6). |
| `Raycast.uitkx` | `raycast.gd` | plain `.gd` | Portal-walking ray/segment/sector math — pure `Vector2` geometry, no engine dependency once off `UnityEngine.Vector2`; low risk. |

No Unity file has **no** port target — every piece of the original maps onto something concrete above.

## 3. Phased implementation plan

Recommended as **one feature branch** (`feat/doom-guitkx-port` or similar), following this repo's
`dev-process` methodology (research → develop → test → bughunt → fix → commit → repeat), but with
commits per milestone below — not one giant commit — mirroring how the VS2022 parity campaign
was run (many commits, phases marked done incrementally, one PR at the end). Given the size,
expect this to span multiple sessions; each phase below is independently demoable so progress is
always visible and testable, not a big-bang integration at the end.

- [ ] **Phase 0 — Data + textures, no rendering.** Port `doom_types.gd`, `doom_textures.gd`,
  `doom_maps.gd` (§2). Verification: a headless GDScript test script that calls
  `DoomTextures.ensure_built()` and asserts every expected texture key exists and is non-null, and
  that `DoomMaps.build_level(n)` returns a sane map for all 6 levels. No UI yet.
- [ ] **Phase 1 — Static frame, no game loop.** Port `raycast.gd` and enough of `game_logic.gd`
  (`new_game`, `cast_frame`/`build_column_sector`) to render one static frame from a fixed player
  position/angle. Build `doom_game_screen_logic.gd` and the real per-strip `@for`-emitted markup in
  `doom_game_screen.guitkx` (§1.1). Verification: **run it in the Godot editor and visually
  confirm** a level renders correctly (walls/floors/ceilings/sky, no game loop, no input) — this is
  the riskiest single milestone (validates the entire §1.1 rendering approach, both visually and,
  informally, in terms of how the editor feels running it) and should be de-risked before anything
  else is built on top of it. Also a first, informal read on reconciler cost under this element
  count — not yet at full tick rate/game-loop load (that's Phase 2), but worth noting.
- [ ] **Phase 2 — Input + movement + the tick loop.** Port the input-capture split (§1.5), the
  `doom_game_screen.hooks.guitkx` tick loop (§1.2), and `game_logic.gd`'s player movement/physics
  (WASD, mouse-look, gravity/jump/crouch, step-up, collision). Verification: walk around a level
  in the editor; mouse-look and movement feel right; cursor captures/releases correctly.
- [ ] **Phase 3 — Combat, AI, pickups, doors.** Port weapons (melee/hitscan/projectile), monster
  AI (`UpdateMonster`, line-of-sight, chase/attack states), damage (`DamageMobj`/`Hurt`, splash,
  barrel chain reactions), pickups (`TryGivePickup`), and the door FSM. Verification: fight
  monsters, take/deal damage, pick up items, open doors, across at least 2 of the 6 levels.
- [ ] **Phase 4 — HUD, face, minimap.** Port `doom_hud.guitkx`, `doom_face.guitkx`,
  `doom_minimap.guitkx` (real keyed elements per §1.1, same element count as the original).
  Verification: HUD numbers track real game state; face reacts to health/hurt/god-mode/death;
  minimap shows player position correctly.
- [ ] **Phase 5 — Menu + screen flow + overlays.** Port `doom_main_menu.guitkx`, `doom_game.guitkx`
  (screen switch, restart/next-level session-version bump), game-over/victory overlays.
  Verification: full loop — menu → play → die/win → back to menu or next level — across all 6
  levels, no dead ends.
- [ ] **Phase 6 — Polish / deviations from the reference.** Fix the RNG inconsistency (§1.6)
  everywhere. Decide whether to add audio (the Unity original has **none** — see §9 — so this is
  a genuinely new addition, not a port; `useSfx` exists and is documented but has zero existing
  in-repo example to copy from, so budget real prototyping time if pursued, not just a mechanical
  port). Decide whether to add `useTween`/`useAnimate` for flashes/bob instead of the original's
  raw-math-into-style-every-frame approach (also a deviation, not a port — the original does no
  tweening at all). Gallery-table discoverability entry, if wanted (§1.8).

## 4. Testing & verification plan

Matching this repo's existing conventions (`CLAUDE.md`, `.github/workflows/test.yml`):

- **Compile-correctness is free**: `tests/guitkx_build.gd` will compile every new `.guitkx` file
  automatically as part of the existing CI sweep — no extra setup needed for that layer.
- **New pure-logic regression suite**: `tests/doom_game_test.gd`, headless, exercising
  `GameLogic.new_game`/`tick` directly (no reconciler/UI involved) with synthetic `InputCmd`s —
  e.g. "after N ticks of forward-move input, player position changed as expected and stayed within
  map bounds," "a hitscan attack against a monster in `AIState.Idle` at point-blank range reduces
  its health," "a rocket splash within radius damages the player." This is the layer that can
  actually assert simulation correctness headlessly.
- **Render-smoke coverage**: add one entry to `tests/demos_test.gd`'s existing "renders every
  demo" sweep — mount `DoomGame`'s menu screen (not the live game loop) and assert it renders
  without error, consistent with how every other demo is covered there.
- **What CANNOT be verified headlessly**: raycasting visual fidelity (are the walls/floors/sky
  actually painted correctly, does the minimap look right, does the HUD layout look right) —
  this needs manual play-testing in the Godot editor, called out explicitly per phase above.
  Accept this as a known limitation of headless CI for this particular feature, same as the
  repo's existing `demos_test.gd` disclaimer that it checks "render without error," not visual
  correctness.
- Given this is explicitly meant to stress the reconciler, also add a `tests/doom_game_bench.gd`
  (matching the repo's existing `bench*.gd`/`microbench.gd` convention, not pass/fail) that
  measures full-tick reconciliation cost (several hundred keyed host elements rebuilt/diffed) once
  Phase 1 lands, and track it across phases — this is the closest thing to a real answer to "how
  does the library handle this many elements," which is the actual point of this port.

## 5. Unity-specific concerns already resolved by the decisions above

Recapping §1 concisely, since these were the highest-risk items the Unity research surfaced:

1. Software-3D-via-styled-elements → ported as real `<TextureRect>`/`<ColorRect>` host elements,
   one per strip/sprite/tracer, reconciled every tick exactly like the original's `VisualElement`s
   (§1.1) — **this is the demo's whole point, not a risk to resolve away; Phase 1 exists to
   observe how it actually performs, not to pick a cheaper alternative.**
2. `InputSystem.onAfterUpdate` raw-delta workaround → unnecessary; Godot delivers real relative
   motion under mouse capture (§1.5).
3. Blank-cursor-texture hack → unnecessary; `Input.mouse_mode = MOUSE_MODE_CAPTURED` (§1.5).
4. `el.schedule.Execute(...).Every(16)` manual batching → unnecessary; this repo's reconciler
   already coalesces to one render/frame (§1.2).
5. `UnityEngine.Random` vs `Frand` inconsistency → one deterministic LCG everywhere (§1.6).
6. `Texture2D`/`SetPixels32` → `Image`/`ImageTexture` (§2, `doom_textures.gd` row) — mechanical,
   needs a line-by-line rewrite of ~15 generator functions but no architectural risk.
7. C# struct/`ref` value semantics → plain GDScript reference-type classes, actually **simpler**
   than the original, not just different (§1.4).
8. `PickingMode.Ignore` → `mouse_filter = MOUSE_FILTER_IGNORE` (direct 1:1 analogue, no further
   design needed — apply everywhere the original uses it: minimap, decorative overlay elements).
9. Capture-phase keyboard handling (`onKeyDownCapture`, UI-Toolkit-specific event phases) →
   resolved by moving input capture to the bootstrap script's `_unhandled_input` (§1.5) rather
   than trying to replicate UI Toolkit's capture/bubble model inside `.guitkx` markup.

## 6. Explicit deviations from the Unity reference (not gaps — decisions)

- RNG consolidated to one deterministic source (§1.6) — original has a minor inconsistency.
- No audio in scope by default — original has none either; adding any would be a genuinely new
  feature, not a port (§3, Phase 6).
- No tween/animation library calls in scope by default — original does none either (all "animation"
  is per-frame math baked into style values, which ports directly); `useTween`/`useAnimate` are
  available as an optional Phase 6 enhancement, not required for parity.
- None planned for the viewport/minimap rendering approach — it's a deliberate 1:1 port of the
  original's per-element technique (§1.1, §0), not an area to deviate in.

## 7. Risks

- **Performance risk (highest, and intentional)**: §1.1 deliberately reconciles several hundred
  keyed host elements every tick — more, and under more varied real-gameplay conditions, than any
  existing demo in this repo (`examples/demos/stress_test/` is the closest precedent, at smaller
  scale). This is the entire reason to port this specific demo: to find out how the fiber
  reconciler actually performs under this load. If it's slow, that's a real finding to report and
  discuss, not a defect to quietly engineer around by falling back to custom drawing or reducing
  element counts. Phase 1 (§3) is the first checkpoint to observe this, and `tests/doom_game_bench.gd`
  (§4) exists to keep measuring it as later phases add load (AI, more sprites, more tracers).
- **Scale risk**: `game_logic.gd` alone is ~1,900+ lines of dense simulation/rendering math in the
  original; this is a large, multi-session port by nature, not a quick feature. The phased plan
  (§3) exists to keep it demoable and reviewable incrementally rather than one enormous PR.
- **Texture coordinate-convention risk**: the Unity version's documented vertical pixel-buffer flip
  (`DoomTextures.Apply()`) is a Unity/UI-Toolkit-specific texture-coordinate quirk; whether an
  `AtlasTexture`'s `region` needs an equivalent flip when windowing into the generated `Image`
  should be verified empirically in Phase 0/1, not assumed either way.
- **Per-tick `AtlasTexture` allocation cost** (§1.1): unlike Unity's approach (reposition the same
  shared `Texture2D` asset via numeric style props), this port constructs a fresh `AtlasTexture`
  resource per strip per tick, since each strip's sampled region changes every frame and multiple
  strips can't safely share one mutable `AtlasTexture` instance within the same frame (aliasing —
  see §1.1's open question). This is a real, possibly-nontrivial allocation cost the original
  doesn't have; measure it, don't assume it away.
- **`texture_filter` API surface**: this plan names `CanvasItem.TEXTURE_FILTER_NEAREST` from
  general Godot 4 knowledge, not from a source read in this repo or the engine docs — confirm the
  exact property/enum name against the installed Godot 4.7 API at implementation time.
- **No audio/tween reference to copy**: if Phase 6 adds `useSfx`/`useTween`/`useAnimate`, there is
  no existing `.guitkx` example exercising them under real load (only `tween.guitkx`'s simple
  single-node demo) — budget real prototyping time, not a mechanical port.

## 8. Open questions for the repo owner

1. **Discoverability** (§1.8): standalone scene only, or also add a gallery-table launcher entry?
2. **Branch/PR granularity**: one branch/PR for the whole port (this plan's default assumption,
   matching the VS2022 parity precedent), or split into multiple smaller PRs per phase given the
   size? The single-branch approach risks a very large, slow-to-review PR; splitting risks
   half-finished, non-demoable intermediate states landing on `dev`.
3. **Phase 6 scope**: pursue audio/tween additions in this same effort, or ship a faithful port
   first (no audio, no tweening, matching the Unity reference exactly) and treat audio/animation
   as a clearly-separate follow-up feature?
4. **Level scope**: port all 6 levels up front, or get end-to-end working on 1–2 levels first
   (Phase 3/5) and treat the remaining levels as a fast final step once the engine is proven (since
   the level data itself, per §2, is low-risk/mechanical once `MapBuilder` exists)?

## 9. What this research did and didn't verify

Did: read every `.guitkx` file under `examples/` in full; read `hooks.gd`, `v.gd`, `signal_store.gd`,
`signal_registry.gd`, `context.gd`, `media.gd`, `style.gd`, `style_sheet.gd`, `suspense.gd`,
`reactive_root.gd`, `reactive_root_node.gd`, `host_config.gd`, `router/router.gd`, `router/history.gd`,
`guitkx_markup.gd`, most of `guitkx.gd`, `guitkx_vocabulary.gen.gd`, and root `README.md` in full;
read every file (all `.cs`/`.uitkx`) under the Unity `DoomGame` sample folder in full.

Did not: run any Godot code for this feature (nothing has been implemented yet — this is a plan
only); verify exact Godot 4.7 `CanvasItem`/`Image`/`ImageTexture` API names beyond general
knowledge (flagged in §7); confirm whether ReactiveUIToolKit's C# API has a `Signal`/store
mechanism used in *other* Unity samples beyond this one (irrelevant to the port either way, per
§1.3, but noted as unconfirmed rather than asserted).
