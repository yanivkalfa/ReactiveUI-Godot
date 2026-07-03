class_name X
extends RefCounted
## AUTO-GENERATED from t10_match_arms.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var v = props.get("v", 0)
	var __cf0 = null
	match v:
		0:
			__cf0 = V.label({ "text": "zero" })
		1:
			__cf0 = V.label({ "text": "one" })
		_:
			__cf0 = V.label({ "text": "many" })
	return V.vbox({}, [__cf0])
