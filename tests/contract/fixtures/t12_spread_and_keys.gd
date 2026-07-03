class_name X
extends RefCounted
## AUTO-GENERATED from t12_spread_and_keys.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var extra = props.get("extra", {})
	return V.vbox({}, [V.label(V._spread_all([(extra), { "text": "s" }]), [], "k1"), V.label({ "text": "t" }, [], "k1")])
