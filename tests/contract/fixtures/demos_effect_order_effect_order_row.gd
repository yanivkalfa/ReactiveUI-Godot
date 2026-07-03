class_name DemoEffectOrderRow
extends RefCounted
## AUTO-GENERATED from demos_effect_order_effect_order_row.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var idx = props.get("idx")
	var append = props.get("append")
	var eff = func():
		append.call("▶ mount row %d" % idx)
		return func(): append.call("■ unmount row %d" % idx)
	Hooks.useEffect(eff, [])
	return V.label({ "text": "• row %d" % idx })
