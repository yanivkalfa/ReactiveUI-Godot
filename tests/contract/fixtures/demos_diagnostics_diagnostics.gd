class_name DemoDiagnostics
extends RefCounted
## AUTO-GENERATED from demos_diagnostics_diagnostics.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	RUIDiagnostics.enabled = true
	var tick = Hooks.useState(0)
	var shown = Hooks.useState(RUIDiagnostics.report())
	var capture = func():
		shown[1].call(RUIDiagnostics.report())
		return Callable()
	Hooks.useEffect(capture, [tick[0]])
	var do_reset = func():
		RUIDiagnostics.reset()
		shown[1].call(RUIDiagnostics.report())
	var rep: Dictionary = shown[0]
	return V.fc(DemoBox.render, { "title": "Diagnostics — render/commit metrics" }, [V.label({ "text": "renders: %d    commits: %d" % [rep["renders"], rep["commits"]] }), V.label({ "text": "placements: %d    updates: %d    deletions: %d" % [rep["placements"], rep["updates"], rep["deletions"]] }), V.label({ "text": "captured after the last click's commit (displaying is itself a render)", "style": {"font_color": Color(0.55, 0.55, 0.55)} }), V.hbox({ "style": {"separation": 8} }, [V.button({ "text": "Trigger a render", "onClick": func(): tick[1].call(tick[0] + 1) }), V.button({ "text": "Reset counters", "onClick": do_reset })])])
