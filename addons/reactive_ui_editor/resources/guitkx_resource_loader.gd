@tool
extends ResourceFormatLoader
## Loads a .guitkx file as a GuitkxResource so double-clicking it in the FileSystem dock routes to
## the reactive_ui_editor main screen (via EditorNode's ResourceLoader.exists() -> _handles/_edit path).
##
## Deliberately has NO class_name: the plugin registers this instance explicitly with
## ResourceLoader.add_resource_format_loader() in _enter_tree and removes it in _exit_tree, so the
## `open_guitkx_in_editor` toggle can genuinely turn the double-click routing on and off (a
## class_name-registered loader would be permanent). Registering a loader makes ResourceLoader.exists()
## true for .guitkx and is exactly what diverts the double-click away from the built-in text editor.

const EXT := "guitkx"

func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray([EXT])

func _recognize_path(path: String, _type: StringName) -> bool:
	return path.get_extension().to_lower() == EXT

func _handles_type(type: StringName) -> bool:
	return ClassDB.is_parent_class(type, &"Resource")

func _get_resource_type(path: String) -> String:
	return "Resource" if path.get_extension().to_lower() == EXT else ""

func _get_resource_script_class(path: String) -> String:
	return "GuitkxResource" if path.get_extension().to_lower() == EXT else ""

func _load(path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:
	var res := GuitkxResource.new()
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null:
		res.from_text(f.get_as_text())
		f.close()
	else:
		return FileAccess.get_open_error()
	return res
