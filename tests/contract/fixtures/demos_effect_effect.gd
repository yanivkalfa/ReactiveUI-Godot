class_name DemoEffect
extends RefCounted
## AUTO-GENERATED from demos_effect_effect.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var on = Hooks.useState(true)
	var log = Hooks.useRef([])
	var eff = func():
		var was: bool = on[0]
		log["current"].append("▶ setup (dep=%s)" % was)
		return func(): log["current"].append("■ cleanup (dep=%s)" % was)
	Hooks.useEffect(eff, [on[0]])
	return V.fc(DemoBox.render, { "title": "useEffect — lifecycle + cleanup" }, [V.button({ "text": "Toggle dependency (now %s)" % on[0], "onClick": func(): on[1].call(not on[0]) }), V.label({ "text": "Effect log (cleanup runs before the next setup):", "style": {"font_color": Color(0.7, 0.7, 0.7)} }), V.label({ "text": "\n".join(log["current"]) })])
