class_name DemoContextConsumer
extends RefCounted
## AUTO-GENERATED from demos_context_context_consumer.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var accent = Hooks.useContext("accent")
	return V.panel({ "style": {"bg_color": accent, "corner_radius": 6, "pad": 12} }, [V.label({ "text": "I'm tinted by context", "style": {"font_color": Color.WHITE} })])
