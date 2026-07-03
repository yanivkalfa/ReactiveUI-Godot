class_name DemoReducer
extends RefCounted
## AUTO-GENERATED from demos_reducer_reducer.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var reducer = func(state, action):
		match action:
			"inc": return state + 1
			"dec": return state - 1
			"reset": return 0
		return state
	var r = Hooks.useReducer(reducer, 0)
	return V.fc(DemoBox.render, { "title": "useReducer — actions instead of raw setters" }, [V.label({ "text": "State: %d" % r[0], "style": {"font_size": 28} }), V.hbox({ "style": {"separation": 8} }, [V.button({ "text": "dec", "onClick": func(): r[1].call("dec") }), V.button({ "text": "inc", "onClick": func(): r[1].call("inc") }), V.button({ "text": "reset", "onClick": func(): r[1].call("reset") })])])
