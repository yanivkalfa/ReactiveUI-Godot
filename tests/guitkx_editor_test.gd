extends SceneTree
## Headless tests for the editor-layer pieces that don't need a live Godot editor: the
## GuitkxCodeEdit substrate configuration (parity plan §2B E-table) and, as later workstreams
## land, dirty-state logic, path retargeting, and diagnostics rendering records.
## Run: godot --headless --path . --script res://tests/guitkx_editor_test.gd

const CodeEditScript := preload("res://addons/reactive_ui_editor/editor/guitkx_code_edit.gd")

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_substrate()
	print("[guitkx_editor_test] %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

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
