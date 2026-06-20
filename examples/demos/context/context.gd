class_name DemoContext
extends RefCounted

static func render(_p: Dictionary, _c: Array) -> RUIVNode:
	var accent := Hooks.use_state(Color(0.3, 0.6, 1.0))
	Hooks.provide_context("accent", accent[0])
	return DemoUtil.box("Context — provide / use", [
		V.hbox({ "style": { "separation": 8 } }, [
			V.button({ "text": "Blue", "on_pressed": func(): accent[1].call(Color(0.3, 0.6, 1.0)) }),
			V.button({ "text": "Green", "on_pressed": func(): accent[1].call(Color(0.3, 0.85, 0.45)) }),
			V.button({ "text": "Red", "on_pressed": func(): accent[1].call(Color(0.9, 0.4, 0.35)) }),
		]),
		V.label({ "text": "Consumers below read 'accent' from context (no props passed):", "style": { "font_color": Color(0.7, 0.7, 0.7) } }),
		V.fc(DemoContext.consumer),
		V.fc(DemoContext.consumer),
	])

static func consumer(_p: Dictionary, _c: Array) -> RUIVNode:
	var accent = Hooks.use_context("accent")
	return V.panel({ "style": { "bg_color": accent, "corner_radius": 6, "pad": 12 } }, [
		V.label({ "text": "I'm tinted by context", "style": { "font_color": Color.WHITE } }),
	])
