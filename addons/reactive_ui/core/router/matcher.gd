class_name RUIRouteMatcher
extends RefCounted
## Path matching + ranking. Patterns support static segments ("/users"), params
## (":id"), and a trailing splat ("*"). Ports the engine-agnostic RouteMatcher/
## RouteRanker logic (more specific routes win, splat loses).

## Match `path` against `pattern`. Returns { "params": {...} } or null.
static func match_pattern(pattern: String, path: String):
	var pp := _segments(pattern)
	var ps := _segments(path)
	var params := {}
	var i := 0
	while i < pp.size():
		var seg: String = pp[i]
		if seg == "*":
			params["*"] = "/".join(ps.slice(i))
			return { "params": params }
		if i >= ps.size():
			return null
		if seg.begins_with(":"):
			params[seg.substr(1)] = ps[i]
		elif seg != ps[i]:
			return null
		i += 1
	if ps.size() != pp.size():
		return null
	return { "params": params }

## Higher = more specific. Static > param > splat; root ("/") beats splat.
static func rank(pattern: String) -> int:
	var score := 4
	for s in _segments(pattern):
		if s == "*": score -= 3
		elif s.begins_with(":"): score += 5
		else: score += 10
	return score

## Best match across a route table. Returns { "route": {...}, "params": {...} } or null.
static func match_routes(routes: Array, path: String):
	var best = null
	var best_rank := -2147483648
	for r in routes:
		var m = match_pattern(str(r.get("path", "")), path)
		if m != null:
			var rk := rank(str(r.get("path", "")))
			if rk > best_rank:
				best_rank = rk
				best = { "route": r, "params": m["params"] }
	return best

static func _segments(path: String) -> Array:
	return Array(path.strip_edges().split("/", false))
