extends SceneTree
## Dev/CI helper: (re)compile EVERY .guitkx under res://examples to its sibling .gd, reporting
## compiler diagnostics. Text-level errors (markup/structure) fail the run here; GDScript-level
## errors surface when the project is scanned (run demos_test.gd next for the real render check).
##   godot --headless --path <project> --script res://tests/guitkx_build.gd
const Codegen = preload("res://addons/reactive_ui/guitkx/guitkx_codegen.gd")

func _initialize() -> void:
	var errors := 0
	var warnings := 0
	var paths: Array = Codegen.find_all("res://examples")
	paths.sort()
	for p in paths:
		var r: Dictionary = Codegen.compile_file(p)
		if not r["ok"]:
			errors += 1
			printerr("COMPILE FAIL  %s" % p)
			for d in r.get("diagnostics", [str(r.get("error", "?"))]):
				printerr("    %s" % str(d))
			continue
		var warns: Array = []
		for d in r["diagnostics"]:
			warns.append(str(d))
		warnings += warns.size()
		if warns.is_empty():
			print("OK    %s -> %s" % [p, r["gd_path"]])
		else:
			print("WARN  %s -> %s" % [p, r["gd_path"]])
			for w in warns:
				print("    %s" % w)
	print("\n[guitkx_build] %d file(s), %d error(s), %d warning(s)" % [paths.size(), errors, warnings])
	quit(1 if errors > 0 else 0)
