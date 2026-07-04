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
	_test_find_bar()
	_test_deps_handshake()
	_test_schema_sync()
	_test_scan_diags()
	_cleanup_tmp()
	print("[guitkx_editor_test] %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

# Never leave a temp .guitkx behind: the reactive_ui watcher in a live editor would sweep/compile it.
func _cleanup_tmp() -> void:
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))

# Editor-layer scripts only load inside a live editor; a parse error there would otherwise ship
# unseen. load() returns a script object even for a broken script, so gate on can_instantiate()
# (false when compilation failed), not on null.
func _test_parses() -> void:
	for p in [
		"res://addons/reactive_ui_editor/plugin.gd",
		"res://addons/reactive_ui_editor/rui_editor_deps.gd",
		"res://addons/reactive_ui_editor/editor/guitkx_editor_view.gd",
		"res://addons/reactive_ui_editor/editor/guitkx_code_edit.gd",
		"res://addons/reactive_ui_editor/editor/guitkx_find_bar.gd",
		"res://addons/reactive_ui_editor/editor/guitkx_diagnostics_renderer.gd",
		"res://addons/reactive_ui_editor/editor/guitkx_problems_panel.gd",
		"res://addons/reactive_ui_editor/resources/guitkx_resource.gd",
		"res://addons/reactive_ui_editor/resources/guitkx_resource_loader.gd",
	]:
		var s: GDScript = load(p)
		_ok(s != null and s.can_instantiate(), "%s compiles" % str(p).get_file())

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

	# An untouched scratch buffer must not be diagnosed (field capture: red X on an empty editor).
	v._refresh_diagnostics()
	_ok(v._code_edit.get_line_gutter_icon(0, v._code_edit.diag_gutter) == null,
		"empty pathless buffer carries no diagnostics")

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

# W4/G24 — find bar: open seeds from selection, counts, steps forward/back with wrap, case toggle.
func _test_find_bar() -> void:
	const FindBar := preload("res://addons/reactive_ui_editor/editor/guitkx_find_bar.gd")
	var ce: CodeEdit = CodeEditScript.new()
	ce.text = "alpha beta\ngamma alpha\nALPHA end"
	var bar: HBoxContainer = FindBar.new()
	bar.attach(ce)

	_ok(not bar.visible, "find bar hidden by default")
	ce.select(0, 0, 0, 5)  # "alpha"
	bar.open_bar()
	_ok(bar.visible, "open shows the bar")
	_ok(bar.query_text() == "alpha", "open seeds the query from the selection")
	_ok(bar.armed_search() == "alpha", "all-match highlight armed")
	_ok(bar._count.text.begins_with("3 match"), "case-insensitive count includes ALPHA")

	# Live-jump landed on match 2 (after the caret); stepping selects match 3, then wraps to match 1.
	bar.find_step(true)
	_ok(ce.get_selected_text().to_lower() == "alpha", "next selects a match")
	_ok(ce.get_caret_line() == 2, "next advances to the last match")
	bar.find_step(true)
	_ok(ce.get_caret_line() == 0, "forward search wraps to the top")

	bar.find_step(false)
	_ok(ce.get_caret_line() == 2, "backward search wraps to the bottom")

	# Case-sensitive narrows to the two lowercase hits.
	bar._case.button_pressed = true
	bar._update_search()
	_ok(bar._count.text.begins_with("2 match"), "case-sensitive count excludes ALPHA")

	bar.close_bar()
	_ok(not bar.visible, "close hides the bar")
	_ok(bar.armed_search() == "", "close clears the match highlight")

	bar.free()
	ce.free()

# W5/F9 — dependency handshake facts + the numeric version comparator.
func _test_deps_handshake() -> void:
	const Deps := preload("res://addons/reactive_ui_editor/rui_editor_deps.gd")
	var check: Dictionary = Deps.satisfied()
	_ok(bool(check.get("ok", false)), "handshake passes in this repo (reactive_ui present)")
	var ver: String = Deps.installed_version()
	_ok(ver != "" and ver.split(".").size() == 3, "installed reactive_ui version parses (got '%s')" % ver)
	_ok(not Deps._version_lt(ver, Deps.MIN_REACTIVE_UI), "installed version satisfies MIN_REACTIVE_UI")
	_ok(Deps._version_lt("0.8.1", "0.8.2"), "semver: 0.8.1 < 0.8.2")
	_ok(Deps._version_lt("0.9.9", "0.10.0"), "semver: numeric, not lexicographic")
	_ok(not Deps._version_lt("0.8.2", "0.8.2"), "semver: equal is not less")
	_ok(not Deps._version_lt("1.0.0", "0.9.9"), "semver: major dominates")

# W6/F8/F12 — the bundled schema is a hand-synced copy with no generator; these tripwires turn
# silent drift (between the two shipping editors, and against the compiler's tag universe) into
# CI failures.
func _test_schema_sync() -> void:
	var bundled := FileAccess.get_file_as_string("res://addons/reactive_ui_editor/data/guitkx-schema.json")
	var grammar := FileAccess.get_file_as_string("res://ide-extensions/grammar/guitkx-schema.json")
	_ok(bundled != "", "bundled schema readable")
	if grammar != "":
		# Byte-identity with the source grammar (the copy the VS Code tooling ships from). The
		# grammar file is absent from store installs — this arm runs in the repo/CI only.
		_ok(bundled == grammar,
			"bundled schema == ide-extensions grammar (resync: copy grammar/guitkx-schema.json into addons/reactive_ui_editor/data/)")
	var parsed: Variant = JSON.parse_string(bundled)
	_ok(parsed is Dictionary and (parsed as Dictionary).has("hostElements"), "bundled schema parses")
	# Every schema host element must exist in the compiler's vocabulary (the source of truth the
	# watcher compiles with) — a tag added there but not here silently vanishes from completion.
	var vocab_tags: Dictionary = RUIGuitkx.vocab().get("host_tags", {})
	_ok(not vocab_tags.is_empty(), "compiler vocabulary host_tags readable")
	var missing: Array = []
	for el in (parsed as Dictionary).get("hostElements", []):
		var tag := str((el as Dictionary).get("tag", ""))
		if tag != "" and not vocab_tags.has(tag):
			missing.append(tag)
	_ok(missing.is_empty(), "schema hostElements ⊆ compiler vocabulary (unknown: %s)" % str(missing))

# Field captures from the M1 acceptance pass: fixture pollution + parse-masked 0105.
func _test_scan_diags() -> void:
	const Scan := preload("res://addons/reactive_ui_editor/lsp/guitkx_scan_diags.gd")

	# .gdignore honored: the contract fixtures (duplicate/broken decls) never reach the index.
	GuitkxWorkspace.rescan()
	var polluted := false
	for p in GuitkxWorkspace.all_paths():
		if str(p).contains("/contract/fixtures/"):
			polluted = true
	_ok(not polluted, ".gdignore folders excluded from the workspace scan")
	var demo_box := GuitkxWorkspace.lookup("DemoBox")
	_ok(str(demo_box.get("path", "")).contains("examples/demos"),
		"DemoBox resolves to the real demo, not a fixture (got %s)" % str(demo_box.get("path", "")))

	# Severity constant stays pinned to the compiler's.
	_ok(Scan.SEVERITY_ERROR == RUIGuitkxDiag.ERROR, "scan severity matches RUIGuitkxDiag.ERROR")

	# The user's exact shape: typo'd open + original close -> parse error masks compiler 0105;
	# the scan still flags the typo with a did-you-mean.
	var src := "component T() {\n\treturn (\n\t\t<DemoaBox>\n\t\t\t<Label text=\"x\" />\n\t\t</DemoBox>\n\t)\n}\n"
	var recs: Array = Scan.unknown_tags(src, ["DemoBox"])
	_ok(recs.size() == 1, "scan flags exactly the typo'd tag (got %d)" % recs.size())
	if recs.size() == 1:
		var r: Dictionary = recs[0]
		_ok(str(r.get("code")) == "GUITKX0105", "scan record carries 0105")
		_ok(str(r.get("message")).contains("did you mean <DemoBox>"), "did-you-mean names the real component")
		_ok(int(r.get("offset")) == src.find("DemoaBox"), "scan anchors at the tag name")

	# No false positives: known tags, hosts, module-locals, comparisons, strings.
	_ok(Scan.unknown_tags("component T() {\n\treturn (\n\t\t<Label text=\"a\" />\n\t)\n}", []).is_empty(),
		"host tags pass")
	_ok(Scan.unknown_tags("component Card() {\n\treturn (\n\t\t<Card2 />\n\t)\n}\ncomponent Card2() {\n\treturn (\n\t\t<Label />\n\t)\n}", []).is_empty(),
		"module-local components pass without any known set")
	_ok(Scan.unknown_tags("component T() {\n\tvar x = a <level\n\treturn (\n\t\t<Label />\n\t)\n}", []).is_empty(),
		"comparisons are not tags")
	_ok(Scan.unknown_tags("component T() {\n\tvar s = \"<FakeTag>\"\n\treturn (\n\t\t<Label />\n\t)\n}", []).is_empty(),
		"tags inside strings are skipped")
	var low: Array = Scan.unknown_tags("component T() {\n\treturn (\n\t\t<vboxx />\n\t)\n}", [])
	_ok(low.size() == 1 and str((low[0] as Dictionary).get("message")).contains("vboxx"),
		"unknown lowercase factory flagged")

	# End-to-end: the view merges scan records into the gutter (parse error present).
	var fa := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	fa.store_string(src)
	fa.close()
	var v: Control = ViewScript.new()
	v.open_path(TMP_PATH)
	var line := 2  # <DemoaBox> line
	var meta: Variant = v._code_edit.get_line_gutter_metadata(line, v._code_edit.diag_gutter)
	_ok(meta is Dictionary and str((meta as Dictionary).get("code", "")) == "GUITKX0105",
		"view surfaces the scan-tier 0105 in the gutter despite the parse error")
	v.free()
