class_name X
extends RefCounted
## AUTO-GENERATED from t04_early_return_in_if.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var ready = props.get("ready", false)
	if not ready:
	return V.label({ "text": "early" })
