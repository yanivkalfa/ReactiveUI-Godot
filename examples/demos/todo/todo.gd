class_name DemoTodo
extends RefCounted

static func render(_p: Dictionary, _c: Array) -> RUIVNode:
	var items := Hooks.use_state([])
	var text := Hooks.use_state("")
	var next_id := Hooks.use_ref(1)
	var add := func():
		if text[0].strip_edges() == "":
			return
		var arr: Array = items[0].duplicate()
		arr.append({ "id": next_id["current"], "text": text[0] })
		next_id["current"] += 1
		items[1].call(arr)
		text[1].call("")
	var remove := func(id):
		var arr: Array = []
		for it in items[0]:
			if it["id"] != id:
				arr.append(it)
		items[1].call(arr)
	var rows: Array = []
	for it in items[0]:
		rows.append(V.fc(DemoTodo.row, { "key": it["id"], "item": it, "on_remove": remove }))
	return DemoUtil.box("Todo — keyed list + events", [
		V.hbox({ "style": { "separation": 8 } }, [
			V.line_edit({ "text": text[0], "placeholder_text": "New todo…", "on_text_changed": func(t): text[1].call(t), "on_text_submitted": func(_t): add.call(), "style": { "expand_h": true } }),
			V.button({ "text": "Add", "on_pressed": func(): add.call() }),
		]),
		V.label({ "text": "%d item(s) — keys preserve row identity on add/remove" % items[0].size(), "style": { "font_color": Color(0.7, 0.7, 0.7) } }),
		V.vbox({ "style": { "separation": 4 } }, rows),
	])

static func row(props: Dictionary, _c: Array) -> RUIVNode:
	var it: Dictionary = props["item"]
	var on_remove: Callable = props["on_remove"]
	return V.hbox({ "style": { "separation": 8 } }, [
		V.label({ "text": "•  " + str(it["text"]), "style": { "expand_h": true } }),
		V.button({ "text": " ✕ ", "on_pressed": func(): on_remove.call(it["id"]) }),
	])
