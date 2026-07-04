@tool
class_name GuitkxCodeEdit
extends CodeEdit
## The editing surface for a .guitkx buffer. Self-configures editing UX, assigns the .guitkx
## SyntaxHighlighter, owns a dedicated diagnostics gutter, and offers minimal tag completion. All of
## it reads the reactive_ui_editor/* Project Settings so each feature honours its toggle.

## Emitted when the user clicks the diagnostics gutter icon on a diagnosed line.
signal gutter_diagnostic_clicked(line: int, record: Variant)

## Emitted when Ctrl+click resolves a component tag to its declaration (parity plan G1). The view
## owns navigation (open the file, place the caret); the widget only resolves.
signal definition_requested(path: String, offset: int)

var diag_gutter: int = -1

var _highlighter: GuitkxCodeHighlighter
var _theme_source: Control
var _line_diags: Dictionary = {}  # line (int) -> Array of diagnostic records (from the view)

func _init() -> void:
	# Pure CodeEdit state — safe in every context (editor, headless tests), so the widget is never
	# half-configured (a -1 diag_gutter would make the diagnostics renderer index out of bounds).
	configure()

func _ready() -> void:
	if not Engine.is_editor_hint():
		return

	# Syntax highlighting (own SyntaxHighlighter route). Always assigned; the highlighter honours
	# KEY_HIGHLIGHTING per line, so the toggle applies live without a plugin reload. Editor-only:
	# the highlighter reads EditorSettings theme colours.
	_highlighter = GuitkxCodeHighlighter.new()
	syntax_highlighter = _highlighter

	# Refresh highlight colours when the editor theme changes.
	_theme_source = EditorInterface.get_base_control()
	if _theme_source != null and not _theme_source.theme_changed.is_connected(_on_theme_changed):
		_theme_source.theme_changed.connect(_on_theme_changed)

## Applies the whole editing substrate: indentation, delimiters, brace pairs, gutters, view
## comforts, completion triggers, and hover. Pure CodeEdit state with no editor-singleton
## dependency, so the headless suite instantiates a GuitkxCodeEdit and asserts this directly
## (tests/guitkx_editor_test.gd).
func configure() -> void:
	# Indentation — MUST match the formatter's output (guitkx_formatter.gd defaults: spaces, 2),
	# or live typing and format-on-save fight each other and every save produces mixed indent.
	indent_use_spaces = true
	indent_size = 2
	indent_automatic = true
	draw_tabs = true

	if not has_comment_delimiter("#"):
		add_comment_delimiter("#", "", true)
	if not has_string_delimiter("\""):
		add_string_delimiter("\"", "\"")
	if not has_string_delimiter("'"):
		add_string_delimiter("'", "'")

	# CodeEdit already ships the default { } ( ) [ ] " " ' ' auto-close pairs; re-adding them throws
	# "auto brace completion open key '...' already exists". `<` -> `>` is ours to add for markup.
	auto_brace_completion_enabled = true
	auto_brace_completion_highlight_matching = true
	if not auto_brace_completion_pairs.has("<"):
		add_auto_brace_completion_pair("<", ">")

	# Gutters + view comforts, mirroring the built-in script editor's defaults.
	gutters_draw_line_numbers = true
	line_folding = true
	gutters_draw_fold_gutter = true
	highlight_current_line = true
	highlight_all_occurrences = true
	minimap_draw = true
	caret_blink = true
	scroll_smooth = true
	scroll_past_end_of_file = true
	# One ruler at the formatter's print width.
	line_length_guidelines = [100]

	# Diagnostics gutter (icon type), to the right of the built-in gutters. Guarded so a repeat
	# configure() (plugin reload, re-open) never allocates a duplicate gutter.
	if diag_gutter == -1:
		diag_gutter = get_gutter_count()
		add_gutter(diag_gutter)
		set_gutter_type(diag_gutter, TextEdit.GUTTER_TYPE_ICON)
		set_gutter_width(diag_gutter, 24)
		set_gutter_clickable(diag_gutter, true)
	if not gutter_clicked.is_connected(_on_gutter_clicked):
		gutter_clicked.connect(_on_gutter_clicked)

	# Markup completion. Triggers: `<` (tags), `@` (directives), space (attributes), `.` (builtin
	# members like Color./Vector2.), `"` (attribute values + style-dict keys); the context
	# classifier decides what to offer per caret position. KEY_COMPLETION is honoured live.
	code_completion_enabled = true
	code_completion_prefixes = PackedStringArray(["<", "@", " ", ".", "\""])

	# Markup hover: Godot 4.4+ CodeEdit emits `symbol_hovered` while the mouse rests on a symbol —
	# but ONLY when `symbol_tooltip_on_hover` is set; without it the signal never fires and hover is
	# dead. Both are 4.4+, guarded so older builds no-op.
	if "symbol_tooltip_on_hover" in self:
		symbol_tooltip_on_hover = true
	if has_signal("symbol_hovered") and not is_connected("symbol_hovered", _on_symbol_hovered):
		connect("symbol_hovered", _on_symbol_hovered)

	# Go-to-definition (G1): Ctrl+hover validates component tags as lookup words (underline +
	# pointer), Ctrl+click resolves through the workspace index and asks the view to navigate.
	symbol_lookup_on_click = true
	if not symbol_validate.is_connected(_on_symbol_validate):
		symbol_validate.connect(_on_symbol_validate)
	if not symbol_lookup.is_connected(_on_symbol_lookup):
		symbol_lookup.connect(_on_symbol_lookup)

func _exit_tree() -> void:
	if _theme_source != null and _theme_source.theme_changed.is_connected(_on_theme_changed):
		_theme_source.theme_changed.disconnect(_on_theme_changed)

func _on_theme_changed() -> void:
	if _highlighter != null:
		_highlighter.update_colors()
		queue_redraw()

## Ctrl+/ comment toggle (E12): comments the caret line / every selected line with `# `, or
## uncomments when they all already are — one undoable operation, like the built-in script editor.
func _gui_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.is_command_or_control_pressed() \
			and (k.keycode == KEY_SLASH or k.keycode == KEY_KP_DIVIDE):
		toggle_comment()
		accept_event()

func toggle_comment() -> void:
	var from_line := get_caret_line()
	var to_line := from_line
	if has_selection():
		from_line = get_selection_from_line()
		to_line = get_selection_to_line()
		# A selection ending at column 0 shouldn't drag the next line into the toggle.
		if to_line > from_line and get_selection_to_column() == 0:
			to_line -= 1
	var all_commented := true
	for ln in range(from_line, to_line + 1):
		var t := get_line(ln).strip_edges()
		if t != "" and not t.begins_with("#"):
			all_commented = false
			break
	begin_complex_operation()
	for ln in range(from_line, to_line + 1):
		var line := get_line(ln)
		if line.strip_edges() == "":
			continue
		if all_commented:
			var idx := line.find("#")
			var rest := line.substr(idx + 1)
			if rest.begins_with(" "):
				rest = rest.substr(1)
			set_line(ln, line.substr(0, idx) + rest)
		else:
			var ws := line.length() - line.strip_edges(true, false).length()
			set_line(ln, line.substr(0, ws) + "# " + line.substr(ws))
	end_complex_operation()

## Replaces the whole buffer as ONE undoable edit. Assigning `.text` clears the undo history —
## with format-on-save enabled that meant every Save destroyed Ctrl+Z (parity plan G33). The
## caret is preserved (clamped to the new bounds).
func set_text_undoable(new_text: String) -> void:
	var l := get_caret_line()
	var c := get_caret_column()
	begin_complex_operation()
	select_all()
	delete_selection()
	insert_text_at_caret(new_text)
	end_complex_operation()
	set_caret_line(mini(l, maxi(0, get_line_count() - 1)))
	set_caret_column(mini(c, get_line(get_caret_line()).length()))

## Fade the given lines (a set: line -> true) as unreachable code. [BUG-V6]
func set_dim_lines(lines: Dictionary) -> void:
	if _highlighter != null:
		_highlighter.set_dim_lines(lines)
		queue_redraw()

func _on_gutter_clicked(line: int, gutter: int) -> void:
	if gutter == diag_gutter:
		gutter_diagnostic_clicked.emit(line, get_line_gutter_metadata(line, diag_gutter))

# Context-aware markup completion: tag names (host + user components), per-tag attributes / events,
# and directives. The logic lives in the UI-free GuitkxCompletion provider (unit-tested headlessly);
# this override just maps its items onto CodeEdit options. Attribute-value / embedded contexts yield
# nothing in Phase 1 (the analyzer layer owns those). [plans/GODOT_ANALYZER_INTEGRATION_PLAN.md §7]
func _request_code_completion(_force: bool) -> void:
	if not RUIEditorSettings.is_enabled(RUIEditorSettings.KEY_COMPLETION):
		return
	var text := get_text()
	var off := GuitkxContext.offset_of(text, get_caret_line(), get_caret_column())
	var items := GuitkxCompletion.for_caret(text, off)
	if items.is_empty():
		return
	for it in items:
		add_code_completion_option(_kind_of(str(it["kind"])), str(it["display"]), str(it["insert"]))
	update_code_completion_options(true)

func _kind_of(kind: String) -> int:
	match kind:
		GuitkxCompletion.CLASS:
			return CodeEdit.KIND_CLASS
		GuitkxCompletion.SIGNAL:
			return CodeEdit.KIND_SIGNAL
		GuitkxCompletion.MEMBER:
			return CodeEdit.KIND_MEMBER
		_:
			return CodeEdit.KIND_PLAIN_TEXT

func _on_symbol_validate(symbol: String) -> void:
	set_symbol_lookup_word_as_valid(GuitkxWorkspace.is_component(symbol))

func _on_symbol_lookup(symbol: String, _line: int, _column: int) -> void:
	var hit := GuitkxWorkspace.lookup(symbol)
	if hit.is_empty():
		return
	definition_requested.emit(str(hit.get("path", "")), int(hit.get("offset", 0)))

## Diagnostics for the current buffer, keyed by line — folded into the hover card so the message
## (and its did-you-mean) is readable without clicking the gutter. [field ask]
func set_line_diagnostics(by_line: Dictionary) -> void:
	_line_diags = by_line

# Markup hover: GuitkxHover owns the (tested) logic; the text stored in tooltip_text is raw
# Markdown, rendered rich by _make_custom_tooltip at show time (no stale-tooltip double delay —
# the previous native-tooltip path often needed a second hover pass to display anything).
func _on_symbol_hovered(_symbol: String, line: int, column: int) -> void:
	if not RUIEditorSettings.is_enabled(RUIEditorSettings.KEY_HOVER):
		tooltip_text = ""
		return
	var text := get_text()
	var md := GuitkxHover.for_caret(text, GuitkxContext.offset_of(text, line, column))
	tooltip_text = compose_hover(md, line)

## Prepend the hovered line's diagnostics (message includes any did-you-mean) to the symbol card.
func compose_hover(symbol_md: String, line: int) -> String:
	var parts: Array = []
	for rec in _line_diags.get(line, []):
		if rec is Dictionary:
			parts.append("**%s** `%s` — %s" % [
				str(rec.get("severity", "error")).to_upper(), str(rec.get("code", "")),
				str(rec.get("message", ""))])
	if symbol_md != "":
		parts.append(symbol_md)
	return "\n\n".join(parts)

## Rich tooltip: `for_text` is the raw Markdown from _on_symbol_hovered.
func _make_custom_tooltip(for_text: String) -> Object:
	if for_text.strip_edges().is_empty():
		return null
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rtl.custom_minimum_size = Vector2(480, 0)
	rtl.text = GuitkxHover.md_to_bbcode(for_text)
	return rtl
