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
var _fs_debounce: Timer

func _enter_tree() -> void:
	RUIEditorSettings.register_all()

	_view = GuitkxEditorView.new()
	EditorInterface.get_editor_main_screen().add_child(_view)
	_make_visible(false)

	_problems = GuitkxProblemsPanel.new()
	_view.set_problems_panel(_problems)
	_problems.diagnostic_activated.connect(_on_problem_activated)
	_problems_button = add_control_to_bottom_panel(_problems, "Problems")

	# Follow the open file through dock renames/moves/deletes (parity plan L1/L2) — otherwise the
	# view's path goes stale and Save resurrects the old filename with the user's edits in it.
	var dock := EditorInterface.get_file_system_dock()
	dock.files_moved.connect(_on_file_moved)
	dock.folder_moved.connect(_on_folder_moved)
	dock.file_removed.connect(_on_file_removed)
	dock.folder_removed.connect(_on_folder_removed)

	# Keep the component index + cross-file bindings fresh when the filesystem shape changes
	# (external creates/renames/deletes — G15/P2). Debounced: filesystem_changed fires in bursts.
	_fs_debounce = Timer.new()
	_fs_debounce.one_shot = true
	_fs_debounce.wait_time = 0.5
	_fs_debounce.timeout.connect(_on_fs_settled)
	add_child(_fs_debounce)
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_fs_changed)

	# open_guitkx_in_editor is structural (it registers a ResourceFormatLoader that changes global
	# double-click routing), so — unlike highlighting/completion/diagnostics/format — it applies on
	# plugin reload, not live: flip it, then disable/re-enable the addon for it to take effect.
	if RUIEditorSettings.is_enabled(RUIEditorSettings.KEY_OPEN_IN_EDITOR):
		_register_loader()

func _exit_tree() -> void:
	_unregister_loader()
	var efs := EditorInterface.get_resource_filesystem()
	if efs.filesystem_changed.is_connected(_on_fs_changed):
		efs.filesystem_changed.disconnect(_on_fs_changed)
	var dock := EditorInterface.get_file_system_dock()
	if dock.files_moved.is_connected(_on_file_moved):
		dock.files_moved.disconnect(_on_file_moved)
	if dock.folder_moved.is_connected(_on_folder_moved):
		dock.folder_moved.disconnect(_on_folder_moved)
	if dock.file_removed.is_connected(_on_file_removed):
		dock.file_removed.disconnect(_on_file_removed)
	if dock.folder_removed.is_connected(_on_folder_removed):
		dock.folder_removed.disconnect(_on_folder_removed)
	if _problems != null:
		remove_control_from_bottom_panel(_problems)
		_problems.queue_free()
		_problems = null
	_problems_button = null
	if _view != null:
		_view.queue_free()
		_view = null

## Godot asks every plugin for unsaved state before quitting: a non-empty string joins the editor's
## own quit-confirmation dialog (parity plan L4 — without this, quit silently drops the buffer).
func _get_unsaved_status(for_scene: String) -> String:
	if for_scene.is_empty() and _view != null and _view.is_dirty():
		return "Reactive UI Editor: '%s' has unsaved changes." % _view.current_path()
	return ""

## Godot's own save flows (Save All, save-on-quit confirm) flush our buffer as "external data".
func _save_external_data() -> void:
	if _view != null:
		_view.save_silent()

## Called when the user hits Play: flush the buffer first so the game runs what's on screen (the
## watcher then recompiles the sibling .gd before launch).
func _apply_changes() -> void:
	if _view != null:
		_view.save_silent()

func _on_file_moved(old_file: String, new_file: String) -> void:
	if _view != null and _view.current_path() == old_file:
		_view.retarget_path(new_file)

func _on_folder_moved(old_folder: String, new_folder: String) -> void:
	if _view == null:
		return
	var cur := _view.current_path()
	var prefix := old_folder if old_folder.ends_with("/") else old_folder + "/"
	if cur.begins_with(prefix):
		var dst := new_folder if new_folder.ends_with("/") else new_folder + "/"
		_view.retarget_path(dst + cur.substr(prefix.length()))

func _on_file_removed(file: String) -> void:
	if _view != null and _view.current_path() == file:
		_view.mark_detached()

func _on_folder_removed(folder: String) -> void:
	if _view == null:
		return
	var prefix := folder if folder.ends_with("/") else folder + "/"
	if _view.current_path().begins_with(prefix):
		_view.mark_detached()

func _on_fs_changed() -> void:
	if _fs_debounce != null and _fs_debounce.is_inside_tree():
		_fs_debounce.start()

func _on_fs_settled() -> void:
	GuitkxWorkspace.rescan()
	if _view != null:
		_view.on_workspace_changed()

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
	if object == null:
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
