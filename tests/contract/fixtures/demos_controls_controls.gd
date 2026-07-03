class_name DemoControls
extends RefCounted
## AUTO-GENERATED from demos_controls_controls.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var v = Hooks.useState(40.0)
	return V.fc(DemoBox.render, { "title": "Controls — a slice of the 60-control set" }, [V.check_button({ "text": "CheckButton" }), V.check_box({ "text": "CheckBox" }), V.hbox({ "style": {"separation": 8} }, [V.h_slider({ "min_value": 0, "max_value": 100, "value": v[0], "onChange": func(x): v[1].call(x), "style": {"min_width": 220} }), V.label({ "text": "%d" % int(v[0]) })]), V.progress_bar({ "min_value": 0, "max_value": 100, "value": v[0], "style": {"min_width": 260} }), V.label({ "text": "ItemList:" }), V.item_list({ "items": ["Apple", "Banana", "Cherry", "Date"], "style": {"min_height": 90} }), V.label({ "text": "Tree (declarative, expansion preserved):" }), V.tree({ "hide_root": true, "items": [
				{ "id": "fruit", "text": "🍎 Fruit", "children": [{ "id": "apple", "text": "Apple" }, { "id": "pear", "text": "Pear" }] },
				{ "id": "veg", "text": "🥕 Veg", "children": [{ "id": "carrot", "text": "Carrot" }] },
			], "style": {"min_height": 150} })])
