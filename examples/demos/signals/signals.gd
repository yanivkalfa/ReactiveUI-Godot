class_name DemoSignals
extends RefCounted

static var _shared_count := RUISignal.new(0)

static func render(_p: Dictionary, _c: Array) -> RUIVNode:
	return DemoUtil.box("Signals — shared state, no prop drilling", [
		V.label({ "text": "Two independent components read the SAME RUISignal:", "style": { "font_color": Color(0.7, 0.7, 0.7) } }),
		V.fc(DemoSignals.display),
		V.fc(DemoSignals.display),
		V.button({ "text": "Increment shared signal", "on_pressed": func(): _shared_count.update(func(v): return v + 1) }),
	])

static func display(_p: Dictionary, _c: Array) -> RUIVNode:
	var v = Hooks.use_signal(_shared_count)
	return V.panel({ "style": { "bg_color": Color(0.18, 0.18, 0.22), "corner_radius": 6, "pad": 10 } }, [
		V.label({ "text": "consumer sees: %d" % v }),
	])
