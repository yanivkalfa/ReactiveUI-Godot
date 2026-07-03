class_name DemoStressNative
extends RefCounted
## AUTO-GENERATED from demos_stress_native_stress_native.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var box_count = Hooks.useState(300)
	var duration = Hooks.useState(10.0)
	var count_text = Hooks.useState("300")
	var dur_text = Hooks.useState("10")
	var running = Hooks.useState(false)
	var version = Hooks.useState(0)
	var area_ref = Hooks.useRef(null)

	var loop = DemoStressNativeHooks.use_stress_loop(area_ref, box_count[0], duration[0], running[0], version[0], running[1])

	var status := "Native stress test — Ready (press Start)"
	if loop["finished"]:
		status = "DONE (native) — %d boxes | Avg FPS: %.1f | %.1fs | Frames: %d" % [box_count[0], loop["fps"], loop["elapsed"], loop["frames"]]
	elif running[0]:
		status = "Running (native) — %d boxes | FPS: %.1f | %.1f/%.0fs | Frames: %d" % [box_count[0], loop["fps"], loop["elapsed"], duration[0], loop["frames"]]

	var start := func():
		if running[0]:
			return
		var n := int(count_text[0]) if count_text[0].is_valid_int() else 0
		var d := float(dur_text[0]) if dur_text[0].is_valid_float() else 0.0
		if n > 0 and n <= 10000 and d > 0:
			box_count[1].call(n)
			duration[1].call(d)
			version[1].call(version[0] + 1)
			running[1].call(true)
	return V.fc(DemoBox.render, { "title": "Native stress test — raw ColorRects, no reconciler (engine ceiling)" }, [V.hbox({ "style": {"separation": 8} }, [V.label({ "text": status, "style": {"expand_h": true} }), V.label({ "text": "Boxes:" }), V.line_edit({ "text": count_text[0], "onChange": func(t): count_text[1].call(t), "style": {"min_width": 70} }), V.label({ "text": "Secs:" }), V.line_edit({ "text": dur_text[0], "onChange": func(t): dur_text[1].call(t), "style": {"min_width": 50} }), V.button({ "text": "Running…" if running[0] else ("Restart" if loop["finished"] else "Start"), "onClick": start })]), V.control({ "ref": area_ref, "clip_contents": true, "style": {"expand_h": true, "expand_v": true, "min_height": 320} })])
