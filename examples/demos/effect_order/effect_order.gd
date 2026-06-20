class_name DemoEffectOrder
extends RefCounted

static func render(_p: Dictionary, _c: Array) -> RUIVNode:
	var n := Hooks.use_state(3)
	var log := Hooks.use_state([])
	var append := func(msg): log[1].call(func(arr): return arr + [msg])
	var rows: Array = []
	for i in n[0]:
		rows.append(V.fc(DemoEffectOrder.row, { "key": str(i), "idx": i, "append": append }))
	return DemoUtil.box("Effect cleanup order — mount / unmount", [
		V.hbox({ "style": { "separation": 8 } }, [
			V.button({ "text": "− row", "on_pressed": func(): n[1].call(maxi(0, n[0] - 1)) }),
			V.label({ "text": "%d rows" % n[0] }),
			V.button({ "text": "+ row", "on_pressed": func(): n[1].call(n[0] + 1) }),
		]),
		V.vbox({ "style": { "separation": 2 } }, rows),
		V.label({ "text": "Effect log (add/remove rows — cleanup runs on unmount):", "style": { "font_color": Color(0.7, 0.7, 0.7) } }),
		V.label({ "text": "\n".join(log[0]) }),
	])

static func row(props: Dictionary, _c: Array) -> RUIVNode:
	var idx: int = props["idx"]
	var ap: Callable = props["append"]
	var eff := func():
		ap.call("▶ mount row %d" % idx)
		return func(): ap.call("■ unmount row %d" % idx)
	Hooks.use_effect(eff, [])
	return V.label({ "text": "• row %d" % idx })
