class_name GuitkxCounter
extends RefCounted
## AUTO-GENERATED from Counter.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var start = props.get("start", 0)
	var s = Hooks.use_state(start)
	var count = s[0]
	var set_count = s[1]
	var __cf0 = null
	if count > 5:
		__cf0 = V.label({ "text": "High five!" })
	return V.vbox({ "style": {"separation": 8} }, [V.label({ "text": "Count: %d" % count }), V.button({ "text": "+1", "on_pressed": func(): set_count.call(count + 1) }), __cf0])
