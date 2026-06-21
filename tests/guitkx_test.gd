extends SceneTree
## Milestone 2.1 compiler test: (1) compile-text checks on a hook-using component, and
## (2) an end-to-end runtime test — compile a hook-free component, write the generated .gd,
## load it, mount it through the reconciler, and verify the real Godot node tree.

const Codegen = preload("res://addons/reactive_ui/guitkx/guitkx_codegen.gd")

func _initialize() -> void:
	_run()

func _run() -> void:
	_test_emit()
	_test_runtime()
	_test_control_flow()
	_test_match()
	_test_hook()
	_test_diagnostics()
	_test_codegen()
	print("[guitkx_test] ALL PASSED")
	quit()

func _test_diagnostics() -> void:
	# rules of hooks: a hook called inside an if-block in setup
	var roh := RUIGuitkx.compile("component Bad(c: bool = true) {\n\tvar a = use_state(0)\n\tif c:\n\t\tvar b = use_state(1)\n\treturn ( <Label /> )\n}\n", "Bad")
	_check_true(str(roh["diagnostics"]).contains("GUITKX0013"), "rules-of-hooks warning (got %s)" % str(roh["diagnostics"]))
	# duplicate literal keys among siblings
	var dk := RUIGuitkx.compile("component Dup() {\n\treturn (\n\t\t<VBox>\n\t\t\t<Label key=\"x\" />\n\t\t\t<Label key=\"x\" />\n\t\t</VBox>\n\t)\n}\n", "Dup")
	_check_true(str(dk["diagnostics"]).contains("GUITKX0104"), "duplicate-key warning (got %s)" % str(dk["diagnostics"]))
	# loop child missing key
	var lk := RUIGuitkx.compile("component LK(items: Array = []) {\n\treturn (\n\t\t<VBox>\n\t\t\t@for (it in items) { <Label text={ it } /> }\n\t\t</VBox>\n\t)\n}\n", "LK")
	_check_true(str(lk["diagnostics"]).contains("GUITKX0106"), "keyless-loop-child warning (got %s)" % str(lk["diagnostics"]))
	# a clean component emits no warnings
	var clean := RUIGuitkx.compile("component Clean() {\n\tvar a = use_state(0)\n\treturn ( <Label text={ str(a[0]) } /> )\n}\n", "Clean")
	_check_true(clean["ok"] and str(clean["diagnostics"]) == "[]", "clean component has no diagnostics (got %s)" % str(clean["diagnostics"]))

func _test_hook() -> void:
	var src := "hook use_counter(start: int = 0) {\n" + \
		"\tvar s = use_state(start)\n" + \
		"\treturn [s[0], func(): s[1].call(s[0] + 1)]\n" + \
		"}\n"
	var r := RUIGuitkx.compile(src, "UseCounter")
	if not r["ok"]:
		_fail("hook: compile failed: " + str(r["diagnostics"]))
	var gd: String = r["gd"]
	print("--- generated (UseCounter) ---\n" + gd + "----------------------------")
	_check(gd, "class_name UseCounter", "hook class name from file")
	_check(gd, "static func use_counter(start: int = 0):", "hook function signature (params verbatim)")
	_check(gd, "Hooks.use_state(start)", "hook body auto-prefixed")
	_check_true(not ("\t\tvar s " in gd), "hook body single-indented")
	var gd2 := gd.replace("class_name UseCounter\n", "")
	var path := "user://__guitkx_hook.gd"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(gd2)
	f.close()
	_check_true(load(path) != null, "hook .gd loads/parses")
	# module files are rejected (one declaration per file)
	var mr := RUIGuitkx.compile("module Widgets {\n\tcomponent A() { return ( <Label /> ) }\n}\n", "Widgets")
	_check_true(not mr["ok"] and str(mr["diagnostics"]).contains("GUITKX0103"), "module rejected with GUITKX0103")
	# empty / no declaration is rejected
	var er := RUIGuitkx.compile("@class_name Foo\n# just a comment\n", "Foo")
	_check_true(not er["ok"] and str(er["diagnostics"]).contains("GUITKX0102"), "no-declaration rejected with GUITKX0102")

func _test_match() -> void:
	var src := "component Status(state: String = \"idle\") {\n" + \
		"\treturn (\n" + \
		"\t\t<VBox>\n" + \
		"\t\t\t@match (state) {\n" + \
		"\t\t\t\t@case (\"loading\") { <Label text=\"Loading...\" /> }\n" + \
		"\t\t\t\t@case (\"done\") { <Label text=\"Done!\" /> }\n" + \
		"\t\t\t\t@default { <Label text=\"Idle\" /> }\n" + \
		"\t\t\t}\n" + \
		"\t\t</VBox>\n" + \
		"\t)\n}\n"
	var r := RUIGuitkx.compile(src, "Status")
	if not r["ok"]:
		_fail("match: compile failed: " + str(r["diagnostics"]))
	var gd: String = r["gd"]
	print("--- generated (Status) ---\n" + gd + "----------------------------")
	_check(gd, "match state:", "@match subject")
	_check(gd, "\"loading\":", "@case pattern")
	_check(gd, "_:", "@default arm")
	# runtime: "done" -> "Done!", unknown -> "Idle"
	var gd2 := gd.replace("class_name Status\n", "")
	var path := "user://__guitkx_status.gd"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(gd2)
	f.close()
	var script = load(path)
	_check_true(script != null, "Status .gd loads")
	var c := Control.new()
	root.add_child(c)
	var app := ReactiveRoot.create(c, V.fc(script.render, { "state": "done" }))
	var lbl := _find_first(c, "Label")
	_check_true(lbl != null and lbl.text == "Done!", "@case done -> 'Done!' (got %s)" % (lbl.text if lbl else "<none>"))
	app.unmount()
	c.free()
	var c2 := Control.new()
	root.add_child(c2)
	var app2 := ReactiveRoot.create(c2, V.fc(script.render, { "state": "wat" }))
	var lbl2 := _find_first(c2, "Label")
	_check_true(lbl2 != null and lbl2.text == "Idle", "@default -> 'Idle' (got %s)" % (lbl2.text if lbl2 else "<none>"))
	app2.unmount()
	c2.free()

func _test_codegen() -> void:
	# the sibling-.gd codegen mechanism (RUIGuitkxCodegen), engine-free so it runs under --script
	var gx := "res://tests/__guitkx_fixture.guitkx"
	var src := "component Fixture(msg: String = \"hi\") {\n\treturn ( <Label text={ msg } /> )\n}\n"
	var f := FileAccess.open(gx, FileAccess.WRITE)
	_check_true(f != null, "can write fixture .guitkx under res://")
	f.store_string(src)
	f.close()
	_check_true(Codegen.find_all("res://tests").has(gx), "find_all locates the fixture")
	_check_true(Codegen.is_stale(gx), "fixture stale before compile (no sibling .gd)")
	var r := Codegen.compile_file(gx)
	_check_true(r["ok"], "compile_file ok: " + str(r))
	var gd := Codegen.gd_path_for(gx)
	_check_true(FileAccess.file_exists(gd), "sibling .gd written next to the .guitkx")
	var gd_src := FileAccess.get_file_as_string(gd)
	_check(gd_src, "class_name Fixture", "sibling .gd named from the file")
	_check(gd_src, "V.label(", "sibling .gd compiled the markup")
	_check_true(not Codegen.is_stale(gx), "not stale right after compile")
	# delete the .gd -> stale again (missing-file branch)
	DirAccess.remove_absolute(gd)
	_check_true(Codegen.is_stale(gx), "stale again after sibling .gd removed")
	DirAccess.remove_absolute(gx)

func _test_control_flow() -> void:
	var src := "component List2(items: Array = [], show_header: bool = true) {\n" + \
		"\treturn (\n" + \
		"\t\t<VBox>\n" + \
		"\t\t\t@if (show_header) { <Label text=\"Header\" /> }\n" + \
		"\t\t\t@for (it in items) { <Label text={ str(it) } /> }\n" + \
		"\t\t</VBox>\n" + \
		"\t)\n}\n"
	var r := RUIGuitkx.compile(src, "List2")
	if not r["ok"]:
		_fail("control_flow: compile failed: " + str(r["diagnostics"]))
	var gd: String = r["gd"]
	print("--- generated (List2) ---\n" + gd + "----------------------------")
	_check(gd, "var __cf0 = null", "@if hoisted to pre-statement")
	_check(gd, "if show_header:", "@if condition")
	_check(gd, "var __cf1: Array = []", "@for accumulator")
	_check(gd, "for it in items:", "@for header")
	_check(gd, "__cf1.append(", "@for body append")
	_check(gd, "[__cf0, __cf1]", "control-flow locals referenced in children")
	# runtime: header shown + 2 items -> 3 Labels; header hidden -> 2 Labels
	var gd2 := gd.replace("class_name List2\n", "")
	var path := "user://__guitkx_list2.gd"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(gd2)
	f.close()
	var script = load(path)
	_check_true(script != null, "List2 .gd loads")
	# fresh container per case (headless --script has no frame loop, so queued frees don't flush)
	var c := Control.new()
	root.add_child(c)
	var app := ReactiveRoot.create(c, V.fc(script.render, { "items": ["a", "b"], "show_header": true }))
	_check_true(_count_class(c, "Label") == 3, "header + 2 items = 3 Labels (got %d)" % _count_class(c, "Label"))
	app.unmount()
	c.free()
	var c2 := Control.new()
	root.add_child(c2)
	var app2 := ReactiveRoot.create(c2, V.fc(script.render, { "items": ["a", "b"], "show_header": false }))
	_check_true(_count_class(c2, "Label") == 2, "no header -> 2 Labels (got %d)" % _count_class(c2, "Label"))
	app2.unmount()
	c2.free()

func _count_class(node: Node, cls: String) -> int:
	var total := 1 if node.get_class() == cls else 0
	for ch in node.get_children():
		total += _count_class(ch, cls)
	return total

func _test_emit() -> void:
	var src := "@class_name Greeting\n\ncomponent Greeting(name: String = \"World\") {\n" + \
		"\tvar s = use_state(0)\n" + \
		"\treturn (\n" + \
		"\t\t<VBox style={ {\"separation\": 8} }>\n" + \
		"\t\t\t<Label text={ \"Hello, %s (%d)\" % [name, s[0]] } />\n" + \
		"\t\t\t<Button text=\"+1\" on_pressed={ inc } />\n" + \
		"\t\t</VBox>\n" + \
		"\t)\n}\n"
	var r := RUIGuitkx.compile(src, "Greeting")
	if not r["ok"]:
		_fail("emit: compile failed: " + str(r["diagnostics"]))
	var gd: String = r["gd"]
	print("--- generated (Greeting) ---\n" + gd + "----------------------------")
	_check(gd, "class_name Greeting", "class_name")
	_check(gd, "props.get(\"name\", \"World\")", "param unpack")
	_check(gd, "Hooks.use_state(0)", "hook auto-prefix")
	_check(gd, "V.vbox(", "VBox -> V.vbox")
	_check(gd, "V.label(", "Label -> V.label")
	_check(gd, "V.button(", "Button -> V.button")
	_check(gd, "\"on_pressed\": inc", "event prop")
	_check(gd, "\"style\":", "style prop")

func _test_runtime() -> void:
	# hook-free so render() can run outside a reconcile; multi-line setup exercises the dedent fix
	# (a double-indented second setup line would be a parse error on load)
	var src := "component Box2(label: String = \"hi\") {\n" + \
		"\tvar upper = label.to_upper()\n" + \
		"\tvar tag = \"[\" + upper + \"]\"\n" + \
		"\treturn (\n" + \
		"\t\t<VBox>\n" + \
		"\t\t\t<Label text={ tag } />\n" + \
		"\t\t\t<Button text=\"go\" />\n" + \
		"\t\t</VBox>\n" + \
		"\t)\n}\n"
	var r := RUIGuitkx.compile(src, "Box2")
	if not r["ok"]:
		_fail("runtime: compile failed: " + str(r["diagnostics"]))
	var gd: String = r["gd"].replace("class_name Box2\n", "")   # avoid global-name registration on load
	_check(gd, "\tvar upper = label.to_upper()", "setup line 1 single-indented")
	_check(gd, "\tvar tag = ", "setup line 2 single-indented (dedent fix)")
	_check_true(not ("\t\tvar tag" in gd), "setup line 2 NOT double-indented")
	var path := "user://__guitkx_box2.gd"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(gd)
	f.close()
	var script = load(path)
	_check_true(script != null, "generated .gd loads as a script")
	var c := Control.new()
	root.add_child(c)
	var app := ReactiveRoot.create(c, V.fc(script.render, { "label": "WORLD" }))
	# walk the produced node tree
	var vbox := _find_first(c, "VBoxContainer")
	_check_true(vbox != null, "rendered a VBoxContainer")
	var lbl := _find_first(c, "Label")
	_check_true(lbl != null and lbl.text == "[WORLD]", "Label text bound from setup-derived value")
	var btn := _find_first(c, "Button")
	_check_true(btn != null and btn.text == "go", "Button text literal")
	app.unmount()
	c.queue_free()

func _find_first(node: Node, cls: String) -> Node:
	if node.get_class() == cls:
		return node
	for ch in node.get_children():
		var r := _find_first(ch, cls)
		if r != null:
			return r
	return null

func _check(haystack: String, needle: String, msg: String) -> void:
	if not (needle in haystack):
		_fail("MISSING [%s]: expected to find `%s`" % [msg, needle])

func _check_true(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)

func _fail(msg: String) -> void:
	print("[guitkx_test] FAIL: ", msg)
	quit(1)
