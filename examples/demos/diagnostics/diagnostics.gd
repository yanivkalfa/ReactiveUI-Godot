class_name DemoDiagnostics
extends RefCounted

static func render(_p: Dictionary, _c: Array) -> RUIVNode:
	RUIDiagnostics.enabled = true
	var tick := Hooks.use_state(0)
	var shown := Hooks.use_state(RUIDiagnostics.report())
	var capture := func():
		shown[1].call(RUIDiagnostics.report())
		return Callable()
	Hooks.use_effect(capture, [tick[0]])
	var do_reset := func():
		RUIDiagnostics.reset()
		shown[1].call(RUIDiagnostics.report())
	var rep: Dictionary = shown[0]
	return DemoUtil.box("Diagnostics — render/commit metrics", [
		V.label({ "text": "renders: %d    commits: %d" % [rep["renders"], rep["commits"]] }),
		V.label({ "text": "placements: %d    updates: %d    deletions: %d" % [rep["placements"], rep["updates"], rep["deletions"]] }),
		V.label({ "text": "captured after the last click's commit (displaying is itself a render)", "style": { "font_color": Color(0.55, 0.55, 0.55) } }),
		V.hbox({ "style": { "separation": 8 } }, [
			V.button({ "text": "Trigger a render", "on_pressed": func(): tick[1].call(tick[0] + 1) }),
			V.button({ "text": "Reset counters", "on_pressed": do_reset }),
		]),
	])
