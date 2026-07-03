class_name DemoKeyed
extends RefCounted
## AUTO-GENERATED from demos_keyed_keyed.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var items = Hooks.useState(["A", "B", "C", "D", "E"])
	var shuffle = func():
		var arr: Array = items[0].duplicate()
		arr.shuffle()
		items[1].call(arr)
	var __cf0: Array = []
	for id in items[0]:
		__cf0.append(V.fc(DemoKeyedTile.render, { "id": id }, [], str(id)))
	return V.fc(DemoBox.render, { "title": "Keyed diff — identity survives reordering" }, [V.button({ "text": "Shuffle", "onClick": shuffle }), V.label({ "text": "Each tile keeps its node (and its random color) across shuffles — that's keys at work.", "style": {"font_color": Color(0.7, 0.7, 0.7)} }), V.hbox({ "style": {"separation": 6} }, [__cf0])])
