class_name DemoSlicing
extends RefCounted
## AUTO-GENERATED from demos_slicing_slicing.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var sliced = Hooks.useState(RUIConfig.time_slicing)
	var rev = Hooks.useState(0)
	var toggle = func():
		RUIConfig.time_slicing = not sliced[0]
		sliced[1].call(not sliced[0])
	var __cf0: Array = []
	for i in 25:
		__cf0.append(V.label({ "text": "row %d  (rev %d)" % [i, rev[0]] }, [], str(i)))
	return V.fc(DemoBox.render, { "title": "Time-slicing — chunk big renders across frames" }, [V.hbox({ "style": {"separation": 8} }, [V.button({ "text": "Time-slicing: %s" % ("ON" if sliced[0] else "OFF"), "onClick": toggle }), V.button({ "text": "Re-render 25 rows", "onClick": func(): rev[1].call(rev[0] + 1) })]), V.label({ "text": "With slicing ON, big updates spread over frames (commit stays atomic).", "style": {"font_color": Color(0.7, 0.7, 0.7)} }), V.scroll({ "style": {"min_height": 200} }, [V.vbox({ "style": {"separation": 2} }, [__cf0])])])
