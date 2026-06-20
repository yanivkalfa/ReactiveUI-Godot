class_name DemoBailout
extends RefCounted

static func render(_p: Dictionary, _c: Array) -> RUIVNode:
	var n := Hooks.use_state(0)
	return DemoUtil.box("Bailout — unchanged children skip re-render", [
		V.label({ "text": "Parent state: %d" % n[0] }),
		V.button({ "text": "Re-render parent", "on_pressed": func(): n[1].call(n[0] + 1) }),
		V.label({ "text": "The child's props never change → its render count stays flat:", "style": { "font_color": Color(0.7, 0.7, 0.7) } }),
		V.fc(DemoBailout.child, { "label": "static" }),
	])

static func child(_p: Dictionary, _c: Array) -> RUIVNode:
	var renders := Hooks.use_ref(0)
	renders["current"] += 1
	return V.panel({ "style": { "bg_color": Color(0.2, 0.2, 0.26), "corner_radius": 6, "pad": 10 } }, [
		V.label({ "text": "child render count: %d  (bailed out)" % renders["current"] }),
	])
