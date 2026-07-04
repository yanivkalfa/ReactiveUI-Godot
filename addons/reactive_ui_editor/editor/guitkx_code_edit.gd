@tool
class_name GuitkxCodeEdit
extends CodeEdit
## The editing surface for a .guitkx buffer. Self-configures editing UX, assigns the .guitkx
## SyntaxHighlighter, owns a dedicated diagnostics gutter, and offers minimal tag completion. All of
## it reads the reactive_ui_editor/* Project Settings so each feature honours its toggle.

## Emitted when the user clicks the diagnostics gutter icon on a diagnosed line.
signal gutter_diagnostic_clicked(line: int, record: Variant)

var diag_gutter: int = -1

var _highlighter: GuitkxCodeHighlighter
var _theme_source: Control

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

	# Markup completion (Phase 1). Trigger on `<` (tags), `@` (directives) and space (attributes); the
	# context classifier decides what to offer per caret position. KEY_COMPLETION is honoured live.
	code_completion_enabled = true
	code_completion_prefixes = PackedStringArray(["<", "@", " "])

	# Markup hover: Godot 4.4+ CodeEdit emits `symbol_hovered` while the mouse rests on a symbol —
	# but ONLY when `symbol_tooltip_on_hover` is set; without it the signal never fires and hover is
	# dead. Both are 4.4+, guarded so older builds no-op.
	if "symbol_tooltip_on_hover" in self:
		symbol_tooltip_on_hover = true
	if has_signal("symbol_hovered") and not is_connected("symbol_hovered", _on_symbol_hovered):
		connect("symbol_hovered", _on_symbol_hovered)

func _exit_tree() -> void:
	if _theme_source != null and _theme_source.theme_changed.is_connected(_on_theme_changed):
		_theme_source.theme_changed.disconnect(_on_theme_changed)

func _on_theme_changed() -> void:
	if _highlighter != null:
		_highlighter.update_colors()
		queue_redraw()

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

# Markup hover -> native tooltip. GuitkxHover owns the (tested) logic; here we just render it plain.
func _on_symbol_hovered(_symbol: String, line: int, column: int) -> void:
	if not RUIEditorSettings.is_enabled(RUIEditorSettings.KEY_HOVER):
		tooltip_text = ""
		return
	var text := get_text()
	tooltip_text = _plain_md(GuitkxHover.for_caret(text, GuitkxContext.offset_of(text, line, column)))

# Strip the tiny Markdown subset our hover uses (`code`, **bold**) for a native plain-text tooltip.
func _plain_md(md: String) -> String:
	return md.replace("`", "").replace("**", "")
