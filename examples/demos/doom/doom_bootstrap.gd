extends Control
## Faithful port of the Unity ReactiveUIToolKit `DoomGame` sample's
## `DoomGameRuntimeBootstrap.cs` -- mounts the Doom demo as its own standalone scene
## (not embedded in the gallery, per plan §1.8: it needs full-bleed rendering and
## exclusive mouse capture). Mirrors examples/app.gd's own
## ReactiveRoot.create()/.unmount() mount pattern.
##
## Phase 2 (plans/DOOM_GAME_GUITKX_PORT_PLAN.md): also owns raw input capture and
## `Input.mouse_mode` (plan §1.5) -- `.guitkx` components/hooks are plain functions,
## they can't override Godot's input virtual methods, so this real Node script is
## the only place that can see keyboard/mouse events at all. Writes into
## `DoomInputState.shared`; `doom_game_screen.hooks.guitkx`'s tick loop reads and
## consumes it once per physics frame.
##
## Two Unity-specific workarounds the original needed disappear entirely here
## (plan §1.5): Godot delivers real relative motion via `InputEventMouseMotion`
## even while `Input.mouse_mode == MOUSE_MODE_CAPTURED` (no raw-delta-via-a-
## separate-input-system hack needed), and `MOUSE_MODE_CAPTURED` both locks and
## hides the OS cursor natively (no blank-cursor-texture hack needed).

var _app: ReactiveRoot

# TEMP DIAGNOSTIC (remove after profiling): live perf HUD to read the REAL built-game
# cost split. --headless never rasterizes, so this is the only way to tell whether the
# frame is CPU-bound (TIME_PROCESS ~= frame time) or render-bound (thousands of draw
# calls / high objects). vsync is disabled here so fps shows the true ceiling, not 60.
var _perf_label: Label
var _perf_timer := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Default mouse_filter is STOP -- this full-screen Control would otherwise
	# swallow every mouse motion/click as its OWN GUI input before it ever
	# becomes "unhandled" input, so _unhandled_input below would never fire at
	# all (the same reasoning doom_game_screen.guitkx's rendered elements
	# already got IGNORE for, just missed here on the outer bootstrap node).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_app = ReactiveRoot.create(self, V.fc(DoomGameScreen.render))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_build_perf_overlay()

func _build_perf_overlay() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)
	_perf_label = Label.new()
	_perf_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	_perf_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_perf_label.add_theme_constant_override("outline_size", 4)
	_perf_label.add_theme_font_size_override("font_size", 15)
	_perf_label.position = Vector2(8, 8)
	_perf_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_perf_label)

func _process(delta: float) -> void:
	if _perf_label == null:
		return
	_perf_timer += delta
	if _perf_timer < 0.25:
		return
	_perf_timer = 0.0
	var fps := Engine.get_frames_per_second()
	var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objs := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var prims := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var frame_ms := 1000.0 / maxf(1.0, float(fps))
	# Split the CPU frame: sim (GameLogic.tick = raycast + movement + doors) vs
	# reconcile+render (the rest of process time = rebuild vnodes + diff 2384 nodes + commit).
	var tick_ms := GameLogic.last_tick_us / 1000.0
	var cast_ms := GameLogic.last_cast_us / 1000.0
	var reconcile_ms := maxf(0.0, proc_ms - tick_ms)
	var bound := "CPU-bound" if proc_ms >= frame_ms * 0.6 else "RENDER-bound"
	_perf_label.text = "FPS %d   frame %.1f ms   [%s]\nCPU process %.1f ms   physics %.1f ms\n  sim(tick) %.1f ms   (of which cast_frame %.1f ms)\n  reconcile+render ~%.1f ms\ndraw calls %d   objects %d   prims %d   nodes %d" % [
		fps, frame_ms, bound, proc_ms, phys_ms, tick_ms, cast_ms, reconcile_ms, draws, objs, prims, nodes]

func _exit_tree() -> void:
	if _app != null:
		_app.unmount()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _unhandled_input(event: InputEvent) -> void:
	var s := DoomInputState.shared
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		s.pending_yaw += motion.relative.x * DoomTypes.C.MOUSE_YAW_SENS
		# Godot's InputEventMouseMotion.relative.y is positive DOWNWARD (screen
		# coords, Y-down); Unity's Mouse.delta.y is positive UPWARD. The original
		# accumulates `pendingPitch -= d.y`, so to reproduce the same look-feel
		# under the flipped axis we accumulate `+= relative.y` (a straight port of
		# `-= relative.y` would invert the vertical axis -- that was the bug).
		s.pending_pitch += motion.relative.y
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			s.attack = true
			# Re-engage cursor lock on click (in case Escape was pressed earlier).
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			s.attack = false
		return

	if event is InputEventKey:
		var key := event as InputEventKey
		if key.echo:
			return # ignore OS key-repeat, only care about the true press/release edge
		match key.keycode:
			KEY_W, KEY_UP:
				s.forward = key.pressed
			KEY_S, KEY_DOWN:
				s.back = key.pressed
			KEY_A, KEY_LEFT:
				s.strafe_left = key.pressed
			KEY_D, KEY_RIGHT:
				s.strafe_right = key.pressed
			KEY_Q:
				s.turn_left = key.pressed
			KEY_E:
				if key.pressed:
					s.pending_use = true
			KEY_SHIFT:
				s.run = key.pressed
			KEY_SPACE:
				s.jump = key.pressed
			KEY_C:
				s.crouch = key.pressed
			KEY_1:
				if key.pressed:
					s.pending_weapon_switch = 1
			KEY_2:
				if key.pressed:
					s.pending_weapon_switch = 2
			KEY_3:
				if key.pressed:
					s.pending_weapon_switch = 3
			KEY_4:
				if key.pressed:
					s.pending_weapon_switch = 4
			KEY_5:
				if key.pressed:
					s.pending_weapon_switch = 5
			KEY_6:
				if key.pressed:
					s.pending_weapon_switch = 6
			KEY_7:
				if key.pressed:
					s.pending_weapon_switch = 7
			KEY_ESCAPE:
				if key.pressed:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Clear all held keys when the game window loses OS focus -- otherwise a key
## released while focus was elsewhere stays "down" forever. Matches the
## original's FocusOutEvent handler (there, element-focus; here, window focus,
## since input capture happens at the SceneTree level, not element level).
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		var s := DoomInputState.shared
		s.forward = false
		s.back = false
		s.strafe_left = false
		s.strafe_right = false
		s.turn_left = false
		s.run = false
		s.jump = false
		s.crouch = false
		s.attack = false
