class_name DemoSignalsDisplay
extends RefCounted
## AUTO-GENERATED from demos_signals_signals_display.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var v = Hooks.useSignal(DemoSignalsStore.shared)
	return V.panel({ "style": {"bg_color": Color(0.18, 0.18, 0.22), "corner_radius": 6, "pad": 10} }, [V.label({ "text": "consumer sees: %d" % v })])
