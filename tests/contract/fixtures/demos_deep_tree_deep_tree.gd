class_name DemoDeepTree
extends RefCounted
## AUTO-GENERATED from demos_deep_tree_deep_tree.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var depth = Hooks.useState(8)
	return V.fc(DemoBox.render, { "title": "Deep component tree" }, [V.hbox({ "style": {"separation": 8} }, [V.button({ "text": "− depth", "onClick": func(): depth[1].call(maxi(1, depth[0] - 1)) }), V.label({ "text": "depth %d" % depth[0] }), V.button({ "text": "+ depth", "onClick": func(): depth[1].call(depth[0] + 1) })]), V.fc(DemoDeepTreeNode.render, { "level": depth[0] })])
