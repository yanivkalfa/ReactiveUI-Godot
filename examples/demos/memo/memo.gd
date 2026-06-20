class_name DemoMemo
extends RefCounted

static func render(_p: Dictionary, _c: Array) -> RUIVNode:
	var n := Hooks.use_state(1)
	var other := Hooks.use_state(0)
	var calc_count := Hooks.use_ref(0)
	var mfn := func():
		calc_count["current"] += 1
		var sum := 0
		for i in (n[0] * 50000):
			sum += i
		return sum
	var result = Hooks.use_memo(mfn, [n[0]])
	return DemoUtil.box("use_memo — cache expensive work", [
		V.label({ "text": "n=%d → expensive result=%d" % [n[0], result] }),
		V.label({ "text": "factory ran %d time(s) — only recomputes when n changes" % calc_count["current"], "style": { "font_color": Color(0.7, 0.7, 0.7) } }),
		V.hbox({ "style": { "separation": 8 } }, [
			V.button({ "text": "n + 1 (recomputes)", "on_pressed": func(): n[1].call(n[0] + 1) }),
			V.button({ "text": "unrelated re-render: %d" % other[0], "on_pressed": func(): other[1].call(other[0] + 1) }),
		]),
	])
