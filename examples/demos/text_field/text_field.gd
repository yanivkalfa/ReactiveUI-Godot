class_name DemoTextField
extends RefCounted

static func render(_p: Dictionary, _c: Array) -> RUIVNode:
	var s := Hooks.use_state("")
	return DemoUtil.box("Text Field — controlled input", [
		V.line_edit({
			"text": s[0], "placeholder_text": "Type something…",
			"on_text_changed": func(t): s[1].call(t),
			"style": { "min_width": 280 },
		}),
		V.label({ "text": "You typed: \"%s\"  (%d chars)" % [s[0], s[0].length()] }),
	])
