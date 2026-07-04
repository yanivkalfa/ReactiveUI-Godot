extends SceneTree
## Headless tests for the editor-layer pieces that don't need a live Godot editor: the
## GuitkxCodeEdit substrate configuration (parity plan §2B E-table) and, as later workstreams
## land, dirty-state logic, path retargeting, and diagnostics rendering records.
## Run: godot --headless --path . --script res://tests/guitkx_editor_test.gd

const CodeEditScript := preload("res://addons/reactive_ui_editor/editor/guitkx_code_edit.gd")
const ViewScript := preload("res://addons/reactive_ui_editor/editor/guitkx_editor_view.gd")
const TMP_PATH := "res://tests/__editor_test_tmp.guitkx"
const TMP_SRC := "component EditorTmp() {\n\treturn (\n\t\t<Label text=\"hi\" />\n\t)\n}\n"

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_parses()
	_test_substrate()
	_test_undoable_set_text()
	_test_buffer_state()
	_test_intelligence_wiring()
	_cleanup_tmp()
	print("[guitkx_editor_test] %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

# Never leave a temp .guitkx behind: the reactive_ui watcher in a live editor would sweep/compile it.
func _cleanup_tmp() -> void:
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))

# Editor-layer scripts only load inside a live editor; a parse error there would otherwise ship
# unseen. load() compiles them headlessly.
func _test_parses() -> void:
	_ok(load("res://addons/reactive_ui_editor/plugin.gd") != null, "plugin.gd parses")
	_ok(load("res://addons/reactive_ui_editor/editor/guitkx_editor_view.gd") != null, "editor_view parses")
	_ok(load("res://addons/reactive_ui_editor/editor/guitkx_code_edit.gd") != null, "code_edit parses")
	_ok(load("res://addons/reactive_ui_editor/resources/guitkx_resource.gd") != null, "resource parses")
	_ok(load("res://addons/reactive_ui_editor/resources/guitkx_resource_loader.gd") != null, "loader parses")

func _ok(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("  FAIL: ", msg)

# W1 — every substrate property configure() promises (E1-E10, E16 subset). configure() is pure
# CodeEdit state, deliberately callable without the editor so this suite can pin it.
func _test_substrate() -> void:
	var ce: CodeEdit = CodeEditScript.new()
	ce.configure()

	# E3: indentation matches the formatter (spaces/2), not tabs/4 — the indent fight.
	_ok(ce.indent_use_spaces, "indent uses spaces (formatter parity)")
	_ok(ce.indent_size == 2, "indent size 2 (formatter parity)")
	_ok(ce.indent_automatic, "E5: automatic indent on Enter")
	_ok(ce.draw_tabs, "tab glyphs visible (mixed-indent visibility)")

	# Delimiters feed highlighting + folding.
	_ok(ce.has_comment_delimiter("#"), "# comment delimiter")
	_ok(ce.has_string_delimiter("\""), "double-quote string delimiter")
	_ok(ce.has_string_delimiter("'"), "single-quote string delimiter")

	# E4/E8: auto-close incl. markup's own pair, matching-brace highlight.
	_ok(ce.auto_brace_completion_enabled, "auto-brace completion enabled")
	_ok(ce.auto_brace_completion_pairs.has("<") and str(ce.auto_brace_completion_pairs["<"]) == ">",
		"E4: '<' auto-closes to '>'")
	_ok(ce.auto_brace_completion_highlight_matching, "E8: matching-brace highlight")

	# E1/E9: line numbers + folding gutters.
	_ok(ce.gutters_draw_line_numbers, "E1: line numbers gutter")
	_ok(ce.line_folding, "E9: line folding")
	_ok(ce.gutters_draw_fold_gutter, "E9: fold gutter")

	# E6/E7/E10/E16: view comforts.
	_ok(ce.highlight_current_line, "E6: current-line highlight")
	_ok(ce.highlight_all_occurrences, "E7: occurrence highlight")
	_ok(ce.minimap_draw, "E10: minimap")
	_ok(ce.caret_blink, "caret blinks")
	_ok(ce.scroll_smooth, "smooth scroll")
	_ok(ce.scroll_past_end_of_file, "scroll past end")
	var guides: Array = ce.line_length_guidelines
	_ok(guides.size() == 1 and int(guides[0]) == 100, "ruler at print width 100")

	# Diagnostics gutter: exists, icon-typed, clickable.
	_ok(ce.diag_gutter >= 0, "diagnostics gutter allocated")
	_ok(ce.get_gutter_type(ce.diag_gutter) == TextEdit.GUTTER_TYPE_ICON, "diagnostics gutter is icon type")
	_ok(ce.is_gutter_clickable(ce.diag_gutter), "diagnostics gutter clickable")

	# Completion triggers.
	_ok(ce.code_completion_enabled, "completion enabled")
	var prefixes := ce.code_completion_prefixes
	_ok("<" in prefixes and "@" in prefixes and " " in prefixes, "completion prefixes <, @, space")

	# E2: hover can actually fire — the property gates the symbol_hovered signal entirely.
	if "symbol_tooltip_on_hover" in ce:
		_ok(ce.symbol_tooltip_on_hover, "E2: symbol_tooltip_on_hover set (hover alive)")
		_ok(ce.is_connected("symbol_hovered", ce._on_symbol_hovered), "symbol_hovered connected")

	# configure() must be idempotent — plugin reload / re-open paths may call it again.
	var gutters_before := ce.get_gutter_count()
	ce.configure()
	_ok(ce.get_gutter_count() == gutters_before, "configure() idempotent (no duplicate gutters)")

	ce.free()

# W2/G33 — whole-buffer replacement must be ONE undoable edit; `.text =` wipes undo history.
func _test_undoable_set_text() -> void:
	var ce: CodeEdit = CodeEditScript.new()
	ce.text = "alpha\nbeta"
	ce.clear_undo_history()
	ce.set_caret_line(1)
	ce.set_caret_column(2)
	ce.set_text_undoable("gamma\ndelta\nepsilon")
	_ok(ce.text == "gamma\ndelta\nepsilon", "set_text_undoable replaces the buffer")
	_ok(ce.get_caret_line() == 1 and ce.get_caret_column() == 2, "caret preserved across replace")
	_ok(ce.has_undo(), "replacement is on the undo stack")
	ce.undo()
	_ok(ce.text == "alpha\nbeta", "one undo restores the pre-replace buffer")
	ce.set_text_undoable("x")
	_ok(ce.get_caret_line() == 0 and ce.get_caret_column() == 1, "caret clamped into shrunken buffer")
	ce.free()

# W2 — dirty tracking, retarget (L1), detach (L2), and save_silent's refusal paths (L4 flows).
func _test_buffer_state() -> void:
	var fa := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	fa.store_string(TMP_SRC)
	fa.close()

	var v: Control = ViewScript.new()
	_ok(not v.is_dirty(), "fresh view is clean")
	_ok(v._file_label.text == "(no file)", "fresh view labeled (no file)")

	v.open_path(TMP_PATH)
	_ok(v.current_path() == TMP_PATH, "open_path sets current path")
	_ok(not v.is_dirty(), "freshly opened buffer is clean")
	_ok(v._loaded_mtime != 0, "load records the disk mtime")
	_ok(not v._code_edit.has_undo(), "load clears undo history")

	v._on_text_changed()
	_ok(v.is_dirty(), "user edit marks dirty")
	_ok(v._file_label.text.ends_with("*"), "dirty shown in the file label")

	# L1: rename-follow keeps buffer + dirty state, updates the path.
	v.retarget_path("res://tests/renamed_tmp.guitkx")
	_ok(v.current_path() == "res://tests/renamed_tmp.guitkx", "retarget updates path")
	_ok(v.is_dirty(), "retarget preserves dirty state")
	v.retarget_path(TMP_PATH)

	# G25 conflict: disk changed since load -> silent save must refuse, buffer stays dirty.
	v._loaded_mtime = 1
	_ok(not v.save_silent(), "save_silent refuses on disk conflict")
	_ok(v.is_dirty(), "conflict refusal keeps the buffer dirty")
	v._loaded_mtime = FileAccess.get_modified_time(TMP_PATH)

	# L2: deletion detach -> label + dirty + silent-save refusal (never resurrect during Save All).
	v.mark_detached()
	_ok(v._file_label.text.contains("(deleted on disk)"), "detached shown in the file label")
	_ok(not v.save_silent(), "save_silent refuses to recreate a deleted file")

	# Clean buffer: silent save is a no-op success.
	v._detached = false
	v._dirty = false
	_ok(v.save_silent(), "save_silent no-ops cleanly when nothing is dirty")

	# Same-file reopen with edits must NOT clobber the buffer (the double-click self-open trap).
	v._on_text_changed()
	var before: String = v._code_edit.text
	v._code_edit.text = before + "\n# local edit"
	v.open_path(TMP_PATH)
	_ok(v._code_edit.text.ends_with("# local edit"), "same-file reopen keeps dirty edits")

	v.free()

# W3 — goto-def resolution + navigation, cross-file bindings cache, pathless basename, adaptive gate.
func _test_intelligence_wiring() -> void:
	var fa := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	fa.store_string(TMP_SRC)
	fa.close()
	GuitkxWorkspace.rescan()

	# Workspace exposes the full path list (feeds project_bindings).
	_ok(GuitkxWorkspace.all_paths().has(TMP_PATH), "all_paths includes the temp component")

	# G1: symbol lookup resolves a known component through the widget and emits the navigation
	# request; unknown symbols stay silent.
	var ce: CodeEdit = CodeEditScript.new()
	var got: Array = []
	ce.definition_requested.connect(func(p: String, o: int):
		got.append(p)
		got.append(o))
	ce._on_symbol_lookup("EditorTmp", 0, 0)
	_ok(got.size() == 2 and got[0] == TMP_PATH, "symbol lookup resolves the declaring file")
	_ok(got.size() == 2 and int(got[1]) == TMP_SRC.find("EditorTmp"), "symbol lookup carries the declaration offset")
	got.clear()
	ce._on_symbol_lookup("NoSuchComponentXyz", 0, 0)
	_ok(got.is_empty(), "unknown symbol emits nothing")
	_ok(ce.symbol_lookup_on_click, "ctrl+click lookup enabled")
	ce.free()

	# Same-file navigation places the caret at the declaration.
	var v: Control = ViewScript.new()
	v.open_path(TMP_PATH)
	v._on_definition_requested(TMP_PATH, TMP_SRC.find("EditorTmp"))
	_ok(v._code_edit.get_caret_line() == 0 and v._code_edit.get_caret_column() == TMP_SRC.find("EditorTmp"),
		"same-file goto-def lands on the declaration")

	# Cross-file navigation: pending offset survives the load.
	var second := "res://tests/__editor_test_tmp2.guitkx"
	var fb := FileAccess.open(second, FileAccess.WRITE)
	fb.store_string("component Other() {\n\treturn (\n\t\t<EditorTmp />\n\t)\n}\n")
	fb.close()
	v._on_definition_requested(second, 10)
	_ok(v.current_path() == second, "cross-file goto-def opens the target")
	_ok(v._code_edit.get_caret_line() == 0 and v._code_edit.get_caret_column() == 10,
		"pending jump applied after load")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(second))

	# G13/P2: bindings cache — computed once, invalidated by on_workspace_changed.
	var pb1: Dictionary = v._project_bindings()
	_ok((pb1.get("known", []) as Array).has("EditorTmp"), "project bindings know the temp component")
	_ok(v._bindings_valid, "bindings cached after compute")
	v.on_workspace_changed()
	_ok(v._bindings_valid, "on_workspace_changed recomputes (refresh re-fills the cache)")

	# D4: pathless buffers derive the compile identity from their own declaration.
	v._current_path = ""
	_ok(v._basename("component Foo() {\n}") == "Foo", "pathless basename from declaration")
	_ok(v._basename("# nothing declared") == "Component", "pathless fallback stays 'Component'")
	v._current_path = TMP_PATH
	_ok(v._basename() == "__editor_test_tmp", "pathed basename is the file stem")

	# P1: adaptive debounce math.
	_ok(absf(ViewScript._adaptive_wait(10.0) - 0.3) < 0.001, "fast compiles keep the 0.3s debounce")
	_ok(absf(ViewScript._adaptive_wait(200.0) - 0.8) < 0.001, "189ms-class compiles stretch to ~0.8s")
	_ok(absf(ViewScript._adaptive_wait(3000.0) - 2.0) < 0.001, "debounce capped at 2s")

	v.free()
