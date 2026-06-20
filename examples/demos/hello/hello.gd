class_name DemoHello
extends RefCounted

static func render(_p: Dictionary, _c: Array) -> RUIVNode:
	return DemoUtil.box("Hello World", [
		V.label({ "text": "Hello, reactive Godot! 👋", "style": { "font_size": 20 } }),
		V.label({ "text": "Every demo here is a function component built with V.* + hooks.", "style": { "font_color": Color(0.7, 0.7, 0.7) } }),
	])
