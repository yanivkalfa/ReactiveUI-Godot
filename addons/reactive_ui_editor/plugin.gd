@tool
extends EditorPlugin
## reactive_ui_editor — a main-screen Godot editor for .guitkx files with syntax highlighting and live
## compiler diagnostics. Sibling to the reactive_ui runtime addon, which it depends on for the .guitkx
## compiler/formatter (global classes RUIGuitkx / RUIGuitkxFormatter).
##
## Lifecycle: registers the reactive_ui_editor/* Project Settings, mounts the editor into the main
## screen and a "Problems" list into the bottom panel, and (when open_guitkx_in_editor is on) registers
## a ResourceFormatLoader so double-clicking a .guitkx routes here via _handles/_edit. Everything is
## torn down in _exit_tree so a disable/re-enable cycle leaves no orphans.

const PLUGIN_NAME := "ReactiveUITK"
const LoaderScript := preload("res://addons/reactive_ui_editor/resources/guitkx_resource_loader.gd")

var _view: GuitkxEditorView
var _problems: GuitkxProblemsPanel
var _problems_button: Button
var _loader: ResourceFormatLoader
var _self_edit := false

func _enter_tree() -> void:
	RUIEditorSettings.register_all()

	_view = GuitkxEditorView.new()
	EditorInterface.get_editor_main_screen().add_child(_view)
	_make_visible(false)

	_problems = GuitkxProblemsPanel.new()
	_view.set_problems_panel(_problems)
	_problems.diagnostic_activated.connect(_on_problem_activated)
	_problems_button = add_control_to_bottom_panel(_problems, "Problems")

	# open_guitkx_in_editor is structural (it registers a ResourceFormatLoader that changes global
	# double-click routing), so — unlike highlighting/completion/diagnostics/format — it applies on
	# plugin reload, not live: flip it, then disable/re-enable the addon for it to take effect.
	if RUIEditorSettings.is_enabled(RUIEditorSettings.KEY_OPEN_IN_EDITOR):
		_register_loader()

func _exit_tree() -> void:
	_unregister_loader()
	if _problems != null:
		remove_control_from_bottom_panel(_problems)
		_problems.queue_free()
		_problems = null
	_problems_button = null
	if _view != null:
		_view.queue_free()
		_view = null

func _has_main_screen() -> bool:
	return true

func _get_plugin_name() -> String:
	return PLUGIN_NAME

func _get_plugin_icon() -> Texture2D:
	var t := EditorInterface.get_editor_theme()
	if t != null and t.has_icon("Script", "EditorIcons"):
		return t.get_icon("Script", "EditorIcons")
	return null

func _make_visible(visible: bool) -> void:
	if _view != null:
		_view.visible = visible

func _handles(object: Object) -> bool:
	return object is GuitkxResource

func _edit(object: Object) -> void:
	if _self_edit or object == null:
		return
	if object is GuitkxResource:
		EditorInterface.set_main_screen_editor(PLUGIN_NAME)
		_make_visible(true)
		if _view != null:
			_view.open_resource(object)

func _register_loader() -> void:
	if _loader == null:
		_loader = LoaderScript.new()
		ResourceLoader.add_resource_format_loader(_loader)

func _unregister_loader() -> void:
	if _loader != null:
		ResourceLoader.remove_resource_format_loader(_loader)
		_loader = null

func _on_problem_activated(line: int) -> void:
	EditorInterface.set_main_screen_editor(PLUGIN_NAME)
	_make_visible(true)
	if _view != null:
		_view.goto_line(line)
