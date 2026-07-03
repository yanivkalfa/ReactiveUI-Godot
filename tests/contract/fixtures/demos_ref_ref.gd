class_name DemoRef
extends RefCounted
## AUTO-GENERATED from demos_ref_ref.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var input_ref = Hooks.useRef(null)
	var focus = func():
		if input_ref["current"] != null:
			input_ref["current"].grab_focus()
	return V.fc(DemoBox.render, { "title": "useRef — imperative node access" }, [V.line_edit({ "placeholder_text": "focus me with the button →", "ref": input_ref, "style": {"min_width": 280} }), V.button({ "text": "Focus the field", "onClick": focus })])
