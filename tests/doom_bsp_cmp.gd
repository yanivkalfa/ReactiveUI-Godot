extends SceneTree
const BSP = preload("res://examples/demos/doom/doom_bsp.gd")
func _place(st, x, y, a):
	st.player.x = x; st.player.y = y; st.player.angle = a
	st.player.sector_id = Raycast.point_in_sector_from_hint(st.sector_map, Vector2(x,y), -1)
func _shoot(st, nm):
	var VW=800; var VH=500
	var quads := DoomGameScreenLogic.build_world_geometry(st)
	var root := Control.new(); root.size = Vector2(VW,VH); root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var hz: float = VH*0.5 + st.player.pitch
	var sky := ColorRect.new(); sky.position=Vector2(0,0); sky.size=Vector2(VW,hz); sky.color=Color(0.42,0.44,0.47); sky.z_index=-4096; root.add_child(sky)
	var fb := ColorRect.new(); fb.position=Vector2(0,hz); fb.size=Vector2(VW,VH); fb.color=Color(0.34,0.29,0.22); fb.z_index=-4096; root.add_child(fb)
	for q in quads:
		var tr := TextureRect.new(); tr.position=Vector2(q.x,q.y); tr.size=Vector2(q.w,q.h); tr.texture=q.texture
		tr.stretch_mode=TextureRect.STRETCH_SCALE; tr.modulate=q.modulate; tr.material=q.material; tr.z_index=q.z_index; root.add_child(tr)
	get_root().add_child(root)
	for i in range(5): await process_frame
	get_root().get_texture().get_image().save_png("user://%s.png" % nm)
	print("saved %s (quads=%d)" % [nm, quads.size()])
	root.queue_free(); await process_frame
func _snap(st) -> Array:
	# Extract per-column scalars (the pool is reused between casts, so copy values now).
	var out := []
	for ci in st.frame.columns:
		var m = ci.main
		var etop: float = (m.top_px if m and not m.is_sky else 999.0)
		var ebot: float = (m.bot_px if m and not m.is_sky else 0.0)
		for e in ci.extras:
			if e.top_px < etop: etop = e.top_px
			if e.bot_px > ebot: ebot = e.bot_px
		out.append({
			"top": (m.top_px if m else 0.0), "bot": (m.bot_px if m else 0.0),
			"dist": (m.distance if m else 0.0), "tex": (m.wall_tex_idx if m else -1),
			"sky": (m.is_sky if m else true),
			"nx": ci.extras.size(), "nf": ci.floor_bands.size(), "nc": ci.ceiling_bands.size(),
			"etop": etop, "ebot": ebot,
		})
	return out

func _coldiff(ra: Array, rb: Array) -> void:
	var n: int = mini(ra.size(), rb.size())
	var worst := 0.0; var worst_c := -1; var nbad := 0
	for c in range(n):
		var a = ra[c]; var b = rb[c]
		var d: float = absf(a.top-b.top) + absf(a.bot-b.bot) + absf(a.etop-b.etop) + absf(a.ebot-b.ebot)
		# Real structural break (not the known ±1 band-boundary noise from <1px depth diff).
		var is_struct: bool = (a.sky != b.sky) or (a.nx != b.nx) or (a.tex != b.tex) \
				or absf(a.nf - b.nf) > 2 or absf(a.nc - b.nc) > 2
		if d > 8.0 or is_struct:
			nbad += 1
			if nbad <= 10:
				print("  col %3d  ray[top=%.0f bot=%.0f etop=%.0f ebot=%.0f x=%d f=%d c=%d sky=%s]  bsp[top=%.0f bot=%.0f etop=%.0f ebot=%.0f x=%d f=%d c=%d sky=%s]" % [
					c, a.top,a.bot,a.etop,a.ebot,a.nx,a.nf,a.nc,a.sky, b.top,b.bot,b.etop,b.ebot,b.nx,b.nf,b.nc,b.sky])
		if d > worst: worst = d; worst_c = c
	print("coldiff: %d/%d cols differ (>8px or structural break), worst dPx=%.1f at col %d" % [nbad, n, worst, worst_c])

func _run(level: int, x, y, ang: float, tag: String) -> void:
	var st := GameLogic.new_game(level, DoomTypes.Difficulty.NORMAL)
	if x != null:
		_place(st, x, y, ang)
	else:
		st.player.angle = ang # use the level's own spawn x/y, just aim
		st.player.sector_id = Raycast.point_in_sector_from_hint(st.sector_map, Vector2(st.player.x, st.player.y), -1)
	print("== %s  (L%d @ %.1f,%.1f a=%.2f  view_z spawn) ==" % [tag, level, st.player.x, st.player.y, ang])
	GameLogic.cast_frame(st)
	var ray_cols := _snap(st)
	await _shoot(st, tag + "_ray")
	var bsp = BSP.build(st.sector_map)
	bsp.render_frame(st)
	var bsp_cols := _snap(st)
	await _shoot(st, tag + "_bsp")
	_diff(tag + "_ray", tag + "_bsp")
	_coldiff(ray_cols, bsp_cols)

func _initialize():
	DisplayServer.window_set_size(Vector2i(800,500))
	await _run(1, 24.5, 24.5, 0.0, "cmp")            # E1M1 flat -- regression
	await _run(6, null, null, 0.0, "e6a")            # E1M6 Skybridge (3D floors) -- spawn, 4 aims
	await _run(6, null, null, 1.57, "e6b")
	await _run(6, null, null, 3.14, "e6c")
	await _run(6, null, null, 4.71, "e6d")
	await _run(4, null, null, 0.0, "e4a")            # E1M4 Outpost (3D)
	await _run(4, null, null, 1.57, "e4b")
	quit(0)

func _diff(a: String, b: String) -> void:
	var ia := Image.load_from_file("user://%s.png" % a)
	var ib := Image.load_from_file("user://%s.png" % b)
	if ia == null or ib == null or ia.get_size() != ib.get_size():
		print("diff: cannot compare"); return
	var w := ia.get_width(); var h := ia.get_height()
	var diff := 0; var total := w * h; var maxd := 0.0
	var out := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in range(h):
		for x in range(w):
			var ca := ia.get_pixel(x, y); var cb := ib.get_pixel(x, y)
			var d: float = absf(ca.r-cb.r) + absf(ca.g-cb.g) + absf(ca.b-cb.b)
			if d > 0.02:
				diff += 1
				if d > maxd: maxd = d
				out.set_pixel(x, y, Color(1, 0, 1))
			else:
				out.set_pixel(x, y, Color(ca.r*0.4, ca.g*0.4, ca.b*0.4))
	out.save_png("user://cmp_diff.png")
	print("diff: %d/%d px differ (%.2f%%), max delta %.2f -> cmp_diff.png" % [diff, total, 100.0*diff/total, maxd])
