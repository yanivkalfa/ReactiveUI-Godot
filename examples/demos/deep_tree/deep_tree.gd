class_name DemoDeepTree
extends RefCounted

static func render(_p: Dictionary, _c: Array) -> RUIVNode:
	var depth := Hooks.use_state(8)
	return DemoUtil.box("Deep component tree", [
		V.hbox({ "style": { "separation": 8 } }, [
			V.button({ "text": "− depth", "on_pressed": func(): depth[1].call(maxi(1, depth[0] - 1)) }),
			V.label({ "text": "depth %d" % depth[0] }),
			V.button({ "text": "+ depth", "on_pressed": func(): depth[1].call(depth[0] + 1) }),
		]),
		V.fc(DemoDeepTree.node, { "level": depth[0] }),
	])

static func node(props: Dictionary, _c: Array) -> RUIVNode:
	var level: int = props["level"]
	if level <= 0:
		return V.label({ "text": "🌳 leaf", "style": { "font_color": Color(0.5, 0.9, 0.5) } })
	return V.margin({ "style": { "margin": 5 } }, [
		V.panel({ "style": { "bg_color": Color(0.15, 0.15, 0.18), "pad": 4 } }, [
			V.vbox({ "style": { "separation": 2 } }, [
				V.label({ "text": "level %d" % level, "style": { "font_color": Color(0.6, 0.7, 0.9) } }),
				V.fc(DemoDeepTree.node, { "level": level - 1 }),
			]),
		]),
	])
