extends SceneTree
## Micro: how a property write is done, 1500 ColorRects x 200 frames. Tests whether the
## generic node.set("name", v) the library uses is meaningfully slower than the direct
## node.position = v the native baseline uses (and StringName / set_indexed / Callable variants).
func _initialize() -> void: _run()

func _run() -> void:
	var N := 1500
	var frames := 200
	var rects: Array = []
	for i in N:
		var r := ColorRect.new(); root.add_child(r); rects.append(r)

	var t := Time.get_ticks_usec()
	for f in frames:
		var v := Vector2(f, f)
		for r in rects: r.set("position", v)
	print("(a) set(\"position\", v)      : %.3f ms/f" % ((Time.get_ticks_usec()-t)/1000.0/frames))

	t = Time.get_ticks_usec()
	for f in frames:
		var v := Vector2(f, f)
		for r in rects: r.position = v
	print("(b) r.position = v (direct)  : %.3f ms/f" % ((Time.get_ticks_usec()-t)/1000.0/frames))

	var sn := &"position"
	t = Time.get_ticks_usec()
	for f in frames:
		var v := Vector2(f, f)
		for r in rects: r.set(sn, v)
	print("(c) set(&\"position\", v)      : %.3f ms/f" % ((Time.get_ticks_usec()-t)/1000.0/frames))

	t = Time.get_ticks_usec()
	for f in frames:
		var v := Vector2(f, f)
		for r in rects:
			var rr: ColorRect = r
			rr.position = v
	print("(d) typed-local .position    : %.3f ms/f" % ((Time.get_ticks_usec()-t)/1000.0/frames))

	# (e) cached Callable per node (Callable(node, "set_position") — note set_position takes a Vector2)
	var setters: Array = []
	for r in rects: setters.append(Callable(r, "set_position"))
	t = Time.get_ticks_usec()
	for f in frames:
		var v := Vector2(f, f)
		for cb in setters: cb.call(v)
	print("(e) cached Callable setter   : %.3f ms/f" % ((Time.get_ticks_usec()-t)/1000.0/frames))
	quit()
