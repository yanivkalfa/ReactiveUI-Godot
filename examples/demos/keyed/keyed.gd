class_name DemoKeyed
extends RefCounted

static func render(_p: Dictionary, _c: Array) -> RUIVNode:
	var items := Hooks.use_state(["A", "B", "C", "D", "E"])
	var shuffle := func():
		var arr: Array = items[0].duplicate()
		arr.shuffle()
		items[1].call(arr)
	var rows: Array = []
	for id in items[0]:
		rows.append(V.fc(DemoKeyed.row, { "key": id, "id": id }))
	return DemoUtil.box("Keyed diff — identity survives reordering", [
		V.button({ "text": "Shuffle", "on_pressed": shuffle }),
		V.label({ "text": "Each tile keeps its node (and its random color) across shuffles — that's keys at work.", "style": { "font_color": Color(0.7, 0.7, 0.7) } }),
		V.hbox({ "style": { "separation": 6 } }, rows),
	])

static func row(props: Dictionary, _c: Array) -> RUIVNode:
	var col := Hooks.use_ref(null)
	if col["current"] == null:
		col["current"] = Color(randf() * 0.5 + 0.3, randf() * 0.5 + 0.3, randf() * 0.5 + 0.3)
	return V.panel({ "style": { "bg_color": col["current"], "corner_radius": 6, "min_size": Vector2(54, 54) } }, [
		V.center({}, [V.label({ "text": str(props["id"]), "style": { "font_size": 22, "font_color": Color.WHITE } })]),
	])
