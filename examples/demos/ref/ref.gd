class_name DemoRef
extends RefCounted

static func render(_p: Dictionary, _c: Array) -> RUIVNode:
	var input_ref := Hooks.use_ref(null)
	var focus := func():
		if input_ref["current"] != null:
			input_ref["current"].grab_focus()
	return DemoUtil.box("use_ref — imperative node access", [
		V.line_edit({ "placeholder_text": "focus me with the button →", "ref": input_ref, "style": { "min_width": 280 } }),
		V.button({ "text": "Focus the field", "on_pressed": focus }),
	])
