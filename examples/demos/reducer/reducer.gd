class_name DemoReducer
extends RefCounted

static func render(_p: Dictionary, _c: Array) -> RUIVNode:
	var reducer := func(state, action):
		match action:
			"inc": return state + 1
			"dec": return state - 1
			"reset": return 0
		return state
	var r := Hooks.use_reducer(reducer, 0)
	return DemoUtil.box("use_reducer — actions instead of raw setters", [
		V.label({ "text": "State: %d" % r[0], "style": { "font_size": 28 } }),
		V.hbox({ "style": { "separation": 8 } }, [
			V.button({ "text": "dec", "on_pressed": func(): r[1].call("dec") }),
			V.button({ "text": "inc", "on_pressed": func(): r[1].call("inc") }),
			V.button({ "text": "reset", "on_pressed": func(): r[1].call("reset") }),
		]),
	])
