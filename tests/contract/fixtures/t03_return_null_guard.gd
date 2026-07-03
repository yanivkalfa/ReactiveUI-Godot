class_name X
extends RefCounted
## AUTO-GENERATED from t03_return_null_guard.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var ready = props.get("ready", false)
	if not ready:
		return null
	return V.label({ "text": "on" })
