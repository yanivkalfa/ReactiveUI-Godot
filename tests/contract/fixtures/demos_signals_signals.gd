class_name DemoSignals
extends RefCounted
## AUTO-GENERATED from demos_signals_signals.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	return V.fc(DemoBox.render, { "title": "Signals — shared state, no prop drilling" }, [V.label({ "text": "Two independent components read the SAME RUISignal:", "style": {"font_color": Color(0.7, 0.7, 0.7)} }), V.fc(DemoSignalsDisplay.render, {}), V.fc(DemoSignalsDisplay.render, {}), V.button({ "text": "Increment shared signal", "onClick": func(): DemoSignalsStore.shared.update(func(v): return v + 1) })])
