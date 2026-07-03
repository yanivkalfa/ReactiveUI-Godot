class_name DemoCounter
extends RefCounted
## AUTO-GENERATED from demos_counter_counter.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var s = Hooks.useState(0)
	return V.fc(DemoBox.render, { "title": "Counter — useState" }, [V.label({ "text": "Count: %d" % s[0], "style": {"font_size": 28} }), V.hbox({ "style": {"separation": 8} }, [V.button({ "text": "  −1  ", "onClick": func(): s[1].call(s[0] - 1) }), V.button({ "text": "  +1  ", "onClick": func(): s[1].call(func(c): return c + 1) }), V.button({ "text": " Reset ", "onClick": func(): s[1].call(0) })])])
