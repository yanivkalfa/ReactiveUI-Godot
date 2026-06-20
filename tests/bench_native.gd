extends SceneTree
## NATIVE baseline — the EXACT same workload as tests/bench.gd (N bouncing boxes, only
## position changes, same physics + frame counts), written in pure Godot with ZERO
## ReactiveUI involvement: N ColorRects created once, positions written directly each frame.
## The gap between this and bench.gd IS the library's reconcile/diff/commit overhead.
## Headless = no GPU, so this is the framework-free CPU floor for the workload.
## Run: godot --headless --path <proj> --script res://tests/bench_native.gd

func _initialize() -> void:
	_run()

func _run() -> void:
	for n in [300, 750, 1500, 2000, 3000]:
		await _bench(n)
	quit()

func _make(n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var arr: Array = []
	for i in n:
		arr.append({ "id": "b%d" % i, "x": rng.randf() * 790.0, "y": rng.randf() * 590.0,
			"vx": rng.randf() * 100.0 - 50.0, "vy": rng.randf() * 100.0 - 50.0,
			"color": Color.from_hsv(rng.randf(), 0.7, 0.9) })
	return arr

func _bench(n: int) -> void:
	var c := Control.new()
	c.size = Vector2(800, 600)
	root.add_child(c)
	var boxes := _make(n)
	var sz := Vector2(8, 8)
	# Native: create the ColorRect nodes ONCE (like the reconciler reuses nodes), then just
	# write positions every frame. No vnodes, no diffing, no commit.
	var rects: Array = []
	for b in boxes:
		var r := ColorRect.new()
		r.position = Vector2(b["x"], b["y"])
		r.size = sz
		r.color = b["color"]
		c.add_child(r)
		rects.append(r)
	await process_frame
	await process_frame

	var warm := 15
	var measure := 100
	var t0 := 0
	for i in (warm + measure):
		# Same immutable sim as bench.gd, so the ONLY difference is reconcile vs direct write.
		var next: Array = []
		for b in boxes:
			var nvx: float = b["vx"]
			var nvy: float = b["vy"]
			var nx: float = b["x"] + nvx * 0.016
			var ny: float = b["y"] + nvy * 0.016
			if nx < 0.0 or nx > 790.0: nvx = -nvx
			if ny < 0.0 or ny > 590.0: nvy = -nvy
			next.append({ "id": b["id"], "x": nx, "y": ny, "vx": nvx, "vy": nvy, "color": b["color"] })
		boxes = next
		if i == warm:
			t0 = Time.get_ticks_usec()
		for j in n:
			rects[j].position = Vector2(boxes[j]["x"], boxes[j]["y"])   # direct, no library
		await process_frame

	var elapsed: float = (Time.get_ticks_usec() - t0) / 1000000.0
	print("[native] N=%4d : %7.1f fps   (%.3f ms/frame, direct node writes, headless/no-GPU)" % [n, measure / elapsed, elapsed / measure * 1000.0])
	c.queue_free()
	await process_frame
