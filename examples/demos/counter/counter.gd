class_name DemoCounter
extends RefCounted

static func render(_p: Dictionary, _c: Array) -> RUIVNode:
	var s := Hooks.use_state(0)
	return DemoUtil.box("Counter — use_state", [
		V.label({ "text": "Count: %d" % s[0], "style": { "font_size": 28 } }),
		V.hbox({ "style": { "separation": 8 } }, [
			V.button({ "text": "  −1  ", "on_pressed": func(): s[1].call(s[0] - 1) }),
			V.button({ "text": "  +1  ", "on_pressed": func(): s[1].call(func(c): return c + 1) }),
			V.button({ "text": " Reset ", "on_pressed": func(): s[1].call(0) }),
		]),
	])
