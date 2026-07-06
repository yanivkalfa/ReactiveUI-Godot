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

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_app = ReactiveRoot.create(self, V.fc(DoomGameScreen.render))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _exit_tree() -> void:
	if _app != null:
		_app.unmount()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _unhandled_input(event: InputEvent) -> void:
	var s := DoomInputState.shared
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		s.pending_yaw += motion.relative.x * DoomTypes.C.MOUSE_YAW_SENS
		s.pending_pitch -= motion.relative.y
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
