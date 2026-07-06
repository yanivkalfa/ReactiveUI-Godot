class_name DoomGameScreenLogic
extends RefCounted

## Faithful port of the Unity ReactiveUIToolKit `DoomGame` sample's
## `DoomGameScreenLogic.uitkx` -- pure per-tick list-building functions that feed the
## viewport's `@for`-emitted markup (real host elements per plan §1.1, not a draw
## routine). No hook calls, so a plain script rather than a `.guitkx` `module`/`hook`.
## See plans/DOOM_GAME_GUITKX_PORT_PLAN.md.

class SpriteEntry extends RefCounted:
	var id: int
	var sprite_idx: int
	var screen_x: float
	var screen_y: float
	var size: float
	var distance: float
	var tint: Color
	var light: float

static func build_sprite_list(state: DoomTypes.GameState) -> Array:
	var list: Array = [] # of SpriteEntry
	var p := state.player
	var cos_a := cos(p.angle)
	var sin_a := sin(p.angle)
	var half_h: float = DoomTypes.C.VIEWPORT_H * 0.5
	var plane_scale: float = half_h / tan(DoomTypes.C.HALF_FOV)
	var depth := state.frame.depth_buffer
	var width_scale: float = DoomTypes.C.VIEWPORT_W / float(DoomTypes.C.VIEW_W)
	# Phase 7 (original): eye Z so sprites reproject correctly when the
	# player jumps/crouches.
	var view_z: float = p.z + (0.6 if p.view_height <= 0.0 else p.view_height)

	for i in range(1, state.mobj_count + 1):
		var m: DoomTypes.Mobj = state.mobjs[i]
		if m == null or m.id == 0:
			continue
		if m.kind == DoomTypes.MobjKind.LIGHT:
			continue
		if GameLogic.is_monster(m.kind) and m.state == DoomTypes.AIState.DEAD:
			continue

		var dx := m.x - p.x
		var dy := m.y - p.y
		# forward = (cos a, sin a); right = (-sin a, cos a)
		var ty := dx * cos_a + dy * sin_a # depth along view direction
		var tx := -dx * sin_a + dy * cos_a # lateral, +right
		if ty < 0.2:
			continue

		var screen_x: float = (DoomTypes.C.VIEWPORT_W * 0.5) + (tx / ty) * plane_scale
		var sprite_h: float = (1.0 / ty) * plane_scale * sprite_scale(m.kind)
		# Sprite anchor: feet (m.z) for floor-standing things, slight lift
		# for floating mobjs -- combined into world Z relative to view_z.
		var anchor_world_z := m.z + sprite_vertical_anchor(m.kind)
		var screen_y: float = (DoomTypes.C.VIEWPORT_H * 0.5 + p.pitch) - ((anchor_world_z - view_z) / ty) * plane_scale

		var dcol := int(screen_x / width_scale)
		if dcol >= 0 and dcol < depth.size() and ty > depth[dcol] + 0.05:
			continue
		# Phase 8 (original): floor-step occlusion. If the column's first
		# riser sits in front of the sprite AND the sprite's anchor Z is
		# below the riser top, the riser hides the sprite. Stops monsters
		# from showing through stair treads / second-story plateaus.
		if dcol >= 0 and dcol < state.frame.columns.size():
			var ci: DoomTypes.ColumnInfo = state.frame.columns[dcol]
			if ty > ci.floor_occluder_dist + 0.02 and anchor_world_z < ci.floor_occluder_z - 0.05:
				continue
			# Phase 9 (original): looking-UP occlusion against a
			# ceiling-slab underside. Mirror of the floor-occluder test: if
			# the column has a slab bottom in front of the sprite AND the
			# sprite's anchor sits at or above the slab bottom, the slab
			# hides it.
			if ty > ci.ceiling_occluder_dist + 0.02 and anchor_world_z > ci.ceiling_occluder_z - 0.05:
				continue
			# Phase 8 (original): looking-DOWN occlusion. The first floor
			# band in the ray is the player's own sector floor; its top_px
			# is the cliff/portal silhouette. A sprite in a sector with
			# LOWER floor than that -- i.e. the courtyard seen over a
			# plateau edge -- is partially or fully hidden by the upper
			# floor's visible region. Cull when the sprite anchor projects
			# BELOW (greater screenY than) that silhouette AND the sprite
			# floor is below the upper-band floor.
			var bands := ci.floor_bands
			if bands != null and bands.size() > 0:
				var b0: DoomTypes.FloorBand = bands[0]
				# Projected silhouette of the upper floor's far edge at this column.
				var silh_y := b0.top_px
				if anchor_world_z < b0.floor_z - 0.1 and screen_y > silh_y + 1.0:
					continue

		var light_fade := clampf(1.0 - ty / 16.0, 0.0, 1.0)
		var light := 0.35 + 0.65 * light_fade

		var e := SpriteEntry.new()
		e.id = m.id
		e.sprite_idx = GameLogic.sprite_index_for_mobj(m.kind)
		e.screen_x = screen_x
		e.screen_y = screen_y
		e.size = sprite_h
		e.distance = ty
		e.tint = GameLogic.tint_for_mobj(m.kind, m.state)
		e.light = light
		list.append(e)

	list.sort_custom(func(a: SpriteEntry, b: SpriteEntry) -> bool: return a.distance > b.distance)
	return list

static func sprite_scale(k: int) -> float:
	match k:
		DoomTypes.MobjKind.BARON:
			return 1.6
		DoomTypes.MobjKind.CACODEMON:
			return 1.4
		DoomTypes.MobjKind.DEMON:
			return 1.2
		DoomTypes.MobjKind.BARREL:
			return 0.8
		DoomTypes.MobjKind.PICKUP_HEALTH, DoomTypes.MobjKind.PICKUP_ARMOR, DoomTypes.MobjKind.PICKUP_ARMOR_BLUE, \
		DoomTypes.MobjKind.PICKUP_BULLETS, DoomTypes.MobjKind.PICKUP_SHELLS, DoomTypes.MobjKind.PICKUP_ROCKETS, DoomTypes.MobjKind.PICKUP_CELLS:
			return 0.6
		DoomTypes.MobjKind.KEY_BLUE, DoomTypes.MobjKind.KEY_YELLOW, DoomTypes.MobjKind.KEY_RED:
			return 0.55
		DoomTypes.MobjKind.IMP_FIREBALL, DoomTypes.MobjKind.BARON_BALL, DoomTypes.MobjKind.CACO_BALL, \
		DoomTypes.MobjKind.PLASMA_PROJ, DoomTypes.MobjKind.ROCKET_PROJ, DoomTypes.MobjKind.BFG_PROJ:
			return 0.6
		DoomTypes.MobjKind.EXPLOSION:
			return 1.6
		_:
			return 1.0

static func sprite_vertical_anchor(k: int) -> float:
	if k == DoomTypes.MobjKind.CACODEMON:
		return 0.0
	if k == DoomTypes.MobjKind.LOST_SOUL:
		return -0.05
	if GameLogic.is_projectile(k):
		return -0.05
	if k == DoomTypes.MobjKind.EXPLOSION:
		return -0.05
	return 0.15

# Phase 3 (original): flattened list of extra wall segs (upper/lower from
# portals). The Main seg is rendered separately by the existing wall loop.
class ExtraSegEntry extends RefCounted:
	var col_index: int
	var seg_index: int # index within the column's extras array (stable key)
	var seg: DoomTypes.WallSeg

static func build_extra_seg_list(state: DoomTypes.GameState) -> Array:
	var list: Array = [] # of ExtraSegEntry
	var cols := state.frame.columns
	for i in range(cols.size()):
		var ex: Array = cols[i].extras
		if ex == null:
			continue
		for j in range(ex.size()):
			var e := ExtraSegEntry.new()
			e.col_index = i
			e.seg_index = j
			e.seg = ex[j]
			list.append(e)
	return list

# Phase 7 (original): per-column floor band entries for rendering.
class FloorBandEntry extends RefCounted:
	var col_index: int
	var band: DoomTypes.FloorBand

static func build_floor_band_list(state: DoomTypes.GameState) -> Array:
	var list: Array = [] # of FloorBandEntry
	var cols := state.frame.columns
	for i in range(cols.size()):
		var bands: Array = cols[i].floor_bands
		if bands == null:
			continue
		for j in range(bands.size()):
			var e := FloorBandEntry.new()
			e.col_index = i
			e.band = bands[j]
			list.append(e)
	return list

# Phase 7 (original): horizontally merged floor bands. Adjacent columns
# sharing the same floor slab (Z quantized to 0.2u) and similar screen Y
# range collapse into a single wide rect. Cuts element count from N*B down
# to a handful.
class MergedFloorBand extends RefCounted:
	var col_start: int
	var col_end: int # inclusive
	var top_px: float
	var bot_px: float
	var slab_id: int
	var light: int
	var floor_tex: int
	var floor_z: float
	var behind_slab_id: int # slab immediately behind in the ray (=slab_id if none)
	var behind_floor_z: float # floor_z of slab immediately behind
	var rim_at_far: bool # far edge is a visible step-down

static func build_merged_floor_bands(state: DoomTypes.GameState) -> Array:
	var output: Array = [] # of MergedFloorBand
	var cols := state.frame.columns
	# Per-column FAR -> NEAR (reverse of ray-order source) so the closer band
	# ends up later in the child list and paints OVER farther bands. This
	# library's reconciler paints later `@for` children on top of earlier
	# ones (no z-index), same constraint as the original's UI Toolkit.
	# Cross-column ordering is irrelevant because bands at different X
	# columns don't overlap.
	#
	# Combined with the step-down y_far clamp in build_column_sector, this
	# guarantees:
	#  - Distant lower floors clamped to silhouette -> never paint above the
	#    higher floor's silhouette in pixel space.
	#  - Even with top_px ties from the clamp, the closer band always paints
	#    last because of the deterministic per-column FAR->NEAR loop.
	#
	# No global sort: an unstable sort on top_px ties would randomly invert
	# order per column and produce flicker / covered closer bands.
	for i in range(cols.size()):
		var bands: Array = cols[i].floor_bands
		if bands == null:
			continue
		for j in range(bands.size() - 1, -1, -1):
			var b: DoomTypes.FloorBand = bands[j]
			var slab := roundi(b.floor_z * 5.0)
			var e := MergedFloorBand.new()
			e.col_start = i
			e.col_end = i
			e.top_px = b.top_px
			e.bot_px = b.bot_px
			e.slab_id = slab
			e.light = b.light
			e.floor_tex = b.floor_tex
			e.floor_z = b.floor_z
			e.behind_slab_id = slab
			e.behind_floor_z = b.behind_floor_z
			e.rim_at_far = b.rim_at_far
			output.append(e)
	return output

# Phase 8 (original): ceiling band entry for renderer (one per column-band;
# same pattern as floor bands but no horizontal merge -- keep simple, perf
# budget OK).
class CeilingBandEntry extends RefCounted:
	var col_index: int
	var slab_id: int
	var band: DoomTypes.CeilingBand

static func build_merged_ceiling_bands(state: DoomTypes.GameState) -> Array:
	var output: Array = [] # of CeilingBandEntry
	var cols := state.frame.columns
	for i in range(cols.size()):
		var bands: Array = cols[i].ceiling_bands
		if bands == null:
			continue
		for j in range(bands.size() - 1, -1, -1):
			var b: DoomTypes.CeilingBand = bands[j]
			var slab := roundi(b.ceiling_z * 5.0)
			var e := CeilingBandEntry.new()
			e.col_index = i
			e.slab_id = slab
			e.band = b
			output.append(e)
	return output

# Phase 8 (original): hitscan tracer projection. Walks the ring buffer,
# projects both endpoints into camera space (rotation + perspective),
# near-plane clips, and produces a screen-space rotated rect per live
# tracer. Returns the rect's position+size+angle so the renderer can emit a
# single Box per tracer with no per-frame allocations beyond the output list.
class TracerEntry extends RefCounted:
	var slot: int
	var left: float
	var top: float
	var length: float
	var angle_deg: float
	var alpha: float
	var color_idx: int

const TRACER_NEAR := 0.15

static func build_tracer_list(state: DoomTypes.GameState) -> Array:
	var list: Array = [] # of TracerEntry
	if state.tracers == null:
		return list
	var p := state.player
	var cos_a := cos(p.angle)
	var sin_a := sin(p.angle)
	var half_h: float = DoomTypes.C.VIEWPORT_H * 0.5
	var plane_scale: float = half_h / tan(DoomTypes.C.HALF_FOV)
	var horizon: float = half_h + p.pitch + p.view_shift_px
	var view_z: float = p.z + (0.6 if p.view_height <= 0.0 else p.view_height)

	for i in range(state.tracers.size()):
		var t: DoomTypes.Tracer = state.tracers[i]
		if t == null or t.age_ms >= DoomTypes.C.TRACER_LIFE_MS:
			continue

		# Camera space: forward = (cos a, sin a); right = (-sin a, cos a).
		var adx := t.ax - p.x
		var ady := t.ay - p.y
		var bdx := t.bx - p.x
		var bdy := t.by - p.y
		var ay := adx * cos_a + ady * sin_a # depth
		var ax := -adx * sin_a + ady * cos_a # lateral
		var by := bdx * cos_a + bdy * sin_a
		var bx := -bdx * sin_a + bdy * cos_a
		var az := t.az
		var bz := t.bz

		# Both endpoints behind near plane -> skip.
		if ay < TRACER_NEAR and by < TRACER_NEAR:
			continue
		# Clip the segment against the near plane in camera space.
		if ay < TRACER_NEAR:
			var k: float = (TRACER_NEAR - ay) / (by - ay)
			ax += (bx - ax) * k
			az += (bz - az) * k
			ay = TRACER_NEAR
		elif by < TRACER_NEAR:
			var k2: float = (TRACER_NEAR - by) / (ay - by)
			bx += (ax - bx) * k2
			bz += (az - bz) * k2
			by = TRACER_NEAR

		var screen_ax: float = (DoomTypes.C.VIEWPORT_W * 0.5) + (ax / ay) * plane_scale
		var screen_ay: float = horizon - ((az - view_z) / ay) * plane_scale
		var screen_bx: float = (DoomTypes.C.VIEWPORT_W * 0.5) + (bx / by) * plane_scale
		var screen_by: float = horizon - ((bz - view_z) / by) * plane_scale

		var ddx := screen_bx - screen_ax
		var ddy := screen_by - screen_ay
		var length := sqrt(ddx * ddx + ddy * ddy)
		if length < 4.0:
			continue # too short to read -- muzzle flash covers it
		var angle_deg := rad_to_deg(atan2(ddy, ddx))
		var alpha := 1.0 - (t.age_ms / DoomTypes.C.TRACER_LIFE_MS)

		var e := TracerEntry.new()
		e.slot = i
		e.left = screen_ax
		e.top = screen_ay - DoomTypes.C.TRACER_THICKNESS_PX * 0.5
		e.length = length
		e.angle_deg = angle_deg
		e.alpha = alpha
		e.color_idx = t.color_idx
		list.append(e)

	return list
