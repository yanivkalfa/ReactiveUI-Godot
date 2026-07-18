extends SceneTree
## Perf: 2D BSP front-to-back walk vs the per-column portal ray-walker, timed over a
## 360-deg sweep at each level's spawn (headless, pure CPU -- no rendering). The BSP's
## win shows up most in open views, where the ray-walker pays MAX_RAY_HOPS per column.

func _ray_frame(st) -> void:
	# Replica of cast_frame's ray-walker branch (build_column_sector per column).
	var p = st.player
	var cols = st.frame.columns
	var depth = st.frame.depth_buffer
	var view_z: float = p.z + (0.6 if p.view_height <= 0.0 else p.view_height)
	var horizon: float = DoomTypes.C.VIEWPORT_H * 0.5 + p.pitch
	st.frame.reset_pools()
	for i in range(DoomTypes.C.VIEW_W):
		var camera_x := 2.0 * i / float(DoomTypes.C.VIEW_W) - 1.0
		var ray_ang: float = p.angle + atan(camera_x * tan(DoomTypes.C.HALF_FOV))
		var col = GameLogic.build_column_sector(st, p.x, p.y, cos(ray_ang), sin(ray_ang), cos(ray_ang - p.angle), view_z, horizon)
		cols[i] = col
		depth[i] = col.main.distance

func _bench(level: int) -> void:
	var st = GameLogic.new_game(level, DoomTypes.Difficulty.NORMAL)
	var N := 720
	# Warm up both pools/paths so growth cost doesn't skew the timing.
	for i in range(30):
		st.player.angle = i * TAU / 30.0
		_ray_frame(st); st.bsp.render_frame(st)
	var t0 := Time.get_ticks_usec()
	for i in range(N):
		st.player.angle = i * TAU / float(N)
		_ray_frame(st)
	var ray_us := (Time.get_ticks_usec() - t0) / float(N)
	t0 = Time.get_ticks_usec()
	for i in range(N):
		st.player.angle = i * TAU / float(N)
		st.bsp.render_frame(st)
	var bsp_us := (Time.get_ticks_usec() - t0) / float(N)
	print("L%d @ %.1f,%.1f : ray %6.0f us/frame   bsp %6.0f us/frame   speedup %.2fx" % [
		level, st.player.x, st.player.y, ray_us, bsp_us, ray_us / maxf(bsp_us, 1.0)])

func _initialize() -> void:
	for level in [1, 2, 3, 4, 5, 6]:
		_bench(level)
	quit(0)
