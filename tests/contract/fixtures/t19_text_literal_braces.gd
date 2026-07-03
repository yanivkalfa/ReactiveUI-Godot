class_name LiteralBraces
extends RefCounted
## AUTO-GENERATED from t19_text_literal_braces.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var n = props.get("n", 3)
	return V.vbox({}, [V.label({ "text": "Count:" + str(n) + "items" }), V.label({ "text": str(n) + "at node start" })])
