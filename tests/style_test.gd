extends SceneTree
## Headless tests for the style layer (apply/diff/reset across all channels) and the
## expanded element factories. Run:
##   godot --headless --path <project> --script res://tests/style_test.gd

var _fails := 0
var _passes := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	await _test_style_apply_and_reset()
	await _test_theme_channels()
	await _test_stylebox_builder()
	await _test_state_styles()
	await _test_elements_instantiate()
	print("\n[style_test] %d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)

func _ok(cond: bool, msg: String) -> void:
	if cond: _passes += 1
	else:
		_fails += 1
		printerr("  FAIL: " + msg)
		push_error("FAIL: " + msg)

func _mount(fn: Callable, props := {}) -> Array:
	var c := Control.new()
	root.add_child(c)
	return [c, ReactiveRoot.create(c, V.fc(fn, props))]

func _test_state_styles() -> void:
	# Phase 7.3: per-state StyleBox slots (Godot retains hover/pressed/etc. natively).
	var btn := Button.new()
	RUIStyle.apply(btn, {}, { "hover": { "bg_color": Color.RED }, "pressed": { "bg_color": Color.BLUE } })
	_ok(btn.has_theme_stylebox_override("hover"), "hover state stylebox applied to Button")
	_ok(btn.has_theme_stylebox_override("pressed"), "pressed state stylebox applied to Button")
	RUIStyle.apply(btn, { "hover": { "bg_color": Color.RED }, "pressed": { "bg_color": Color.BLUE } }, { "pressed": { "bg_color": Color.BLUE } })
	_ok(not btn.has_theme_stylebox_override("hover"), "removed hover state stylebox")
	_ok(btn.has_theme_stylebox_override("pressed"), "kept unchanged pressed state stylebox")
	# a Label has no hover slot -> warn-once + no override (never crashes)
	var lbl := Label.new()
	RUIStyle.apply(lbl, {}, { "hover": { "bg_color": Color.RED } })
	_ok(not lbl.has_theme_stylebox_override("hover"), "Label has no hover slot -> no override")
	btn.free()
	lbl.free()

func _test_style_apply_and_reset() -> void:
	var ctrl := { "set": null }
	var comp := func(_p, _ch):
		var s = Hooks.use_state(true)
		ctrl["set"] = s[1]
		var style := { "min_width": 120, "modulate": Color(1, 0, 0) }
		if s[0]:
			style["font_size"] = 22
		return V.label({ "text": "hi", "style": style })

	var m := _mount(comp)
	var lbl: Control = m[0].get_child(0)
	_ok(lbl.custom_minimum_size.x == 120, "min_width applied: %s" % str(lbl.custom_minimum_size.x))
	_ok(lbl.modulate == Color(1, 0, 0), "modulate applied")
	_ok(lbl.has_theme_font_size_override("font_size"), "font_size override applied")

	ctrl["set"].call(false)
	await process_frame
	await process_frame
	_ok(not lbl.has_theme_font_size_override("font_size"), "font_size override REMOVED on style-key removal")
	_ok(lbl.custom_minimum_size.x == 120, "min_width still applied after partial style change")
	m[1].unmount()
	m[0].queue_free()

func _test_theme_channels() -> void:
	var ctrl := { "set": null }
	var comp := func(_p, _ch):
		var s = Hooks.use_state(true)
		ctrl["set"] = s[1]
		var colors := { "font_color": Color(0, 1, 0) }
		if s[0]:
			colors["font_outline_color"] = Color(0, 0, 1)
		return V.label({ "text": "x", "style": { "colors": colors, "constants": { "outline_size": 3 } } })

	var m := _mount(comp)
	var lbl: Control = m[0].get_child(0)
	_ok(lbl.get_theme_color("font_color") == Color(0, 1, 0), "generic color channel applied")
	_ok(lbl.has_theme_color_override("font_outline_color"), "second color override applied")
	_ok(lbl.get_theme_constant("outline_size") == 3, "generic constant channel applied")

	ctrl["set"].call(false)
	await process_frame
	await process_frame
	_ok(not lbl.has_theme_color_override("font_outline_color"), "removed color override pruned (inner diff)")
	_ok(lbl.has_theme_color_override("font_color"), "kept color override retained")
	m[1].unmount()
	m[0].queue_free()

func _test_stylebox_builder() -> void:
	var comp := func(_p, _ch):
		return V.panel({ "style": { "bg_color": Color(0.2, 0.2, 0.2), "corner_radius": 8, "border_width": 2, "border_color": Color(1, 1, 1) } })
	var m := _mount(comp)
	var panel: Control = m[0].get_child(0)
	var sb := panel.get_theme_stylebox("panel")
	_ok(sb is StyleBoxFlat, "StyleBoxFlat built for panel")
	_ok(sb.bg_color == Color(0.2, 0.2, 0.2), "bg_color set")
	_ok(sb.corner_radius_top_left == 8, "corner_radius set")
	_ok(sb.border_width_left == 2, "border_width set")
	m[1].unmount()
	m[0].queue_free()

func _test_elements_instantiate() -> void:
	var comp := func(_p, _ch):
		return V.vbox({}, [
			V.button({ "text": "B" }),
			V.check_button({ "text": "C" }),
			V.option_button({}),
			V.h_slider({}),
			V.progress_bar({ "value": 50 }),
			V.rich_text({ "text": "rt" }),
			V.tabs({}),
			V.tree({}),
			V.item_list({}),
		])
	var m := _mount(comp)
	var vbox: Node = m[0].get_child(0)
	_ok(vbox.get_child_count() == 9, "9 varied controls instantiated, got %d" % vbox.get_child_count())
	_ok(vbox.get_child(0) is Button, "button")
	_ok(vbox.get_child(4) is ProgressBar and vbox.get_child(4).value == 50.0, "progress_bar value prop")
	_ok(vbox.get_child(6) is TabContainer, "tabs")
	_ok(vbox.get_child(7) is Tree, "tree instantiated")
	_ok(vbox.get_child(8) is ItemList, "item_list instantiated")
	m[1].unmount()
	m[0].queue_free()
