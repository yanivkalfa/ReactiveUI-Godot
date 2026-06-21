@tool
extends EditorPlugin
## The library is plain GDScript exposing global `class_name`s (V, Hooks, ReactiveRoot, ...), so
## it is usable as soon as the files exist -- enabling this plugin is optional for the RUNTIME.
## The plugin's job is the .guitkx toolchain: it watches the project filesystem and compiles each
## `Foo.guitkx` to a sibling `Foo.gd` (see RUIGuitkxCodegen). On compile it nudges the editor's
## EditorFileSystem so the generated script is picked up and hot-reloaded.

const Codegen = preload("res://addons/reactive_ui/guitkx/guitkx_codegen.gd")

var _efs: EditorFileSystem
var _busy := false

func _enter_tree() -> void:
	_efs = EditorInterface.get_resource_filesystem()
	_compile_all()
	if _efs and not _efs.filesystem_changed.is_connected(_on_fs_changed):
		_efs.filesystem_changed.connect(_on_fs_changed)

func _exit_tree() -> void:
	if _efs and _efs.filesystem_changed.is_connected(_on_fs_changed):
		_efs.filesystem_changed.disconnect(_on_fs_changed)
	_efs = null

func _on_fs_changed() -> void:
	# The mtime staleness guard makes this self-terminating: writing a .gd makes it newer than its
	# .guitkx, so the next filesystem_changed finds nothing stale and stops. _busy guards re-entry.
	if _busy:
		return
	_compile_all()

func _compile_all() -> void:
	if _efs == null:
		return
	_busy = true
	var res: Dictionary = Codegen.compile_all("res://")
	for entry in res["compiled"]:
		_efs.update_file(entry["gd_path"])
		print("[guitkx] compiled -> ", entry["gd_path"])
		for w in entry["warnings"]:
			push_warning("[guitkx] %s: %s" % [entry["path"], w])
	for e in res["errors"]:
		push_error("[guitkx] %s: %s" % [e["path"], str(e.get("diagnostics", e.get("error", "?")))])
	_busy = false
