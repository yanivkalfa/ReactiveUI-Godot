class_name DemoFragment
extends RefCounted

static func render(_p: Dictionary, _c: Array) -> RUIVNode:
	return DemoUtil.box("Fragment — group nodes without a wrapper", [
		V.label({ "text": "A fragment inserts its children flat — no extra container node:" }),
		V.panel({ "style": { "bg_color": Color(0.18, 0.18, 0.22), "pad": 10 } }, [
			V.vbox({ "style": { "separation": 4 } }, [
				V.label({ "text": "• before fragment" }),
				V.fragment([
					V.label({ "text": "• — fragment child A —", "style": { "font_color": Color(0.6, 0.85, 1.0) } }),
					V.label({ "text": "• — fragment child B —", "style": { "font_color": Color(0.6, 0.85, 1.0) } }),
				]),
				V.label({ "text": "• after fragment" }),
			]),
		]),
	])
