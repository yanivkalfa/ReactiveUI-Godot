class_name DemoTodoRow
extends RefCounted
## AUTO-GENERATED from demos_todo_todo_row.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var item = props.get("item")
	var onRemove = props.get("onRemove")
	return V.hbox({ "style": {"separation": 8} }, [V.label({ "text": "•  " + str(item["text"]), "style": {"expand_h": true} }), V.button({ "text": " ✕ ", "onClick": func(): onRemove.call(item["id"]) })])
