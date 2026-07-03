class_name DemoSpread
extends RefCounted
## AUTO-GENERATED from demos_spread_spread.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var n = Hooks.useState(0)
	var shared = { "custom_minimum_size": Vector2(140, 0), "text": "shared" }
	return V.fc(DemoBox.render, { "title": "Prop spread — {...obj}" }, [V.label({ "text": "A dict is spread into <Button>; props AFTER the spread override it:", "style": {"font_color": Color(0.7, 0.7, 0.7)} }), V.hbox({ "style": {"separation": 8} }, [V.button(V._spread_all([(shared)])), V.button(V._spread_all([(shared), { "text": "count %d" % n[0], "onClick": func(): n[1].call(n[0] + 1) }]))])])
