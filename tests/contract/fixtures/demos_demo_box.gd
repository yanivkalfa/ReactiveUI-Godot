class_name DemoBox
extends RefCounted
## AUTO-GENERATED from demos_demo_box.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var title = props.get("title", "")
	return V.margin({ "style": {"margin": 20} }, [V.vbox({ "style": {"separation": 12} }, [V.label({ "text": title, "style": {"font_size": 24, "font_color": Color(0.55, 0.8, 1.0)} }), V.h_separator({}), (children)])])
