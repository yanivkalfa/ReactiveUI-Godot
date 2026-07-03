class_name DemoContext
extends RefCounted
## AUTO-GENERATED from demos_context_context.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var accent = Hooks.useState(Color(0.3, 0.6, 1.0))
	Hooks.provideContext("accent", accent[0])
	return V.fc(DemoBox.render, { "title": "Context — provide / use" }, [V.hbox({ "style": {"separation": 8} }, [V.button({ "text": "Blue", "onClick": func(): accent[1].call(Color(0.3, 0.6, 1.0)) }), V.button({ "text": "Green", "onClick": func(): accent[1].call(Color(0.3, 0.85, 0.45)) }), V.button({ "text": "Red", "onClick": func(): accent[1].call(Color(0.9, 0.4, 0.35)) })]), V.label({ "text": "Consumers below read 'accent' from context (no props passed):", "style": {"font_color": Color(0.7, 0.7, 0.7)} }), V.fc(DemoContextConsumer.render, {}), V.fc(DemoContextConsumer.render, {})])
