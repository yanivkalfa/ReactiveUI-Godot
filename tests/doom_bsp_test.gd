extends SceneTree
const BSP = preload("res://examples/demos/doom/doom_bsp.gd")
func _initialize() -> void:
	var st := GameLogic.new_game(1, DoomTypes.Difficulty.NORMAL)
	var map: DoomTypes.MapData = st.sector_map
	var w: int = map.cell_width
	var h: int = map.cell_height
	var t0 := Time.get_ticks_usec()
	var bsp = BSP.build(map)
	print("BSP built in %.2f ms: %d leaves (grid %dx%d = %d cells)" % [(Time.get_ticks_usec()-t0)/1000.0, bsp.leaf_count, w, h, w*h])
	var checked := 0; var mism := 0
	for cy in range(h):
		for cx in range(w):
			var expected: int = map.cell_to_sector[cy*w+cx]
			var got: int = bsp.sector_at(cx+0.5, cy+0.5)
			checked += 1
			if got != expected:
				mism += 1
				if mism <= 5: print("  MISMATCH (%d,%d): bsp=%d expected=%d" % [cx,cy,got,expected])
	print("point-location: %d cells, %d mismatches" % [checked, mism])
	var agree := 0; var differ := 0
	for cy in range(1, h-1, 2):
		for cx in range(1, w-1, 2):
			if map.cell_to_sector[cy*w+cx] < 0: continue
			if Raycast.point_in_sector_from_hint(map, Vector2(cx+0.5, cy+0.5), -1) == bsp.sector_at(cx+0.5, cy+0.5): agree += 1
			else: differ += 1
	print("vs point_in_sector_from_hint: %d agree, %d differ" % [agree, differ])
	var lf = bsp.locate(st.player.x, st.player.y)
	print("player leaf: cell(%d,%d) sector=%d segs=%d" % [lf.cx, lf.cy, lf.sector, lf.segs.size()])
	quit(0)
