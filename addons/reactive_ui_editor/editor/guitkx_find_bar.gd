@tool
class_name GuitkxFindBar
extends HBoxContainer
## In-editor find bar (parity plan G24, M1 scope: find only — replace lands with M2). Drives
## TextEdit's built-in search painting (set_search_text highlights every match) plus explicit
## next/prev navigation over TextEdit.search(), which returns Vector2i(column, line) and does not
## wrap — wrapping is handled here. Ctrl+F/F3/Shift+F3/Esc are wired by the owning view.

var _target: CodeEdit
var _query: LineEdit
var _count: Label
var _case: CheckBox
var _armed := ""  # mirrors set_search_text (TextEdit has no getter) — for state checks + tests

func _init() -> void:
	visible = false

	var lbl := Label.new()
	lbl.text = " Find: "
	add_child(lbl)

	_query = LineEdit.new()
	_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_query.placeholder_text = "Search…"
	_query.text_changed.connect(func(_t: String): _update_search())
	_query.gui_input.connect(_on_query_input)
	add_child(_query)

	_count = Label.new()
	_count.text = ""
	add_child(_count)

	_case = CheckBox.new()
	_case.text = "Aa"
	_case.tooltip_text = "Match case"
	_case.toggled.connect(func(_on: bool): _update_search())
	add_child(_case)

	var prev := Button.new()
	prev.text = "↑"
	prev.tooltip_text = "Previous match (Shift+F3)"
	prev.pressed.connect(func(): find_step(false))
	add_child(prev)

	var next := Button.new()
	next.text = "↓"
	next.tooltip_text = "Next match (F3)"
	next.pressed.connect(func(): find_step(true))
	add_child(next)

	var close := Button.new()
	close.text = "✕"
	close.tooltip_text = "Close (Esc)"
	close.pressed.connect(close_bar)
	add_child(close)

func attach(target: CodeEdit) -> void:
	_target = target

## Open (Ctrl+F): seed from the current selection, focus the query, highlight matches.
func open_bar() -> void:
	if _target == null:
		return
	visible = true
	var sel := _target.get_selected_text()
	if sel != "" and not sel.contains("\n"):
		_query.text = sel
	_query.select_all()
	if _query.is_inside_tree():
		_query.grab_focus()
	_update_search()

func close_bar() -> void:
	visible = false
	if _target != null:
		_armed = ""
		_target.set_search_text("")
		_target.queue_redraw()
		if _target.is_inside_tree():
			_target.grab_focus()

func query_text() -> String:
	return _query.text

func armed_search() -> String:
	return _armed

## Jump to the next/previous match from the caret, selecting it. Wraps around the buffer.
func find_step(forward: bool) -> void:
	if _target == null or _query.text.is_empty():
		return
	var q := _query.text
	var flags := _flags() | (0 if forward else TextEdit.SEARCH_BACKWARDS)
	var line := _target.get_caret_line()
	var col := _target.get_caret_column()
	if forward and _target.has_selection():
		# Step past the current match, or a repeated Next would stand still.
		line = _target.get_selection_to_line()
		col = _target.get_selection_to_column()
	elif not forward and _target.has_selection():
		line = _target.get_selection_from_line()
		col = maxi(0, _target.get_selection_from_column() - 1)
	var hit := _target.search(q, flags, line, col)
	if hit.x < 0:
		# Wrap: restart from the top (forward) or from the very end (backward).
		if forward:
			hit = _target.search(q, flags, 0, 0)
		else:
			var last := _target.get_line_count() - 1
			hit = _target.search(q, flags, last, _target.get_line(last).length())
	if hit.x < 0:
		return
	var match_line := hit.y
	var match_col := hit.x
	_target.select(match_line, match_col, match_line, match_col + q.length())
	_target.set_caret_line(match_line)
	_target.set_caret_column(match_col + q.length())
	_target.center_viewport_to_caret()

func _flags() -> int:
	return TextEdit.SEARCH_MATCH_CASE if _case.button_pressed else 0

## Refresh the built-in all-matches highlight + the match counter, and land on the first match at
## or after the caret (live-jump while typing the query).
func _update_search() -> void:
	if _target == null:
		return
	var q := _query.text
	_armed = q
	_target.set_search_text(q)
	_target.set_search_flags(_flags())
	_target.queue_redraw()
	var n := _count_matches(q)
	_count.text = "" if q.is_empty() else ("%d match%s " % [n, "" if n == 1 else "es"])
	if n > 0:
		# Land on the match at/after the caret without advancing past a current selection.
		var hit := _target.search(q, _flags(), _target.get_caret_line(), _target.get_caret_column())
		if hit.x < 0:
			hit = _target.search(q, _flags(), 0, 0)
		if hit.x >= 0:
			_target.select(hit.y, hit.x, hit.y, hit.x + q.length())
			_target.set_caret_line(hit.y)
			_target.set_caret_column(hit.x + q.length())
			_target.center_viewport_to_caret()

func _count_matches(q: String) -> int:
	if q.is_empty():
		return 0
	var hay := _target.text
	if not _case.button_pressed:
		hay = hay.to_lower()
		q = q.to_lower()
	var n := 0
	var from := 0
	while true:
		var i := hay.find(q, from)
		if i < 0:
			break
		n += 1
		from = i + q.length()
	return n

func _on_query_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	match k.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			find_step(not k.shift_pressed)
			accept_event()
		KEY_ESCAPE:
			close_bar()
			accept_event()
