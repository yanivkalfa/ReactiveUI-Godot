extends SceneTree
## EVIDENCE (2026-06-20): isolates the PER-ELEMENT props cost (build + diff + apply to a real
## node), 1500 elements x 120 frames, to decide the typed-props architecture. RESULT proved
## the native Dictionary is optimal in pure GDScript — a generic runtime typed-props scheme is
## ~4x slower, a method-dispatched specialized one is still slower, and only fully INLINED code
## (a source generator emitting at the call site) beats the dict (~10%, but props is <10% of a
## frame). So the library stays on dicts; see memory project-reactiveui-godot PERF ROUND 2.
##   (a) dict        — native Dictionary + node.set("name", v)
##   (c) specialized — typed fields via method dispatch (what a polymorphic runtime gives)
##   (d) inlined     — typed fields, no method calls (what a source generator could emit)
##   (e) raw         — just write the node properties, no diff (the floor)
## Run: godot --headless --path <proj> --script res://tests/microbench.gd

class CRProps extends RefCounted:
	static var _pool: Array = []
	var position: Vector2
	var size: Vector2
	var color: Color
	var hp: bool
	var hs: bool
	var hc: bool
	var _in_use: bool
	static func obtain() -> CRProps:
		var p: CRProps = _pool.pop_back() if not _pool.is_empty() else CRProps.new()
		p._in_use = true; p.hp = false; p.hs = false; p.hc = false
		return p
	func release() -> void:
		if not _in_use: return
		_in_use = false; _pool.append(self)
	func changed(o) -> bool:
		if o == null: return true
		return position != o.position or size != o.size or color != o.color
	func apply(node: ColorRect, o) -> void:
		if hp and (o == null or position != o.position): node.position = position
		if hs and (o == null or size != o.size): node.size = size
		if hc and (o == null or color != o.color): node.color = color

func _initialize() -> void:
	_run()

func _run() -> void:
	var N := 1500
	var frames := 120
	var nodes: Array = []
	for i in N:
		var nd := ColorRect.new()
		root.add_child(nd)
		nodes.append(nd)
	var sz := Vector2(8, 8)
	var col := Color(0.4, 0.6, 0.8)

	# (a) dict
	var prev: Array = []
	prev.resize(N)
	var t := Time.get_ticks_usec()
	for f in frames:
		for i in N:
			var np := { "position": Vector2(i % 800, f), "size": sz, "color": col }
			var op = prev[i]
			if op == null or np != op:
				for k in np:
					if op == null or not op.has(k) or op[k] != np[k]:
						nodes[i].set(k, np[k])
			prev[i] = np
	print("(a) dict        : %.3f ms/frame" % ((Time.get_ticks_usec() - t) / 1000.0 / frames))

	# (c) specialized typed fields via method dispatch (a polymorphic runtime typed-props)
	var prevc: Array = []
	prevc.resize(N)
	t = Time.get_ticks_usec()
	for f in frames:
		for i in N:
			var np := CRProps.obtain()
			np.position = Vector2(i % 800, f); np.hp = true
			np.size = sz; np.hs = true
			np.color = col; np.hc = true
			var op = prevc[i]
			if np.changed(op):
				np.apply(nodes[i], op)
			if op != null: op.release()
			prevc[i] = np
	print("(c) specialized : %.3f ms/frame" % ((Time.get_ticks_usec() - t) / 1000.0 / frames))

	# (d) inlined specialized — no method calls, direct field + property writes (the absolute
	# GDScript ceiling; what a source generator could emit straight at the call site).
	var prevd: Array = []
	prevd.resize(N)
	t = Time.get_ticks_usec()
	for f in frames:
		for i in N:
			var np := CRProps.obtain()
			var pos := Vector2(i % 800, f)
			np.position = pos
			np.size = sz
			np.color = col
			var op = prevd[i]
			var nd: ColorRect = nodes[i]
			if op == null:
				nd.position = pos; nd.size = sz; nd.color = col
			else:
				if pos != op.position: nd.position = pos
				if sz != op.size: nd.size = sz
				if col != op.color: nd.color = col
				op.release()
			prevd[i] = np
	print("(d) inlined spec: %.3f ms/frame" % ((Time.get_ticks_usec() - t) / 1000.0 / frames))

	# (e) raw lower bound: just write the 3 node properties directly, no props object at all.
	t = Time.get_ticks_usec()
	for f in frames:
		for i in N:
			var nd: ColorRect = nodes[i]
			nd.position = Vector2(i % 800, f)
			nd.size = sz
			nd.color = col
	print("(e) raw node set: %.3f ms/frame" % ((Time.get_ticks_usec() - t) / 1000.0 / frames))
	quit()
