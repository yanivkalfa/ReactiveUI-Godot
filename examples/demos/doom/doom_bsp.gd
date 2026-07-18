class_name DoomBSP
extends RefCounted

## 2D BSP for the Doom sector map (Phase 1: builder + point-location).
##
## The Unity DoomGame is a per-column ray-walker; this is a Godot-only divergence that trades
## that for a precomputed tree so visible-surface finding is distance-independent (no MAX_RAY_HOPS
## cap, no open-room cost blow-up). It plugs into the SAME per-column output the rest of the
## pipeline consumes -- Phase 2 fills state.frame.columns[i], Phase 3 the floor/ceiling/3D-floor
## bands. 3D floors ride along untouched: the tree is horizontal-only (which walls do I see);
## heights + extra_floors stay in the Sector data drawn per column.
##
## The map is grid-aligned (from_tiles: one sector per cell), so the partition is a grid-split
## (k-d) tree -- robust, balanced (~log2(cells) deep), no floating-point seg-splitting. Leaves are
## single cells (convex subsectors); internal nodes split a cell range in half on its longer axis.

# A wall segment = one Linedef in world coords, carrying its sector sides + textures (for Phase 2).
class Seg extends RefCounted:
	var ax: float
	var ay: float
	var bx: float
	var by: float
	var line_id: int
	var front_sector: int
	var back_sector: int   # -1 = solid one-sided wall
	var mid_tex: int
	var upper_tex: int
	var lower_tex: int

# Leaf / subsector = one grid cell.
class Leaf extends RefCounted:
	var cx: int
	var cy: int
	var sector: int        # -1 if this cell is solid (Wall)
	var segs: Array        # of Seg -- the linedefs bounding this cell's sector

# Internal node: split the cell range in half along `axis` (0 = x, 1 = y) at cell boundary `split`.
class BSPNode extends RefCounted:
	var axis: int
	var split: int         # cells with coord < split -> low, else -> high
	var low                # BSPNode or Leaf
	var high               # BSPNode or Leaf

var root                   # Node or Leaf
var leaf_count: int = 0
var _map: DoomTypes.MapData

## Build the tree for a sector map. O(cells); called once at level load.
static func build(map: DoomTypes.MapData) -> DoomBSP:
	var b := DoomBSP.new()
	b._map = map
	var w: int = map.cell_width
	var h: int = map.cell_height
	if w <= 0 or h <= 0:
		return b
	b.root = b._build(0, 0, w, h)
	return b

func _build(x0: int, y0: int, x1: int, y1: int):
	if (x1 - x0) <= 1 and (y1 - y0) <= 1:
		return _make_leaf(x0, y0)
	var n := BSPNode.new()
	if (x1 - x0) >= (y1 - y0):
		n.axis = 0
		n.split = (x0 + x1) >> 1
		n.low = _build(x0, y0, n.split, y1)
		n.high = _build(n.split, y0, x1, y1)
	else:
		n.axis = 1
		n.split = (y0 + y1) >> 1
		n.low = _build(x0, y0, x1, n.split)
		n.high = _build(x0, n.split, x1, y1)
	return n

func _make_leaf(cx: int, cy: int) -> Leaf:
	leaf_count += 1
	var lf := Leaf.new()
	lf.cx = cx
	lf.cy = cy
	var w: int = _map.cell_width
	lf.sector = _map.cell_to_sector[cy * w + cx] if (cy * w + cx) < _map.cell_to_sector.size() else -1
	lf.segs = []
	if lf.sector >= 0:
		var sec: DoomTypes.Sector = _map.sectors[lf.sector]
		if sec.line_ids != null:
			for li in sec.line_ids:
				var ln: DoomTypes.Linedef = _map.lines[li]
				var s := Seg.new()
				s.ax = _map.vertices[ln.v1].p.x
				s.ay = _map.vertices[ln.v1].p.y
				s.bx = _map.vertices[ln.v2].p.x
				s.by = _map.vertices[ln.v2].p.y
				s.line_id = li
				s.front_sector = ln.front_sector
				s.back_sector = ln.back_sector
				s.mid_tex = ln.mid_tex
				s.upper_tex = ln.upper_tex
				s.lower_tex = ln.lower_tex
				lf.segs.append(s)
	return lf

## Descend to the leaf containing world point (px, py). O(tree depth).
func locate(px: float, py: float) -> Leaf:
	var cx := int(floor(px))
	var cy := int(floor(py))
	var node = root
	while node is BSPNode:
		var nd: BSPNode = node
		if nd.axis == 0:
			node = nd.low if cx < nd.split else nd.high
		else:
			node = nd.low if cy < nd.split else nd.high
	return node

## Sector id at a world point (-1 if solid / out of bounds), for point-location parity checks.
func sector_at(px: float, py: float) -> int:
	if px < 0.0 or py < 0.0 or px >= _map.cell_width or py >= _map.cell_height:
		return -1
	var lf := locate(px, py)
	return lf.sector if lf != null else -1

# ───────────────────────── Phase 2: wall rendering ─────────────────────────
# Fill state.frame.columns[i].main + extras + depth_buffer by a front-to-back BSP walk with
# per-column occlusion. Distance-independent (no MAX_RAY_HOPS cap). Floor/ceiling/3D-floor bands
# are Phase 3 (left empty here). Projection matches game_logic.build_column_sector:
#   depth = camera-space forward dist;  scale = VIEWPORT_H / depth;
#   screen_x = W/2 + (lateral/depth)*plane  (plane = W/2 / tan(HALF_FOV));
#   wall_y = horizon - (world_z - view_z) * scale.
const _NEAR := 0.05
var _st: DoomTypes.GameState
var _px: float
var _py: float
var _cos: float
var _sin: float
var _half_w: float
var _plane: float
var _horizon: float
var _view_z: float
var _strip: float
var _solid: PackedByteArray
var _wtop: PackedFloat32Array
var _wbot: PackedFloat32Array
var _cols: Array
var _depth: PackedFloat32Array
var _processed: Dictionary
var _nsolid: int
var _ncols: int
var _pdepth: PackedFloat32Array   # per-column near-edge depth of the floor/ceiling span so far

func render_frame(st: DoomTypes.GameState) -> void:
	var p := st.player
	_st = st
	_ncols = DoomTypes.C.VIEW_W
	_px = p.x
	_py = p.y
	_cos = cos(p.angle)
	_sin = sin(p.angle)
	_half_w = DoomTypes.C.VIEWPORT_W * 0.5
	_plane = _half_w / tan(DoomTypes.C.HALF_FOV)
	_horizon = DoomTypes.C.VIEWPORT_H * 0.5 + p.pitch
	_view_z = p.z + (0.6 if p.view_height <= 0.0 else p.view_height)
	_strip = DoomTypes.C.VIEWPORT_W / float(_ncols)
	st.frame.reset_pools()
	_cols = st.frame.columns
	_depth = st.frame.depth_buffer
	_solid = PackedByteArray(); _solid.resize(_ncols)
	_wtop = PackedFloat32Array(); _wtop.resize(_ncols)
	_wbot = PackedFloat32Array(); _wbot.resize(_ncols)
	_pdepth = PackedFloat32Array(); _pdepth.resize(_ncols)
	_processed = {}
	_nsolid = 0
	for i in range(_ncols):
		_solid[i] = 0
		_wtop[i] = 0.0
		_wbot[i] = DoomTypes.C.VIEWPORT_H
		_pdepth[i] = _NEAR
		_depth[i] = DoomTypes.C.MAX_RAY
		var ci := DoomTypes.ColumnInfo.new()
		var sky := st.frame.take_wallseg()
		sky.is_sky = true
		sky.distance = DoomTypes.C.MAX_RAY
		sky.top_px = 0.0
		sky.bot_px = DoomTypes.C.VIEWPORT_H
		ci.main = sky
		ci.extras = []
		ci.floor_bands = []
		ci.ceiling_bands = []
		ci.floor_occluder_dist = INF
		ci.floor_occluder_z = -INF
		ci.ceiling_occluder_dist = INF
		ci.ceiling_occluder_z = INF
		_cols[i] = ci
	if root != null:
		_walk(root)

func _walk(node) -> void:
	if _nsolid >= _ncols:
		return
	if node is Leaf:
		var lf: Leaf = node
		if lf.sector >= 0:
			var cxp := lf.cx + 0.5
			var cyp := lf.cy + 0.5
			for seg in lf.segs:
				if not _processed.has(seg.line_id):
					_render_seg(seg, lf.sector, cxp, cyp)
		return
	var nd: BSPNode = node
	var near_low := (_px < float(nd.split)) if nd.axis == 0 else (_py < float(nd.split))
	if near_low:
		_walk(nd.low)
		_walk(nd.high)
	else:
		_walk(nd.high)
		_walk(nd.low)

func _render_seg(seg: Seg, near_sector: int, cxp: float, cyp: float) -> void:
	# from_tiles winding is inconsistent, so don't infer sides from it. near = the leaf's
	# sector (known); far = the seg's OTHER side. Backface-cull by whether the player is on
	# the same side of the seg as this leaf's cell center (both must agree).
	var sc := (seg.bx - seg.ax) * (cyp - seg.ay) - (seg.by - seg.ay) * (cxp - seg.ax)
	var sp := (seg.bx - seg.ax) * (_py - seg.ay) - (seg.by - seg.ay) * (_px - seg.ax)
	if sc * sp < 0.0:
		return
	var far_sector := seg.back_sector if seg.front_sector == near_sector else seg.front_sector
	var adx := seg.ax - _px; var ady := seg.ay - _py
	var bdx := seg.bx - _px; var bdy := seg.by - _py
	var a_depth := adx * _cos + ady * _sin
	var a_lat := -adx * _sin + ady * _cos
	var b_depth := bdx * _cos + bdy * _sin
	var b_lat := -bdx * _sin + bdy * _cos
	var au := 0.0
	var bu := 1.0
	if a_depth < _NEAR and b_depth < _NEAR:
		return
	if a_depth < _NEAR:
		var t := (_NEAR - a_depth) / (b_depth - a_depth)
		a_lat += (b_lat - a_lat) * t; au += (bu - au) * t; a_depth = _NEAR
	elif b_depth < _NEAR:
		var t := (_NEAR - b_depth) / (a_depth - b_depth)
		b_lat += (a_lat - b_lat) * t; bu += (au - bu) * t; b_depth = _NEAR
	var sxa := _half_w + (a_lat / a_depth) * _plane
	var sxb := _half_w + (b_lat / b_depth) * _plane
	if sxa > sxb:
		var tmp = sxa; sxa = sxb; sxb = tmp
		tmp = a_depth; a_depth = b_depth; b_depth = tmp
		tmp = au; au = bu; bu = tmp
	if sxb - sxa < 0.001:
		return
	_processed[seg.line_id] = true
	var c0: int = maxi(0, int(ceil(sxa / _strip)))
	var c1: int = mini(_ncols - 1, int(floor(sxb / _strip)))
	if c0 > c1:
		return
	var inv_a := 1.0 / a_depth
	var inv_b := 1.0 / b_depth
	var near_sec: DoomTypes.Sector = _st.sector_map.sectors[near_sector]
	var far_sec: DoomTypes.Sector = _st.sector_map.sectors[far_sector] if far_sector >= 0 else null
	# Solid = one-sided wall or a closed door (back collapsed) -> terminal full-height wall.
	var solid_wall := far_sec == null or (far_sec.ceiling_z <= far_sec.floor_z + 0.001)
	var fz := near_sec.floor_z
	var cz := near_sec.ceiling_z
	var ceil_for_wall: float = minf(cz, fz + 2.5) if near_sec.is_sky else cz
	var floor_below_eye := fz < _view_z - 0.001
	var ceil_above_eye := (not near_sec.is_sky) and cz > _view_z + 0.001
	var vp_h: float = DoomTypes.C.VIEWPORT_H
	for c in range(c0, c1 + 1):
		if _solid[c] != 0:
			continue
		var scr_x := c * _strip + _strip * 0.5
		var frac := (scr_x - sxa) / (sxb - sxa)
		var inv_z := inv_a + (inv_b - inv_a) * frac
		if inv_z <= 0.0:
			continue
		var depth_c := 1.0 / inv_z
		# No front-to-back guard here: k-d traversal is per-ray front-to-back except at rare
		# corner grazes, and skipping a "backward" seg there would drop a legitimate near wall
		# (verified: cols 27/56 at view 24.5,24.5,0). The _solid[c] check (first solid wall per
		# column wins) and the b_bot>b_top band-inversion check below absorb any out-of-order
		# seg without dropping geometry -- matching the ray-walker to <1px.
		var scale := vp_h / depth_c
		var scale_near := vp_h / maxf(_pdepth[c], 0.05)
		var tex_u := (au * inv_a + (bu * inv_b - au * inv_a) * frac) / inv_z
		var light: int = GameLogic.light_from_dist(depth_c, near_sec.light)
		var win_top := _wtop[c]
		var win_bot := _wbot[c]

		# ── 1. Floor band for the near sector, [near edge .. far edge] clipped to the window.
		if floor_below_eye:
			var y_floor_far := _horizon + (_view_z - fz) * scale
			var y_floor_near := _horizon + (_view_z - fz) * scale_near
			var b_top: float = win_top if y_floor_far < win_top else y_floor_far
			var b_bot: float = win_bot if y_floor_near > win_bot else y_floor_near
			if b_bot > b_top + 0.5:
				var rim_at_far := far_sec != null and not solid_wall \
						and (fz - far_sec.floor_z) >= 0.15 and b_top <= y_floor_far + 0.5
				var fb := _st.frame.take_floorband()
				fb.distance = depth_c; fb.top_px = b_top; fb.bot_px = b_bot
				fb.floor_z = fz; fb.light = light; fb.floor_tex = near_sec.floor_tex
				fb.behind_floor_z = -INF; fb.rim_at_far = rim_at_far
				_cols[c].floor_bands.append(fb)
			if y_floor_far < win_bot:
				win_bot = y_floor_far

		# ── 2. Ceiling band for the near sector (non-sky), from window top down to far edge.
		if ceil_above_eye:
			var y_ceil_far := _horizon - (cz - _view_z) * scale
			var c_bot_band: float = win_bot if y_ceil_far > win_bot else y_ceil_far
			if c_bot_band > win_top + 0.5:
				var cb := _st.frame.take_ceilband()
				cb.distance = depth_c; cb.top_px = win_top; cb.bot_px = c_bot_band
				cb.ceiling_z = cz; cb.light = light; cb.ceiling_tex = near_sec.ceiling_tex
				_cols[c].ceiling_bands.append(cb)
			if y_ceil_far > win_top:
				win_top = y_ceil_far

		# ── 2b. ExtraFloor (3D floor) slabs. Front-sector slabs first (top plane ->
		#    floor band, bottom plane -> ceiling band, exposed side -> wall; a side hit
		#    edge-on from inside the slab body terminates the column), then back-only
		#    slabs (side + top/bottom + window tighten). Mirrors build_column_sector.
		var slab_terminated := false
		var terminator_wall: DoomTypes.WallSeg = null
		if near_sec.extra_floors != null:
			for ef: DoomTypes.ExtraFloor in near_sec.extra_floors:
				var shared_with_back := false
				if far_sec != null and far_sec.extra_floors != null:
					for bef: DoomTypes.ExtraFloor in far_sec.extra_floors:
						if absf(bef.bottom_z - ef.bottom_z) < 0.01 and absf(bef.top_z - ef.top_z) < 0.01:
							shared_with_back = true; break
				var above_slab := _view_z > ef.top_z + 0.001
				var below_slab := _view_z < ef.bottom_z - 0.001
				var slab_light := GameLogic.light_from_dist(depth_c, near_sec.light if ef.light == 0 else ef.light)
				if above_slab:
					var yt_far := _horizon + (_view_z - ef.top_z) * scale
					var yt_near := _horizon + (_view_z - ef.top_z) * scale_near
					var bt: float = win_top if yt_far < win_top else yt_far
					var bb: float = win_bot if yt_near > win_bot else yt_near
					if bb > bt + 0.5:
						var fb2 := _st.frame.take_floorband()
						fb2.distance = depth_c; fb2.top_px = bt; fb2.bot_px = bb
						fb2.floor_z = ef.top_z; fb2.light = slab_light; fb2.floor_tex = ef.top_tex
						fb2.behind_floor_z = -INF; fb2.rim_at_far = not shared_with_back
						_cols[c].floor_bands.append(fb2)
					if yt_far < win_bot: win_bot = yt_far
					if _cols[c].floor_occluder_dist > depth_c:
						_cols[c].floor_occluder_dist = depth_c; _cols[c].floor_occluder_z = ef.top_z
				if below_slab:
					var yb_far := _horizon - (ef.bottom_z - _view_z) * scale
					var cbb: float = win_bot if yb_far > win_bot else yb_far
					if cbb > win_top + 0.5:
						var cbd := _st.frame.take_ceilband()
						cbd.distance = depth_c; cbd.top_px = win_top; cbd.bot_px = cbb
						cbd.ceiling_z = ef.bottom_z; cbd.light = slab_light; cbd.ceiling_tex = ef.bottom_tex
						_cols[c].ceiling_bands.append(cbd)
					if yb_far > win_top: win_top = yb_far
					if _cols[c].ceiling_occluder_dist > depth_c:
						_cols[c].ceiling_occluder_dist = depth_c; _cols[c].ceiling_occluder_z = ef.bottom_z
				if not shared_with_back and ef.solid:
					var ws_top := _horizon - (ef.top_z - _view_z) * scale
					var ws_bot := _horizon - (ef.bottom_z - _view_z) * scale
					var ct: float = win_top if ws_top < win_top else ws_top
					var cb: float = win_bot if ws_bot > win_bot else ws_bot
					if cb > ct + 0.5:
						var sw := _st.frame.take_wallseg()
						sw.top_px = ct; sw.bot_px = cb; sw.distance = depth_c
						sw.wall_tex_idx = ef.side_tex; sw.tex_u = tex_u; sw.light_level = slab_light
						sw.hit_vertical = false; sw.is_sky = false; sw.tex_offset_px = ws_top - ct
						if not above_slab and not below_slab:
							slab_terminated = true; terminator_wall = sw
						else:
							_cols[c].extras.append(sw)
		if far_sec != null and far_sec.extra_floors != null:
			for ef2: DoomTypes.ExtraFloor in far_sec.extra_floors:
				if not ef2.solid:
					continue
				var in_front := false
				if near_sec.extra_floors != null:
					for fef: DoomTypes.ExtraFloor in near_sec.extra_floors:
						if absf(fef.bottom_z - ef2.bottom_z) < 0.01 and absf(fef.top_z - ef2.top_z) < 0.01:
							in_front = true; break
				if in_front:
					continue
				var slab_light2 := GameLogic.light_from_dist(depth_c, far_sec.light if ef2.light == 0 else ef2.light)
				var above2 := _view_z > ef2.top_z + 0.001
				var below2 := _view_z < ef2.bottom_z - 0.001
				var y_top_far2 := _horizon - (ef2.top_z - _view_z) * scale
				var y_bot_far2 := _horizon - (ef2.bottom_z - _view_z) * scale
				var ct2: float = win_top if y_top_far2 < win_top else y_top_far2
				var cb2: float = win_bot if y_bot_far2 > win_bot else y_bot_far2
				if cb2 > ct2 + 0.5:
					var sw2 := _st.frame.take_wallseg()
					sw2.top_px = ct2; sw2.bot_px = cb2; sw2.distance = depth_c
					sw2.wall_tex_idx = ef2.side_tex; sw2.tex_u = tex_u; sw2.light_level = slab_light2
					sw2.hit_vertical = false; sw2.is_sky = false; sw2.tex_offset_px = y_top_far2 - ct2
					_cols[c].extras.append(sw2)
				if above2:
					var yt_near2 := _horizon + (_view_z - ef2.top_z) * scale_near
					var yt_far_flip := _horizon + (_view_z - ef2.top_z) * scale
					var bt2: float = win_top if yt_far_flip < win_top else yt_far_flip
					var bb2: float = win_bot if yt_near2 > win_bot else yt_near2
					if bb2 > bt2 + 0.5:
						var fb3 := _st.frame.take_floorband()
						fb3.distance = depth_c; fb3.top_px = bt2; fb3.bot_px = bb2
						fb3.floor_z = ef2.top_z; fb3.light = slab_light2; fb3.floor_tex = ef2.top_tex
						fb3.behind_floor_z = -INF; fb3.rim_at_far = true
						_cols[c].floor_bands.append(fb3)
				if below2:
					var cb3: float = win_bot if y_bot_far2 > win_bot else y_bot_far2
					if cb3 > win_top + 0.5:
						var cbd2 := _st.frame.take_ceilband()
						cbd2.distance = depth_c; cbd2.top_px = win_top; cbd2.bot_px = cb3
						cbd2.ceiling_z = ef2.bottom_z; cbd2.light = slab_light2; cbd2.ceiling_tex = ef2.bottom_tex
						_cols[c].ceiling_bands.append(cbd2)
				if not below2:
					if y_top_far2 < win_bot: win_bot = y_top_far2
				else:
					if y_bot_far2 > win_top: win_top = y_bot_far2
		if slab_terminated:
			_cols[c].main = terminator_wall
			_cols[c].front_floor_z = fz
			_depth[c] = depth_c
			_solid[c] = 1
			_nsolid += 1
			continue

		# ── 3. Wall (terminal) or portal upper/lower, clipped to the tightened window.
		if solid_wall:
			var unclipped_top := _horizon - (ceil_for_wall - _view_z) * scale
			var wt := unclipped_top
			var wb := _horizon - (fz - _view_z) * scale
			if wt < win_top: wt = win_top
			if wb > win_bot: wb = win_bot
			var m := _st.frame.take_wallseg()
			m.top_px = wt; m.bot_px = wb; m.distance = depth_c
			m.wall_tex_idx = seg.mid_tex; m.tex_u = tex_u; m.light_level = light
			m.hit_vertical = false; m.is_sky = (far_sec != null and far_sec.is_sky)
			m.tex_offset_px = unclipped_top - wt
			_cols[c].main = m
			_cols[c].front_floor_z = fz
			_depth[c] = depth_c
			_solid[c] = 1
			_nsolid += 1
		else:
			# Portal upper: back ceiling lower than front (skip sky-back -> sky shows through).
			if far_sec.ceiling_z < cz - 0.001 and not far_sec.is_sky:
				var u_un := _horizon - (cz - _view_z) * scale
				var ut := u_un
				var ub := _horizon - (far_sec.ceiling_z - _view_z) * scale
				if ut < win_top: ut = win_top
				if ub > win_bot: ub = win_bot
				if ub > ut + 0.5:
					var us := _st.frame.take_wallseg()
					us.top_px = ut; us.bot_px = ub; us.distance = depth_c
					us.wall_tex_idx = seg.upper_tex; us.tex_u = tex_u; us.light_level = light
					us.hit_vertical = false; us.is_sky = false; us.tex_offset_px = u_un - ut
					_cols[c].extras.append(us)
				if ub > win_top: win_top = ub
			# Portal lower (step-up): back floor higher than front.
			if far_sec.floor_z > fz + 0.001:
				if _cols[c].floor_occluder_dist > depth_c:
					_cols[c].floor_occluder_dist = depth_c
					_cols[c].floor_occluder_z = far_sec.floor_z
				var l_un := _horizon - (far_sec.floor_z - _view_z) * scale
				var lt := l_un
				var lb := _horizon - (fz - _view_z) * scale
				if lt < win_top: lt = win_top
				if lb > win_bot: lb = win_bot
				if lb > lt + 0.5:
					var ls := _st.frame.take_wallseg()
					ls.top_px = lt; ls.bot_px = lb; ls.distance = depth_c
					ls.wall_tex_idx = seg.lower_tex; ls.tex_u = tex_u; ls.light_level = light
					ls.hit_vertical = false; ls.is_sky = false
					ls.is_riser = (far_sec.floor_z - fz) >= 0.5; ls.tex_offset_px = l_un - lt
					_cols[c].extras.append(ls)
				if l_un < win_bot: win_bot = l_un
			# Commit the tightened window + advance the near edge for the next sector.
			_wtop[c] = win_top
			_wbot[c] = win_bot
			_pdepth[c] = depth_c
			if win_bot - win_top < 1.0:
				_depth[c] = depth_c
				_solid[c] = 1
				_nsolid += 1
