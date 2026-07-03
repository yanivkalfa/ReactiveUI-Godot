class_name DemoMemo
extends RefCounted
## AUTO-GENERATED from demos_memo_memo.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var n = Hooks.useState(1)
	var other = Hooks.useState(0)
	var calc_count = Hooks.useRef(0)
	var mfn = func():
		calc_count["current"] += 1
		var sum := 0
		for i in (n[0] * 50000):
			sum += i
		return sum
	var result = Hooks.useMemo(mfn, [n[0]])
	return V.fc(DemoBox.render, { "title": "useMemo — cache expensive work" }, [V.label({ "text": "n=%d → expensive result=%d" % [n[0], result] }), V.label({ "text": "factory ran %d time(s) — only recomputes when n changes" % calc_count["current"], "style": {"font_color": Color(0.7, 0.7, 0.7)} }), V.hbox({ "style": {"separation": 8} }, [V.button({ "text": "n + 1 (recomputes)", "onClick": func(): n[1].call(n[0] + 1) }), V.button({ "text": "unrelated re-render: %d" % other[0], "onClick": func(): other[1].call(other[0] + 1) })])])
