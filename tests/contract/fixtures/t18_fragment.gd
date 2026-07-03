class_name NamedFragment
extends RefCounted
## AUTO-GENERATED from t18_fragment.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var xs = props.get("xs", [])
	var __cf0: Array = []
	for i in 3:
		__cf0.append(V.fc(Fragment.render, {}, [V.label({ "text": str(i) })], str(i)))
	return V.vbox({}, [V.fc(Fragment.render, {}, [V.label({ "text": "a" }), V.label({ "text": "b" })]), __cf0])
