class_name DoomInputState
extends RefCounted

## Shared, plain-script input accumulator bridging `doom_bootstrap.gd`'s
## `_unhandled_input` (the only thing that CAN see raw Godot input events --
## `.guitkx` components/hooks are plain functions, not Nodes) and the
## `use_doom_game` hook's per-tick consumption. Mirrors the Unity original's
## `inputRef`/`pendingYaw`/`pendingPitch` ref-scratch pattern (plan §1.5) --
## mutating this must NOT itself trigger a re-render, only the tick's
## `setState` call should, which is why it lives outside the reactive tree
## entirely (same reasoning as `signals_store.gd`'s "module grammar has no
## class-level static var").

static var shared := DoomInputState.new()

var forward := false
var back := false
var strafe_left := false
var strafe_right := false
var turn_left := false
var run := false
var jump := false
var crouch := false
var attack := false

# One-shot flags: set on key/click-down, consumed (and reset to false/0) by
# the next tick -- matches the original's pendingUse/pendingWeaponSwitch.
var pending_use := false
var pending_weapon_switch := 0
var pending_yaw := 0.0
var pending_pitch := 0.0

func reset() -> void:
	forward = false
	back = false
	strafe_left = false
	strafe_right = false
	turn_left = false
	run = false
	jump = false
	crouch = false
	attack = false
	pending_use = false
	pending_weapon_switch = 0
	pending_yaw = 0.0
	pending_pitch = 0.0
