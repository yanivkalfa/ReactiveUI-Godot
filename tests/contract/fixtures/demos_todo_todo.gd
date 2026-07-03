class_name DemoTodo
extends RefCounted
## AUTO-GENERATED from demos_todo_todo.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var items = Hooks.useState([])
	var text = Hooks.useState("")
	var next_id = Hooks.useRef(1)
	var add = func():
		if text[0].strip_edges() == "":
			return
		var arr: Array = items[0].duplicate()
		arr.append({ "id": next_id["current"], "text": text[0] })
		next_id["current"] += 1
		items[1].call(arr)
		text[1].call("")
	var remove = func(id):
		var arr: Array = []
		for it in items[0]:
			if it["id"] != id:
				arr.append(it)
		items[1].call(arr)
	var __cf0: Array = []
	for it in items[0]:
		__cf0.append(V.fc(DemoTodoRow.render, { "item": it, "onRemove": remove }, [], it["id"]))
	return V.fc(DemoBox.render, { "title": "Todo — keyed list + events" }, [V.hbox({ "style": {"separation": 8} }, [V.line_edit({ "text": text[0], "placeholder_text": "New todo…", "onChange": func(t): text[1].call(t), "onSubmit": func(_t): add.call(), "style": {"expand_h": true} }), V.button({ "text": "Add", "onClick": func(): add.call() })]), V.label({ "text": "%d item(s) — keys preserve row identity on add/remove" % items[0].size(), "style": {"font_color": Color(0.7, 0.7, 0.7)} }), V.vbox({ "style": {"separation": 4} }, [__cf0])])
