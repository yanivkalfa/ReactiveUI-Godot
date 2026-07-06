extends Control
## Faithful port of the Unity ReactiveUIToolKit `DoomGame` sample's
## `DoomGameRuntimeBootstrap.cs` -- mounts the Doom demo as its own standalone scene
## (not embedded in the gallery, per plan §1.8: it needs full-bleed rendering and,
## in later phases, exclusive mouse capture). Mirrors examples/app.gd's own
## ReactiveRoot.create()/.unmount() mount pattern.
##
## Phase 1 scope: mounts a single static frame (DoomGameScreen). Input capture,
## mouse-mode toggling, and the game-tick loop are Phase 2 (plans/DOOM_GAME_GUITKX_PORT_PLAN.md).

var _app: ReactiveRoot

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_app = ReactiveRoot.create(self, V.fc(DoomGameScreen.render))

func _exit_tree() -> void:
	if _app != null:
		_app.unmount()
