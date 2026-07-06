class_name GameLogic
extends RefCounted

## Faithful port of the Unity ReactiveUIToolKit `DoomGame` sample's `GameLogic.uitkx` --
## the simulation + sector/portal raycasting renderer. Ports through Phase 2 of
## plans/DOOM_GAME_GUITKX_PORT_PLAN.md: `new_game`, the renderer (`cast_frame`/
## `build_column_sector`/`cast_ray`), and `tick`/`update_player` (movement, mouse-look,
## jump/crouch/step-up, collision). Weapons, monster/projectile/pickup AI, damage, and
## the door FSM are the original's Tick() path too, but ported in Phase 3 (combat/AI/
## pickups/doors) -- see the "Tick / Player" section below for exactly what's deferred.
##
## `ref GameState`/`ref Sector`/etc in the original become plain mutation, since GDScript
## objects are already reference types (no `ref` keyword needed) -- see plan §1.4.
## C#'s `out` parameters (e.g. BuildColumnSector's `out float depthOut`) have no GDScript
## equivalent; here it's eliminated entirely since every return path in the original sets
## depthOut == the returned column's Main.Distance (provably redundant, not a behavior
## change) -- the caller just reads `column.main.distance`.

class RayHit extends RefCounted:
	var distance: float
	var wall_tex_idx: int
	var tex_u: float
	var light: int
	var hit_vertical: bool
	var is_sky: bool

# Phase 2 (original): when true, cast_frame uses Raycast.cast (portal walker on the
# sector graph). When false, falls back to the original DDA grid walker. Toggle
# off if a regression appears -- the engine should still play.
const USE_SECTOR_RAYCAST := true

# ───── Public API ─────

static func new_game(level: int, diff: int) -> DoomTypes.GameState:
	var start := DoomMaps.build_level(level)
	var st := DoomTypes.GameState.new()
	st.level = level
	st.difficulty = diff
	st.map = start.map
	st.mobjs = []
	st.mobjs.resize(DoomTypes.C.MAX_MOBJS)
	st.mobj_count = 0
	st.next_mobj_id = 1
	st.frame = DoomTypes.FrameData.new()
	st.frame.columns = []
	st.frame.columns.resize(DoomTypes.C.VIEW_W)
	st.frame.depth_buffer = PackedFloat32Array()
	st.frame.depth_buffer.resize(DoomTypes.C.VIEW_W)

	var player := DoomTypes.PlayerState.new()
	player.x = start.player_x
	player.y = start.player_y
	player.angle = start.player_angle
	player.pitch = 0.0
	player.health = DoomTypes.C.START_HEALTH
	player.armor = 0
	player.armor_class = 0
	player.weapon = DoomTypes.WeaponType.PISTOL
	player.ammo = [50, 0, 0, 0]
	player.owned_weapons = [true, true, false, false, false, false, false]
	player.keys = DoomTypes.KeyCard.NONE
	player.alive = true
	player.face_state = 1
	player.face_timer = 0.5
	player.message_text = ""
	st.player = player

	st.rng_seed = 12345 + level * 17
	st.tic = 0
	st.tracers = []
	st.tracers.resize(DoomTypes.C.MAX_TRACERS)
	for i in range(st.tracers.size()):
		st.tracers[i] = DoomTypes.Tracer.new()
	st.tracer_count = 0
	st.boss_exit_gated = start.boss_exit_gated

	# Phase 1 (original): build the parallel sector model (no rendering use yet).
	st.sector_map = DoomTypes.MapData.from_tiles(st.map)
	st.sector_map.player_start = Vector2(start.player_x, start.player_y)
	st.sector_map.player_start_angle = start.player_angle
	st.sector_map.player_start_sector = Raycast.point_in_sector_from_hint(st.sector_map, st.sector_map.player_start, -1)
	st.player.view_height = DoomTypes.C.PLAYER_VIEW_HEIGHT
	st.player.sector_id = st.sector_map.player_start_sector

	for m in start.mobjs:
		add_mobj(st, m)
	var kill_total := 0
	for i in range(1, st.mobj_count + 1):
		if is_monster(st.mobjs[i].kind):
			kill_total += 1
	st.kill_total = kill_total

	cast_frame(st)
	return st

# ───── Tick / Player (Phase 2 scope) ─────
# Doors, sector-light animation, monster/projectile/pickup updates, and weapon
# firing are also part of the original's Tick()/UpdatePlayer() path, but are
# ported in Phase 3 (combat/AI/pickups/doors) -- every deferred call site below
# is marked with a comment, not silently dropped. Closed doors still correctly
# block movement in the meantime (blocks_movement_z checks door_state), they
# just never open since update_doors isn't ported yet.

static func tick(st: DoomTypes.GameState, dt: float, input: DoomTypes.InputCmd) -> void:
	if st.game_over or st.victory:
		st.time_accum += dt
		advance_face(st, dt) # still advance face timer for fun
		cast_frame(st)
		return
	st.tic += 1
	st.time_accum += dt

	update_player(st, input, dt)
	# Phase 3 (original): update_doors(st, dt); update_sectors(st, dt) -- door
	# FSM + sector light animation.
	# Phase 3 (original): for i in range(1, st.mobj_count + 1): update_mobj(st, i, dt)
	# -- monsters/projectiles/pickups are frozen until AI/combat lands.

	compact_mobjs(st)
	advance_face(st, dt)

	# decay flashes
	if st.player.hurt_flash > 0:
		st.player.hurt_flash = maxf(0.0, st.player.hurt_flash - dt * 2.0)
	if st.player.pickup_flash > 0:
		st.player.pickup_flash = maxf(0.0, st.player.pickup_flash - dt * 3.0)
	if st.player.muzzle_flash > 0:
		st.player.muzzle_flash = maxf(0.0, st.player.muzzle_flash - dt)
	if st.player.message_timer > 0:
		st.player.message_timer = maxf(0.0, st.player.message_timer - dt)

	# Phase 8 (original): age hitscan tracers (ms units; capped at LIFE so dead
	# slots are skipped at render time and naturally overwritten by ring index).
	if st.tracers != null:
		var dt_ms := dt * 1000.0
		for i in range(st.tracers.size()):
			if st.tracers[i].age_ms < DoomTypes.C.TRACER_LIFE_MS:
				st.tracers[i].age_ms = minf(DoomTypes.C.TRACER_LIFE_MS, st.tracers[i].age_ms + dt_ms)

	cast_frame(st)

static func update_player(st: DoomTypes.GameState, input: DoomTypes.InputCmd, dt: float) -> void:
	var p := st.player
	if not p.alive:
		return

	# Mouse-look (ALWAYS ON)
	p.angle += input.yaw_delta
	p.pitch -= input.pitch_delta * DoomTypes.C.MOUSE_PITCH_SENS
	p.pitch = clampf(p.pitch, -DoomTypes.C.MAX_PITCH, DoomTypes.C.MAX_PITCH)

	# Keyboard turn
	if input.turn_left:
		p.angle -= DoomTypes.C.TURN_SPEED * dt
	if input.turn_right:
		p.angle += DoomTypes.C.TURN_SPEED * dt

	var speed: float = DoomTypes.C.MOVE_SPEED * (DoomTypes.C.RUN_MULT if input.run else 1.0)
	var strafe: float = DoomTypes.C.STRAFE_SPEED * (DoomTypes.C.RUN_MULT if input.run else 1.0)
	var fwd_x := cos(p.angle)
	var fwd_y := sin(p.angle)
	var rgt_x := -fwd_y
	var rgt_y := fwd_x

	var dx := 0.0
	var dy := 0.0
	if input.forward:
		dx += fwd_x * speed * dt
		dy += fwd_y * speed * dt
	if input.back:
		dx -= fwd_x * speed * dt
		dy -= fwd_y * speed * dt
	if input.strafe_right:
		dx += rgt_x * strafe * dt
		dy += rgt_y * strafe * dt
	if input.strafe_left:
		dx -= rgt_x * strafe * dt
		dy -= rgt_y * strafe * dt

	move_actor(st, p, dx, dy, DoomTypes.C.PLAYER_RADIUS, true)

	# Phase 2 (original): keep player.sector_id tracking the current sector for
	# the sector-based renderer/collision. Cheap hint-walk; falls back to brute
	# force if hint fails.
	if st.sector_map.is_valid():
		p.sector_id = Raycast.point_in_sector_from_hint(st.sector_map, Vector2(p.x, p.y), p.sector_id)

	# Phase 7 (original): vertical movement -- gravity, jump, crouch. Player
	# feet (Z) are anchored to the current sector floor unless airborne.
	update_player_vertical(st, p, input, dt)

	if absf(dx) > 0.001 or absf(dy) > 0.001:
		p.bob_t += dt * 8.0

	# exit?
	var gx := int(p.x)
	var gy := int(p.y)
	var c := st.map.at_safe(gx, gy)
	if c.kind == DoomTypes.CellKind.EXIT:
		if st.boss_exit_gated and any_boss_alive(st):
			if (st.tic % 60) == 0:
				p.message_text = "Kill the boss first."
				p.message_timer = 1.5
		else:
			st.victory = true
			return
	if c.kind == DoomTypes.CellKind.LIQUID:
		# damage 1hp/sec for nukage etc
		if (st.tic % 30) == 0:
			hurt(st, p, 1, 0)

	# weapon switch
	if input.weapon_switch != 0:
		var idx: int = input.weapon_switch - 1
		if idx >= 0 and idx < p.owned_weapons.size() and p.owned_weapons[idx]:
			p.weapon = idx

	# shooting
	if p.shoot_cooldown > 0:
		p.shoot_cooldown -= dt
	# Phase 3 (original): if input.attack and p.shoot_cooldown <= 0: fire_weapon(st)
	# -- weapons aren't ported yet; the Attack input is captured but does nothing.

	# use key (open doors)
	# Phase 3 (original): if input.use: try_use(st) -- doors aren't ported yet;
	# the Use input is captured but does nothing.

# Phase 7 (original): vertical physics for the player. Tracks Z (feet height)
# against the floor of the player's current sector. Jump applies upward
# velocity when on the ground; crouch lowers the view height temporarily.
static func update_player_vertical(st: DoomTypes.GameState, p: DoomTypes.PlayerState, input: DoomTypes.InputCmd, dt: float) -> void:
	var floor_z := 0.0
	var ceil_z := 1.0
	if st.sector_map.is_valid() and p.sector_id >= 0:
		var sec: DoomTypes.Sector = st.sector_map.sectors[p.sector_id]
		floor_z = standing_floor_in(sec, p.z, DoomTypes.C.STEP_HEIGHT)
		ceil_z = ceiling_above_in(sec, p.z, DoomTypes.C.PLAYER_HEIGHT)
	var on_ground: bool = p.z <= floor_z + 0.001 and p.z_vel <= 0.0
	# Edge-detect: only jump on the rising edge of the Jump key, not while held.
	var jump_edge: bool = input.jump and not p.jump_held_prev
	p.jump_held_prev = input.jump
	if on_ground and jump_edge:
		p.z_vel = DoomTypes.C.JUMP_VELOCITY
		on_ground = false
	if not on_ground:
		p.z_vel -= DoomTypes.C.GRAVITY * dt
		p.z += p.z_vel * dt
		if p.z <= floor_z:
			p.z = floor_z
			p.z_vel = 0.0
		# Bonk into ceiling
		if p.z + DoomTypes.C.PLAYER_HEIGHT > ceil_z:
			p.z = ceil_z - DoomTypes.C.PLAYER_HEIGHT
			if p.z_vel > 0.0:
				p.z_vel = 0.0
	else:
		p.z = floor_z
	# Crouch lowers view height (smooth)
	var target_view: float = DoomTypes.C.CROUCH_HEIGHT if input.crouch else DoomTypes.C.PLAYER_VIEW_HEIGHT
	p.view_height = lerpf(p.view_height, target_view, minf(1.0, dt * 8.0))

## `actor` is either `st.player` or a `DoomTypes.Mobj` -- both independently
## declare `x`/`y` fields; GDScript's duck typing reaches either via plain
## property access, standing in for the original's `ref float x, ref float y`
## (GDScript has no reference parameters for value types like float, but
## mutating a shared object's fields directly achieves the same effect and is
## the more idiomatic GDScript translation -- see plan §1.4).
static func move_actor(st: DoomTypes.GameState, actor, dx: float, dy: float, radius: float, is_player: bool, self_idx: int = -1) -> void:
	var x: float = actor.x
	var y: float = actor.y
	var nx := x + dx
	var ny := y + dy
	# X axis
	if not collides_at(st, nx, y, radius, is_player, self_idx):
		x = nx
	if not collides_at(st, x, ny, radius, is_player, self_idx):
		y = ny
	actor.x = x
	actor.y = y

	# Phase 7 (original): step-up. After horizontal motion, snap player Z up to
	# the tallest cell footprint they're standing on (within STEP_HEIGHT).
	# Phase 9 (original): step-up uses the actor's CURRENT foot_z as the lower
	# bound, not 0 -- otherwise dropping into a pit at Z<0 trampolines the
	# player back to Z=0 because every neighbor cell's floor (Z=0) is greater
	# than the trivially-initialized best_floor.
	if is_player:
		var foot_z := st.player.z
		var gx0 := int(x - radius)
		var gx1 := int(x + radius)
		var gy0 := int(y - radius)
		var gy1 := int(y + radius)
		var best_floor := foot_z
		for gy in range(gy0, gy1 + 1):
			for gx in range(gx0, gx1 + 1):
				var fz: float = st.map.floor_at(gx, gy, foot_z, DoomTypes.C.STEP_HEIGHT)
				if fz > best_floor and fz - foot_z <= DoomTypes.C.STEP_HEIGHT + 0.001:
					best_floor = fz
		# Only auto-snap up while on or near the ground; jumping/falling is
		# handled by gravity in update_player_vertical.
		if best_floor > foot_z and absf(st.player.z_vel) < 0.01:
			st.player.z = best_floor
			st.player.z_vel = 0.0

static func collides_at(st: DoomTypes.GameState, x: float, y: float, r: float, is_player: bool, self_idx: int) -> bool:
	# wall collision with circle vs cell. For the player we use Z-aware
	# blocking so they can step over short ledges and crouch under low
	# ceilings; monsters retain the old 2D blocker semantics.
	var gx0 := int(x - r)
	var gx1 := int(x + r)
	var gy0 := int(y - r)
	var gy1 := int(y + r)
	var foot_z: float = st.player.z if is_player else 0.0
	var head_z: float
	if is_player:
		head_z = st.player.z + (DoomTypes.C.CROUCH_HEIGHT + 0.15 if st.player.view_height < DoomTypes.C.PLAYER_VIEW_HEIGHT else DoomTypes.C.PLAYER_HEIGHT)
	else:
		head_z = 0.7
	for gy in range(gy0, gy1 + 1):
		for gx in range(gx0, gx1 + 1):
			var blocks: bool = st.map.blocks_movement_z(gx, gy, foot_z, head_z, DoomTypes.C.STEP_HEIGHT) if is_player else st.map.blocks_movement(gx, gy)
			if blocks:
				var cx: float = clampf(x, gx, gx + 1)
				var cy: float = clampf(y, gy, gy + 1)
				var ddx := x - cx
				var ddy := y - cy
				if ddx * ddx + ddy * ddy < r * r:
					return true
	# mobj-vs-mobj (only for monsters)
	if not is_player and self_idx > 0:
		# don't push other monsters too aggressively, but block on big ones
		for j in range(1, st.mobj_count + 1):
			if j == self_idx:
				continue
			var m: DoomTypes.Mobj = st.mobjs[j]
			if m == null or m.id == 0 or (not is_monster(m.kind) and m.kind != DoomTypes.MobjKind.BARREL):
				continue
			if m.health <= 0:
				continue
			var dx2 := x - m.x
			var dy2 := y - m.y
			var r2 := r + m.radius
			if dx2 * dx2 + dy2 * dy2 < r2 * r2 * 0.7:
				return true
		# collide with player
		var pdx := x - st.player.x
		var pdy := y - st.player.y
		var pr := r + DoomTypes.C.PLAYER_RADIUS
		if pdx * pdx + pdy * pdy < pr * pr:
			return true
	return false

static func hurt(st: DoomTypes.GameState, p: DoomTypes.PlayerState, dmg_in: int, dir_hint: int) -> void:
	if not p.alive:
		return
	var dmg := dmg_in
	var diff: int = st.difficulty
	if diff == 0:
		dmg = int(dmg * 0.6)
	elif diff == 2:
		dmg = int(dmg * 1.5)
	if dmg < 1:
		dmg = 1

	if p.armor_class > 0 and p.armor > 0:
		var frac: float = 0.5 if p.armor_class == 2 else 0.33
		var absorb: int = mini(p.armor, int(dmg * frac))
		p.armor -= absorb
		dmg -= absorb
		if p.armor <= 0:
			p.armor_class = 0
	p.health -= dmg
	p.hurt_flash = minf(1.0, p.hurt_flash + dmg / 60.0)
	p.last_damage_dir = dir_hint
	p.face_state = 6
	p.face_timer = 0.5 # hurt face
	if p.health <= 0:
		p.health = 0
		p.alive = false
		p.face_state = 7
		st.game_over = true

## Widened from the original's `AdvanceFace(ref PlayerState p, dt)` to also
## take `st` -- needed to call the single consolidated `frand` RNG (plan
## §1.6, which replaces the original's stray `UnityEngine.Random.value`
## jitter here with the same deterministic LCG used everywhere else, fixing
## a real, minor inconsistency in the reference).
static func advance_face(st: DoomTypes.GameState, dt: float) -> void:
	var p := st.player
	p.face_timer -= dt
	if p.face_timer > 0:
		return
	if not p.alive:
		p.face_state = 7
		p.face_timer = 1.0
		return
	if p.hurt_flash > 0.3:
		p.face_state = 6
		p.face_timer = 0.4
		return
	var hp := p.health
	var bucket: int
	if hp >= 80:
		bucket = 1
	elif hp >= 60:
		bucket = 2
	elif hp >= 40:
		bucket = 3
	elif hp >= 20:
		bucket = 4
	else:
		bucket = 5
	p.face_state = bucket
	p.face_timer = 0.45 + frand(st) * 0.4

# ───── Mobj pool ─────

static func add_mobj(st: DoomTypes.GameState, m: DoomTypes.Mobj) -> void:
	if m.id == 0:
		m.id = st.next_mobj_id
		st.next_mobj_id += 1
	# Phase 8 (original): anchor newly-spawned mobj to the actual sector floor
	# at its spawn (X,Y). Without this, monsters spawned on a raised floor
	# (e.g. second-story plateau) sit at Z=0 -- sprites render through the
	# floor and 3D LOS uses the wrong height. Projectiles already set their
	# own Z.
	if st.sector_map.is_valid() and not is_projectile(m.kind) and m.z == 0.0:
		var sec := Raycast.point_in_sector_from_hint(st.sector_map, Vector2(m.x, m.y), -1)
		if sec >= 0:
			m.sector_id = sec
			# Phase 9 (original): pick the highest reachable surface so
			# monsters spawned inside an ExtraFloor footprint land on the
			# slab top, not the basement floor below it.
			m.z = standing_floor_in(st.sector_map.sectors[sec], 1e6, 1e6)
	# Phase 7 (original): floating mobjs hover above the floor.
	if m.kind == DoomTypes.MobjKind.CACODEMON or m.kind == DoomTypes.MobjKind.LOST_SOUL:
		m.z += 0.4

	if st.mobj_count + 1 < st.mobjs.size():
		st.mobj_count += 1
		st.mobjs[st.mobj_count] = m
	else:
		# find a free slot
		for i in range(1, st.mobjs.size()):
			if st.mobjs[i] == null or st.mobjs[i].id == 0:
				st.mobjs[i] = m
				return

static func compact_mobjs(st: DoomTypes.GameState) -> void:
	# periodic compaction: shrink mobj_count by trailing empties
	while st.mobj_count > 0 and (st.mobjs[st.mobj_count] == null or st.mobjs[st.mobj_count].id == 0):
		st.mobj_count -= 1

# Phase 9 (original): highest standable surface within `step_up` of the
# actor's feet, considering the sector floor and any solid ExtraFloor.top_z.
# The actor can stand on whichever is highest yet still reachable by a single
# step.
static func standing_floor_in(sec: DoomTypes.Sector, foot_z: float, step_up: float) -> float:
	var best := sec.floor_z
	if sec.extra_floors != null:
		for ef in sec.extra_floors:
			if not ef.solid:
				continue
			if ef.top_z <= foot_z + step_up + 0.001 and ef.top_z > best:
				best = ef.top_z
	return best

# Phase 9 (original): lowest blocking surface above the actor's head. Sector
# ceiling by default, or the bottom of any ExtraFloor that sits above the
# head (so a basement-dweller hits the courtyard slab as a low ceiling).
static func ceiling_above_in(sec: DoomTypes.Sector, foot_z: float, actor_height: float) -> float:
	var head_z := foot_z + actor_height
	var ceil_v: float = 1e9 if sec.is_sky else sec.ceiling_z
	if sec.extra_floors != null:
		for ef in sec.extra_floors:
			if not ef.solid:
				continue
			if ef.bottom_z >= head_z - 0.001 and ef.bottom_z < ceil_v:
				ceil_v = ef.bottom_z
	return ceil_v

# ───── Renderer ─────

static func cast_frame(st: DoomTypes.GameState) -> void:
	var p := st.player
	var cols := st.frame.columns
	var depth := st.frame.depth_buffer
	var use_sector := USE_SECTOR_RAYCAST and st.sector_map.is_valid() and p.sector_id >= 0
	# Phase 7 (original): real eye height. Walls reproject against this so
	# jump/crouch actually CHANGES geometry (walls get shorter, you see more
	# floor) rather than simply tilting the horizon. Sky/floor bands stay
	# anchored to the pitch-only horizon.
	var view_z := p.z + (0.6 if p.view_height <= 0.0 else p.view_height)
	var horizon := DoomTypes.C.VIEWPORT_H * 0.5 + p.pitch
	st.player.view_shift_px = 0.0

	for i in range(DoomTypes.C.VIEW_W):
		var camera_x := 2.0 * i / float(DoomTypes.C.VIEW_W) - 1.0 # -1..1
		var ray_ang := p.angle + atan(camera_x * tan(DoomTypes.C.HALF_FOV))
		var rdx := cos(ray_ang)
		var rdy := sin(ray_ang)
		var ang_cos := cos(ray_ang - p.angle)

		if use_sector:
			var col := build_column_sector(st, p.x, p.y, rdx, rdy, ang_cos, view_z, horizon)
			cols[i] = col
			depth[i] = col.main.distance
		else:
			var hit := cast_ray(st, p.x, p.y, rdx, rdy)
			var perp: float = hit.distance * ang_cos
			if perp < 0.001:
				perp = 0.001
			depth[i] = perp
			var wall_h: float = DoomTypes.C.VIEWPORT_H / perp
			var top := horizon - wall_h * 0.5
			var bot := horizon + wall_h * 0.5
			var light := light_from_dist(perp, hit.light)
			var col_info := DoomTypes.ColumnInfo.new()
			var main_seg := DoomTypes.WallSeg.new()
			main_seg.top_px = top
			main_seg.bot_px = bot
			main_seg.distance = perp
			main_seg.wall_tex_idx = hit.wall_tex_idx
			main_seg.tex_u = hit.tex_u
			main_seg.light_level = light
			main_seg.hit_vertical = hit.hit_vertical
			main_seg.is_sky = hit.is_sky
			col_info.main = main_seg
			col_info.extras = []
			col_info.floor_bands = []
			col_info.ceiling_bands = []
			cols[i] = col_info

# Phase 3 + Plan C (original): portal-walking column build with Doom-style
# vertical occlusion clipping. Maintains a per-ray (win_top, win_bot) screen-Y
# window tightened by every front floor / front ceiling / portal wall surface
# crossed. All emitted geometry is pre-clipped to that window -- so within a
# single column nothing ever overlaps in Y, and the renderer's paint order
# becomes correctness-irrelevant.
#
# Why this beats clamp-and-sort hacks:
#  - Stairs DOWN: the lower step's floor band is naturally clipped to the
#    upper step's silhouette (win_bot = upper_floor.y_far). No phantom cliff
#    wall has to be invented -- the cliff face is geometrically occluded by
#    the upper floor surface from the player's POV, so we don't emit it.
#  - Step UP: emits a real lower wall (riser) clipped to the window, then
#    pushes win_bot up. Subsequent floor bands beyond the riser only paint in
#    the still-visible top portion.
#  - Sky / open ceilings: don't push win_top; sky shows through.
#  - Closed door / terminal solid wall: emits Main clipped, ray ends.
#  - Window collapses -> ray bails early (perf win).
static func build_column_sector(st: DoomTypes.GameState, ox: float, oy: float, rdx: float, rdy: float,
		ang_cos: float, view_z: float, horizon: float) -> DoomTypes.ColumnInfo:
	var hits: Array = Raycast.cast(st.sector_map, Vector2(ox, oy), st.player.sector_id, Vector2(rdx, rdy))
	var extras: Array = [] # of DoomTypes.WallSeg
	var bands: Array = [] # of DoomTypes.FloorBand
	var ceil_bands: Array = [] # of DoomTypes.CeilingBand
	# Phase 8 (original): first step-up riser captured for sprite occlusion.
	var floor_occ_dist: float = INF
	var floor_occ_z: float = -INF
	# Phase 9 (original): closest ceiling-slab underside encountered along the
	# ray. Sprites past this distance whose anchor sits at-or-above this Z are
	# hidden by the slab.
	var ceil_occ_dist: float = INF
	var ceil_occ_z: float = INF

	# Vertical occlusion window. Stuff farther than the current hit can only
	# paint inside [win_top, win_bot]. Tightens monotonically as we walk the
	# ray, never widens.
	var win_top := 0.0
	var win_bot: float = DoomTypes.C.VIEWPORT_H
	var prev_perp := 0.001

	for i in range(hits.size()):
		var h: Raycast.WallHit = hits[i]
		var terminal := h.to_sector < 0
		var front: DoomTypes.Sector = st.sector_map.sectors[h.from_sector]
		var back: DoomTypes.Sector = null
		if h.to_sector >= 0:
			back = st.sector_map.sectors[h.to_sector]
			# Closed door: treat as terminal full-height wall.
			if back.ceiling_z <= back.floor_z + 0.001:
				terminal = true
		var line: DoomTypes.Linedef = st.sector_map.lines[h.linedef_id]

		var perp: float = h.distance * ang_cos
		if perp < 0.001:
			perp = 0.001
		var scale: float = DoomTypes.C.VIEWPORT_H / perp
		var scale_near: float = DoomTypes.C.VIEWPORT_H / maxf(prev_perp, 0.05)
		var light := light_from_dist(perp, front.light)

		var fz := front.floor_z
		var cz := front.ceiling_z
		# Floor projection at this hit (far edge of the band) and at the
		# previous hit (near edge of the band).
		var y_floor_far := horizon + (view_z - fz) * scale
		var y_floor_near := horizon + (view_z - fz) * scale_near
		# Ceiling projection (only meaningful when cz > view_z).
		var y_ceil_far := horizon - (cz - view_z) * scale

		# ── 1. Emit floor band for the segment we just crossed, clipped to
		#    the current visibility window. Skip floors at/above the eye --
		#    those don't render as a floor surface (they look like ceiling).
		if fz < view_z - 0.001:
			var b_top := y_floor_far
			var b_bot := y_floor_near
			if b_top < win_top:
				b_top = win_top
			if b_bot > win_bot:
				b_bot = win_bot
			if b_bot > b_top + 0.5:
				# Rim chalk-line is drawn at the far edge of the upper-step's
				# band when we're about to step down to a lower sector. Drawn
				# for any meaningful drop (>= 0.15u so 0.2u stair treads each
				# get their own line) and only when the band's top edge is the
				# true unclipped silhouette (not chopped by a higher occluder).
				var rim_at_far := h.to_sector >= 0 \
						and not terminal \
						and (fz - back.floor_z) >= 0.15 \
						and b_top <= y_floor_far + 0.5
				var fb := DoomTypes.FloorBand.new()
				fb.top_px = b_top
				fb.bot_px = b_bot
				fb.floor_z = fz
				fb.light = light
				fb.floor_tex = front.floor_tex
				fb.behind_floor_z = -INF
				fb.rim_at_far = rim_at_far
				bands.append(fb)

		# ── 2. Tighten window from the front-sector's own occluders. Floor
		#    below eye occludes anything beyond at screenY > y_floor_far
		#    (since farther floor pixels project closer to horizon = smaller
		#    screenY). So win_bot = min(win_bot, y_floor_far). Ceiling above
		#    eye (non-sky) occludes anything beyond above y_ceil_far. Sky
		#    doesn't occlude -- it shows through.
		if fz < view_z - 0.001:
			if y_floor_far < win_bot:
				win_bot = y_floor_far
		# Phase 8 (original): emit ceiling band for the segment we just
		# crossed, mirroring the floor-band logic. Only for non-sky sectors
		# with a ceiling above the eye -- sky leaves the backdrop showing
		# through and ceilings at/below eye look like floors (handled
		# elsewhere).
		if not front.is_sky and cz > view_z + 0.001:
			var c_top_band := win_top
			var c_bot_band := y_ceil_far
			if c_bot_band > win_bot:
				c_bot_band = win_bot
			if c_bot_band > c_top_band + 0.5:
				var cb := DoomTypes.CeilingBand.new()
				cb.top_px = c_top_band
				cb.bot_px = c_bot_band
				cb.ceiling_z = cz
				cb.light = light
				cb.ceiling_tex = front.ceiling_tex
				ceil_bands.append(cb)
		if not front.is_sky and cz > view_z + 0.001:
			if y_ceil_far > win_top:
				win_top = y_ceil_far

		# ── 2b. Phase 9 (original): per-ExtraFloor slab emission. Each slab
		#    contributes up to three surfaces in the front sector: TOP plane
		#    (visible if viewer is above it, acts like a raised floor),
		#    BOTTOM plane (visible if viewer is below it, acts like a low
		#    ceiling), and a SIDE wall on the boundary where the back sector
		#    lacks the same slab. Iterating in bottom_z-ascending order keeps
		#    the cliprange window tightening monotonic.
		var slab_terminated := false
		var terminator_wall: DoomTypes.WallSeg = null
		if front.extra_floors != null:
			for k in range(front.extra_floors.size()):
				var ef: DoomTypes.ExtraFloor = front.extra_floors[k]
				var shared_with_back := false
				if h.to_sector >= 0 and back.extra_floors != null:
					for j in range(back.extra_floors.size()):
						var bef: DoomTypes.ExtraFloor = back.extra_floors[j]
						if absf(bef.bottom_z - ef.bottom_z) < 0.01 and absf(bef.top_z - ef.top_z) < 0.01:
							shared_with_back = true
							break
				var above_slab := view_z > ef.top_z + 0.001
				var below_slab := view_z < ef.bottom_z - 0.001
				var slab_light := light_from_dist(perp, front.light if ef.light == 0 else ef.light)

				# Slab TOP -- visible when viewer above, acts like a raised floor.
				if above_slab:
					var y_top_far := horizon + (view_z - ef.top_z) * scale
					var y_top_near := horizon + (view_z - ef.top_z) * scale_near
					var bt: float = win_top if y_top_far < win_top else y_top_far
					var bb: float = win_bot if y_top_near > win_bot else y_top_near
					if bb > bt + 0.5:
						var fb2 := DoomTypes.FloorBand.new()
						fb2.top_px = bt
						fb2.bot_px = bb
						fb2.floor_z = ef.top_z
						fb2.light = slab_light
						fb2.floor_tex = ef.top_tex
						fb2.behind_floor_z = -INF
						fb2.rim_at_far = not shared_with_back
						bands.append(fb2)
					if y_top_far < win_bot:
						win_bot = y_top_far
					# Sprite occluder hint -- closest slab top wins.
					if floor_occ_dist > perp:
						floor_occ_dist = perp
						floor_occ_z = ef.top_z

				# Slab BOTTOM -- visible when viewer below, acts like a low ceiling.
				if below_slab:
					var y_bot_far := horizon - (ef.bottom_z - view_z) * scale
					var ct := win_top
					var cb2: float = win_bot if y_bot_far > win_bot else y_bot_far
					if cb2 > ct + 0.5:
						var cbd := DoomTypes.CeilingBand.new()
						cbd.top_px = ct
						cbd.bot_px = cb2
						cbd.ceiling_z = ef.bottom_z
						cbd.light = slab_light
						cbd.ceiling_tex = ef.bottom_tex
						ceil_bands.append(cbd)
					if y_bot_far > win_top:
						win_top = y_bot_far
					# Sprite occluder hint -- closest slab bottom wins.
					if ceil_occ_dist > perp:
						ceil_occ_dist = perp
						ceil_occ_z = ef.bottom_z

				# Slab SIDE -- exposed when back sector lacks the same slab.
				# If the viewer is INSIDE the slab body and the side is
				# exposed, the slab is opaque and we terminate the column at
				# this hit.
				if not shared_with_back and ef.solid:
					var w_top := horizon - (ef.top_z - view_z) * scale
					var w_bot := horizon - (ef.bottom_z - view_z) * scale
					var c_top: float = win_top if w_top < win_top else w_top
					var c_bot: float = win_bot if w_bot > win_bot else w_bot
					if c_bot > c_top + 0.5:
						var seg := DoomTypes.WallSeg.new()
						seg.top_px = c_top
						seg.bot_px = c_bot
						seg.distance = perp
						seg.wall_tex_idx = ef.side_tex
						seg.tex_u = h.u
						seg.light_level = slab_light
						seg.hit_vertical = false
						seg.is_sky = false
						seg.tex_offset_px = w_top - c_top
						if not above_slab and not below_slab:
							# Inside slab body -> opaque terminal.
							slab_terminated = true
							terminator_wall = seg
						else:
							extras.append(seg)

		# Phase 9 (original): ALSO emit BACK-only ExtraFloor slabs (those not
		# present in the front sector) -- same surfaces + cliprange
		# tightening as the front loop:
		#   - SIDE wall at the portal (otherwise the slab pillar is
		#     see-through from cells without ExtraFloors of their own).
		#   - TOP plane as a FloorBand when viewer is above the slab --
		#     without this the next stair tread shows no visible top, the
		#     staircase looks like a smooth wall going up instead of
		#     discrete treads.
		#   - BOTTOM plane as a CeilingBand when viewer is below the slab.
		#   - Tighten (win_top, win_bot) by the slab's screen-Y body so
		#     things past the staircase don't bleed THROUGH the slab side.
		#   - Terminate if viewer is INSIDE the slab body (ray hits opaque
		#     side wall edge-on, fully occluded past this hit).
		if h.to_sector >= 0 and back.extra_floors != null:
			for k in range(back.extra_floors.size()):
				var ef2: DoomTypes.ExtraFloor = back.extra_floors[k]
				if not ef2.solid:
					continue
				var in_front := false
				if front.extra_floors != null:
					for j in range(front.extra_floors.size()):
						var fef: DoomTypes.ExtraFloor = front.extra_floors[j]
						if absf(fef.bottom_z - ef2.bottom_z) < 0.01 and absf(fef.top_z - ef2.top_z) < 0.01:
							in_front = true
							break
				if in_front:
					continue
				var slab_light2 := light_from_dist(perp, back.light if ef2.light == 0 else ef2.light)
				var above_slab2 := view_z > ef2.top_z + 0.001
				var below_slab2 := view_z < ef2.bottom_z - 0.001

				# Slab side endpoints in screen Y (positive = down).
				var y_top_far2 := horizon - (ef2.top_z - view_z) * scale
				var y_bot_far2 := horizon - (ef2.bottom_z - view_z) * scale

				# SIDE wall, clipped to current window. Never a terminator:
				# back-only slabs only occlude the screen-Y band
				# [y_top_far2..y_bot_far2]; above and below that band the
				# column stays open so taller slabs further along the ray
				# (e.g. higher stair treads) can still emit.
				var c_top2: float = win_top if y_top_far2 < win_top else y_top_far2
				var c_bot2: float = win_bot if y_bot_far2 > win_bot else y_bot_far2
				if c_bot2 > c_top2 + 0.5:
					var seg2 := DoomTypes.WallSeg.new()
					seg2.top_px = c_top2
					seg2.bot_px = c_bot2
					seg2.distance = perp
					seg2.wall_tex_idx = ef2.side_tex
					seg2.tex_u = h.u
					seg2.light_level = slab_light2
					seg2.hit_vertical = false
					seg2.is_sky = false
					seg2.tex_offset_px = y_top_far2 - c_top2
					extras.append(seg2)

				# TOP plane -- FloorBand visible above the slab.
				if above_slab2:
					var y_top_near2 := horizon + (view_z - ef2.top_z) * scale_near
					var y_top_far_flip := horizon + (view_z - ef2.top_z) * scale
					var bt2: float = win_top if y_top_far_flip < win_top else y_top_far_flip
					var bb2: float = win_bot if y_top_near2 > win_bot else y_top_near2
					if bb2 > bt2 + 0.5:
						var fb3 := DoomTypes.FloorBand.new()
						fb3.top_px = bt2
						fb3.bot_px = bb2
						fb3.floor_z = ef2.top_z
						fb3.light = slab_light2
						fb3.floor_tex = ef2.top_tex
						fb3.behind_floor_z = -INF
						fb3.rim_at_far = true
						bands.append(fb3)

				# BOTTOM plane -- CeilingBand visible below the slab.
				if below_slab2:
					var ct2 := win_top
					var cb3: float = win_bot if y_bot_far2 > win_bot else y_bot_far2
					if cb3 > ct2 + 0.5:
						var cbd2 := DoomTypes.CeilingBand.new()
						cbd2.top_px = ct2
						cbd2.bot_px = cb3
						cbd2.ceiling_z = ef2.bottom_z
						cbd2.light = slab_light2
						cbd2.ceiling_tex = ef2.bottom_tex
						ceil_bands.append(cbd2)

				# Cliprange occlusion. We can only tighten one boundary
				# cleanly (single-window cliprange), so:
				#   - viewer above slab -> occlude below slab top
				#     (win_bot = y_top_far2). This is the stair-walking case:
				#     keeps the upper window open so taller slabs further
				#     along still emit their tops.
				#   - viewer below slab -> occlude above slab bottom
				#     (win_top = y_bot_far2).
				#   - viewer inside slab body -> same as above
				#     (win_bot = y_top_far2). Sacrifices visibility of stuff
				#     below the slab bottom past this hit (usually floor
				#     anyway), but keeps stuff ABOVE the slab top visible --
				#     critical for stair treads going up.
				if not below_slab2:
					if y_top_far2 < win_bot:
						win_bot = y_top_far2
				else:
					if y_bot_far2 > win_top:
						win_top = y_bot_far2

		if slab_terminated:
			var col_t := DoomTypes.ColumnInfo.new()
			col_t.main = terminator_wall
			col_t.extras = extras
			col_t.front_floor_z = fz
			col_t.floor_bands = bands
			col_t.ceiling_bands = ceil_bands
			col_t.floor_occluder_dist = floor_occ_dist
			col_t.floor_occluder_z = floor_occ_z
			col_t.ceiling_occluder_dist = ceil_occ_dist
			col_t.ceiling_occluder_z = ceil_occ_z
			return col_t

		# ── 3a. TERMINAL hit (solid wall or closed door). Emit Main clipped
		#    to current window.
		if terminal:
			var ceil_for_wall: float = minf(cz, fz + 2.5) if front.is_sky else cz
			var w_top2 := horizon - (ceil_for_wall - view_z) * scale
			var w_bot2 := horizon - (fz - view_z) * scale
			var unclipped_top := w_top2
			if w_top2 < win_top:
				w_top2 = win_top
			if w_bot2 > win_bot:
				w_bot2 = win_bot
			var main := DoomTypes.WallSeg.new()
			main.top_px = w_top2
			main.bot_px = w_bot2
			main.distance = perp
			main.wall_tex_idx = line.mid_tex
			main.tex_u = h.u
			main.light_level = light
			main.hit_vertical = false
			main.is_sky = h.to_sector >= 0 and back.is_sky
			main.tex_offset_px = unclipped_top - w_top2
			var col := DoomTypes.ColumnInfo.new()
			col.main = main
			col.extras = extras
			col.front_floor_z = fz
			col.floor_bands = bands
			col.ceiling_bands = ceil_bands
			col.floor_occluder_dist = floor_occ_dist
			col.floor_occluder_z = floor_occ_z
			col.ceiling_occluder_dist = ceil_occ_dist
			col.ceiling_occluder_z = ceil_occ_z
			return col

		# ── 3b. PORTAL UPPER: back ceiling LOWER than front ceiling. Emit
		#    upper wall clipped, then push win_top down. Skip for sky-back
		#    (sky portals show sky above, not a wall).
		if back.ceiling_z < front.ceiling_z - 0.001 and not back.is_sky:
			var w_top3 := horizon - (front.ceiling_z - view_z) * scale
			var w_bot3 := horizon - (back.ceiling_z - view_z) * scale
			var c_top3 := w_top3
			var c_bot3 := w_bot3
			if c_top3 < win_top:
				c_top3 = win_top
			if c_bot3 > win_bot:
				c_bot3 = win_bot
			if c_bot3 > c_top3 + 0.5:
				var seg3 := DoomTypes.WallSeg.new()
				seg3.top_px = c_top3
				seg3.bot_px = c_bot3
				seg3.distance = perp
				seg3.wall_tex_idx = line.upper_tex
				seg3.tex_u = h.u
				seg3.light_level = light
				seg3.hit_vertical = false
				seg3.is_sky = false
				seg3.tex_offset_px = w_top3 - c_top3
				extras.append(seg3)
			if w_bot3 > win_top:
				win_top = w_bot3

		# ── 3c. PORTAL LOWER (step-up): back floor HIGHER than front floor.
		#    Emit lower wall clipped, then push win_bot up.
		if back.floor_z > front.floor_z + 0.001:
			# Sprite occlusion: first step-up wins (closest occluder along ray).
			if floor_occ_dist > perp:
				floor_occ_dist = perp
				floor_occ_z = back.floor_z
			var w_top4 := horizon - (back.floor_z - view_z) * scale
			var w_bot4 := horizon - (front.floor_z - view_z) * scale
			var c_top4 := w_top4
			var c_bot4 := w_bot4
			if c_top4 < win_top:
				c_top4 = win_top
			if c_bot4 > win_bot:
				c_bot4 = win_bot
			if c_bot4 > c_top4 + 0.5:
				# Riser flag -> chalk-line rim, only for tall steps.
				var tall_step := (back.floor_z - front.floor_z) >= 0.5
				var seg4 := DoomTypes.WallSeg.new()
				seg4.top_px = c_top4
				seg4.bot_px = c_bot4
				seg4.distance = perp
				seg4.wall_tex_idx = line.lower_tex
				seg4.tex_u = h.u
				seg4.light_level = light
				seg4.hit_vertical = false
				seg4.is_sky = false
				seg4.is_riser = tall_step
				seg4.tex_offset_px = w_top4 - c_top4
				extras.append(seg4)
			if w_top4 < win_bot:
				win_bot = w_top4

		# ── 3d. PORTAL STEP-DOWN (back floor LOWER than front floor):
		#    INTENTIONALLY no wall emitted. The cliff face from above is
		#    geometrically occluded by the upper floor surface -- emitting
		#    it produces "phantom brick stripes" on stairs. The visual "rim"
		#    is the silhouette = upper band's far edge, already drawn above.
		#    Beyond this hit, the lower floor's band paints clipped to the
		#    already-tightened win_bot=y_floor_far.

		prev_perp = perp

		# Window collapsed -> nothing past this hit can be visible.
		if win_bot - win_top < 1.0:
			var main5 := DoomTypes.WallSeg.new()
			main5.top_px = 0.0
			main5.bot_px = 0.0
			main5.distance = perp
			main5.wall_tex_idx = 0
			main5.tex_u = 0.0
			main5.light_level = light
			main5.hit_vertical = false
			main5.is_sky = false
			var col5 := DoomTypes.ColumnInfo.new()
			col5.main = main5
			col5.extras = extras
			col5.front_floor_z = fz
			col5.floor_bands = bands
			col5.ceiling_bands = ceil_bands
			col5.floor_occluder_dist = floor_occ_dist
			col5.floor_occluder_z = floor_occ_z
			col5.ceiling_occluder_dist = ceil_occ_dist
			col5.ceiling_occluder_z = ceil_occ_z
			return col5

	# Ray escaped -- sky column.
	var main6 := DoomTypes.WallSeg.new()
	main6.top_px = 0.0
	main6.bot_px = 0.0
	main6.distance = DoomTypes.C.MAX_RAY
	main6.wall_tex_idx = 0
	main6.tex_u = 0.0
	main6.light_level = 200
	main6.hit_vertical = false
	main6.is_sky = true
	var col6 := DoomTypes.ColumnInfo.new()
	col6.main = main6
	col6.extras = extras
	col6.front_floor_z = 0.0
	col6.floor_bands = bands
	col6.ceiling_bands = ceil_bands
	col6.floor_occluder_dist = floor_occ_dist
	col6.floor_occluder_z = floor_occ_z
	col6.ceiling_occluder_dist = ceil_occ_dist
	col6.ceiling_occluder_z = ceil_occ_z
	return col6

## DDA grid-walker fallback (used when USE_SECTOR_RAYCAST is false).
static func cast_ray(st: DoomTypes.GameState, ox: float, oy: float, dx: float, dy: float) -> RayHit:
	var map_x := int(ox)
	var map_y := int(oy)
	var delta_x: float = 1e30 if dx == 0.0 else absf(1.0 / dx)
	var delta_y: float = 1e30 if dy == 0.0 else absf(1.0 / dy)
	var step_x: int
	var step_y: int
	var side_x: float
	var side_y: float
	if dx < 0.0:
		step_x = -1
		side_x = (ox - map_x) * delta_x
	else:
		step_x = 1
		side_x = (map_x + 1.0 - ox) * delta_x
	if dy < 0.0:
		step_y = -1
		side_y = (oy - map_y) * delta_y
	else:
		step_y = 1
		side_y = (map_y + 1.0 - oy) * delta_y

	var vertical := false
	var safety := 0
	while safety < 96:
		safety += 1
		if side_x < side_y:
			side_x += delta_x
			map_x += step_x
			vertical = true
		else:
			side_y += delta_y
			map_y += step_y
			vertical = false
		if map_x < 0 or map_x >= st.map.width or map_y < 0 or map_y >= st.map.height:
			var esc := RayHit.new()
			esc.distance = DoomTypes.C.MAX_RAY
			esc.is_sky = true
			esc.light = 200
			return esc
		var c := st.map.at_safe(map_x, map_y)
		if c.kind == DoomTypes.CellKind.WALL or (c.kind >= DoomTypes.CellKind.DOOR and c.kind <= DoomTypes.CellKind.DOOR_RED and c.door_state < 250):
			var dist: float
			var u: float
			if vertical:
				dist = side_x - delta_x
				var hit_y := oy + dist * dy
				u = hit_y - floor(hit_y)
				if dx > 0.0:
					u = 1.0 - u
			else:
				dist = side_y - delta_y
				var hit_x := ox + dist * dx
				u = hit_x - floor(hit_x)
				if dy < 0.0:
					u = 1.0 - u
			# for doors with partial open, account by shifting the texture
			# vertically -- just clip distance min
			if dist < 0.05:
				dist = 0.05
			var rh := RayHit.new()
			rh.distance = dist
			rh.wall_tex_idx = c.wall_tex_idx
			rh.tex_u = u
			rh.light = c.light_level
			rh.hit_vertical = vertical
			rh.is_sky = false
			return rh
		if c.kind == DoomTypes.CellKind.EXIT and c.wall_tex_idx != 0:
			var dist2: float
			var u2: float
			if vertical:
				dist2 = side_x - delta_x
				var hit_y2 := oy + dist2 * dy
				u2 = hit_y2 - floor(hit_y2)
				if dx > 0.0:
					u2 = 1.0 - u2
			else:
				dist2 = side_y - delta_y
				var hit_x2 := ox + dist2 * dx
				u2 = hit_x2 - floor(hit_x2)
				if dy < 0.0:
					u2 = 1.0 - u2
			var rh2 := RayHit.new()
			rh2.distance = dist2
			rh2.wall_tex_idx = DoomTextures.W_EXIT
			rh2.tex_u = u2
			rh2.light = 240
			rh2.hit_vertical = vertical
			return rh2
	var esc2 := RayHit.new()
	esc2.distance = DoomTypes.C.MAX_RAY
	esc2.is_sky = true
	esc2.light = 200
	return esc2

static func light_from_dist(dist: float, cell_light: int) -> int:
	var fade := clampf(1.0 - dist / 14.0, 0.0, 1.0)
	var v := int(cell_light * (0.35 + 0.65 * fade))
	if v < 30:
		v = 30
	if v > 255:
		v = 255
	return v

# ───── Misc classification helpers ─────
# (Needed by the renderer's sprite-list building and by later phases; ported
# now since each is tiny and self-contained.)

static func is_monster(k: int) -> bool:
	return k == DoomTypes.MobjKind.IMP or k == DoomTypes.MobjKind.DEMON or k == DoomTypes.MobjKind.BARON \
			or k == DoomTypes.MobjKind.CACODEMON or k == DoomTypes.MobjKind.LOST_SOUL \
			or k == DoomTypes.MobjKind.ZOMBIEMAN or k == DoomTypes.MobjKind.SHOTGUNNER

static func is_boss(k: int) -> bool:
	return k == DoomTypes.MobjKind.BARON or k == DoomTypes.MobjKind.CACODEMON

# True while any boss-tier monster (Baron / Cacodemon) is still alive on the
# map. Used to gate level-exit cells when LevelStart.boss_exit_gated is set.
static func any_boss_alive(st: DoomTypes.GameState) -> bool:
	for i in range(1, st.mobj_count + 1):
		var m: DoomTypes.Mobj = st.mobjs[i]
		if m == null or not is_boss(m.kind):
			continue
		if m.state == DoomTypes.AIState.DEAD:
			continue
		return true
	return false

static func is_projectile(k: int) -> bool:
	return k == DoomTypes.MobjKind.IMP_FIREBALL or k == DoomTypes.MobjKind.BARON_BALL or k == DoomTypes.MobjKind.CACO_BALL \
			or k == DoomTypes.MobjKind.ROCKET_PROJ or k == DoomTypes.MobjKind.PLASMA_PROJ or k == DoomTypes.MobjKind.BFG_PROJ

static func is_pickup(k: int) -> bool:
	return k >= DoomTypes.MobjKind.PICKUP_HEALTH and k <= DoomTypes.MobjKind.KEY_RED

static func sprite_index_for_mobj(k: int) -> int:
	match k:
		DoomTypes.MobjKind.IMP:
			return DoomTextures.S_IMP
		DoomTypes.MobjKind.DEMON:
			return DoomTextures.S_DEMON
		DoomTypes.MobjKind.BARON:
			return DoomTextures.S_BARON
		DoomTypes.MobjKind.CACODEMON:
			return DoomTextures.S_CACO
		DoomTypes.MobjKind.LOST_SOUL:
			return DoomTextures.S_LOSTSOUL
		DoomTypes.MobjKind.ZOMBIEMAN:
			return DoomTextures.S_IMP # reuse
		DoomTypes.MobjKind.SHOTGUNNER:
			return DoomTextures.S_BARON # reuse with tint
		DoomTypes.MobjKind.CORPSE:
			return DoomTextures.S_CORPSE
		DoomTypes.MobjKind.IMP_FIREBALL:
			return DoomTextures.S_FIREBALL
		DoomTypes.MobjKind.BARON_BALL:
			return DoomTextures.S_FIREBALL
		DoomTypes.MobjKind.CACO_BALL:
			return DoomTextures.S_PLASMA
		DoomTypes.MobjKind.ROCKET_PROJ:
			return DoomTextures.S_ROCKET_PROJ
		DoomTypes.MobjKind.PLASMA_PROJ:
			return DoomTextures.S_PLASMA
		DoomTypes.MobjKind.BFG_PROJ:
			return DoomTextures.S_BFG_PROJ
		DoomTypes.MobjKind.EXPLOSION:
			return DoomTextures.S_EXPLOSION
		DoomTypes.MobjKind.PICKUP_HEALTH:
			return DoomTextures.S_HEALTH
		DoomTypes.MobjKind.PICKUP_ARMOR:
			return DoomTextures.S_ARMOR
		DoomTypes.MobjKind.PICKUP_ARMOR_BLUE:
			return DoomTextures.S_ARMOR
		DoomTypes.MobjKind.PICKUP_BULLETS:
			return DoomTextures.S_AMMO_BULLETS
		DoomTypes.MobjKind.PICKUP_SHELLS:
			return DoomTextures.S_AMMO_SHELLS
		DoomTypes.MobjKind.PICKUP_ROCKETS:
			return DoomTextures.S_AMMO_ROCKETS
		DoomTypes.MobjKind.PICKUP_CELLS:
			return DoomTextures.S_AMMO_CELLS
		DoomTypes.MobjKind.PICKUP_SHOTGUN:
			return DoomTextures.S_PICKUP_SHOTGUN
		DoomTypes.MobjKind.PICKUP_CHAINGUN:
			return DoomTextures.S_PICKUP_CHAIN
		DoomTypes.MobjKind.PICKUP_ROCKET_LAUNCHER:
			return DoomTextures.S_PICKUP_ROCKET
		DoomTypes.MobjKind.PICKUP_PLASMA:
			return DoomTextures.S_PICKUP_PLASMA
		DoomTypes.MobjKind.PICKUP_BFG:
			return DoomTextures.S_PICKUP_BFG
		DoomTypes.MobjKind.KEY_BLUE:
			return DoomTextures.S_KEY_BLUE
		DoomTypes.MobjKind.KEY_YELLOW:
			return DoomTextures.S_KEY_YELLOW
		DoomTypes.MobjKind.KEY_RED:
			return DoomTextures.S_KEY_RED
		DoomTypes.MobjKind.BARREL:
			return DoomTextures.S_BARREL
		DoomTypes.MobjKind.LIGHT:
			return DoomTextures.S_LIGHT
		_:
			return DoomTextures.S_IMP

static func tint_for_mobj(k: int, s: int) -> Color:
	if s == DoomTypes.AIState.PAIN:
		return Color(255.0 / 255.0, 200.0 / 255.0, 200.0 / 255.0, 1.0)
	match k:
		DoomTypes.MobjKind.SHOTGUNNER:
			return Color(150.0 / 255.0, 220.0 / 255.0, 150.0 / 255.0, 1.0)
		DoomTypes.MobjKind.ZOMBIEMAN:
			return Color(180.0 / 255.0, 180.0 / 255.0, 200.0 / 255.0, 1.0)
		_:
			return Color(1.0, 1.0, 1.0, 1.0)

static func message(p: DoomTypes.PlayerState, text: String, dur: float) -> void:
	p.message_text = text
	p.message_timer = dur

## Tiny LCG random -- deterministic per game (matches the original's `Frand`).
static func frand(st: DoomTypes.GameState) -> float:
	st.rng_seed = wrapi(st.rng_seed * 1103515245 + 12345, -2147483648, 2147483648)
	return float((st.rng_seed >> 16) & 0x7fff) / float(0x7fff)
