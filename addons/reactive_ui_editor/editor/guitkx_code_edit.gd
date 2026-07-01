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
var _control_tags: PackedStringArray = PackedStringArray()
var _theme_source: Control

func _ready() -> void:
	if not Engine.is_editor_hint():
		return

	# Editing UX — tabs to match the compiler/formatter default (indent_use_spaces=false).
	indent_use_spaces = false
	indent_size = 4
	if not has_comment_delimiter("#"):
		add_comment_delimiter("#", "", true)
	if not has_string_delimiter("\""):
		add_string_delimiter("\"", "\"")
	if not has_string_delimiter("'"):
		add_string_delimiter("'", "'")
	# CodeEdit already ships the default { } ( ) [ ] " " ' ' auto-close pairs; re-adding them throws
	# "auto brace completion open key '...' already exists", so we just enable the feature.
	auto_brace_completion_enabled = true

	# Syntax highlighting (own SyntaxHighlighter route). Always assigned; the highlighter honours
	# KEY_HIGHLIGHTING per line, so the toggle applies live without a plugin reload.
	_highlighter = GuitkxCodeHighlighter.new()
	syntax_highlighter = _highlighter

	# Diagnostics gutter (icon type), to the right of the built-in gutters.
	diag_gutter = get_gutter_count()
	add_gutter(diag_gutter)
	set_gutter_type(diag_gutter, TextEdit.GUTTER_TYPE_ICON)
	set_gutter_width(diag_gutter, 24)
	set_gutter_clickable(diag_gutter, true)
	gutter_clicked.connect(_on_gutter_clicked)

	# Minimal completion for host tags. Enabled at the engine level so _request_code_completion always
	# fires; the KEY_COMPLETION toggle is honoured live inside that override.
	code_completion_enabled = true
	code_completion_prefixes = PackedStringArray(["<"])
	_control_tags = ClassDB.get_inheriters_from_class("Control")

	# Refresh highlight colours when the editor theme changes.
	_theme_source = EditorInterface.get_base_control()
	if _theme_source != null and not _theme_source.theme_changed.is_connected(_on_theme_changed):
		_theme_source.theme_changed.connect(_on_theme_changed)

func _exit_tree() -> void:
	if _theme_source != null and _theme_source.theme_changed.is_connected(_on_theme_changed):
		_theme_source.theme_changed.disconnect(_on_theme_changed)

func _on_theme_changed() -> void:
	if _highlighter != null:
		_highlighter.update_colors()
		queue_redraw()

## Fade the given lines (a set: line -> true) as unreachable code. [BUG-V6]
func set_dim_lines(lines: Dictionary) -> void:
	if _highlighter != null:
		_highlighter.set_dim_lines(lines)
		queue_redraw()

func _on_gutter_clicked(line: int, gutter: int) -> void:
	if gutter == diag_gutter:
		gutter_diagnostic_clicked.emit(line, get_line_gutter_metadata(line, diag_gutter))

# Suggest Control-derived host tags immediately after a `<`.
func _request_code_completion(_force: bool) -> void:
	if not RUIEditorSettings.is_enabled(RUIEditorSettings.KEY_COMPLETION):
		return
	var line := get_line(get_caret_line())
	var before := line.substr(0, get_caret_column())
	var lt := before.rfind("<")
	if lt == -1 or before.rfind(">") > lt:
		return
	var seg := before.substr(lt + 1)
	if seg.contains(" ") or seg.contains("/"):
		return  # past the tag name — attributes are out of scope for Phase 1
	for tag in _control_tags:
		add_code_completion_option(CodeEdit.KIND_CLASS, tag, tag)
	update_code_completion_options(true)
