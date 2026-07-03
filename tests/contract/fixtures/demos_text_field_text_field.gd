class_name DemoTextField
extends RefCounted
## AUTO-GENERATED from demos_text_field_text_field.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var s = Hooks.useState("")
	return V.fc(DemoBox.render, { "title": "Text Field — controlled input" }, [V.line_edit({ "text": s[0], "placeholder_text": "Type something…", "onChange": func(t): s[1].call(t), "style": {"min_width": 280} }), V.label({ "text": "You typed: \"%s\"  (%d chars)" % [s[0], s[0].length()] })])
