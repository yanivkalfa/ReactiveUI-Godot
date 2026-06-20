class_name DemoSlicing
extends RefCounted

static func render(_p: Dictionary, _c: Array) -> RUIVNode:
	var sliced := Hooks.use_state(RUIConfig.time_slicing)
	var rev := Hooks.use_state(0)
	var toggle := func():
		RUIConfig.time_slicing = not sliced[0]
		sliced[1].call(not sliced[0])
	var rows: Array = []
	for i in 25:
		rows.append(V.label({ "text": "row %d  (rev %d)" % [i, rev[0]], "key": str(i) }))
	return DemoUtil.box("Time-slicing — chunk big renders across frames", [
		V.hbox({ "style": { "separation": 8 } }, [
			V.button({ "text": "Time-slicing: %s" % ("ON" if sliced[0] else "OFF"), "on_pressed": toggle }),
			V.button({ "text": "Re-render 25 rows", "on_pressed": func(): rev[1].call(rev[0] + 1) }),
		]),
		V.label({ "text": "With slicing ON, big updates spread over frames (commit stays atomic).", "style": { "font_color": Color(0.7, 0.7, 0.7) } }),
		V.scroll({ "style": { "min_height": 200 } }, [V.vbox({ "style": { "separation": 2 } }, rows)]),
	])
