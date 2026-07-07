class_name DoomMaps
extends RefCounted

## Faithful port of the Unity ReactiveUIToolKit `DoomGame` sample's `DoomMaps.uitkx` --
## the fluent MapBuilder DSL + the 6 hand-authored levels (E1M1-E1M6). Pure data/logic,
## no engine dependency, so this is a plain script rather than `.guitkx`.
## See plans/DOOM_GAME_GUITKX_PORT_PLAN.md.

class LevelStart extends RefCounted:
	var map: DoomTypes.MapDef
	var player_x: float
	var player_y: float
	var player_angle: float
	var mobjs: Array # of DoomTypes.Mobj
	# When true, this level's Exit cells will only fire victory once every
	# boss-tier monster (Baron, Cacodemon) is dead.
	var boss_exit_gated: bool

class MapBuilder extends RefCounted:
	var w: int
	var h: int
	var cells: Array # of DoomTypes.Cell
	var map_name: String
	var mobjs: Array = [] # of DoomTypes.Mobj
	var px: float
	var py: float
	var p_ang: float
	var boss_exit_gated: bool = false

	func _init(width: int, height: int, level_name: String) -> void:
		w = width
		h = height
		map_name = level_name
		cells = []
		cells.resize(w * h)
		for i in range(cells.size()):
			var c := DoomTypes.Cell.new()
			c.kind = DoomTypes.CellKind.EMPTY
			c.wall_tex_idx = DoomTextures.W_BRICK_GREY
			c.floor_tex_idx = DoomTextures.F_CONCRETE
			c.ceiling_tex_idx = DoomTextures.F_CONCRETE
			c.light_level = 200
			cells[i] = c

	func at(x: int, y: int) -> DoomTypes.Cell:
		return cells[y * w + x]

	func border(wall_tex: int) -> MapBuilder:
		for x in range(w):
			var top := at(x, 0)
			top.kind = DoomTypes.CellKind.WALL
			top.wall_tex_idx = wall_tex
			var bot := at(x, h - 1)
			bot.kind = DoomTypes.CellKind.WALL
			bot.wall_tex_idx = wall_tex
		for y in range(h):
			var l := at(0, y)
			l.kind = DoomTypes.CellKind.WALL
			l.wall_tex_idx = wall_tex
			var r := at(w - 1, y)
			r.kind = DoomTypes.CellKind.WALL
			r.wall_tex_idx = wall_tex
		return self

	func fill(x0: int, y0: int, x1: int, y1: int, floor_tex: int, ceil_tex: int, light: int) -> MapBuilder:
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				if x < 0 or x >= w or y < 0 or y >= h:
					continue
				var c := at(x, y)
				c.kind = DoomTypes.CellKind.EMPTY
				c.floor_tex_idx = floor_tex
				c.ceiling_tex_idx = ceil_tex
				c.light_level = light
				c.is_sky = false # explicit fill = not outdoors
		return self

	func box(x0: int, y0: int, x1: int, y1: int, wall_tex: int) -> MapBuilder:
		for x in range(x0, x1 + 1):
			if x >= 0 and x < w:
				if y0 >= 0 and y0 < h:
					var c := at(x, y0)
					c.kind = DoomTypes.CellKind.WALL
					c.wall_tex_idx = wall_tex
				if y1 >= 0 and y1 < h:
					var c2 := at(x, y1)
					c2.kind = DoomTypes.CellKind.WALL
					c2.wall_tex_idx = wall_tex
		for y in range(y0, y1 + 1):
			if y >= 0 and y < h:
				if x0 >= 0 and x0 < w:
					var c := at(x0, y)
					c.kind = DoomTypes.CellKind.WALL
					c.wall_tex_idx = wall_tex
				if x1 >= 0 and x1 < w:
					var c2 := at(x1, y)
					c2.kind = DoomTypes.CellKind.WALL
					c2.wall_tex_idx = wall_tex
		return self

	func wall(x: int, y: int, wall_tex: int) -> MapBuilder:
		if x < 0 or x >= w or y < 0 or y >= h:
			return self
		var c := at(x, y)
		c.kind = DoomTypes.CellKind.WALL
		c.wall_tex_idx = wall_tex
		return self

	func door(x: int, y: int, kind: int = DoomTypes.CellKind.DOOR) -> MapBuilder:
		if x < 0 or x >= w or y < 0 or y >= h:
			return self
		var c := at(x, y)
		c.kind = kind
		if kind == DoomTypes.CellKind.DOOR_BLUE:
			c.wall_tex_idx = DoomTextures.W_DOOR_BLUE
		elif kind == DoomTypes.CellKind.DOOR_YELLOW:
			c.wall_tex_idx = DoomTextures.W_DOOR_YELLOW
		elif kind == DoomTypes.CellKind.DOOR_RED:
			c.wall_tex_idx = DoomTextures.W_DOOR_RED
		else:
			c.wall_tex_idx = DoomTextures.W_DOOR
		c.door_state = 0
		c.door_timer = 0
		return self

	func exit(x: int, y: int) -> MapBuilder:
		if x < 0 or x >= w or y < 0 or y >= h:
			return self
		var c := at(x, y)
		c.kind = DoomTypes.CellKind.EXIT
		c.wall_tex_idx = DoomTextures.W_EXIT
		return self

	# Walkable exit pad -- same trigger semantics as exit() but the cell
	# renders as plain floor (no EXIT-sign wall block). The blue floor
	# texture is the visual cue.
	func exit_pad(x: int, y: int) -> MapBuilder:
		if x < 0 or x >= w or y < 0 or y >= h:
			return self
		var c := at(x, y)
		c.kind = DoomTypes.CellKind.EXIT
		c.wall_tex_idx = 0
		c.floor_tex_idx = DoomTextures.F_BLUE
		return self

	func liquid(x0: int, y0: int, x1: int, y1: int, tex: int) -> MapBuilder:
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				if x < 0 or x >= w or y < 0 or y >= h:
					continue
				var c := at(x, y)
				c.kind = DoomTypes.CellKind.LIQUID
				c.floor_tex_idx = tex
		return self

	# Phase 7 (original): raised platform / step. Sets per-cell floor_z on an
	# existing walkable cell. Use STEP_HEIGHT (0.4) units for a single step.
	func step(x0: int, y0: int, x1: int, y1: int, floor_z: float) -> MapBuilder:
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				if x < 0 or x >= w or y < 0 or y >= h:
					continue
				at(x, y).floor_z = floor_z
		return self

	# Phase 7 (original): low ceiling / overhang. Sets per-cell ceiling_z.
	# Implicitly clears the sky flag because a bounded ceiling is the
	# opposite of sky.
	func low_ceiling(x0: int, y0: int, x1: int, y1: int, ceil_z: float) -> MapBuilder:
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				if x < 0 or x >= w or y < 0 or y >= h:
					continue
				var c := at(x, y)
				c.ceiling_z = ceil_z
				c.is_sky = false
		return self

	# Phase 7 (original): open-air ceiling. Player can jump as high as they
	# like and looks up into sky.
	func sky(x0: int, y0: int, x1: int, y1: int) -> MapBuilder:
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				if x < 0 or x >= w or y < 0 or y >= h:
					continue
				at(x, y).is_sky = true
		return self

	func player_start(x: float, y: float, angle: float) -> MapBuilder:
		px = x
		py = y
		p_ang = angle
		return self

	# Phase 9 (original): stack a 3D floor slab into the rectangle
	# [x0..x1, y0..y1]. The slab spans world-Z [bottom_z, top_z]; the player
	# walks on top_z and the underside is visible as a "ceiling" below
	# bottom_z. Multiple calls in the same footprint stack: a basement under
	# a courtyard is sector floor + slab whose top is the courtyard surface;
	# a balcony over a hall is the hall + slab whose bottom is the hall ceiling.
	func floor_3d(x0: int, y0: int, x1: int, y1: int, bottom_z: float, top_z: float,
			side_tex: int, top_tex: int, bottom_tex: int = 0, light: int = 200, solid: bool = true) -> MapBuilder:
		var bt := top_tex if bottom_tex == 0 else bottom_tex
		var ef := DoomTypes.ExtraFloor.new()
		ef.bottom_z = bottom_z
		ef.top_z = top_z
		ef.side_tex = side_tex
		ef.top_tex = top_tex
		ef.bottom_tex = bt
		ef.light = light
		ef.solid = solid
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				if x < 0 or x >= w or y < 0 or y >= h:
					continue
				var c := at(x, y)
				if c.kind == DoomTypes.CellKind.WALL:
					continue
				if c.extra_floors == null:
					c.extra_floors = []
				# Insert keeping extra_floors sorted by bottom_z ascending;
				# renderer and Z-resolver both rely on this invariant.
				var ins := 0
				while ins < c.extra_floors.size() and c.extra_floors[ins].bottom_z <= bottom_z:
					ins += 1
				c.extra_floors.insert(ins, ef)
		return self

	func spawn(kind: int, x: float, y: float, angle: float = 0.0) -> MapBuilder:
		var m := DoomTypes.Mobj.new()
		m.id = 0 # assigned later
		m.kind = kind
		m.state = DoomTypes.AIState.IDLE # original's ternary here was tautological (both branches IDLE)
		m.x = x
		m.y = y
		m.angle = angle
		m.health = DoomMaps.health_for(kind)
		m.radius = DoomMaps.radius_for(kind)
		m.height = DoomMaps.height_for(kind)
		m.anim_frame = 0
		mobjs.append(m)
		return self

	func build() -> LevelStart:
		var map := DoomTypes.MapDef.new()
		map.width = w
		map.height = h
		map.cells = cells
		map.name = map_name
		var result := LevelStart.new()
		result.map = map
		result.player_x = px
		result.player_y = py
		result.player_angle = p_ang
		result.mobjs = mobjs
		result.boss_exit_gated = boss_exit_gated
		return result

static func health_for(k: int) -> int:
	match k:
		DoomTypes.MobjKind.IMP:
			return DoomTypes.C.HP_IMP
		DoomTypes.MobjKind.DEMON:
			return DoomTypes.C.HP_DEMON
		DoomTypes.MobjKind.BARON:
			return DoomTypes.C.HP_BARON
		DoomTypes.MobjKind.CACODEMON:
			return DoomTypes.C.HP_CACO
		DoomTypes.MobjKind.LOST_SOUL:
			return DoomTypes.C.HP_LOST
		DoomTypes.MobjKind.ZOMBIEMAN:
			return DoomTypes.C.HP_ZOMBIE
		DoomTypes.MobjKind.SHOTGUNNER:
			return DoomTypes.C.HP_SHOTG
		DoomTypes.MobjKind.BARREL:
			return DoomTypes.C.HP_BARREL
		_:
			return 1

static func radius_for(k: int) -> float:
	match k:
		DoomTypes.MobjKind.CACODEMON, DoomTypes.MobjKind.BARON:
			return 0.42
		DoomTypes.MobjKind.DEMON:
			return 0.36
		DoomTypes.MobjKind.BARREL:
			return 0.25
		DoomTypes.MobjKind.IMP_FIREBALL, DoomTypes.MobjKind.BARON_BALL, DoomTypes.MobjKind.CACO_BALL, \
		DoomTypes.MobjKind.PLASMA_PROJ, DoomTypes.MobjKind.ROCKET_PROJ, DoomTypes.MobjKind.BFG_PROJ:
			return 0.12
		_:
			return 0.3

static func height_for(k: int) -> float:
	match k:
		DoomTypes.MobjKind.BARON:
			return 1.1
		DoomTypes.MobjKind.CACODEMON:
			return 0.9
		DoomTypes.MobjKind.IMP, DoomTypes.MobjKind.ZOMBIEMAN, DoomTypes.MobjKind.SHOTGUNNER:
			return 0.85
		DoomTypes.MobjKind.DEMON:
			return 0.7
		DoomTypes.MobjKind.LOST_SOUL:
			return 0.5
		DoomTypes.MobjKind.BARREL:
			return 0.55
		DoomTypes.MobjKind.PICKUP_HEALTH, DoomTypes.MobjKind.PICKUP_ARMOR, DoomTypes.MobjKind.PICKUP_ARMOR_BLUE, \
		DoomTypes.MobjKind.PICKUP_BULLETS, DoomTypes.MobjKind.PICKUP_SHELLS, DoomTypes.MobjKind.PICKUP_ROCKETS, DoomTypes.MobjKind.PICKUP_CELLS, \
		DoomTypes.MobjKind.PICKUP_SHOTGUN, DoomTypes.MobjKind.PICKUP_CHAINGUN, DoomTypes.MobjKind.PICKUP_ROCKET_LAUNCHER, \
		DoomTypes.MobjKind.PICKUP_PLASMA, DoomTypes.MobjKind.PICKUP_BFG, \
		DoomTypes.MobjKind.KEY_BLUE, DoomTypes.MobjKind.KEY_YELLOW, DoomTypes.MobjKind.KEY_RED:
			return 0.35
		_:
			return 0.7

# ───── Levels ─────

static func build_level(level: int) -> LevelStart:
	match level:
		1:
			return level1()
		2:
			return level2()
		3:
			return level3()
		4:
			return level4()
		5:
			return level5()
		6:
			return level6()
		_:
			return level1()

# E1M1 -- "Hangar" -- key-chain progression:
#   entrance corridor -> hub (yellow key here)
#   yellow door east -> red key
#   red door west -> blue key
#   blue door north -> boss room -> walk onto blue exit pad to finish
# Boss-gated: victory only fires once Baron + Cacodemon are dead.
static func level1() -> LevelStart:
	var b := MapBuilder.new(48, 48, "E1M1: Hangar")
	# outer arena
	b.fill(1, 1, 46, 46, DoomTextures.F_CONCRETE, DoomTextures.F_CONCRETE, 200)
	b.border(DoomTextures.W_TECH_PANEL)

	# starting corridor (bottom)
	b.fill(20, 38, 28, 46, DoomTextures.F_TILE, DoomTextures.F_CONCRETE, 220)
	b.box(19, 37, 29, 47, DoomTextures.W_TECH_PANEL)
	b.fill(20, 38, 28, 46, DoomTextures.F_TILE, DoomTextures.F_CONCRETE, 220)

	# hub (center)
	b.fill(10, 18, 38, 36, DoomTextures.F_TILE, DoomTextures.F_CONCRETE, 200)
	b.box(9, 17, 39, 37, DoomTextures.W_TECH_PANEL)
	b.fill(10, 18, 38, 36, DoomTextures.F_TILE, DoomTextures.F_CONCRETE, 200)

	# door from corridor -> hub
	b.door(24, 37)

	# pillars in hub
	b.wall(16, 24, DoomTextures.W_BRICK_RED)
	b.wall(16, 30, DoomTextures.W_BRICK_RED)
	b.wall(32, 24, DoomTextures.W_BRICK_RED)
	b.wall(32, 30, DoomTextures.W_BRICK_RED)

	# west wing (left from player view) -- locked behind RED door, holds blue key
	b.fill(2, 20, 8, 34, DoomTextures.F_TILE, DoomTextures.F_CONCRETE, 180)
	b.box(1, 19, 9, 35, DoomTextures.W_BRICK_GREY)
	b.fill(2, 20, 8, 34, DoomTextures.F_TILE, DoomTextures.F_CONCRETE, 180)
	b.door(9, 27, DoomTypes.CellKind.DOOR_RED)

	# east wing (right from player view) -- locked behind YELLOW door, holds red key
	b.fill(40, 20, 45, 34, DoomTextures.F_TILE, DoomTextures.F_CONCRETE, 160)
	b.box(39, 19, 46, 35, DoomTextures.W_HELL_STONE)
	b.fill(40, 20, 45, 34, DoomTextures.F_TILE, DoomTextures.F_CONCRETE, 160)
	b.door(39, 27, DoomTypes.CellKind.DOOR_YELLOW)

	# north wing -- BOSS ROOM, locked behind BLUE door.
	# Back wall (y=4..5) is paved with blue exit-pad tiles; stepping onto
	# any of them ends the level once the boss + helper are dead.
	b.fill(18, 4, 30, 16, DoomTextures.F_TILE, DoomTextures.F_CONCRETE, 230)
	b.box(17, 3, 31, 17, DoomTextures.W_BRICK_RED)
	b.fill(18, 4, 30, 16, DoomTextures.F_TILE, DoomTextures.F_CONCRETE, 230)
	b.door(24, 17, DoomTypes.CellKind.DOOR_BLUE)
	for ex in range(20, 29):
		b.exit_pad(ex, 4)
		b.exit_pad(ex, 5)
	# Mark the back wall behind the exit pads in blue brick so the player
	# knows where the level ends.
	for wx in range(19, 30):
		b.wall(wx, 3, DoomTextures.W_BRICK_BLUE)

	# player start (corridor, facing north toward the hub door)
	b.player_start(24.5, 44.5, -PI / 2.0)

	# ── Pickups & keys ──
	# Hub welcome stash + the YELLOW key sits openly in the middle so the
	# player picks it up the moment they enter.
	b.spawn(DoomTypes.MobjKind.PICKUP_BULLETS, 24.5, 41.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_HEALTH, 21.5, 41.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_HEALTH, 27.5, 41.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_ARMOR, 24.5, 33.5)
	b.spawn(DoomTypes.MobjKind.KEY_YELLOW, 24.5, 27.5)

	# East wing -- RED key + ammo for the next leg.
	b.spawn(DoomTypes.MobjKind.KEY_RED, 43.5, 27.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_BULLETS, 42.5, 24.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_SHELLS, 42.5, 30.5)

	# West wing -- BLUE key + the shotgun (you'll want it for the boss).
	b.spawn(DoomTypes.MobjKind.KEY_BLUE, 5.5, 27.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_SHOTGUN, 5.5, 24.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_SHELLS, 6.5, 30.5)

	# Hub barrels for fun chain explosions.
	b.spawn(DoomTypes.MobjKind.BARREL, 20.5, 26.5)
	b.spawn(DoomTypes.MobjKind.BARREL, 28.5, 26.5)
	b.spawn(DoomTypes.MobjKind.BARREL, 24.5, 22.5)

	# ── Monsters ──
	# Hub patrol.
	b.spawn(DoomTypes.MobjKind.ZOMBIEMAN, 14.5, 24.5, 0.0)
	b.spawn(DoomTypes.MobjKind.ZOMBIEMAN, 34.5, 30.5, PI)
	b.spawn(DoomTypes.MobjKind.ZOMBIEMAN, 24.5, 22.5, PI / 2.0)
	# Wing dwellers.
	b.spawn(DoomTypes.MobjKind.IMP, 4.5, 24.5, 0.0)
	b.spawn(DoomTypes.MobjKind.IMP, 4.5, 31.5, 0.0)
	b.spawn(DoomTypes.MobjKind.IMP, 43.5, 22.5, PI)
	b.spawn(DoomTypes.MobjKind.IMP, 43.5, 32.5, PI)
	# Boss room -- Baron (boss) + Cacodemon (helper). Both must die before
	# the exit pad becomes active. Two health pickups inside as a bonus.
	b.spawn(DoomTypes.MobjKind.BARON, 24.5, 10.5, PI / 2.0)
	b.spawn(DoomTypes.MobjKind.CACODEMON, 20.5, 8.5, PI / 2.0)
	b.spawn(DoomTypes.MobjKind.PICKUP_HEALTH, 19.5, 14.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_ARMOR, 28.5, 14.5)

	b.boss_exit_gated = true
	return b.build()

# E1M2 -- "Toxin Refinery" -- bigger maze with nukage and demons
static func level2() -> LevelStart:
	var b := MapBuilder.new(48, 48, "E1M2: Toxin Refinery")
	b.fill(1, 1, 46, 46, DoomTextures.F_TILE, DoomTextures.F_CONCRETE, 180)
	b.border(DoomTextures.W_TECH_PANEL)

	# central courtyard
	b.fill(16, 16, 32, 32, DoomTextures.F_TILE, DoomTextures.F_CONCRETE, 200)

	# nukage moat surrounding center
	b.liquid(14, 22, 15, 26, DoomTextures.F_NUKAGE)
	b.liquid(33, 22, 34, 26, DoomTextures.F_NUKAGE)
	b.liquid(22, 14, 26, 15, DoomTextures.F_NUKAGE)
	b.liquid(22, 33, 26, 34, DoomTextures.F_NUKAGE)

	# 4 corner rooms connected via doors
	b.box(2, 2, 14, 14, DoomTextures.W_BRICK_GREY)
	b.fill(3, 3, 13, 13, DoomTextures.F_TILE, DoomTextures.F_CONCRETE, 170)
	b.at(14, 8).kind = DoomTypes.CellKind.EMPTY
	b.door(14, 8)

	b.box(34, 2, 46, 14, DoomTextures.W_HELL_STONE)
	b.fill(35, 3, 45, 13, DoomTextures.F_TILE, DoomTextures.F_CONCRETE, 150)
	b.at(34, 8).kind = DoomTypes.CellKind.EMPTY
	b.door(34, 8, DoomTypes.CellKind.DOOR_RED)

	b.box(2, 34, 14, 46, DoomTextures.W_WOOD)
	b.fill(3, 35, 13, 45, DoomTextures.F_TILE, DoomTextures.F_CONCRETE, 200)
	b.at(14, 40).kind = DoomTypes.CellKind.EMPTY
	b.door(14, 40)

	b.box(34, 34, 46, 46, DoomTextures.W_MARBLE)
	b.fill(35, 35, 45, 45, DoomTextures.F_TILE, DoomTextures.F_CONCRETE, 230)
	b.at(34, 40).kind = DoomTypes.CellKind.EMPTY
	b.door(34, 40, DoomTypes.CellKind.DOOR_YELLOW)
	b.exit(45, 40)

	# player start
	b.player_start(24.5, 24.5, 0.0)

	# weapons
	b.spawn(DoomTypes.MobjKind.PICKUP_CHAINGUN, 24.5, 18.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_SHOTGUN, 24.5, 30.5)

	# keys
	b.spawn(DoomTypes.MobjKind.KEY_RED, 8.5, 8.5) # SW corner
	b.spawn(DoomTypes.MobjKind.KEY_YELLOW, 8.5, 40.5) # NW corner -- wait actually y axis: top=0
	# ammo + health
	b.spawn(DoomTypes.MobjKind.PICKUP_BULLETS, 24.5, 22.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_SHELLS, 22.5, 24.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_SHELLS, 26.5, 24.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_HEALTH, 20.5, 28.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_HEALTH, 28.5, 28.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_ARMOR_BLUE, 40.5, 40.5)

	# monsters
	b.spawn(DoomTypes.MobjKind.IMP, 18.5, 18.5, 0.0)
	b.spawn(DoomTypes.MobjKind.IMP, 30.5, 18.5, PI)
	b.spawn(DoomTypes.MobjKind.IMP, 18.5, 30.5, 0.0)
	b.spawn(DoomTypes.MobjKind.IMP, 30.5, 30.5, PI)
	b.spawn(DoomTypes.MobjKind.DEMON, 7.5, 7.5)
	b.spawn(DoomTypes.MobjKind.DEMON, 7.5, 11.5)
	b.spawn(DoomTypes.MobjKind.SHOTGUNNER, 41.5, 7.5, PI)
	b.spawn(DoomTypes.MobjKind.SHOTGUNNER, 41.5, 11.5, PI)
	b.spawn(DoomTypes.MobjKind.IMP, 7.5, 41.5, 0.0)
	b.spawn(DoomTypes.MobjKind.DEMON, 41.5, 41.5, PI)
	b.spawn(DoomTypes.MobjKind.CACODEMON, 37.5, 37.5)
	b.spawn(DoomTypes.MobjKind.ZOMBIEMAN, 24.5, 5.5)
	b.spawn(DoomTypes.MobjKind.ZOMBIEMAN, 24.5, 43.5)
	b.spawn(DoomTypes.MobjKind.ZOMBIEMAN, 5.5, 24.5)
	b.spawn(DoomTypes.MobjKind.ZOMBIEMAN, 43.5, 24.5)
	b.spawn(DoomTypes.MobjKind.BARREL, 22.5, 22.5)
	b.spawn(DoomTypes.MobjKind.BARREL, 26.5, 22.5)
	b.spawn(DoomTypes.MobjKind.BARREL, 22.5, 26.5)
	b.spawn(DoomTypes.MobjKind.BARREL, 26.5, 26.5)

	return b.build()

# E1M3 -- "Phobos Lab" -- open arena with high-tier weapons + Baron
static func level3() -> LevelStart:
	var b := MapBuilder.new(56, 56, "E1M3: Phobos Lab")
	b.fill(1, 1, 54, 54, DoomTextures.F_TILE, DoomTextures.F_CONCRETE, 200)
	b.border(DoomTextures.W_HELL_STONE)

	# center pit of blood
	b.liquid(24, 24, 32, 32, DoomTextures.F_BLOOD)

	# 4 pillars of fire
	b.wall(20, 20, DoomTextures.W_HELL_STONE)
	b.wall(36, 20, DoomTextures.W_HELL_STONE)
	b.wall(20, 36, DoomTextures.W_HELL_STONE)
	b.wall(36, 36, DoomTextures.W_HELL_STONE)

	# weapon bunkers in 4 corners
	b.box(4, 4, 12, 12, DoomTextures.W_TECH_PANEL)
	b.fill(5, 5, 11, 11, DoomTextures.F_TILE, DoomTextures.F_CONCRETE, 220)
	b.at(12, 8).kind = DoomTypes.CellKind.EMPTY
	b.box(44, 4, 52, 12, DoomTextures.W_TECH_PANEL)
	b.fill(45, 5, 51, 11, DoomTextures.F_TILE, DoomTextures.F_CONCRETE, 220)
	b.at(44, 8).kind = DoomTypes.CellKind.EMPTY
	b.box(4, 44, 12, 52, DoomTextures.W_TECH_PANEL)
	b.fill(5, 45, 11, 51, DoomTextures.F_TILE, DoomTextures.F_CONCRETE, 220)
	b.at(12, 48).kind = DoomTypes.CellKind.EMPTY
	b.box(44, 44, 52, 52, DoomTextures.W_TECH_PANEL)
	b.fill(45, 45, 51, 51, DoomTextures.F_TILE, DoomTextures.F_CONCRETE, 220)
	b.at(44, 48).kind = DoomTypes.CellKind.EMPTY

	# exit teleporter pad
	b.exit(28, 4)

	b.player_start(28.5, 50.5, -PI / 2.0)

	# weapons
	b.spawn(DoomTypes.MobjKind.PICKUP_SHOTGUN, 8.5, 8.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_CHAINGUN, 48.5, 8.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_ROCKET_LAUNCHER, 8.5, 48.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_PLASMA, 48.5, 48.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_BFG, 28.5, 28.5)

	# ammo galore
	b.spawn(DoomTypes.MobjKind.PICKUP_SHELLS, 9.5, 7.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_SHELLS, 9.5, 9.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_BULLETS, 47.5, 7.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_BULLETS, 47.5, 9.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_ROCKETS, 9.5, 47.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_ROCKETS, 9.5, 49.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_CELLS, 47.5, 47.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_CELLS, 47.5, 49.5)

	b.spawn(DoomTypes.MobjKind.PICKUP_ARMOR_BLUE, 28.5, 36.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_HEALTH, 26.5, 50.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_HEALTH, 30.5, 50.5)

	# demonic horde
	b.spawn(DoomTypes.MobjKind.IMP, 14.5, 14.5)
	b.spawn(DoomTypes.MobjKind.IMP, 42.5, 14.5)
	b.spawn(DoomTypes.MobjKind.IMP, 14.5, 42.5)
	b.spawn(DoomTypes.MobjKind.IMP, 42.5, 42.5)
	b.spawn(DoomTypes.MobjKind.DEMON, 22.5, 16.5)
	b.spawn(DoomTypes.MobjKind.DEMON, 34.5, 16.5)
	b.spawn(DoomTypes.MobjKind.DEMON, 22.5, 40.5)
	b.spawn(DoomTypes.MobjKind.DEMON, 34.5, 40.5)
	b.spawn(DoomTypes.MobjKind.CACODEMON, 16.5, 28.5)
	b.spawn(DoomTypes.MobjKind.CACODEMON, 40.5, 28.5)
	b.spawn(DoomTypes.MobjKind.LOST_SOUL, 28.5, 14.5)
	b.spawn(DoomTypes.MobjKind.LOST_SOUL, 28.5, 42.5)
	b.spawn(DoomTypes.MobjKind.SHOTGUNNER, 18.5, 18.5)
	b.spawn(DoomTypes.MobjKind.SHOTGUNNER, 38.5, 18.5)
	b.spawn(DoomTypes.MobjKind.BARON, 28.5, 8.5, PI / 2.0)

	return b.build()

# E1M4 -- "Outpost" -- Phase 7 showcase (original): open courtyard with sky,
# stair staircase, raised platform you must jump or climb onto, and a low
# tunnel you must crouch through.
static func level4() -> LevelStart:
	var b := MapBuilder.new(40, 40, "E1M4: Outpost")

	# Outdoor courtyard floor (grass under sky)
	b.fill(2, 2, 37, 37, DoomTextures.F_GRASS, DoomTextures.F_GRASS, 230)
	b.border(DoomTextures.W_BRICK_GREY)
	b.sky(2, 2, 37, 37)

	# Player starts in the south, looking north.
	b.player_start(8.5, 32.5, -PI / 2.0)

	# Stairs going up north toward a raised plateau (smaller rises so you can
	# walk up without jumping; total ~1.0 over 5 steps).
	b.step(6, 24, 14, 24, 0.0)
	b.step(6, 23, 14, 23, 0.2)
	b.step(6, 22, 14, 22, 0.4)
	b.step(6, 21, 14, 21, 0.6)
	b.step(6, 20, 14, 20, 0.8)
	# Plateau on top
	b.step(4, 14, 16, 19, 1.0)

	# Raised pillar of brick to the east (must jump to climb)
	b.step(22, 30, 26, 32, 0.7)

	# Low tunnel west (height 0.7, must crouch). Opens into a small room.
	b.box(20, 16, 28, 22, DoomTextures.W_BRICK_GREY)
	b.fill(21, 17, 27, 21, DoomTextures.F_TILE, DoomTextures.F_CONCRETE, 160)
	# Tunnel mouth (open the south wall)
	b.at(24, 22).kind = DoomTypes.CellKind.EMPTY
	b.at(24, 22).floor_tex_idx = DoomTextures.F_TILE
	b.low_ceiling(24, 22, 24, 22, 0.7)
	b.low_ceiling(21, 17, 27, 21, 1.4)

	# A taller "lookout tower" in the NE -- sky room with high parapet.
	b.box(28, 4, 36, 12, DoomTextures.W_BRICK_RED)
	b.fill(29, 5, 35, 11, DoomTextures.F_TILE, DoomTextures.F_TILE, 220)
	b.sky(29, 5, 35, 11)
	# Doorway in
	b.at(32, 12).kind = DoomTypes.CellKind.EMPTY
	b.at(32, 12).floor_tex_idx = DoomTextures.F_TILE

	# Exit on the plateau
	b.exit(10, 16)

	# Some enemies and pickups
	# (enemies disabled for Phase 7 traversal testing, in the original)
	# b.spawn(DoomTypes.MobjKind.IMP, 10.5, 18.5)
	# b.spawn(DoomTypes.MobjKind.DEMON, 24.5, 31.5)
	# b.spawn(DoomTypes.MobjKind.CACODEMON, 32.5, 8.5)
	# b.spawn(DoomTypes.MobjKind.ZOMBIEMAN, 24.5, 19.5)
	# b.spawn(DoomTypes.MobjKind.SHOTGUNNER, 6.5, 26.5)

	b.spawn(DoomTypes.MobjKind.PICKUP_HEALTH, 8.5, 28.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_SHELLS, 12.5, 16.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_SHOTGUN, 24.5, 31.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_ARMOR, 32.5, 8.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_BULLETS, 24.5, 19.5)

	return b.build()

# E1M5 -- "Watchtower" -- Phase 8 showcase (original): small ground-floor
# courtyard, staircase up to a second-story balcony, and a guard room on top
# with a small squad. Tight 28x28 layout so the action stays close.
static func level5() -> LevelStart:
	var b := MapBuilder.new(28, 28, "E1M5: Watchtower")

	# Ground level: outdoor courtyard with sky.
	b.fill(2, 2, 25, 25, DoomTextures.F_GRASS, DoomTextures.F_GRASS, 220)
	b.border(DoomTextures.W_BRICK_GREY)
	b.sky(2, 2, 25, 25)

	# Player starts in the south, looking north toward the tower.
	b.player_start(14.5, 22.5, -PI / 2.0)

	# Guard room (second story): 8x5 cells at Z=2.0, real ceiling at Z=3.6.
	b.fill(4, 3, 11, 7, DoomTextures.F_TILE, DoomTextures.F_TILE, 200)
	b.step(4, 3, 11, 7, 2.0)
	b.low_ceiling(4, 3, 11, 7, 3.6)
	b.box(3, 2, 12, 8, DoomTextures.W_BRICK_RED)

	# Open-sky balcony connecting stairs to the guard room.
	b.fill(9, 8, 12, 11, DoomTextures.F_TILE, DoomTextures.F_TILE, 220)
	b.step(9, 8, 12, 11, 2.0)
	b.sky(9, 8, 12, 11)

	# Doorway from balcony into guard room.
	b.at(10, 8).kind = DoomTypes.CellKind.EMPTY
	b.at(10, 8).floor_tex_idx = DoomTextures.F_TILE
	b.at(11, 8).kind = DoomTypes.CellKind.EMPTY
	b.at(11, 8).floor_tex_idx = DoomTextures.F_TILE
	b.step(10, 8, 11, 8, 2.0)
	b.low_ceiling(10, 8, 11, 8, 3.6)

	# Staircase: 10 steps of 0.2u rising from south to north along x=10..12.
	b.step(10, 21, 12, 21, 0.2)
	b.step(10, 20, 12, 20, 0.4)
	b.step(10, 19, 12, 19, 0.6)
	b.step(10, 18, 12, 18, 0.8)
	b.step(10, 17, 12, 17, 1.0)
	b.step(10, 16, 12, 16, 1.2)
	b.step(10, 15, 12, 15, 1.4)
	b.step(10, 14, 12, 14, 1.6)
	b.step(10, 13, 12, 13, 1.8)
	b.step(10, 12, 12, 12, 2.0)

	# Cover pillar in the courtyard.
	b.wall(20, 18, DoomTextures.W_BRICK_RED)

	# Exit pad inside the guard room.
	b.exit(6, 4)

	# Pickups along the route.
	b.spawn(DoomTypes.MobjKind.PICKUP_SHOTGUN, 14.5, 17.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_SHELLS, 11.5, 14.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_HEALTH, 18.5, 20.5)
	b.spawn(DoomTypes.MobjKind.PICKUP_ARMOR, 8.5, 5.5)

	# Enemies -- small, focused encounter.
	# Courtyard: 1 sniper.
	b.spawn(DoomTypes.MobjKind.ZOMBIEMAN, 22.5, 12.5, PI)
	# Guard room squad: 1 shotgunner, 2 imps.
	b.spawn(DoomTypes.MobjKind.SHOTGUNNER, 6.5, 5.5, PI / 2.0)
	b.spawn(DoomTypes.MobjKind.IMP, 9.5, 4.5, PI / 2.0)
	b.spawn(DoomTypes.MobjKind.IMP, 5.5, 6.5, PI / 2.0)

	return b.build()

# E1M6 -- "Skybridge" -- Phase 9 showcase (original): a TRUE three-story
# building with walkable floors stacked at the same XY footprint. Each story
# has the same plan -- back of the building hosts the upper slabs, front
# opens through an atrium so the player can look up/down between floors.
#   Story 1 (Z=0)        : ground hall, accessed via south doorway
#   Story 2 (Z=3.2..3.5) : slab covering the back 2/3 of the footprint
#   Story 3 (Z=6.4..6.7) : smaller slab covering the back 1/3
# Access:
#   Ground -> 2nd  : exterior staircase on the EAST side (per-cell step)
#   2nd   -> 3rd  : INTERNAL staircase made of stacked ExtraFloor slabs
#                  rising from slab#1 top up to slab#2 top
#   Plus: a basement pit at Z=-1.5 in the courtyard (no way out -- death pit).
# No exit trigger -- this is the final level, fight your way through.
static func level6() -> LevelStart:
	var b := MapBuilder.new(32, 32, "E1M6: Skybridge")

	# Outdoor courtyard with sky.
	b.fill(1, 1, 30, 30, DoomTextures.F_GRASS, DoomTextures.F_GRASS, 220)
	b.border(DoomTextures.W_BRICK_GREY)
	b.sky(1, 1, 30, 30)

	# Player starts in the south courtyard, looking north.
	b.player_start(16.5, 26.5, -PI / 2.0)

	# ── Building 12x12 at (10..21, 6..17) ──
	b.fill(10, 6, 21, 17, DoomTextures.F_TILE, DoomTextures.F_TILE, 200)
	# Tall sector ceiling -- the visible "ceilings" inside are the slab
	# bottoms at Z=3.2 (between floors 1 & 2) and Z=6.4 (between 2 & 3).
	b.low_ceiling(10, 6, 21, 17, 10.0)
	b.box(9, 5, 22, 18, DoomTextures.W_BRICK_RED)

	# South doorway into the ground hall.
	b.at(15, 18).kind = DoomTypes.CellKind.EMPTY
	b.at(15, 18).floor_tex_idx = DoomTextures.F_TILE
	b.at(16, 18).kind = DoomTypes.CellKind.EMPTY
	b.at(16, 18).floor_tex_idx = DoomTextures.F_TILE

	# 2nd-floor slab -- back 2/3 of the footprint (y=6..14). Atrium open
	# above the south strip (y=15..17) so you can look up/down.
	b.floor_3d(10, 6, 21, 14, 3.2, 3.5,
			DoomTextures.W_BRICK_RED, DoomTextures.F_TILE,
			DoomTextures.F_TILE, 200)

	# 3rd-floor slab -- WEST HALF only (x=10..13). The internal staircase
	# climbs through cells x=14..15, which must be CLEAR of slab#2 --
	# otherwise the slab body (Z=6.4..6.7) overlaps the player's head as
	# they climb past Z=5.5, and collision blocks them out.
	b.floor_3d(10, 6, 13, 10, 6.4, 6.7,
			DoomTextures.W_BRICK_RED, DoomTextures.F_TILE,
			DoomTextures.F_TILE, 200)

	# ── Exterior EAST staircase: ground -> 2nd floor ──
	# 2-cell-wide (x=23..24) so player has room to walk straight up. 8
	# treads at 0.4u (= STEP_HEIGHT) so player walks up without jumping.
	b.step(23, 14, 24, 14, 0.4)
	b.step(23, 13, 24, 13, 0.8)
	b.step(23, 12, 24, 12, 1.2)
	b.step(23, 11, 24, 11, 1.6)
	b.step(23, 10, 24, 10, 2.0)
	b.step(23, 9, 24, 9, 2.4)
	b.step(23, 8, 24, 8, 2.8)
	b.step(23, 7, 24, 7, 3.2)

	# East-wall opening at (22, 7) acts as a landing onto slab#1.
	# Cell sits at Z=3.2 -- slab#1 top is Z=3.5, a 0.3u step westward.
	b.at(22, 7).kind = DoomTypes.CellKind.EMPTY
	b.at(22, 7).floor_tex_idx = DoomTextures.F_TILE
	b.at(22, 7).floor_z = 3.2
	b.at(22, 7).ceiling_z = 10.0

	# ── Internal staircase: 2nd -> 3rd floor ──
	# 2-cell-wide stacked ExtraFloor slabs at columns x=14..15, going north
	# (y=13 -> y=7). Each slab sits on top of slab#1 (bottom_z=3.5) with
	# rising top_z in 0.4u increments. Tread 7 (top Z=6.3) lets the player
	# make a final 0.4u climb west onto slab#2 (top Z=6.7).
	b.floor_3d(14, 13, 15, 13, 3.5, 3.9, DoomTextures.W_BRICK_RED, DoomTextures.F_TILE)
	b.floor_3d(14, 12, 15, 12, 3.5, 4.3, DoomTextures.W_BRICK_RED, DoomTextures.F_TILE)
	b.floor_3d(14, 11, 15, 11, 3.5, 4.7, DoomTextures.W_BRICK_RED, DoomTextures.F_TILE)
	b.floor_3d(14, 10, 15, 10, 3.5, 5.1, DoomTextures.W_BRICK_RED, DoomTextures.F_TILE)
	b.floor_3d(14, 9, 15, 9, 3.5, 5.5, DoomTextures.W_BRICK_RED, DoomTextures.F_TILE)
	b.floor_3d(14, 8, 15, 8, 3.5, 5.9, DoomTextures.W_BRICK_RED, DoomTextures.F_TILE)
	b.floor_3d(14, 7, 15, 7, 3.5, 6.3, DoomTextures.W_BRICK_RED, DoomTextures.F_TILE)

	# ── Basement pit in the courtyard (death pit -- no way out) ──
	b.fill(3, 13, 6, 16, DoomTextures.F_LAVA, DoomTextures.F_LAVA, 160)
	b.step(3, 13, 6, 16, -1.5)

	# ── Pickups ──
	b.spawn(DoomTypes.MobjKind.PICKUP_SHOTGUN, 16.5, 21.5) # courtyard
	b.spawn(DoomTypes.MobjKind.PICKUP_ARMOR, 16.5, 11.5) # ground hall
	b.spawn(DoomTypes.MobjKind.PICKUP_HEALTH, 12.5, 10.5) # 2nd floor
	b.spawn(DoomTypes.MobjKind.PICKUP_SHELLS, 18.5, 12.5) # 2nd floor
	b.spawn(DoomTypes.MobjKind.PICKUP_ROCKETS, 11.5, 7.5) # 3rd floor (west)
	b.spawn(DoomTypes.MobjKind.PICKUP_CELLS, 12.5, 8.5) # 3rd floor (west)

	# ── Enemies, distributed across all three stories ──
	b.spawn(DoomTypes.MobjKind.ZOMBIEMAN, 27.5, 15.5, PI)
	b.spawn(DoomTypes.MobjKind.IMP, 12.5, 13.5, -PI / 2.0)
	b.spawn(DoomTypes.MobjKind.IMP, 19.5, 13.5, -PI / 2.0)
	b.spawn(DoomTypes.MobjKind.SHOTGUNNER, 16.5, 16.5, -PI / 2.0)
	b.spawn(DoomTypes.MobjKind.IMP, 12.5, 9.5)
	b.spawn(DoomTypes.MobjKind.SHOTGUNNER, 19.5, 9.5)
	b.spawn(DoomTypes.MobjKind.IMP, 11.5, 8.5)

	# No exit trigger -- final level.

	return b.build()
