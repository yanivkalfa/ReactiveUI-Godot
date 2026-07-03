class_name DemoBailoutChild
extends RefCounted
## AUTO-GENERATED from demos_bailout_bailout_child.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var renders = Hooks.useRef(0)
	renders["current"] += 1
	return V.panel({ "style": {"bg_color": Color(0.2, 0.2, 0.26), "corner_radius": 6, "pad": 10} }, [V.label({ "text": "child render count: %d  (bailed out)" % renders["current"] })])
