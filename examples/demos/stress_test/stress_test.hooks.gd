class_name DemoStressHooks
extends RefCounted
## The stress-test simulation hook + physics — the GDScript analogue of
## StressTest.hooks.uitkx (`useStressTestLoop`). Generates N bouncing boxes and, while
## `running`, ticks them every frame (re-rendering all of them) and measures avg FPS.

static func make_boxes(count: int, w: float, h: float) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var out: Array = []
	for j in count:
		var fs := 8.0 + rng.randf() * 16.0
		out.append({
			"id": "b%d" % j,
			"x": rng.randf() * maxf(1.0, w - fs),
			"y": rng.randf() * maxf(1.0, h - fs),
			"size": fs,
			"vx": (60.0 + rng.randf() * 120.0) * (1.0 if rng.randf() > 0.5 else -1.0),
			"vy": (60.0 + rng.randf() * 120.0) * (1.0 if rng.randf() > 0.5 else -1.0),
			"color": Color.from_hsv(rng.randf(), 0.7, 0.9),
		})
	return out

static func step_boxes(boxes: Array, dt: float, w: float, h: float) -> Array:
	var next: Array = []
	for b in boxes:
		var nx: float = b["x"] + b["vx"] * dt
		var ny: float = b["y"] + b["vy"] * dt
		var nvx: float = b["vx"]
		var nvy: float = b["vy"]
		if nx < 0: nx = 0; nvx = -nvx
		elif nx + b["size"] > w: nx = w - b["size"]; nvx = -nvx
		if ny < 0: ny = 0; nvy = -nvy
		elif ny + b["size"] > h: ny = h - b["size"]; nvy = -nvy
		next.append({ "id": b["id"], "x": nx, "y": ny, "size": b["size"], "vx": nvx, "vy": nvy, "color": b["color"] })
	return next

## Returns { boxes, fps, elapsed, frames, finished }.
static func use_stress_loop(area_ref: Dictionary, box_count: int, duration: float, running: bool, version: int, set_running: Callable) -> Dictionary:
	var boxes := Hooks.use_state([])
	var fps := Hooks.use_state(0.0)
	var elapsed := Hooks.use_state(0.0)
	var frames := Hooks.use_state(0)
	var finished := Hooks.use_state(false)
	var sim := Hooks.use_ref({})
	var running_ref := Hooks.use_ref(false)
	var duration_ref := Hooks.use_ref(10.0)
	running_ref["current"] = running
	duration_ref["current"] = duration

	var setup := func():
		if not running:
			return Callable()
		var area = area_ref["current"]
		if area == null or not area.is_inside_tree():
			return Callable()
		var sz: Vector2 = area.size
		var w: float = sz.x if sz.x > 1 else 600.0
		var h: float = sz.y if sz.y > 1 else 380.0
		var fresh := make_boxes(box_count, w, h)
		sim["current"] = { "boxes": fresh, "last_ms": -1, "total_ms": 0.0, "frames": 0, "elapsed": 0.0, "w": w, "h": h }
		boxes[1].call(fresh)
		fps[1].call(0.0); elapsed[1].call(0.0); frames[1].call(0); finished[1].call(false)
		var cb := func():
			if not running_ref["current"]:
				return
			var s: Dictionary = sim["current"]
			var now := Time.get_ticks_msec()
			if s["last_ms"] < 0:
				s["last_ms"] = now
				return
			var dt: float = (now - s["last_ms"]) / 1000.0
			s["last_ms"] = now
			s["frames"] += 1
			s["total_ms"] += dt
			s["elapsed"] += dt
			var cur_fps: float = (s["frames"] / s["total_ms"]) if s["total_ms"] > 0 else 0.0
			if s["elapsed"] >= duration_ref["current"]:
				fps[1].call(cur_fps); elapsed[1].call(s["elapsed"]); frames[1].call(s["frames"]); finished[1].call(true)
				set_running.call(false)   # stop from the ticker (no stale-finished race on restart)
				return
			s["boxes"] = step_boxes(s["boxes"], dt, s["w"], s["h"])
			boxes[1].call(s["boxes"])
			fps[1].call(cur_fps); elapsed[1].call(s["elapsed"]); frames[1].call(s["frames"])
		area.get_tree().process_frame.connect(cb)
		return func():
			if is_instance_valid(area) and area.is_inside_tree():
				area.get_tree().process_frame.disconnect(cb)
	Hooks.use_effect(setup, [version, running])

	return { "boxes": boxes[0], "fps": fps[0], "elapsed": elapsed[0], "frames": frames[0], "finished": finished[0] }
