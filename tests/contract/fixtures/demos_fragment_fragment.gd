class_name DemoFragment
extends RefCounted
## AUTO-GENERATED from demos_fragment_fragment.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	return V.fc(DemoBox.render, { "title": "Fragment — group nodes without a wrapper" }, [V.label({ "text": "A fragment inserts its children flat — no extra container node:" }), V.panel({ "style": {"bg_color": Color(0.18, 0.18, 0.22), "pad": 10} }, [V.vbox({ "style": {"separation": 4} }, [V.label({ "text": "• before fragment" }), V.fragment([V.label({ "text": "• — fragment child A —", "style": {"font_color": Color(0.6, 0.85, 1.0)} }), V.label({ "text": "• — fragment child B —", "style": {"font_color": Color(0.6, 0.85, 1.0)} })]), V.label({ "text": "• after fragment" })])])])
