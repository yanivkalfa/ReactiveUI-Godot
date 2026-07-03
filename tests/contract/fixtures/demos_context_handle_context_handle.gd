class_name DemoContextHandle
extends RefCounted
## AUTO-GENERATED from demos_context_handle_context_handle.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	const AccentContext = preload("res://examples/demos/context_handle/accent_context.gd")
	var accent = Hooks.useState(Color(0.4, 0.7, 1.0))
	Hooks.provideContext(AccentContext.HANDLE, accent[0])
	return V.fc(DemoBox.render, { "title": "Context handle — createContext / RUIContext" }, [V.label({ "text": "A createContext() handle (object identity, no string keys) provided to the subtree:", "style": {"font_color": Color(0.7, 0.7, 0.7)} }), V.hbox({ "style": {"separation": 8} }, [V.button({ "text": "Blue", "onClick": func(): accent[1].call(Color(0.4, 0.7, 1.0)) }), V.button({ "text": "Green", "onClick": func(): accent[1].call(Color(0.35, 0.85, 0.45)) }), V.button({ "text": "Red", "onClick": func(): accent[1].call(Color(0.9, 0.4, 0.35)) })]), V.fc(DemoContextHandleSwatch.render, {})])
