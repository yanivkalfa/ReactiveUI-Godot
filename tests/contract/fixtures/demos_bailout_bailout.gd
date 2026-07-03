class_name DemoBailout
extends RefCounted
## AUTO-GENERATED from demos_bailout_bailout.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var n = Hooks.useState(0)
	return V.fc(DemoBox.render, { "title": "Bailout — unchanged children skip re-render" }, [V.label({ "text": "Parent state: %d" % n[0] }), V.button({ "text": "Re-render parent", "onClick": func(): n[1].call(n[0] + 1) }), V.label({ "text": "The child's props never change → its render count stays flat:", "style": {"font_color": Color(0.7, 0.7, 0.7)} }), V.fc(DemoBailoutChild.render, { "label": "static" })])
