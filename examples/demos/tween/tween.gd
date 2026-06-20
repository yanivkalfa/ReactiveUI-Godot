class_name DemoTween
extends RefCounted

static func render(_p: Dictionary, _c: Array) -> RUIVNode:
	var box_ref := Hooks.use_ref(null)
	var n := Hooks.use_state(0)
	Hooks.use_tween(box_ref, "modulate", Color(1, 1, 1, 1), 0.5, [n[0]])
	var pulse := func():
		if box_ref["current"] != null:
			box_ref["current"].modulate = Color(1, 1, 1, 0.0)
		n[1].call(n[0] + 1)
	return DemoUtil.box("use_tween — animate a node via Godot's Tween", [
		V.button({ "text": "Pulse (fade in)", "on_pressed": pulse }),
		V.panel({ "ref": box_ref, "style": { "bg_color": Color(0.3, 0.6, 0.9), "corner_radius": 8, "min_size": Vector2(220, 90), "pad": 12 } }, [
			V.label({ "text": "I fade in on every pulse", "style": { "font_color": Color.WHITE } }),
		]),
	])
