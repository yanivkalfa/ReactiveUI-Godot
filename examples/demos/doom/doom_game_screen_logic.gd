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

		# Wall occlusion via the AUTHORITATIVE tile line-of-sight (map.blocks_rays). The sector
		# depth buffer under-occludes vs the tile map -- from_tiles doesn't wall off every solid
		# tile, so a thing behind a solid tile would otherwise LEAK THROUGH THE WALL (both the BSP
		# and ray-walker paths, since both read the sector map). tile-LOS is the documented source
		# of truth for occlusion; the per-column depth clip below still trims partial occlusion by
		# actually-rendered walls. (2D LOS -- vertical/3D-floor occlusion stays with the
		# floor/ceiling occluder tests further down.)
		if not GameLogic.has_line_of_sight(state, p.x, p.y, m.x, m.y):
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

## Small `style` dict builder for the viewport markup. Exists purely so
## doom_game_screen.guitkx's `@for` bodies pass an already-built Dictionary rather than
## writing an inline `{...}` dict literal inside a directive body (a `.guitkx` compiler
## markup/code-lexis scanning limitation for that construct, unrelated to game logic).
static func tint_style(c: Color) -> Dictionary:
	return {"modulate": c}

# ───── Unified world render list (Unity's single-container painter's algorithm) ─────
# One flat list of every solid world quad -- terminal walls, portal/stair extra-segs,
# and actor sprites -- each carrying a `z_index` so Godot's native (C++) canvas sort does the
# depth ordering. The list is NOT sorted in GDScript and NOT reordered per frame: it's emitted
# in a STABLE order (by column), so the reconciler only rewrites CHANGED props instead of every
# slot after a re-sort -- the real per-frame win over the old `sort_custom` painter's list.
#
# z_index = zband * WORLD_Z_STRIDE + distanceRank (nearer = higher). The ZBAND encodes Unity's
# paint order so bands can never z-fight walls (the drips): ceiling bands 0, floor bands 1,
# SOLIDS (walls + segs + sprites) 2. Within the solids band, walls and sprites depth-rank against
# each other, so a nearer wall column paints over a sprite PER COLUMN (fixes sprite-through-wall).
#
# HUD isolation without a CanvasLayer: the markup gives the world_group container z_index
# WORLD_GROUP_Z, and z_as_relative (Godot default) shifts EVERY world child down by that, so a
# child's effective z is WORLD_GROUP_Z + (0..3071) = -4000..-929 -- strictly BELOW the HUD, which
# stays at the default z 0. Sky + floor backstop go to BACKDROP_Z (below the whole world). So the
# global canvas sort can never leak a world quad over the crosshair/gun/minimap (the old z_index
# footgun) and never lets the sky paint over a wall.
const WORLD_Z_STRIDE := 1024
const ZBAND_CEILING := 0
const ZBAND_FLOOR := 1
const ZBAND_SOLID := 2                     # world child z_index range: 0..3071
const WORLD_GROUP_Z := -4000               # container offset -> world children ride to -4000..-929
const BACKDROP_Z := -4096                  # sky + floor backstop, below the whole world

static func world_z(zband: int, distance: float) -> int:
	# distance 0..MAX_RAY -> rank STRIDE-1..0 (nearer = higher), offset into the band.
	var t: float = clampf((DoomTypes.C.MAX_RAY - distance) / DoomTypes.C.MAX_RAY, 0.0, 1.0)
	return zband * WORLD_Z_STRIDE + int(t * (WORLD_Z_STRIDE - 1))

class WorldQuad extends RefCounted:
	var x: float
	var y: float
	var w: float
	var h: float
	var texture: Texture2D
	var modulate: Color        # tint (sprites: tint*light; walls/bands: mono shade)
	var self_modulate: Color
	var material: Material
	var distance: float
	var z_index: int = 0       # = world_z(zband, distance); Godot's canvas sort orders by this
	var key: String = ""       # STABLE per-element key (Unity's scheme) -> keyed reconcile, no churn

# 1x1 white texture -- solid band/sprite quads tint it via modulate, so every world quad
# is the same node type (TextureRect) and slot-reuses without type churn as the sort order
# and count shift each frame.
static var _white_tex: Texture2D

static func white_tex() -> Texture2D:
	if _white_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex

# Minimum wall/seg brightness. Dark sectors otherwise crush walls, thin stair risers and
# mortar columns to near-black (hard black bars). Raise for a brighter level, lower for a
# moodier one -- a top-level readability knob applied to every wall/seg's mono shade.
const MIN_WALL_SHADE := 0.55

# Vertical TILING wall shader (matches Unity's BackgroundRepeat-Y): 1 world-Z unit = 64 texels,
# so one tile is texPx = VIEWPORT_H/distance screen px tall. Each wall/seg feeds its column's data
# through SHADER UNIFORMS (set_shader_parameter -- the correct data path; self_modulate is a
# post-shader tint that can't feed a shader, which is why packing data there failed before).
# A ShaderMaterial pooled per element KEY keeps material identity stable for the keyed reconcile
# (the style dict stays equal; only the uniforms change, so Godot re-renders without a re-diff).
# This is the fix for the "walls stretch / warp / bend" limitation.
static var _wall_shader: Shader
static var _wall_mats: Dictionary = {} # element key -> ShaderMaterial, persists across frames

static func _wall_shader_res() -> Shader:
	if _wall_shader == null:
		_wall_shader = Shader.new()
		_wall_shader.code = "shader_type canvas_item;\nrender_mode unshaded;\nuniform sampler2D wall_tex : filter_nearest;\nuniform float tex_u = 0.0;\nuniform float tiles = 1.0;\nuniform float peg = 0.0;\nuniform float shade = 1.0;\nvoid fragment() {\n\tfloat vv = fract(UV.y * tiles - peg);\n\tvec4 c = texture(wall_tex, vec2(clamp(tex_u, 0.0, 0.999), vv));\n\tCOLOR = vec4(c.rgb * shade, c.a);\n}\n"
	return _wall_shader

static func _wall_material(key: String) -> ShaderMaterial:
	var m: ShaderMaterial = _wall_mats.get(key)
	if m == null:
		m = ShaderMaterial.new()
		m.shader = _wall_shader_res()
		_wall_mats[key] = m
	return m

# One wall/seg column, vertically TILED (no stretch). The shader samples wall_tex at
# (tex_u, fract(UV.y*tiles - peg)) where tiles = h/texPx (texPx = VIEWPORT_H/distance) and
# peg = tex_offset_px/texPx pegs the tile grid across the raycaster's vertical clip. Shade in-shader.
static func _wall_quad(x: float, y: float, w: float, h: float, wall_tex: Texture2D, tex_u: float, distance: float, tex_offset_px: float, shade: float, zband: int, key: String) -> WorldQuad:
	var q := WorldQuad.new()
	q.x = floorf(x) # integer pixel: sub-pixel x + nearest leaves a 1px seam every column
	q.y = y
	q.w = w
	q.h = h
	q.texture = white_tex() # the shader reads wall_tex; the TextureRect just needs SOME texture for UVs
	q.modulate = Color.WHITE
	q.self_modulate = Color.WHITE
	var mat := _wall_material(key)
	var texpx: float = DoomTypes.C.VIEWPORT_H / maxf(0.1, distance)
	mat.set_shader_parameter("wall_tex", wall_tex)
	mat.set_shader_parameter("tex_u", tex_u)
	mat.set_shader_parameter("tiles", h / texpx)
	mat.set_shader_parameter("peg", tex_offset_px / texpx)
	mat.set_shader_parameter("shade", shade)
	q.material = mat
	q.distance = distance
	q.z_index = world_z(zband, distance)
	q.key = key
	return q

# Flat-color quad (floor/ceiling bands): the 1x1 white texture tinted by modulate, no shader.
static func _band_quad(x: float, y: float, w: float, h: float, color: Color, distance: float, zband: int, key: String) -> WorldQuad:
	var q := WorldQuad.new()
	q.x = floorf(x) # integer pixel -> no per-column seam (see _wall_quad)
	q.y = y
	q.w = w
	q.h = h
	q.texture = white_tex()
	q.modulate = color
	q.self_modulate = Color.WHITE
	q.material = null
	q.distance = distance
	q.z_index = world_z(zband, distance)
	q.key = key
	return q

static func build_world_geometry(state: DoomTypes.GameState) -> Array:
	var list: Array = [] # of WorldQuad
	var walls := DoomTextures.walls()
	var strip: float = DoomTypes.C.STRIP_W

	# Floor + ceiling BANDS -- in the SAME container but on FIXED PAINT LAYERS (Unity's
	# DoomGameScreen order: ceiling band 0, floor band 1, seg 2, wall 3). Sorting purely
	# by ray distance let a nearer dark ceiling/floor band paint OVER a wall (the "ceiling
	# leaking onto the wall" drips, and the per-column top comb). Layer order guarantees
	# every wall/seg paints over every band -- exactly Unity's "painted BEFORE walls so
	# wall texels stay on top." Within a layer we still sort far->near for band-vs-band and
	# wall-vs-wall occlusion. Colors + padding mirror the formulas from the Unity markup.
	for i in range(DoomTypes.C.VIEW_W):
		var ci: DoomTypes.ColumnInfo = state.frame.columns[i]
		if ci == null:
			continue
		var col_x: float = i * strip
		# FAR -> NEAR (reverse ray order) so nearer bands land LATER in the list -- the tie-break
		# for equal z-ranks matches Unity (nearer paints on top). Keyed by column + band index so
		# identity survives the per-column count changing frame to frame (no unkeyed churn).
		# MERGE consecutive same-slab floor bands (one per crossed tile) into ONE tall quad.
		# E1M1 is one-sector-per-tile, so a ray over flat floor emits ~15 identical-slab bands;
		# collapsing them cuts ~1900 floor quads to ~160 -- the real per-frame allocation win.
		if ci.floor_bands != null:
			var fbands: Array = ci.floor_bands
			var fn: int = fbands.size()
			var fg: int = 0
			var fgi: int = 0
			while fg < fn:
				var fslab: int = roundi(fbands[fg].floor_z * 5.0)
				var ftop: float = INF
				var fbot: float = -INF
				var fnear: DoomTypes.FloorBand = fbands[fg]
				var fe: int = fg
				while fe < fn and roundi(fbands[fe].floor_z * 5.0) == fslab:
					var b: DoomTypes.FloorBand = fbands[fe]
					ftop = minf(ftop, b.top_px)
					fbot = maxf(fbot, b.bot_px)
					if b.distance < fnear.distance:
						fnear = b
					fe += 1
				fg = fe
				var fh: float = (fbot - ftop) + 4.0
				if fh < 1.0:
					fgi += 1
					continue
				var lift: float = clampf(fnear.floor_z * 0.10, -0.1, 0.25)
				var flight: float = fnear.light / 255.0
				var fbright: float = maxf(1.0, 0.6 + flight * 0.8)
				var fcol := Color(clampf((0.34 + lift) * fbright, 0.0, 1.0), clampf((0.29 + lift) * fbright, 0.0, 1.0), clampf((0.22 + lift * 0.5) * fbright, 0.0, 1.0), 1.0)
				list.append(_band_quad(col_x - 0.5, ftop, strip + 2.0, fh, fcol, fnear.distance, ZBAND_FLOOR, "fb%d_%d" % [i, fgi]))
				fgi += 1
		if ci.ceiling_bands != null:
			var cbands: Array = ci.ceiling_bands
			var cn: int = cbands.size()
			var cg: int = 0
			var cgi: int = 0
			while cg < cn:
				var cslab: int = roundi(cbands[cg].ceiling_z * 5.0)
				var ctopmin: float = INF
				var cbotmax: float = -INF
				var cnear: DoomTypes.CeilingBand = cbands[cg]
				var ce: int = cg
				while ce < cn and roundi(cbands[ce].ceiling_z * 5.0) == cslab:
					var b: DoomTypes.CeilingBand = cbands[ce]
					ctopmin = minf(ctopmin, b.top_px)
					cbotmax = maxf(cbotmax, b.bot_px)
					if b.distance < cnear.distance:
						cnear = b
					ce += 1
				cg = ce
				var ctop: float = ctopmin - 2.0
				var ch: float = (cbotmax + 4.0) - ctop
				if ch < 1.0:
					cgi += 1
					continue
				var clift: float = clampf(cnear.ceiling_z * 0.04, 0.0, 0.20)
				var clight: float = cnear.light / 255.0
				var cbright: float = maxf(1.0, 0.55 + clight * 0.85)
				var ccol := Color(clampf((0.22 + clift) * cbright, 0.0, 1.0), clampf((0.22 + clift) * cbright, 0.0, 1.0), clampf((0.26 + clift) * cbright, 0.0, 1.0), 1.0)
				list.append(_band_quad(col_x - 1.0, ctop, strip + 2.0, ch, ccol, cnear.distance, ZBAND_CEILING, "cb%d_%d" % [i, cgi]))
				cgi += 1

	# Portal / stair extra-segs (upper + lower walls at each traversed portal).
	for ex in build_extra_seg_list(state):
		var ecol: DoomTypes.WallSeg = ex.seg
		var eh: float = ecol.bot_px - ecol.top_px
		if eh < 1.0:
			continue
		# Floor brightness at MIN_WALL_SHADE so dark sectors don't crush walls/segs to black
		# (that's what turned mortar columns, thin risers and distant slivers into hard black bars).
		var elight_f: float = maxf(MIN_WALL_SHADE, ecol.light_level / 255.0)
		list.append(_wall_quad(ex.col_index * strip, ecol.top_px, strip + 2.0, eh, walls[ecol.wall_tex_idx], ecol.tex_u, ecol.distance, ecol.tex_offset_px, elight_f, ZBAND_SOLID, "x%d_%d" % [ex.col_index, ex.seg_index]))

	# Main per-column terminal walls.
	for i in range(DoomTypes.C.VIEW_W):
		var col: DoomTypes.WallSeg = state.frame.columns[i].main
		if col.is_sky:
			continue
		var light_f: float = col.light_level / 255.0
		var vert_dim: float = 0.85 if col.hit_vertical else 1.0
		list.append(_wall_quad(i * strip, col.top_px, strip + 2.0, col.bot_px - col.top_px, walls[col.wall_tex_idx], col.tex_u, col.distance, col.tex_offset_px, maxf(MIN_WALL_SHADE, light_f * vert_dim), ZBAND_SOLID, "w%d" % i))

	# Actor SPRITES -- folded into the SAME container, in the SOLID z-band. A billboard is ONE
	# quad with a single z (its center distance), so a z-band can't clip it per column: a
	# monster whose center peeks past a wall edge / through a doorway jamb would bleed its whole
	# body over the nearer wall (the "enemy through the wall" bug). So we depth-clip HERE in
	# screen columns: walk the columns the sprite covers, keep only those where it's in front of
	# that column's wall (depth buffer), and emit one AtlasTexture quad per contiguous visible
	# run -- the un-occluded slice, CUT (not squashed) at the wall edge. Usually 1 quad; 2 when a
	# wall edge crosses it. build_sprite_list still does the floor/ceiling-occluder + fully-behind
	# culls, so most sprites arrive already visible.
	var sprite_texs := DoomTextures.sprites()
	var depth := state.frame.depth_buffer
	var nvcols: int = DoomTypes.C.VIEW_W
	for s in build_sprite_list(state):
		var e: SpriteEntry = s
		if e.sprite_idx < 0 or e.sprite_idx >= sprite_texs.size() or e.size <= 0.5:
			continue
		var tex: Texture2D = sprite_texs[e.sprite_idx]
		var tw: float = float(tex.get_width())
		var th: float = float(tex.get_height())
		var left_px: float = e.screen_x - e.size * 0.5
		var right_px: float = e.screen_x + e.size * 0.5
		var top_px: float = e.screen_y - e.size * 0.5
		var mod := Color(e.tint.r * e.light, e.tint.g * e.light, e.tint.b * e.light, 1.0)
		var zi: int = world_z(ZBAND_SOLID, e.distance)
		var c0: int = maxi(0, int(floor(left_px / strip)))
		var c1: int = mini(nvcols - 1, int(floor((right_px - 0.001) / strip)))
		# Contiguous runs of columns where the sprite is in front of the wall.
		var runs: Array = [] # of [start_col, end_col]
		var rs: int = -1
		for col in range(c0, c1 + 1):
			var dwall: float = depth[col] if col < depth.size() else 1e9
			var vis: bool = e.distance <= dwall + 0.05
			if vis and rs < 0:
				rs = col
			elif (not vis) and rs >= 0:
				runs.append([rs, col - 1]); rs = -1
		if rs >= 0:
			runs.append([rs, c1])
		for run in runs:
			var gx0: float = maxf(left_px, run[0] * strip)
			var gx1: float = minf(right_px, (run[1] + 1) * strip)
			if gx1 <= gx0 + 0.5:
				continue
			var u0: float = (gx0 - left_px) / e.size
			var u1: float = (gx1 - left_px) / e.size
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(u0 * tw, 0.0, maxf(1.0, (u1 - u0) * tw), th)
			var sq := WorldQuad.new()
			sq.x = gx0; sq.y = top_px; sq.w = gx1 - gx0; sq.h = e.size
			sq.texture = atlas
			sq.modulate = mod
			sq.self_modulate = Color.WHITE
			sq.material = null
			sq.distance = e.distance
			sq.z_index = zi
			# Keyed by sprite id + run start column -- stable identity as the clip shifts.
			sq.key = "s%d_%d" % [e.id, run[0]]
			list.append(sq)

	# NO GDScript sort: every quad carries a z_index (world_z), and Godot's native canvas sort
	# does the depth ordering. The list stays in stable build order (column-major, then sprites)
	# so the reconciler only rewrites CHANGED props each frame instead of every slot.
	return list

# ───── Minimap feed (DoomMinimap.uitkx's two inline @foreach loops) ─────
# Ported here as pure builders (house pattern) rather than inline in the markup.
# Colors are the minimap palette, baked in so the markup stays a trivial @for.

class MinimapCell extends RefCounted:
	var cx: int
	var cy: int
	var color: Color

class MinimapDot extends RefCounted:
	var x: float
	var y: float
	var color: Color

static func build_minimap_cells(state: DoomTypes.GameState) -> Array:
	var list: Array = [] # of MinimapCell
	var map := state.map
	var mw: int = map.width
	var mh: int = map.height
	var wall_clr := Color(0.55, 0.40, 0.20, 1.0)
	var door_clr := Color(0.85, 0.65, 0.10, 1.0)
	var door_blue := Color(0.30, 0.55, 1.00, 1.0)
	var door_yellow := Color(0.95, 0.85, 0.20, 1.0)
	var door_red := Color(0.95, 0.20, 0.20, 1.0)
	var exit_clr := Color(0.40, 0.95, 0.40, 1.0)
	for cy in range(mh):
		for cx in range(mw):
			var cell: DoomTypes.Cell = map.cells[cy * mw + cx]
			var col: Color
			match cell.kind:
				DoomTypes.CellKind.WALL:
					col = wall_clr
				DoomTypes.CellKind.EXIT:
					col = exit_clr
				DoomTypes.CellKind.DOOR_BLUE:
					col = door_blue
				DoomTypes.CellKind.DOOR_YELLOW:
					col = door_yellow
				DoomTypes.CellKind.DOOR_RED:
					col = door_red
				DoomTypes.CellKind.DOOR:
					col = door_clr
				_:
					continue
			var e := MinimapCell.new()
			e.cx = cx
			e.cy = cy
			e.color = col
			list.append(e)
	return list

static func build_minimap_dots(state: DoomTypes.GameState) -> Array:
	var list: Array = [] # of MinimapDot
	var enemy_clr := Color(0.95, 0.20, 0.15, 1.0)
	var pickup_clr := Color(0.30, 0.85, 0.85, 1.0)
	var door_blue := Color(0.30, 0.55, 1.00, 1.0)
	var door_yellow := Color(0.95, 0.85, 0.20, 1.0)
	var door_red := Color(0.95, 0.20, 0.20, 1.0)
	for i in range(1, state.mobj_count + 1):
		var m: DoomTypes.Mobj = state.mobjs[i]
		if m == null or m.id == 0 or m.collected:
			continue
		if GameLogic.is_monster(m.kind) and m.state == DoomTypes.AIState.DEAD:
			continue
		var col: Color
		if GameLogic.is_monster(m.kind):
			col = enemy_clr
		elif m.kind == DoomTypes.MobjKind.KEY_BLUE:
			col = door_blue
		elif m.kind == DoomTypes.MobjKind.KEY_YELLOW:
			col = door_yellow
		elif m.kind == DoomTypes.MobjKind.KEY_RED:
			col = door_red
		elif GameLogic.is_pickup(m.kind):
			col = pickup_clr
		else:
			continue
		var e := MinimapDot.new()
		e.x = m.x
		e.y = m.y
		e.color = col
		list.append(e)
	return list
