class_name DemoGallery
extends RefCounted
## The demo gallery shell: a scrollable sidebar + a content area. Each entry points at a
## Demo<Name>.render — one folder per demo under examples/demos/ (component / .hooks / .style
## split, mirroring the ReactiveUIToolkit Samples layout).

static func gallery(_p: Dictionary, _c: Array) -> RUIVNode:
	var sel := Hooks.use_state(0)
	var demos := table()
	var buttons: Array = []
	for i in demos.size():
		var idx := i
		var is_sel: bool = sel[0] == i
		buttons.append(V.button({
			"text": demos[i]["title"],
			"on_pressed": func(): sel[1].call(idx),
			"style": {
				"expand_h": true,
				"bg_color": Color(0.2, 0.4, 0.7) if is_sel else Color(0.18, 0.18, 0.22),
				"corner_radius": 4, "pad": 6,
			},
		}))
	return V.hbox({ "style": { "fill": true } }, [
		V.panel({ "style": { "bg_color": Color(0.1, 0.1, 0.12), "min_width": 210 } }, [
			V.margin({ "style": { "margin": 8 } }, [
				V.vbox({ "style": { "separation": 4, "expand_v": true } }, [
					V.label({ "text": "Reactive UI", "style": { "font_size": 22, "font_color": Color(0.0, 0.9, 0.75) } }),
					V.label({ "text": "Godot demo gallery", "style": { "font_color": Color(0.6, 0.6, 0.6) } }),
					V.h_separator({}),
					V.scroll({ "horizontal_scroll_mode": ScrollContainer.SCROLL_MODE_DISABLED, "style": { "expand_v": true } }, [
						V.vbox({ "style": { "separation": 4 } }, buttons),
					]),
				]),
			]),
		]),
		V.panel({ "style": { "bg_color": Color(0.13, 0.13, 0.16), "expand_h": true, "expand_v": true } }, [
			V.fc(demos[sel[0]]["fn"]),
		]),
	])

static func table() -> Array:
	return [
		{ "title": "Hello", "fn": DemoHello.render },
		{ "title": "Counter", "fn": DemoCounter.render },
		{ "title": "use_reducer", "fn": DemoReducer.render },
		{ "title": "use_memo", "fn": DemoMemo.render },
		{ "title": "Text Field", "fn": DemoTextField.render },
		{ "title": "use_effect", "fn": DemoEffect.render },
		{ "title": "use_ref (focus)", "fn": DemoRef.render },
		{ "title": "use_tween", "fn": DemoTween.render },
		{ "title": "Signals", "fn": DemoSignals.render },
		{ "title": "Context", "fn": DemoContext.render },
		{ "title": "Bailout", "fn": DemoBailout.render },
		{ "title": "Fragment", "fn": DemoFragment.render },
		{ "title": "Todo (keyed)", "fn": DemoTodo.render },
		{ "title": "Keyed shuffle", "fn": DemoKeyed.render },
		{ "title": "Portal", "fn": DemoPortal.render },
		{ "title": "Router", "fn": DemoRouter.render },
		{ "title": "Diagnostics", "fn": DemoDiagnostics.render },
		{ "title": "Time-slicing", "fn": DemoSlicing.render },
		{ "title": "Effect order", "fn": DemoEffectOrder.render },
		{ "title": "Deep tree", "fn": DemoDeepTree.render },
		{ "title": "Styling", "fn": DemoStyling.render },
		{ "title": "Controls", "fn": DemoControls.render },
		{ "title": "Stress test", "fn": DemoStress.render },
		{ "title": "Stress (native)", "fn": DemoStressNative.render },
	]
