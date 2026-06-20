class_name DemoEffect
extends RefCounted

static func render(_p: Dictionary, _c: Array) -> RUIVNode:
	var on := Hooks.use_state(true)
	var log := Hooks.use_ref([])
	var eff := func():
		var was: bool = on[0]
		log["current"].append("▶ setup (dep=%s)" % was)
		return func(): log["current"].append("■ cleanup (dep=%s)" % was)
	Hooks.use_effect(eff, [on[0]])
	return DemoUtil.box("use_effect — lifecycle + cleanup", [
		V.button({ "text": "Toggle dependency (now %s)" % on[0], "on_pressed": func(): on[1].call(not on[0]) }),
		V.label({ "text": "Effect log (cleanup runs before the next setup):", "style": { "font_color": Color(0.7, 0.7, 0.7) } }),
		V.label({ "text": "\n".join(log["current"]) }),
	])
