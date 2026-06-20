class_name RUIStyle
extends RefCounted
## Declarative styling for Godot Controls. Godot has no USS/CSS: styling is Control
## properties + size flags (layout) and Theme overrides / StyleBox (paint). This layer
## maps a `style` Dictionary onto all of that, and is the ONLY place that knows Godot
## styling APIs.
##
## THREE LAYERS OF COVERAGE (least to most explicit):
##
## 1. Friendly shorthands — the common 90% (see `_apply_key` / `_reset`):
##      min_width/min_height/min_size, grow_h/grow_v, expand_h/expand_v, h_align/v_align,
##      modulate/self_modulate, rotation, scale, pivot, visible, clip, mouse_filter,
##      tooltip, z_index, color/font_color, font, font_size, separation, h_separation,
##      v_separation, outline_size, outline_color.
##
## 2. StyleBox builder — bg_color, border_color, border_width, corner_radius, pad combine
##    into ONE StyleBoxFlat applied to the control's primary stylebox slot.
##
## 3. Generic theme channels — reach ANY theme item of ANY control (100% coverage):
##      "colors": { name: Color }, "constants": { name: int }, "fonts": { name: Font },
##      "font_sizes": { name: int }, "icons": { name: Texture2D }, "styleboxes": { name: StyleBox }
##
## Anything else (anchors, offsets, custom_minimum_size, etc.) is a plain Control
## property and is set via the vnode's normal props, not `style`.

const BOX_KEYS := ["bg_color", "border_color", "border_width", "corner_radius", "pad"]
const THEME_CHANNELS := {
	"colors": "color", "constants": "constant", "fonts": "font",
	"font_sizes": "font_size", "icons": "icon", "styleboxes": "stylebox",
}

## Diff `old_style` against `new_style` and apply the delta to `node`.
static func apply(node: Node, old_style: Dictionary, new_style: Dictionary) -> void:
	if not (node is Control):
		return
	if old_style.is_empty() and new_style.is_empty():
		return

	# 1. Combined StyleBox (rebuild if any box key changed/added/removed).
	if _box_differs(old_style, new_style):
		_apply_box(node, new_style)

	# 2. Generic theme channels (inner-diffed per item name).
	for ch in THEME_CHANNELS:
		var oldm: Dictionary = old_style.get(ch, {})
		var newm: Dictionary = new_style.get(ch, {})
		if oldm != newm:
			_apply_theme_map(node, THEME_CHANNELS[ch], oldm, newm)

	# 3. Simple shorthands: reset removed, apply changed.
	for k in old_style.keys():
		if new_style.has(k) or k in BOX_KEYS or THEME_CHANNELS.has(k):
			continue
		_reset(node, k)
	for k in new_style.keys():
		if k in BOX_KEYS or THEME_CHANNELS.has(k):
			continue
		if not old_style.has(k) or old_style[k] != new_style[k]:
			_apply_key(node, k, new_style[k])

# --------------------------------------------------------------------------
# Generic theme channels
# --------------------------------------------------------------------------

static func _apply_theme_map(node: Control, kind: String, old_map: Dictionary, new_map: Dictionary) -> void:
	for name in old_map.keys():
		if not new_map.has(name):
			node.call("remove_theme_%s_override" % kind, name)
	for name in new_map.keys():
		if not old_map.has(name) or old_map[name] != new_map[name]:
			node.call("add_theme_%s_override" % kind, name, new_map[name])

# --------------------------------------------------------------------------
# StyleBox builder
# --------------------------------------------------------------------------

static func _box_differs(old_style: Dictionary, new_style: Dictionary) -> bool:
	for k in BOX_KEYS:
		if old_style.get(k) != new_style.get(k):
			return true
	return false

static func _apply_box(node: Control, style: Dictionary) -> void:
	var slot := _primary_stylebox_name(node)
	if slot == "":
		# bg_color/border/etc. were requested on a control with no primary stylebox slot
		# (e.g. Label, a box container) — it would silently do nothing. Warn once. [audit M5]
		if not node.has_meta("__rui_boxw"):
			for k in BOX_KEYS:
				if style.has(k):
					push_warning("[reactive_ui] bg_color/border/corner_radius/pad need a Panel/Button/LineEdit-like control; %s has no primary stylebox. (warned once)" % node.get_class())
					node.set_meta("__rui_boxw", true)
					break
		return
	var has_box := false
	for k in BOX_KEYS:
		if style.has(k):
			has_box = true
			break
	if not has_box:
		node.remove_theme_stylebox_override(slot)
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = style.get("bg_color", Color(0, 0, 0, 0))
	if style.has("border_width"):
		var w: int = int(style["border_width"])
		sb.border_width_left = w
		sb.border_width_right = w
		sb.border_width_top = w
		sb.border_width_bottom = w
	if style.has("border_color"):
		sb.border_color = style["border_color"]
	if style.has("corner_radius"):
		var r: int = int(style["corner_radius"])
		sb.corner_radius_top_left = r
		sb.corner_radius_top_right = r
		sb.corner_radius_bottom_left = r
		sb.corner_radius_bottom_right = r
	if style.has("pad"):
		var p: float = float(style["pad"])
		sb.content_margin_left = p
		sb.content_margin_right = p
		sb.content_margin_top = p
		sb.content_margin_bottom = p
	node.add_theme_stylebox_override(slot, sb)

static func _primary_stylebox_name(node: Control) -> String:
	if node is Panel or node is PanelContainer:
		return "panel"
	if node is Button:  # Button + CheckBox/CheckButton/OptionButton/MenuButton/ColorPickerButton
		return "normal"
	if node is LineEdit or node is TextEdit:
		return "normal"
	if node is ProgressBar:
		return "background"
	return ""   # no meaningful primary stylebox slot — don't write into a phantom "panel" [audit M5]

# --------------------------------------------------------------------------
# Friendly shorthands
# --------------------------------------------------------------------------

static func _apply_key(node: Control, key: String, value) -> void:
	match key:
		"min_width": node.custom_minimum_size.x = value
		"min_height": node.custom_minimum_size.y = value
		"min_size": node.custom_minimum_size = value
		"fill":
			# Anchor to fill the parent. For a TOP-LEVEL node under a plain Control (e.g. the
			# reactive root mount), since size_flags only apply inside a Container.
			node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT if value else Control.PRESET_TOP_LEFT)
		"grow_h": node.size_flags_horizontal = _size_flag(value)
		"grow_v": node.size_flags_vertical = _size_flag(value)
		"expand_h": node.size_flags_horizontal = Control.SIZE_EXPAND_FILL if value else Control.SIZE_FILL
		"expand_v": node.size_flags_vertical = Control.SIZE_EXPAND_FILL if value else Control.SIZE_FILL
		"h_align": node.size_flags_horizontal = _size_flag(value)
		"v_align": node.size_flags_vertical = _size_flag(value)
		"modulate": node.modulate = value
		"self_modulate": node.self_modulate = value
		"rotation": node.rotation = deg_to_rad(value)
		"scale": node.scale = value
		"pivot": node.pivot_offset = value
		"visible": node.visible = value
		"clip": node.clip_contents = value
		"mouse_filter": node.mouse_filter = _mouse_filter(value)
		"tooltip": node.tooltip_text = str(value)
		"z_index": node.z_index = value
		"color", "font_color": node.add_theme_color_override("font_color", value)
		"font": node.add_theme_font_override("font", value)
		"font_size": node.add_theme_font_size_override("font_size", value)
		"outline_color": node.add_theme_color_override("font_outline_color", value)
		"outline_size": node.add_theme_constant_override("outline_size", value)
		"separation": node.add_theme_constant_override("separation", value)
		"h_separation": node.add_theme_constant_override("h_separation", value)
		"v_separation": node.add_theme_constant_override("v_separation", value)
		"margin":
			for side in ["left", "top", "right", "bottom"]:
				node.add_theme_constant_override("margin_" + side, value)
		_:
			push_warning("[reactive_ui] Unknown style key '%s' (use the colors/constants/… channels for arbitrary theme items)." % key)

static func _reset(node: Control, key: String) -> void:
	match key:
		"min_width": node.custom_minimum_size.x = 0
		"min_height": node.custom_minimum_size.y = 0
		"min_size": node.custom_minimum_size = Vector2.ZERO
		"fill": node.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		"grow_h", "h_align", "expand_h": node.size_flags_horizontal = Control.SIZE_FILL
		"grow_v", "v_align", "expand_v": node.size_flags_vertical = Control.SIZE_FILL
		"modulate": node.modulate = Color.WHITE
		"self_modulate": node.self_modulate = Color.WHITE
		"rotation": node.rotation = 0.0
		"scale": node.scale = Vector2.ONE
		"pivot": node.pivot_offset = Vector2.ZERO
		"visible": node.visible = true
		"clip": node.clip_contents = false
		"mouse_filter": node.mouse_filter = Control.MOUSE_FILTER_STOP
		"tooltip": node.tooltip_text = ""
		"z_index": node.z_index = 0
		"color", "font_color": node.remove_theme_color_override("font_color")
		"font": node.remove_theme_font_override("font")
		"font_size": node.remove_theme_font_size_override("font_size")
		"outline_color": node.remove_theme_color_override("font_outline_color")
		"outline_size": node.remove_theme_constant_override("outline_size")
		"separation": node.remove_theme_constant_override("separation")
		"h_separation": node.remove_theme_constant_override("h_separation")
		"v_separation": node.remove_theme_constant_override("v_separation")
		"margin":
			for side in ["left", "top", "right", "bottom"]:
				node.remove_theme_constant_override("margin_" + side)
		_:
			pass

static func _size_flag(value) -> int:
	if value is int:
		return value
	match value:
		"fill": return Control.SIZE_FILL
		"expand": return Control.SIZE_EXPAND
		"expand_fill", "grow": return Control.SIZE_EXPAND_FILL
		"center", "shrink_center": return Control.SIZE_SHRINK_CENTER
		"begin", "shrink_begin", "start": return Control.SIZE_SHRINK_BEGIN
		"end", "shrink_end": return Control.SIZE_SHRINK_END
		_: return Control.SIZE_FILL

static func _mouse_filter(value) -> int:
	if value is int:
		return value
	match value:
		"stop": return Control.MOUSE_FILTER_STOP
		"pass": return Control.MOUSE_FILTER_PASS
		"ignore": return Control.MOUSE_FILTER_IGNORE
		_: return Control.MOUSE_FILTER_STOP
