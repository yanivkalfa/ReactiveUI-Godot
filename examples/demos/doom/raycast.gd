class_name Raycast
extends RefCounted

## Faithful port of the Unity ReactiveUIToolKit `DoomGame` sample's `Raycast.uitkx` --
## portal-walking ray/segment/sector math. Pure Vector2 geometry, no engine dependency.
## C#'s `out` parameters have no GDScript equivalent -- functions that used them return
## a Dictionary of named results instead (the natural, unavoidable translation, not a
## behavior change). See plans/DOOM_GAME_GUITKX_PORT_PLAN.md.

class WallHit extends RefCounted:
	var distance: float # ray parameter t at hit
	var hit: Vector2 # world-space (x,y)
	var linedef_id: int
	var from_sector: int # sector we were traversing when we hit
	var to_sector: int # -1 if solid wall, else neighbor sector
	var is_backside: bool # ray hit the line from its back side
	var u: float # 0..1 along the linedef (v1->v2)
	var seg_length: float # |v2 - v1| in world units
	var is_sky: bool # back sector has is_sky and ceiling above

# ──────────────────────────────────────────────────────────────────────────
#  Geometry primitives
# ──────────────────────────────────────────────────────────────────────────

## Returns whether the ray (origin, dir, |dir|=1) intersects segment (a,b).
## Result dict: {"hit": bool, "t": ray distance >= 0, "u": along segment 0..1,
## "backside": true if ray hits the segment from the right of v1->v2 direction}.
static func ray_segment(origin: Vector2, dir: Vector2, a: Vector2, b: Vector2) -> Dictionary:
	var sd := b - a
	var denom := dir.x * sd.y - dir.y * sd.x
	if absf(denom) < 1e-7:
		return {"hit": false, "t": 0.0, "u": 0.0, "backside": false} # parallel
	var oa := origin - a
	# t along ray: (oa x sd) / (dir x sd)
	var tt := (oa.x * sd.y - oa.y * sd.x) / -denom
	# u along segment: (oa x dir) / (dir x sd)
	var uu := (oa.x * dir.y - oa.y * dir.x) / -denom
	if tt < 0.0:
		return {"hit": false, "t": 0.0, "u": 0.0, "backside": false}
	if uu < 0.0 or uu > 1.0:
		return {"hit": false, "t": 0.0, "u": 0.0, "backside": false}
	# The "front" of a linedef is to the RIGHT of v1->v2 (Doom convention).
	# Right-of(v1->v2) means cross(sd, oa) > 0. If our origin is to the left,
	# we are hitting the back side.
	var backside := denom > 0.0
	return {"hit": true, "t": tt, "u": uu, "backside": backside}

## Polygon containment via crossing-number using a sector's linedefs. The
## sector is convex in our generated maps, but this tolerates concave too.
static func point_in_sector(map: DoomTypes.MapData, sector_id: int, p: Vector2) -> bool:
	if sector_id < 0 or sector_id >= map.sectors.size():
		return false
	var s: DoomTypes.Sector = map.sectors[sector_id]
	var crossings := 0
	for i in range(s.line_ids.size()):
		var ln: DoomTypes.Linedef = map.lines[s.line_ids[i]]
		var a: Vector2 = map.vertices[ln.v1].p
		var b: Vector2 = map.vertices[ln.v2].p
		if (a.y > p.y) != (b.y > p.y):
			var x_cross := a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y)
			if p.x < x_cross:
				crossings += 1
	return (crossings & 1) == 1

## Best-effort sector lookup. Tries hint first, then any neighbor of hint
## through a two-sided line, then brute-forces all sectors. Returns -1 if the
## point is in no sector (e.g. outside the map).
static func point_in_sector_from_hint(map: DoomTypes.MapData, p: Vector2, hint: int) -> int:
	if hint >= 0 and point_in_sector(map, hint, p):
		return hint
	if hint >= 0:
		var s: DoomTypes.Sector = map.sectors[hint]
		for i in range(s.line_ids.size()):
			var ln: DoomTypes.Linedef = map.lines[s.line_ids[i]]
			var neighbor: int = ln.back_sector if ln.front_sector == hint else ln.front_sector
			if neighbor >= 0 and point_in_sector(map, neighbor, p):
				return neighbor
	for i in range(map.sectors.size()):
		if point_in_sector(map, i, p):
			return i
	return -1

# ──────────────────────────────────────────────────────────────────────────
#  Portal-walking ray cast
# ──────────────────────────────────────────────────────────────────────────

## Cast a ray from `origin` (inside `origin_sector`) in direction `dir` (must
## be unit length). Walks through two-sided linedefs into adjacent sectors.
## Stops at the first one-sided line, the first solid (Impassable flag), or
## after MAX_RAY_HOPS / MAX_RAY distance.
##
## Returns a list of hits in order of distance along the ray. The LAST hit is
## the terminal one. The renderer uses this list to draw upper/lower portal
## segs at each portal crossing and the final wall on close.
static func cast(map: DoomTypes.MapData, origin: Vector2, origin_sector: int, dir: Vector2) -> Array:
	var hits: Array = [] # of WallHit
	if not map.is_valid() or origin_sector < 0:
		return hits

	var current_sector := origin_sector
	var cursor := origin
	var accumulated_t := 0.0

	for hop in range(DoomTypes.C.MAX_RAY_HOPS):
		var sec: DoomTypes.Sector = map.sectors[current_sector]

		# Find the closest linedef of the current sector that the ray hits, in
		# front of the cursor (t > epsilon to avoid re-hitting the entry).
		var best_line_local := -1
		var best_t: float = INF
		var best_u := 0.0
		var best_back := false

		for li in range(sec.line_ids.size()):
			var line_id: int = sec.line_ids[li]
			var ln: DoomTypes.Linedef = map.lines[line_id]
			var a: Vector2 = map.vertices[ln.v1].p
			var b: Vector2 = map.vertices[ln.v2].p
			var res := ray_segment(cursor, dir, a, b)
			if res["hit"]:
				var t: float = res["t"]
				if t > 1e-4 and t < best_t:
					best_t = t
					best_line_local = line_id
					best_u = res["u"]
					best_back = res["backside"]

		if best_line_local < 0:
			break # ray escaped (shouldn't happen on closed sector)
		if accumulated_t + best_t > DoomTypes.C.MAX_RAY:
			break

		var hit_line: DoomTypes.Linedef = map.lines[best_line_local]
		var hit_pos := cursor + dir * best_t
		var va: Vector2 = map.vertices[hit_line.v1].p
		var vb: Vector2 = map.vertices[hit_line.v2].p
		var seg_len := (vb - va).length()

		var neighbor := -1
		var is_portal := (hit_line.flags & DoomTypes.LinedefFlags.TWO_SIDED) != 0 \
				and (hit_line.flags & DoomTypes.LinedefFlags.IMPASSABLE) == 0
		if is_portal:
			neighbor = hit_line.back_sector if hit_line.front_sector == current_sector else hit_line.front_sector

		var is_sky := false
		if neighbor >= 0:
			is_sky = map.sectors[neighbor].is_sky

		var wh := WallHit.new()
		wh.distance = accumulated_t + best_t
		wh.hit = hit_pos
		wh.linedef_id = best_line_local
		wh.from_sector = current_sector
		wh.to_sector = neighbor
		wh.is_backside = best_back
		wh.u = best_u
		wh.seg_length = seg_len
		wh.is_sky = is_sky
		hits.append(wh)

		if neighbor < 0:
			break # solid wall -- stop
		# Step cursor slightly past the hit into the neighbor sector.
		cursor = hit_pos + dir * 1e-3
		accumulated_t += best_t
		current_sector = neighbor

	return hits

# ──────────────────────────────────────────────────────────────────────────
#  Convenience helpers
# ──────────────────────────────────────────────────────────────────────────

## Distance from point P to segment AB (squared, plus the parameter u).
## Result dict: {"dist_sq": float, "u": float}.
static func dist_point_to_segment_sq(p: Vector2, a: Vector2, b: Vector2) -> Dictionary:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 1e-9:
		return {"dist_sq": (p - a).length_squared(), "u": 0.0}
	var u: float = (p - a).dot(ab) / len_sq
	u = clampf(u, 0.0, 1.0)
	var closest := a + ab * u
	return {"dist_sq": (p - closest).length_squared(), "u": u}

## Test whether a circle at center with radius collides with any solid
## linedef of `sector_id` (or any one-sided line). Used by (the original's)
## Phase 5+ collision.
static func circle_hits_solid_line(map: DoomTypes.MapData, sector_id: int, center: Vector2, radius: float) -> bool:
	if sector_id < 0:
		return true
	var s: DoomTypes.Sector = map.sectors[sector_id]
	var r2 := radius * radius
	for i in range(s.line_ids.size()):
		var ln: DoomTypes.Linedef = map.lines[s.line_ids[i]]
		var is_portal := (ln.flags & DoomTypes.LinedefFlags.TWO_SIDED) != 0 \
				and (ln.flags & DoomTypes.LinedefFlags.IMPASSABLE) == 0
		if is_portal:
			continue
		var a: Vector2 = map.vertices[ln.v1].p
		var b: Vector2 = map.vertices[ln.v2].p
		var res := dist_point_to_segment_sq(center, a, b)
		if res["dist_sq"] < r2:
			return true
	return false
