@tool
class_name GuitkxProblemsPanel
extends Control
## The bottom-panel "Problems" list for the current .guitkx buffer. Shows one row per diagnostic and
## emits `diagnostic_activated(line)` when a row is double-clicked so the editor can jump the caret.
## The UI is built in code (no .tscn) to keep the addon a pure set of scripts.

signal diagnostic_activated(line: int)

var _list: ItemList
var _summary: Label

func _init() -> void:
	name = "Problems"
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	_summary = Label.new()
	_summary.text = "No problems."
	vbox.add_child(_summary)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.auto_height = false
	_list.item_activated.connect(_on_item_activated)
	vbox.add_child(_list)

	custom_minimum_size = Vector2(0, 140)

## records: Array of { code, severity, message, line } from GuitkxDiagnosticsRenderer.
func set_records(records: Array) -> void:
	if _list == null:
		return
	_list.clear()
	var errors := 0
	var warnings := 0
	for rec in records:
		var is_err: bool = rec.get("severity", "error") == "error"
		if is_err:
			errors += 1
		else:
			warnings += 1
		var mark := "●" if is_err else "▲"
		var idx := _list.add_item("%s  %s   (line %d)" % [mark, rec.get("message", ""), int(rec.get("line", 0)) + 1])
		_list.set_item_custom_fg_color(idx,
			Color(0.95, 0.45, 0.45) if is_err else Color(0.95, 0.8, 0.35))
		_list.set_item_metadata(idx, int(rec.get("line", 0)))
	if records.is_empty():
		_summary.text = "No problems."
	else:
		_summary.text = "%d error(s), %d warning(s)" % [errors, warnings]

func clear() -> void:
	set_records([])

func _on_item_activated(index: int) -> void:
	var meta := _list.get_item_metadata(index)
	if meta != null:
		diagnostic_activated.emit(int(meta))
