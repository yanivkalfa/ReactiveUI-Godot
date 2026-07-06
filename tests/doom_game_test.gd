extends SceneTree
## Doom-game port (plans/DOOM_GAME_GUITKX_PORT_PLAN.md) pure-logic regression suite.
## Phase 0: doom_types.gd / doom_textures.gd / doom_maps.gd -- no reconciler/UI involved.
## Run: godot --headless --path <project> --script res://tests/doom_game_test.gd

const DOOM_DIR := "res://examples/demos/doom/"

var _fails := 0
var _passes := 0

func _initialize() -> void:
	_run()

func _ok(c: bool, m: String) -> void:
	if c:
		_passes += 1
	else:
		_fails += 1
		printerr("  FAIL: " + m)
		push_error("FAIL: " + m)

func _run() -> void:
	_test_types()
	_test_textures()
	_test_maps()
	print("\n[doom_game_test] %d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)

func _test_types() -> void:
	var map := DoomTypes.MapDef.new()
	map.width = 3
	map.height = 3
	map.name = "smoke"
	map.cells = []
	for i in range(9):
		var c := DoomTypes.Cell.new()
		c.kind = DoomTypes.CellKind.WALL if i == 0 else DoomTypes.CellKind.EMPTY
		c.floor_z = 0.0
		c.ceiling_z = 0.0
		map.cells.append(c)

	var oob := map.at_safe(-1, -1)
	_ok(oob.kind == DoomTypes.CellKind.WALL, "at_safe out-of-bounds is WALL")
	_ok(map.blocks_movement(0, 0) == true, "blocks_movement: wall cell blocks")
	_ok(map.blocks_movement(1, 0) == false, "blocks_movement: empty cell doesn't block")

	var sector_map := DoomTypes.MapData.from_tiles(map)
	_ok(sector_map.is_valid(), "from_tiles: sector map is valid")
	_ok(sector_map.sectors.size() == 8, "from_tiles: 8 non-wall cells -> 8 sectors, got %d" % sector_map.sectors.size())
	_ok(sector_map.lines.size() > 0, "from_tiles: generated linedefs")

	var gs := DoomTypes.GameState.new()
	gs.player = DoomTypes.PlayerState.new()
	gs.player.health = DoomTypes.C.START_HEALTH
	gs.mobjs = []
	gs.map = map
	gs.sector_map = sector_map
	_ok(gs.player.health == 100, "GameState/PlayerState/C constant wiring")

func _test_textures() -> void:
	DoomTextures.ensure_built()

	var walls := DoomTextures.walls()
	_ok(walls.size() == DoomTextures.W_COUNT, "walls has W_COUNT entries")
	var walls_ok := true
	for t in walls:
		if t == null:
			walls_ok = false
	_ok(walls_ok, "every wall texture is non-null")

	var floors := DoomTextures.floors()
	_ok(floors.size() == DoomTextures.F_COUNT, "floors has F_COUNT entries")

	var sprites := DoomTextures.sprites()
	_ok(sprites.size() == DoomTextures.S_COUNT, "sprites has S_COUNT entries")

	_ok(DoomTextures.sky() != null, "sky is non-null")
	_ok(DoomTextures.sky().get_width() == 512 and DoomTextures.sky().get_height() == 100, "sky is 512x100")

	_ok(DoomTextures.faces().size() == 8, "faces has 8 entries")
	_ok(DoomTextures.weapons().size() == 8, "weapons has 8 entries")

	var brick: Texture2D = walls[DoomTextures.W_BRICK_RED]
	_ok(brick.get_width() == DoomTextures.TEX_W and brick.get_height() == DoomTextures.TEX_H, "brick tex is 64x64")
	var brick_img := brick.get_image()
	var non_zero := false
	for y in range(DoomTextures.TEX_H):
		for x in range(DoomTextures.TEX_W):
			if brick_img.get_pixel(x, y).a > 0.0:
				non_zero = true
				break
		if non_zero:
			break
	_ok(non_zero, "brick texture has non-transparent pixels")

	_ok(DoomTextures.walls() == walls, "ensure_built is idempotent (same array instance)")

func _test_maps() -> void:
	var expected_names := [
		"E1M1: Hangar", "E1M2: Toxin Refinery", "E1M3: Phobos Lab",
		"E1M4: Outpost", "E1M5: Watchtower", "E1M6: Skybridge",
	]
	for level in range(1, 7):
		var ls := DoomMaps.build_level(level)
		_ok(ls != null, "level %d builds" % level)
		_ok(ls.map.name == expected_names[level - 1], "level %d name = '%s'" % [level, expected_names[level - 1]])
		_ok(ls.map.cells.size() == ls.map.width * ls.map.height, "level %d cell count matches width*height" % level)
		_ok(ls.mobjs.size() > 0, "level %d has mobjs" % level)
		_ok(ls.player_x > 0.0 and ls.player_y > 0.0, "level %d has a player start" % level)

		var bad := 0
		for c in ls.map.cells:
			if c.kind == DoomTypes.CellKind.WALL and (c.wall_tex_idx < 0 or c.wall_tex_idx >= DoomTextures.W_COUNT):
				bad += 1
		_ok(bad == 0, "level %d has no out-of-range wall texture indices" % level)

		var sector_map := DoomTypes.MapData.from_tiles(ls.map)
		_ok(sector_map.is_valid(), "level %d sector map is valid" % level)

	var l1 := DoomMaps.build_level(1)
	_ok(l1.boss_exit_gated == true, "level 1 is boss-exit-gated")
	var l2 := DoomMaps.build_level(2)
	_ok(l2.boss_exit_gated == false, "level 2 is not boss-exit-gated")

	var l6 := DoomMaps.build_level(6)
	var found_extra_floor := false
	for c in l6.map.cells:
		if c.extra_floors != null and c.extra_floors.size() > 0:
			found_extra_floor = true
			break
	_ok(found_extra_floor, "level 6 has a 3D floor (extra_floors)")

	_ok(DoomMaps.health_for(DoomTypes.MobjKind.BARON) == DoomTypes.C.HP_BARON, "health_for(BARON)")
	_ok(DoomMaps.radius_for(DoomTypes.MobjKind.CACODEMON) == 0.42, "radius_for(CACODEMON)")
	_ok(DoomMaps.height_for(DoomTypes.MobjKind.KEY_RED) == 0.35, "height_for(KEY_RED)")
