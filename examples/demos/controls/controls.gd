class_name DemoControls
extends RefCounted

static func render(_p: Dictionary, _c: Array) -> RUIVNode:
	var v := Hooks.use_state(40.0)
	return DemoUtil.box("Controls — a slice of the 60-control set", [
		V.check_button({ "text": "CheckButton" }),
		V.check_box({ "text": "CheckBox" }),
		V.hbox({ "style": { "separation": 8 } }, [
			V.h_slider({ "min_value": 0, "max_value": 100, "value": v[0], "on_value_changed": func(x): v[1].call(x), "style": { "min_width": 220 } }),
			V.label({ "text": "%d" % int(v[0]) }),
		]),
		V.progress_bar({ "min_value": 0, "max_value": 100, "value": v[0], "style": { "min_width": 260 } }),
		V.label({ "text": "ItemList:" }),
		V.item_list({ "items": ["Apple", "Banana", "Cherry", "Date"], "style": { "min_height": 90 } }),
		V.label({ "text": "Tree (declarative, expansion preserved):" }),
		V.tree({ "hide_root": true, "style": { "min_height": 150 }, "items": [
			{ "id": "fruit", "text": "🍎 Fruit", "children": [{ "id": "apple", "text": "Apple" }, { "id": "pear", "text": "Pear" }] },
			{ "id": "veg", "text": "🥕 Veg", "children": [{ "id": "carrot", "text": "Carrot" }] },
		] }),
	])
