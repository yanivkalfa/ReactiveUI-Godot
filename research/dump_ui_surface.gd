extends SceneTree
## Dumps Godot's FULL Control/UI surface (every control + every theme item + properties)
## straight from the engine via ClassDB + ThemeDB. This is the authoritative source for
## "all components and all styles Godot supports" — more accurate than docs.
##
## Run: godot --headless --path <proj> --script res://research/dump_ui_surface.gd
## Writes: research/godot_ui_surface.json (full) + research/GODOT_UI_SURFACE.md (digest)

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://research")
	var theme := ThemeDB.get_default_theme()

	var all: Array = ["Control"]
	for c in ClassDB.get_inheriters_from_class("Control"):
		all.append(c)
	all.sort()

	var full := {}
	var instantiable: Array = []
	for cls in all:
		var can := ClassDB.can_instantiate(cls)
		full[cls] = {
			"parent": ClassDB.get_parent_class(cls),
			"can_instantiate": can,
			"properties": _props_for(cls),
			"theme": {
				"colors": _arr(theme.get_color_list(cls)),
				"constants": _arr(theme.get_constant_list(cls)),
				"fonts": _arr(theme.get_font_list(cls)),
				"font_sizes": _arr(theme.get_font_size_list(cls)),
				"icons": _arr(theme.get_icon_list(cls)),
				"styleboxes": _arr(theme.get_stylebox_list(cls)),
			},
		}
		if can:
			instantiable.append(cls)

	_write_json("res://research/godot_ui_surface.json", full)
	_write_md("res://research/GODOT_UI_SURFACE.md", full, all, instantiable)

	print("[dump] Control-derived classes total=%d  instantiable=%d" % [all.size(), instantiable.size()])
	print("[dump] instantiable: %s" % ", ".join(instantiable))
	quit()

func _props_for(cls: String) -> Array:
	var out: Array = []
	for p in ClassDB.class_get_property_list(cls, true):
		var usage: int = int(p.get("usage", 0))
		if usage & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP):
			continue
		if not (usage & PROPERTY_USAGE_EDITOR):
			continue
		var t: int = int(p.get("type", 0))
		if t == TYPE_NIL:
			continue
		out.append({ "name": p.get("name", ""), "type": type_string(t), "hint": p.get("hint_string", "") })
	return out

func _arr(p) -> Array:
	var out: Array = []
	for x in p:
		out.append(x)
	out.sort()
	return out

func _write_json(path: String, data) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t", false))
	f.close()

func _write_md(path: String, full: Dictionary, all: Array, instantiable: Array) -> void:
	var s := "# Godot UI surface (auto-dumped from ClassDB + ThemeDB)\n\n"
	s += "Control-derived classes: %d total, %d instantiable.\n\n" % [all.size(), instantiable.size()]

	s += "## Instantiable controls (the host elements to support)\n\n"
	for cls in instantiable:
		s += "- `%s` (extends `%s`)\n" % [cls, full[cls]["parent"]]

	s += "\n## Abstract / base classes (not instantiable)\n\n"
	for cls in all:
		if not full[cls]["can_instantiate"]:
			s += "- `%s` (extends `%s`)\n" % [cls, full[cls]["parent"]]

	s += "\n## Control base properties (layout + common vocabulary)\n\n"
	for p in full["Control"]["properties"]:
		s += "- `%s`: %s%s\n" % [p["name"], p["type"], (" [" + p["hint"] + "]") if p["hint"] != "" else ""]

	s += "\n## Theme items per control type (the full 'styles' surface)\n\n"
	for cls in all:
		var th: Dictionary = full[cls]["theme"]
		var total := int(th["colors"].size()) + int(th["constants"].size()) + int(th["fonts"].size()) \
			+ int(th["font_sizes"].size()) + int(th["icons"].size()) + int(th["styleboxes"].size())
		if total == 0:
			continue
		s += "### %s\n" % cls
		if th["colors"].size():     s += "- colors: %s\n" % ", ".join(th["colors"])
		if th["constants"].size():  s += "- constants: %s\n" % ", ".join(th["constants"])
		if th["fonts"].size():      s += "- fonts: %s\n" % ", ".join(th["fonts"])
		if th["font_sizes"].size(): s += "- font_sizes: %s\n" % ", ".join(th["font_sizes"])
		if th["icons"].size():      s += "- icons: %s\n" % ", ".join(th["icons"])
		if th["styleboxes"].size(): s += "- styleboxes: %s\n" % ", ".join(th["styleboxes"])
		s += "\n"

	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(s)
	f.close()
