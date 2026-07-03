class_name DemoContextHandleSwatch
extends RefCounted
## AUTO-GENERATED from demos_context_handle_context_handle_swatch.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	const AccentContext = preload("res://examples/demos/context_handle/accent_context.gd")
	var c = Hooks.useContext(AccentContext.HANDLE)
	return V.label({ "text": "   ● this label reads the accent straight from the context handle", "style": {"font_color": c} })
