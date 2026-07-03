class_name DemoDeepTreeNode
extends RefCounted
## AUTO-GENERATED from demos_deep_tree_deep_tree_node.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var level = props.get("level", 0)
	var __cf0 = null
	if level <= 0:
		__cf0 = V.label({ "text": "🌳 leaf", "style": {"font_color": Color(0.5, 0.9, 0.5)} })
	else:
		__cf0 = V.margin({ "style": {"margin": 5} }, [V.panel({ "style": {"bg_color": Color(0.15, 0.15, 0.18), "pad": 4} }, [V.vbox({ "style": {"separation": 2} }, [V.label({ "text": "level %d" % level, "style": {"font_color": Color(0.6, 0.7, 0.9)} }), V.fc(DemoDeepTreeNode.render, { "level": level - 1 })])])])
	return V.fragment([__cf0])
