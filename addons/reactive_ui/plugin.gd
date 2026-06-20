@tool
extends EditorPlugin
## The library is plain GDScript exposing global `class_name`s (V, Hooks,
## ReactiveRoot, ...), so it is usable as soon as the files exist in the project —
## enabling this plugin is optional. It exists so the library shows up under
## Project > Project Settings > Plugins, and as the hook for future editor tooling
## (a .gitkx import plugin, devtools, etc.).

func _enter_tree() -> void:
	pass

func _exit_tree() -> void:
	pass
