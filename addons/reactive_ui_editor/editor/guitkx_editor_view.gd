@tool
class_name GuitkxEditorView
extends Control
## The main-screen panel: a toolbar (Open / Save / Format + current-file label) over a GuitkxCodeEdit.
## Owns the edit -> debounced-compile -> diagnostics pipeline, the buffer's dirty/conflict state, and
## every guard that keeps the user's work safe (unsaved-switch confirms, external-change detection,
## deleted/renamed-source tracking). Depends on the reactive_ui addon's global classes RUIGuitkx
## (compiler) and RUIGuitkxFormatter (formatter).
##
## Save writes ONLY the .guitkx text to disk; the reactive_ui plugin's own filesystem watcher owns
## regenerating the sibling .gd, so the two never fight over the same file.

const MAX_LIVE_COMPILE := 150_000  # chars; above this, compile on Save only. Measured: ~2.1ms/KB on
                                   # the MAIN thread, so 150K ≈ 300ms worst-case stall per pause (P1).
const DEBOUNCE_SEC := 0.3

# Preload (not the global class name): a freshly-added class_name is absent from the global class
# cache on cold checkouts/headless runs, which would fail this whole script's parse.
const FindBarScript := preload("res://addons/reactive_ui_editor/editor/guitkx_find_bar.gd")

var _code_edit: GuitkxCodeEdit
var _file_label: Label
var _find_bar: HBoxContainer  # GuitkxFindBar (typed loosely; see FindBarScript note)
var _debounce: Timer
var _problems: GuitkxProblemsPanel
var _err_icon: Texture2D
var _warn_icon: Texture2D
var _current_path: String = ""

# Buffer state (W2, parity plan G32/G25/L1/L2). _loading suppresses the text_changed handler while
# WE set the buffer (loads, format rewrites), so only user edits mark it dirty.
var _dirty := false
var _loading := false
var _detached := false          # the source file was deleted/moved away on disk
var _loaded_mtime := 0          # disk mtime the buffer was loaded from / last saved to

# Cross-file compile context (W3, G13/P2): project_bindings() costs ~35ms over ~100 files, so it is
# cached and recomputed only when the filesystem shape changes — never per debounce tick.
var _bindings_cache: Dictionary = {}
var _bindings_valid := false

var _pending_jump_offset := -1  # goto-def target applied once the destination file finishes loading
var _last_compile_ms := 0.0     # drives the adaptive debounce (P1)

static var _decl_probe: RegEx = null

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
	_code_edit.definition_requested.connect(_on_definition_requested)
	vbox.add_child(_code_edit)

	_find_bar = FindBarScript.new()
	_find_bar.attach(_code_edit)
	vbox.add_child(_find_bar)
	vbox.move_child(_find_bar, 1)  # between the toolbar and the editor

	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = DEBOUNCE_SEC
	_debounce.timeout.connect(_refresh_diagnostics)
	add_child(_debounce)

func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	var theme := EditorInterface.get_editor_theme()
	if theme != null:
		if theme.has_icon("StatusError", "EditorIcons"):
			_err_icon = theme.get_icon("StatusError", "EditorIcons")
		if theme.has_icon("StatusWarning", "EditorIcons"):
			_warn_icon = theme.get_icon("StatusWarning", "EditorIcons")

## Editor shortcuts while this screen is visible: Ctrl+S saves the .guitkx (without this, Godot's
## global Save Scene eats the keystroke and the buffer silently stays unsaved — G31), Ctrl+F opens
## the find bar, F3/Shift+F3 step matches, Esc closes the bar (G24). Godot's own save flows still
## reach us when the screen is NOT visible, via the plugin's _save_external_data.
func _shortcut_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.is_command_or_control_pressed() and not k.shift_pressed and not k.alt_pressed:
		match k.keycode:
			KEY_S:
				_on_save_pressed()
				accept_event()
			KEY_F:
				_find_bar.open_bar()
				accept_event()
		return
	match k.keycode:
		KEY_F3:
			if not _find_bar.query_text().is_empty():
				if not _find_bar.visible:
					_find_bar.visible = true
				_find_bar.find_step(not k.shift_pressed)
				accept_event()
		KEY_ESCAPE:
			if _find_bar.visible:
				_find_bar.close_bar()
				accept_event()

## External-change watch (parity plan G25): when the editor window regains focus and the file changed
## on disk underneath a CLEAN buffer, reload silently (VS Code behavior). A DIRTY buffer is left
## alone — the conflict is resolved at Save time, where the user gets an explicit choice.
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_IN:
		return
	if _current_path.is_empty() or _loading:
		return
	if not FileAccess.file_exists(_current_path):
		if not _detached:
			mark_detached()
		return
	var disk := FileAccess.get_modified_time(_current_path)
	if _loaded_mtime != 0 and disk != _loaded_mtime and not _dirty:
		open_path(_current_path)

## Wire the shared bottom Problems panel (owned by the plugin).
func set_problems_panel(panel: GuitkxProblemsPanel) -> void:
	_problems = panel

## --- Buffer state (read by the plugin's _get_unsaved_status / lifecycle handlers) ---

func is_dirty() -> bool:
	return _dirty

func current_path() -> String:
	return _current_path

## The open file was renamed/moved on disk (FileSystemDock signal via the plugin): follow it, keep
## the buffer + dirty state. Without this, Save would resurrect the OLD filename and the user's
## edits would silently diverge into a zombie file (parity plan L1).
func retarget_path(new_path: String) -> void:
	_current_path = new_path
	_detached = false
	_loaded_mtime = FileAccess.get_modified_time(new_path) if FileAccess.file_exists(new_path) else 0
	_update_file_label()

## The open file was deleted on disk (parity plan L2). The buffer stays (it may be the only copy of
## the user's work) but is marked detached; Save asks before recreating the file.
func mark_detached() -> void:
	_detached = true
	_dirty = true
	_update_file_label()

## --- Opening ---

## Open a .guitkx from disk (Open button, Problems-panel navigation, double-click route). Guards the
## dirty buffer: same-file reopen with edits just focuses (never clobbers); switching away from a
## dirty buffer asks Save / Discard / Cancel first.
func open_path(path: String) -> void:
	if _dirty and path == _current_path and not _loading:
		# Re-opening the file we're already editing (double-click in the dock): keep the edits.
		if _code_edit.is_inside_tree():
			_code_edit.grab_focus()
		return
	if _dirty and not _current_path.is_empty() and path != _current_path:
		_confirm_unsaved_switch(path)
		return
	_open_path_now(path)

func _open_path_now(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_alert("Cannot open %s (error %d)." % [path, FileAccess.get_open_error()])
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
	if _code_edit.is_inside_tree():
		_code_edit.grab_focus()

## Ctrl+click go-to-definition (G1): same-file jumps immediately; cross-file remembers the target
## offset and opens the file (through the dirty-buffer guard), applied when the load completes.
func _on_definition_requested(path: String, offset: int) -> void:
	if path.is_empty():
		return
	if path == _current_path:
		_goto_offset(offset)
		return
	_pending_jump_offset = offset
	open_path(path)

func _goto_offset(offset: int) -> void:
	var lc: Dictionary = RUIGuitkxDiag.line_col(_code_edit.text, offset)
	goto_line(int(lc.get("line", 0)))
	_code_edit.set_caret_column(int(lc.get("col", 0)))

## The filesystem shape changed (files added/removed/renamed anywhere): recompute cross-file
## bindings on next compile and refresh so 0105/did-you-mean track reality (G13/G15).
func on_workspace_changed() -> void:
	_bindings_valid = false
	_refresh_diagnostics()

func _load_text(path: String, text: String) -> void:
	_loading = true
	_current_path = path
	_code_edit.text = text
	_code_edit.clear_undo_history()
	_loading = false
	_dirty = false
	_detached = false
	_loaded_mtime = FileAccess.get_modified_time(path) if (not path.is_empty() and FileAccess.file_exists(path)) else 0
	_update_file_label()
	_refresh_diagnostics()
	if _pending_jump_offset >= 0:
		_goto_offset(_pending_jump_offset)
		_pending_jump_offset = -1

func _on_text_changed() -> void:
	if _loading:
		return
	if not _dirty:
		_dirty = true
		_update_file_label()
	if _debounce.is_inside_tree():
		_debounce.start()

func _update_file_label() -> void:
	if _current_path.is_empty():
		_file_label.text = "(no file)"
		return
	var label := _current_path
	if _detached:
		label += "  (deleted on disk)"
	if _dirty:
		label += "  *"
	_file_label.text = label

## --- Diagnostics pipeline ---

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
	# Cross-file context (G13): known component classes + class->generated-.gd map, exactly what the
	# watcher's sweep passes — so unknown-component 0105 (with did-you-mean) arms in-editor too.
	var pb := _project_bindings()
	var t0 := Time.get_ticks_usec()
	var result: Dictionary = RUIGuitkx.compile(
		text, _basename(text), pb.get("known", []), pb.get("bindings", {}))
	_last_compile_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	# Adaptive gate (P1): compiles run on the main thread, so big files stretch the debounce
	# instead of freezing the editor on every typing pause (measured 189ms @ 90KB).
	_debounce.wait_time = _adaptive_wait(_last_compile_ms)
	var diags: Array = result.get("diagnostics", [])
	var records := GuitkxDiagnosticsRenderer.render(
		_code_edit, _code_edit.diag_gutter, diags, _err_icon, _warn_icon)
	if _problems != null:
		_problems.set_records(records)
	_apply_unreachable_dim(text)

func _project_bindings() -> Dictionary:
	if not _bindings_valid:
		_bindings_cache = RUIGuitkxCodegen.project_bindings(GuitkxWorkspace.all_paths())
		_bindings_valid = true
	return _bindings_cache

## Debounce stretched proportionally to the last compile cost, floored at DEBOUNCE_SEC, capped at
## 2s — a 30ms file keeps the snappy 0.3s; a 200ms file waits ~0.8s between compiles.
static func _adaptive_wait(compile_ms: float) -> float:
	return clampf(compile_ms * 4.0 / 1000.0, DEBOUNCE_SEC, 2.0)

## Fade the lines after each component's markup return (unreachable code). [BUG-V6]
func _apply_unreachable_dim(text: String) -> void:
	var lines := {}
	for r in RUIGuitkx.unreachable_line_ranges(text):
		for ln in range(int(r[0]), int(r[1]) + 1):
			lines[ln] = true
	_code_edit.set_dim_lines(lines)

## The identity the compiler checks the declared name against (GUITKX0103). A pathless scratch
## buffer derives it from its own first declaration — the literal "Component" fallback used to
## self-report a spurious name-mismatch on every unsaved buffer (parity plan D4).
func _basename(text: String = "") -> String:
	if not _current_path.is_empty():
		return _current_path.get_file().get_basename()
	if _decl_probe == null:
		_decl_probe = RegEx.new()
		_decl_probe.compile("(?m)^[ \\t]*(?:component|hook|module)[ \\t]+([A-Za-z_][A-Za-z0-9_]*)")
	var m := _decl_probe.search(text)
	if m != null:
		return m.get_string(1)
	return "Component"

## --- Toolbar actions ---

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
		_alert("Open a .guitkx file before saving.")
		return
	# External-change conflict (G25): the file changed on disk since we loaded it. Explicit choice —
	# never silently overwrite someone else's newer content, never silently drop the user's edits.
	if not _detached and FileAccess.file_exists(_current_path):
		var disk := FileAccess.get_modified_time(_current_path)
		if _loaded_mtime != 0 and disk != _loaded_mtime:
			_confirm_two("The file changed on disk since it was loaded.\n%s" % _current_path,
				"Overwrite Disk", _write_buffer,
				"Reload From Disk (discard my edits)", func():
					_dirty = false
					_open_path_now(_current_path))
			return
	# Deleted-source guard (L2): Save would recreate a file the user deliberately deleted — ask.
	if _detached:
		_confirm_one("The source file was deleted (or moved) on disk.\nSave will recreate:\n%s" % _current_path,
			"Recreate File", _write_buffer)
		return
	_write_buffer()

## The unconditional write path (all guards passed). Formats when enabled, writes, and hands the
## change to the reactive_ui watcher via a targeted update_file — the same cadence an external
## editor's save gets (a full scan() momentarily gated the watcher's own triggers; L8).
func _write_buffer() -> void:
	var text := _code_edit.text
	if RUIEditorSettings.is_enabled(RUIEditorSettings.KEY_FORMAT_ON_SAVE):
		text = _formatted(text)
	if text != _code_edit.text:
		_loading = true
		_code_edit.set_text_undoable(text)
		_loading = false
	var f := FileAccess.open(_current_path, FileAccess.WRITE)
	if f == null:
		# Visible failure (L3): push_error alone leaves the user believing the save happened.
		_alert("Could not write %s (error %d).\nThe buffer still holds your changes." % [
			_current_path, FileAccess.get_open_error()])
		push_error("[reactive_ui_editor] cannot write %s (%d)" % [_current_path, FileAccess.get_open_error()])
		return
	f.store_string(text)
	f.close()
	_dirty = false
	_detached = false
	_loaded_mtime = FileAccess.get_modified_time(_current_path)
	_bindings_valid = false  # our own save can change the project's class/binding shape
	_update_file_label()
	EditorInterface.get_resource_filesystem().update_file(_current_path)
	# Keep the component index fresh so renamed/added components complete without a full rescan.
	GuitkxWorkspace.reindex(_current_path, _code_edit.text)
	_refresh_diagnostics()

## Dialog-free save for Godot's own flows (Save All / quit / Play via the plugin's
## _save_external_data / _apply_changes). Refuses on conflict rather than prompting mid-flow;
## the buffer stays dirty and the user resolves it in the editor.
func save_silent() -> bool:
	if _current_path.is_empty() or not _dirty:
		return true
	if _detached:
		push_error("[reactive_ui_editor] %s was deleted on disk — not recreating it during an editor save. Save it explicitly in the Reactive UI editor." % _current_path)
		return false
	if FileAccess.file_exists(_current_path):
		var disk := FileAccess.get_modified_time(_current_path)
		if _loaded_mtime != 0 and disk != _loaded_mtime:
			push_error("[reactive_ui_editor] %s changed on disk — not overwriting during an editor save. Resolve it in the Reactive UI editor." % _current_path)
			return false
	_write_buffer()
	return not _dirty

func _on_format_pressed() -> void:
	var text := _formatted(_code_edit.text)
	if text != _code_edit.text:
		_code_edit.set_text_undoable(text)
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

## --- Dialog helpers (one-shot, self-freeing) ---

func _alert(text: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Reactive UI Editor"
	dlg.dialog_text = text
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()

func _confirm_one(text: String, ok_label: String, on_ok: Callable) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Reactive UI Editor"
	dlg.dialog_text = text
	dlg.ok_button_text = ok_label
	dlg.confirmed.connect(func():
		on_ok.call()
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()

func _confirm_two(text: String, ok_label: String, on_ok: Callable, alt_label: String, on_alt: Callable) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Reactive UI Editor"
	dlg.dialog_text = text
	dlg.ok_button_text = ok_label
	var alt := dlg.add_button(alt_label, true, "alt")
	alt.pressed.connect(func():
		dlg.hide()
		on_alt.call()
		dlg.queue_free())
	dlg.confirmed.connect(func():
		on_ok.call()
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()

## Switching away from a dirty buffer: Save & Open / Discard & Open / Cancel (G32).
func _confirm_unsaved_switch(next_path: String) -> void:
	_confirm_two("Unsaved changes in:\n%s" % _current_path,
		"Save, Then Open", func():
			_on_save_pressed_then(func(): _open_path_now(next_path)),
		"Discard My Edits", func():
			_dirty = false
			_open_path_now(next_path))

## Save, then run `after` — but only if the save actually cleared the dirty flag (a conflict or
## write failure keeps the buffer, and the pending open is dropped rather than losing edits).
func _on_save_pressed_then(after: Callable) -> void:
	_on_save_pressed()
	if not _dirty:
		after.call()

func _make_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b
