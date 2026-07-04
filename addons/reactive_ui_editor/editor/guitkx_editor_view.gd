@tool
class_name GuitkxEditorView
extends Control
## The main-screen panel: a toolbar (Open / Save / Format + current-file label) over a GuitkxCodeEdit.
## Owns the edit -> debounced-compile -> diagnostics pipeline. Depends on the reactive_ui addon's
## global classes RUIGuitkx (compiler) and RUIGuitkxFormatter (formatter).
##
## Save writes ONLY the .guitkx text to disk; the reactive_ui plugin's own filesystem watcher owns
## regenerating the sibling .gd, so the two never fight over the same file.

const MAX_LIVE_COMPILE := 200_000  # chars; above this, compile on Save only (keeps typing responsive)
const DEBOUNCE_SEC := 0.3

var _code_edit: GuitkxCodeEdit
var _file_label: Label
var _debounce: Timer
var _problems: GuitkxProblemsPanel
var _err_icon: Texture2D
var _warn_icon: Texture2D
var _current_path: String = ""

func _init() -> void:
	name = "ReactiveUITK"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	var toolbar := HBoxContainer.new()
	vbox.add_child(toolbar)
	toolbar.add_child(_make_button("Open", _on_open_pressed))
	toolbar.add_child(_make_button("Save", _on_save_pressed))
	toolbar.add_child(_make_button("Format", _on_format_pressed))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	_file_label = Label.new()
	_file_label.text = "(no file)"
	toolbar.add_child(_file_label)

	_code_edit = GuitkxCodeEdit.new()
	_code_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.text_changed.connect(_on_text_changed)
	_code_edit.gutter_diagnostic_clicked.connect(_on_gutter_diagnostic_clicked)
	vbox.add_child(_code_edit)

	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = DEBOUNCE_SEC
	_debounce.timeout.connect(_refresh_diagnostics)
	add_child(_debounce)

func _ready() -> void:
	var theme := EditorInterface.get_editor_theme()
	if theme != null:
		if theme.has_icon("StatusError", "EditorIcons"):
			_err_icon = theme.get_icon("StatusError", "EditorIcons")
		if theme.has_icon("StatusWarning", "EditorIcons"):
			_warn_icon = theme.get_icon("StatusWarning", "EditorIcons")

## Wire the shared bottom Problems panel (owned by the plugin).
func set_problems_panel(panel: GuitkxProblemsPanel) -> void:
	_problems = panel

## Open a .guitkx from disk (Open button + Problems-panel navigation).
func open_path(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[reactive_ui_editor] cannot open %s (%d)" % [path, FileAccess.get_open_error()])
		return
	var text := f.get_as_text()
	f.close()
	_load_text(path, text)

## Open from a double-clicked GuitkxResource (plugin _edit route).
func open_resource(res: GuitkxResource) -> void:
	if res == null:
		return
	# A double-clicked resource can be a CACHE_MODE_REUSE cache hit whose in-memory source predates an
	# external Save (we write .guitkx via FileAccess, never ResourceSaver). Re-read from disk when we
	# can, so a reopen always shows the current file; fall back to res.source only when pathless.
	if not res.resource_path.is_empty() and FileAccess.file_exists(res.resource_path):
		open_path(res.resource_path)
	else:
		_load_text(res.resource_path, res.source)

func goto_line(line: int) -> void:
	if _code_edit == null:
		return
	line = clampi(line, 0, maxi(0, _code_edit.get_line_count() - 1))
	_code_edit.set_caret_line(line)
	_code_edit.set_caret_column(0)
	_code_edit.center_viewport_to_caret()
	_code_edit.grab_focus()

func _load_text(path: String, text: String) -> void:
	_current_path = path
	_file_label.text = path if not path.is_empty() else "(unsaved)"
	_code_edit.text = text
	_refresh_diagnostics()

func _on_text_changed() -> void:
	_debounce.start()

func _refresh_diagnostics() -> void:
	if _code_edit == null:
		return
	if not RUIEditorSettings.is_enabled(RUIEditorSettings.KEY_DIAGNOSTICS):
		GuitkxDiagnosticsRenderer.clear(_code_edit, _code_edit.diag_gutter)
		_code_edit.set_dim_lines({})
		if _problems != null:
			_problems.clear()
		return
	var text := _code_edit.text
	if text.length() > MAX_LIVE_COMPILE:
		# Too large to compile on every keystroke — clear stale decorations so nothing mis-anchors as
		# the text shifts, and rely on the Save-time compile instead.
		GuitkxDiagnosticsRenderer.clear(_code_edit, _code_edit.diag_gutter)
		_code_edit.set_dim_lines({})
		if _problems != null:
			_problems.clear()
		return
	var result: Dictionary = RUIGuitkx.compile(text, _basename())
	var diags: Array = result.get("diagnostics", [])
	var records := GuitkxDiagnosticsRenderer.render(
		_code_edit, _code_edit.diag_gutter, diags, _err_icon, _warn_icon)
	if _problems != null:
		_problems.set_records(records)
	_apply_unreachable_dim(text)

## Fade the lines after each component's markup return (unreachable code). [BUG-V6]
func _apply_unreachable_dim(text: String) -> void:
	var lines := {}
	for r in RUIGuitkx.unreachable_line_ranges(text):
		for ln in range(int(r[0]), int(r[1]) + 1):
			lines[ln] = true
	_code_edit.set_dim_lines(lines)

func _basename() -> String:
	if _current_path.is_empty():
		return "Component"
	return _current_path.get_file().get_basename()

func _on_open_pressed() -> void:
	var dlg := EditorFileDialog.new()
	dlg.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dlg.access = EditorFileDialog.ACCESS_RESOURCES
	dlg.clear_filters()
	dlg.add_filter("*.guitkx", "GUITKX files")
	dlg.file_selected.connect(func(p: String):
		open_path(p)
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	EditorInterface.get_base_control().add_child(dlg)
	dlg.popup_file_dialog()

func _on_save_pressed() -> void:
	if _current_path.is_empty():
		push_warning("[reactive_ui_editor] Open a .guitkx file before saving.")
		return
	var text := _code_edit.text
	if RUIEditorSettings.is_enabled(RUIEditorSettings.KEY_FORMAT_ON_SAVE):
		text = _formatted(text)
	if text != _code_edit.text:
		_set_text_preserving_caret(text)
	var f := FileAccess.open(_current_path, FileAccess.WRITE)
	if f == null:
		push_error("[reactive_ui_editor] cannot write %s (%d)" % [_current_path, FileAccess.get_open_error()])
		return
	f.store_string(text)
	f.close()
	# Let the reactive_ui watcher pick up the change and regenerate the sibling .gd.
	EditorInterface.get_resource_filesystem().scan()
	# Keep the component index fresh so renamed/added components complete without a full rescan.
	GuitkxWorkspace.reindex(_current_path, text)
	_refresh_diagnostics()

func _on_format_pressed() -> void:
	var text := _formatted(_code_edit.text)
	if text != _code_edit.text:
		_set_text_preserving_caret(text)
	_refresh_diagnostics()

func _on_gutter_diagnostic_clicked(_line: int, record: Variant) -> void:
	if record is Dictionary:
		push_warning("[guitkx] %s" % record.get("message", ""))

# RUIGuitkxFormatter.format() returns the source verbatim on any parse error, so this never corrupts.
func _formatted(text: String) -> String:
	var r: Dictionary = RUIGuitkxFormatter.format(text)
	if r.get("ok", false):
		return r.get("text", text)
	return text

func _set_text_preserving_caret(text: String) -> void:
	var l := _code_edit.get_caret_line()
	var c := _code_edit.get_caret_column()
	_code_edit.text = text
	_code_edit.set_caret_line(mini(l, maxi(0, _code_edit.get_line_count() - 1)))
	_code_edit.set_caret_column(c)

func _make_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b
