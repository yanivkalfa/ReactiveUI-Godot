class_name X
extends RefCounted
## AUTO-GENERATED from t06_elif_no_at.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var c = props.get("c", true)
	var __cf0 = null
	if c:
		__cf0 = V.label({ "text": "a" })
	elif false:
		__cf0 = V.label({ "text": "b" })
	return V.vbox({}, [__cf0])
