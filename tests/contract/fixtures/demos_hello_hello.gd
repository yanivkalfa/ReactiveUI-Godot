class_name DemoHello
extends RefCounted
## AUTO-GENERATED from demos_hello_hello.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	return V.fc(DemoBox.render, { "title": "Hello World" }, [V.label({ "text": "Hello, reactive Godot! 👋", "style": {"font_size": 20} }), V.label({ "text": "Every demo here is a .guitkx component — JSX-like markup compiled to a GDScript render fn.", "style": {"font_color": Color(0.7, 0.7, 0.7)} })])
