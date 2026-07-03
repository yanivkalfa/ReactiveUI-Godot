class_name DemoEffectOrder
extends RefCounted
## AUTO-GENERATED from demos_effect_order_effect_order.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var n = Hooks.useState(3)
	var log = Hooks.useState([])
	var append = func(msg): log[1].call(func(arr): return arr + [msg])
	var __cf0: Array = []
	for i in n[0]:
		__cf0.append(V.fc(DemoEffectOrderRow.render, { "idx": i, "append": append }, [], str(i)))
	return V.fc(DemoBox.render, { "title": "Effect cleanup order — mount / unmount" }, [V.hbox({ "style": {"separation": 8} }, [V.button({ "text": "− row", "onClick": func(): n[1].call(maxi(0, n[0] - 1)) }), V.label({ "text": "%d rows" % n[0] }), V.button({ "text": "+ row", "onClick": func(): n[1].call(n[0] + 1) })]), V.vbox({ "style": {"separation": 2} }, [__cf0]), V.label({ "text": "Effect log (add/remove rows — cleanup runs on unmount):", "style": {"font_color": Color(0.7, 0.7, 0.7)} }), V.label({ "text": "\n".join(log[0]) })])
