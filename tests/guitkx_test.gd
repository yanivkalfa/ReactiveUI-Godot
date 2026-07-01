extends SceneTree
## Milestone 2.1 compiler test: (1) compile-text checks on a hook-using component, and
## (2) an end-to-end runtime test — compile a hook-free component, write the generated .gd,
## load it, mount it through the reconciler, and verify the real Godot node tree.

const Codegen = preload("res://addons/reactive_ui/guitkx/guitkx_codegen.gd")

var _failed := false

func _initialize() -> void:
	_run()

func _run() -> void:
	_test_emit()
	_test_runtime()
	_test_control_flow()
	_test_match()
	_test_hook()
	_test_hook_alias()
	_test_hook_member_not_mangled()
	_test_ctrl_flow_in_lambda()
	_test_module()
	_test_module_dup_across_kinds()
	_test_return_null_guard()
	_test_jsx_value()
	_test_diagnostics()
	_test_deep_flatten()
	_test_scanner_fixtures()
	_test_markup_corpus()
	_test_formatter()
	_test_formatter_corpus()
	_test_formatter_options()
	_test_codegen()
	_test_spread()
	if _failed:
		print("[guitkx_test] FAILED")
		quit(1)
	else:
		print("[guitkx_test] ALL PASSED")
		quit()

func _test_module() -> void:
	# module Name { ... } -> one class, named static funcs, intra-module <Card/> -> V.fc(Card, ...)
	var src := "module Widgets {\n" + \
		"\tcomponent Card(title: String = \"\") {\n" + \
		"\t\treturn ( <Panel><Label text={ title } /></Panel> )\n" + \
		"\t}\n" + \
		"\tcomponent Row() {\n" + \
		"\t\treturn ( <HBox><Card title=\"A\" /><Card title=\"B\" /></HBox> )\n" + \
		"\t}\n" + \
		"}\n"
	var r := RUIGuitkx.compile(src, "Widgets")
	if not r["ok"]:
		_fail("module: compile failed: " + str(r["diagnostics"]))
	var gd: String = r["gd"]
	print("--- generated (Widgets module) ---\n" + gd + "----------------------------")
	_check(gd, "class_name Widgets", "module class name")
	_check(gd, "static func Card(", "Card static func")
	_check(gd, "static func Row(", "Row static func")
	_check(gd, "V.fc(Card,", "intra-module <Card/> -> bare sibling static func")
	_check_true(not ("Card.render" in gd), "module-local component does NOT use Foo.render")
	# runtime: Row renders 2 Cards -> 2 Labels
	var gd2 := gd.replace("class_name Widgets\n", "")
	var path := "user://__widgets.gd"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(gd2)
	f.close()
	var script = load(path)
	_check_true(script != null, "module .gd loads")
	var c := Control.new()
	root.add_child(c)
	var app := ReactiveRoot.create(c, V.fc(Callable(script, "Row"), {}))
	_check_true(_count_class(c, "Label") == 2, "Row -> 2 Cards -> 2 Labels got %d" % _count_class(c, "Label"))
	app.unmount()
	c.free()

func _test_jsx_value() -> void:
	# markup nested inside expressions: ternary, short-circuit (and), and a .map() lambda return
	var src := "component JsxVal(items: Array = [\"a\", \"b\"], cond: bool = true) {\n" + \
		"\treturn (\n" + \
		"\t\t<VBox>\n" + \
		"\t\t\t{ <Label text=\"x\" /> if cond else <Label text=\"y\" /> }\n" + \
		"\t\t\t{ cond and <Button text=\"go\" /> }\n" + \
		"\t\t\t{ items.map(func(it): return <Label text={ it } />) }\n" + \
		"\t\t</VBox>\n" + \
		"\t)\n}\n"
	var r := RUIGuitkx.compile(src, "JsxVal")
	if not r["ok"]:
		_fail("jsx_value: compile failed: " + str(r["diagnostics"]))
	var gd: String = r["gd"]
	print("--- generated (JsxVal) ---\n" + gd + "----------------------------")
	_check(gd, "if cond else", "ternary preserved")
	_check_true(not ("<Label" in gd), "no raw <Label markup left in expression")
	_check(gd, "if (cond) else null", "short-circuit `and` desugared to ternary")
	_check(gd, "V.label({ \"text\": it })", "map-lambda markup lowered")
	# runtime: cond=true -> Label x + (map a,b) = 3 Labels, + 1 Button (short-circuit)
	var gd2 := gd.replace("class_name JsxVal\n", "")
	var path := "user://__jsxval.gd"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(gd2)
	f.close()
	var script = load(path)
	_check_true(script != null, "JsxVal .gd loads")
	var c := Control.new()
	root.add_child(c)
	var app := ReactiveRoot.create(c, V.fc(script.render, { "items": ["a", "b"], "cond": true }))
	_check_true(_count_class(c, "Label") == 3, "3 Labels (ternary x + map a,b) got %d" % _count_class(c, "Label"))
	_check_true(_count_class(c, "Button") == 1, "1 Button (short-circuit) got %d" % _count_class(c, "Button"))
	app.unmount()
	c.free()

func _test_hook_alias() -> void:
	# token-boundary hook aliasing: real calls prefixed; identifiers/strings/qualified left alone
	var src := "component HA() {\n" + \
		"\tvar s = useState(0)\n" + \
		"\tvar my_use_state_val = 1\n" + \
		"\tvar note = \"call useState() at the top\"\n" + \
		"\tvar r = Hooks.useRef(null)\n" + \
		"\treturn ( <Label text={ str(s[0]) + str(my_use_state_val) + str(r) } /> )\n}\n"
	var res := RUIGuitkx.compile(src, "HA")
	if not res["ok"]:
		_fail("hook_alias: compile failed: " + str(res["diagnostics"]))
	var gd: String = res["gd"]
	_check(gd, "Hooks.useState(0)", "bare hook call prefixed")
	_check_true(not ("my_Hooks.useState" in gd), "identifier substring NOT corrupted")
	_check(gd, "\"call useState() at the top\"", "string literal NOT corrupted")
	_check_true(not ("Hooks.Hooks." in gd), "already-qualified not double-prefixed")
	_check(gd, "Hooks.useRef(null)", "already-qualified preserved")

func _test_hook_member_not_mangled() -> void:
	# [audit #6] A member call on a non-Hooks receiver named like a hook must NOT be auto-prefixed.
	var src := "component MM() {\n" + \
		"\tvar obj = make_thing()\n" + \
		"\tvar v = obj.useState(0)\n" + \
		"\treturn ( <Label text={ str(v) } /> )\n}\n"
	var res := RUIGuitkx.compile(src, "MM")
	if not res["ok"]:
		_fail("hook_member: compile failed: " + str(res["diagnostics"]))
	var gd: String = res["gd"]
	_check(gd, "obj.useState(0)", "member .useState NOT prefixed")
	_check_true(not ("obj.Hooks." in gd), "no spurious Hooks. after member access")

func _test_ctrl_flow_in_lambda() -> void:
	# [audit #17] control-flow inside a JSX-value lambda must lower INLINE (ternary / .map), not hoist
	# render-level `if/for` statements that can't see the lambda's locals (`it`).
	var src := "component CFL(items: Array = []) {\n" + \
		"\treturn (\n\t\t<VBox>\n" + \
		"\t\t\t{ items.map(func(it): return <>@if (it.ok) { <Label text={ it.name } /> }</>) }\n" + \
		"\t\t</VBox>\n\t)\n}\n"
	var res := RUIGuitkx.compile(src, "CFL")
	if not res["ok"]:
		_fail("ctrl_in_lambda: compile failed: " + str(res["diagnostics"]))
	var gd: String = res["gd"]
	_check_true("if (it.ok)" in gd, "@if lowered to an inline ternary (got: %s)" % gd)
	_check_true(not ("__cf" in gd), "no hoisted __cf statement (would be out of lambda scope)")
	# The generated .gd must be VALID GDScript — the bug produced an undeclared `it` at render scope.
	var script := GDScript.new()
	script.source_code = gd.replace("class_name CFL\n", "")
	_check_true(script.reload() == OK, "generated .gd with inline control-flow compiles cleanly")

	# @for inside a JSX-value lowers to .map (also lambda-safe).
	var src_for := "component CFF(items: Array = []) {\n" + \
		"\treturn ( <VBox>{ true and <>@for (x in items) { <Label text={ x } /> }</> }</VBox> )\n}\n"
	var res_for := RUIGuitkx.compile(src_for, "CFF")
	_check_true(res_for["ok"] and "items).map(func(x)" in str(res_for["gd"]), "@for in expression lowers to .map")

	# @match inside a JSX-value can't be an expression -> diagnostic + degrade (no invalid codegen).
	var src_m := "component CFM(x: int = 0) {\n" + \
		"\treturn ( <VBox>{ true and <>@match (x) { @case (0) { <Label/> } }</> }</VBox> )\n}\n"
	var res_m := RUIGuitkx.compile(src_m, "CFM")
	_check_true(str(res_m["diagnostics"]).contains("GUITKX0113"), "@match in expression emits GUITKX0113")

func _test_module_dup_across_kinds() -> void:
	# [audit #7] component + hook with the SAME name in a module must fail (would emit duplicate funcs).
	var src := "module M {\n" + \
		"component Foo() { return ( <Label/> ) }\n" + \
		"hook Foo() { return 1 }\n}\n"
	var res := RUIGuitkx.compile(src, "M")
	_check_true(not res["ok"], "module component+hook same name rejected")
	_check_true(str(res["diagnostics"]).contains("GUITKX0112"), "duplicate-decl diagnostic emitted")

func _test_return_null_guard() -> void:
	# [audit #19] `return null` as a conditional guard before the real markup return must compile.
	var src := "component G(show: bool = false) {\n" + \
		"\tif not show:\n\t\treturn null\n" + \
		"\treturn ( <Label text=\"ok\" /> )\n}\n"
	var res := RUIGuitkx.compile(src, "G")
	if not res["ok"]:
		_fail("return_null_guard: compile failed: " + str(res["diagnostics"]))
	var gd: String = res["gd"]
	_check_true("return null" in gd, "guard `return null` preserved in setup")
	_check(gd, "V.label(", "real markup return still emitted")

func _test_formatter() -> void:
	const Fmt = preload("res://addons/reactive_ui/guitkx/guitkx_formatter.gd")
	var src := "component  Foo( name: String = \"x\" )  {\n" + \
		"  var s = useState(0)\n" + \
		"  return (\n" + \
		"<VBox>\n" + \
		"<Label text={ name }/>\n" + \
		"@if (s[0] > 0) { <Label text=\"big\" /> }\n" + \
		"</VBox>\n" + \
		"  )\n" + \
		"}\n"
	var r1 := Fmt.format(src)
	_check_true(r1["ok"], "formatter ok")
	var f1: String = r1["text"]
	print("--- formatted ---\n" + f1 + "---")
	_check(f1, "component Foo(name: String = \"x\") {", "header canonicalized")
	_check(f1, "\t\t<VBox>", "markup tab-indented")
	_check(f1, "<Label text={ name } />", "self-close spacing")
	_check(f1, "@if (s[0] > 0) {", "control flow formatted")
	# idempotency
	var f2: String = Fmt.format(f1)["text"]
	_check_true(f1 == f2, "idempotent: format(format(x)) == format(x)")
	# parse error -> verbatim (never corrupt)
	var bad := "component Broken( {\n\treturn ( <Label/> \n}\n"
	_check_true(Fmt.format(bad)["text"] == bad, "parse error -> source returned verbatim")

func _test_formatter_options() -> void:
	# [audit #16] insertSpaceBeforeSelfClose must be honored in the multi-attribute WRAP path, not
	# only the single-line path. With singleAttributePerLine the element wraps; the close must respect
	# the option.
	const Fmt = preload("res://addons/reactive_ui/guitkx/guitkx_formatter.gd")
	var src := "component W() {\n\treturn ( <Label aaa=\"1\" bbb=\"2\" ccc=\"3\" /> )\n}\n"
	var no_space: String = Fmt.format(src, { "singleAttributePerLine": true, "insertSpaceBeforeSelfClose": false })["text"]
	_check_true(no_space.contains("/>") and not no_space.contains(" />"), "wrap path honors insertSpaceBeforeSelfClose=false")
	var with_space: String = Fmt.format(src, { "singleAttributePerLine": true })["text"]
	_check_true(with_space.contains(" />"), "wrap path default keeps the space before />")

func _test_markup_corpus() -> void:
	# the SHARED markup-AST corpus also asserted by the TS parseMarkup test — proves guitkx_markup.gd
	# and markup.ts parse identically (incl. `<`/`>` inside {expr}, the structural-fix bug class).
	const M = preload("res://addons/reactive_ui/guitkx/guitkx_markup.gd")
	var raw := FileAccess.get_file_as_string("res://ide-extensions/lsp-server/test-fixtures/markup-cases.json")
	var corpus = JSON.parse_string(raw)
	_check_true(corpus != null and corpus.size() >= 13, "markup corpus loaded")
	for c in corpus:
		var p = M.new()
		var r: Dictionary = p.parse(c["input"], 0, (c["input"] as String).length())
		_check_true(r["error"] == c["error"], "markup corpus error '%s'" % c["name"])
		_check_true(JSON.stringify(r["nodes"]) == c["tree"], "markup corpus tree '%s'" % c["name"])

func _test_formatter_corpus() -> void:
	# the SHARED golden corpus also asserted by the TS formatGuitkx test — proves the two formatters
	# are byte-identical. Regression-guards the GDScript side against future drift.
	const Fmt = preload("res://addons/reactive_ui/guitkx/guitkx_formatter.gd")
	var raw := FileAccess.get_file_as_string("res://ide-extensions/lsp-server/test-fixtures/formatter-cases.json")
	var corpus = JSON.parse_string(raw)
	_check_true(corpus != null and corpus.size() >= 9, "formatter corpus loaded")
	for c in corpus:
		var got: String = Fmt.format(c["input"])["text"]
		_check_true(got == c["expected"], "formatter corpus '%s'" % c["name"])
		_check_true(Fmt.format(got)["text"] == got, "formatter corpus idempotent '%s'" % c["name"])
	# Unity-style real-file idempotency: format(format(sample)) == format(sample) on every .guitkx.
	const Codegen = preload("res://addons/reactive_ui/guitkx/guitkx_codegen.gd")
	for path in Codegen.find_all("res://examples"):
		var src := FileAccess.get_file_as_string(path)
		var f1: String = Fmt.format(src)["text"]
		_check_true(Fmt.format(f1)["text"] == f1, "sample format idempotent: %s" % path)

func _test_scanner_fixtures() -> void:
	# byte-identity cross-test: the SAME corpus the TS scanner.ts asserts on (prevents lexer drift)
	const L = preload("res://addons/reactive_ui/guitkx/guitkx_lexer.gd")
	var txt := FileAccess.get_file_as_string("res://ide-extensions/lsp-server/test-fixtures/scanner-cases.json")
	if txt == "":
		_fail("scanner fixtures not found / empty")
		return
	var fx = JSON.parse_string(txt)
	for c in fx["skipNoncode"]:
		var got: int = L.skip_noncode(c["input"], int(c["at"]))
		_check_true(got == int(c["expect"]), "skip_noncode(%s, %d) = %d expected %d" % [c["input"], int(c["at"]), got, int(c["expect"])])
	for c in fx["findMatching"]:
		var got2: int = L.find_matching(c["input"], int(c["at"]))
		_check_true(got2 == int(c["expect"]), "find_matching(%s, %d) = %d expected %d" % [c["input"], int(c["at"]), got2, int(c["expect"])])

func _test_deep_flatten() -> void:
	# V._norm must deep-flatten nested arrays (Phase 4 §5: .map().map() children) + drop nulls at depth
	var a := V.label({})
	var b := V.button({})
	var d := V.label({})
	var flat: Array = V._norm([a, [b, [d]]])
	_check_true(flat.size() == 3, "deep _norm flattens nested arrays (got %d)" % flat.size())
	_check_true(flat[0] == a and flat[1] == b and flat[2] == d, "deep _norm preserves order")
	var flat2: Array = V._norm([a, [null, [b, null]], null])
	_check_true(flat2.size() == 2, "deep _norm drops nested nulls (got %d)" % flat2.size())

func _test_diagnostics() -> void:
	# rules of hooks: a hook called inside an if-block in setup
	var roh := RUIGuitkx.compile("component Bad(c: bool = true) {\n\tvar a = useState(0)\n\tif c:\n\t\tvar b = useState(1)\n\treturn ( <Label /> )\n}\n", "Bad")
	_check_true(str(roh["diagnostics"]).contains("GUITKX0013"), "rules-of-hooks warning (got %s)" % str(roh["diagnostics"]))
	# duplicate literal keys among siblings
	var dk := RUIGuitkx.compile("component Dup() {\n\treturn (\n\t\t<VBox>\n\t\t\t<Label key=\"x\" />\n\t\t\t<Label key=\"x\" />\n\t\t</VBox>\n\t)\n}\n", "Dup")
	_check_true(str(dk["diagnostics"]).contains("GUITKX0104"), "duplicate-key warning (got %s)" % str(dk["diagnostics"]))
	# loop child missing key
	var lk := RUIGuitkx.compile("component LK(items: Array = []) {\n\treturn (\n\t\t<VBox>\n\t\t\t@for (it in items) { <Label text={ it } /> }\n\t\t</VBox>\n\t)\n}\n", "LK")
	_check_true(str(lk["diagnostics"]).contains("GUITKX0106"), "keyless-loop-child warning (got %s)" % str(lk["diagnostics"]))
	# a clean component emits no warnings
	var clean := RUIGuitkx.compile("component Clean() {\n\tvar a = useState(0)\n\treturn ( <Label text={ str(a[0]) } /> )\n}\n", "Clean")
	_check_true(clean["ok"] and str(clean["diagnostics"]) == "[]", "clean component has no diagnostics (got %s)" % str(clean["diagnostics"]))

func _test_hook() -> void:
	var src := "hook use_counter(start: int = 0) {\n" + \
		"\tvar s = useState(start)\n" + \
		"\treturn [s[0], func(): s[1].call(s[0] + 1)]\n" + \
		"}\n"
	var r := RUIGuitkx.compile(src, "UseCounter")
	if not r["ok"]:
		_fail("hook: compile failed: " + str(r["diagnostics"]))
	var gd: String = r["gd"]
	print("--- generated (UseCounter) ---\n" + gd + "----------------------------")
	_check(gd, "class_name UseCounter", "hook class name from file")
	_check(gd, "static func use_counter(start: int = 0):", "hook function signature (params verbatim)")
	_check(gd, "Hooks.useState(start)", "hook body auto-prefixed")
	_check_true(not ("\t\tvar s " in gd), "hook body single-indented")
	var gd2 := gd.replace("class_name UseCounter\n", "")
	var path := "user://__guitkx_hook.gd"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(gd2)
	f.close()
	_check_true(load(path) != null, "hook .gd loads/parses")
	# module files are rejected (one declaration per file)
	var mr := RUIGuitkx.compile("module Widgets {\n\tcomponent A() { return ( <Label /> ) }\n}\n", "Widgets")
	_check_true(mr["ok"], "module Name { ... } now compiles (got %s)" % str(mr["diagnostics"]))
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

func _test_spread() -> void:
	# `{...spread}` merges into props left-to-right (later wins), order-preserving, via V._spread_all.
	# Component tag:
	var c := RUIGuitkx.compile("component C(base, t) {\n\treturn ( <Card {...base} title={ t } /> )\n}\n", "C")
	if not c["ok"]:
		_fail("spread: component compile failed: " + str(c["diagnostics"]))
	else:
		_check(c["gd"], "V.fc(Card.render, V._spread_all([(base), { \"title\": t }]))", "spread on a component")
	# Host tag with explicit props both BEFORE and AFTER a spread (order + last-wins preserved):
	var h := RUIGuitkx.compile("component H(cfg) {\n\treturn ( <Button text=\"Hi\" {...cfg} onClick={ f } /> )\n}\n", "H")
	if not h["ok"]:
		_fail("spread: host compile failed: " + str(h["diagnostics"]))
	else:
		_check(h["gd"], "V.button(V._spread_all([{ \"text\": \"Hi\" }, (cfg), { \"onClick\": f }]))", "spread on a host, order preserved")
	# Regression: a plain element (no spread) still emits a bare dict literal (unchanged hot path).
	var p := RUIGuitkx.compile("component P() {\n\treturn ( <Button text=\"Hi\" /> )\n}\n", "P")
	if p["ok"]:
		_check(p["gd"], "V.button({ \"text\": \"Hi\" })", "no-spread element keeps the plain dict literal")
		_check_true(not (p["gd"] as String).contains("_spread_all"), "no-spread element does NOT call _spread_all")

func _test_emit() -> void:
	var src := "@class_name Greeting\n\ncomponent Greeting(name: String = \"World\") {\n" + \
		"\tvar s = useState(0)\n" + \
		"\treturn (\n" + \
		"\t\t<VBox style={ {\"separation\": 8} }>\n" + \
		"\t\t\t<Label text={ \"Hello, %s (%d)\" % [name, s[0]] } />\n" + \
		"\t\t\t<Button text=\"+1\" onClick={ inc } />\n" + \
		"\t\t</VBox>\n" + \
		"\t)\n}\n"
	var r := RUIGuitkx.compile(src, "Greeting")
	if not r["ok"]:
		_fail("emit: compile failed: " + str(r["diagnostics"]))
	var gd: String = r["gd"]
	print("--- generated (Greeting) ---\n" + gd + "----------------------------")
	_check(gd, "class_name Greeting", "class_name")
	_check(gd, "props.get(\"name\", \"World\")", "param unpack")
	_check(gd, "Hooks.useState(0)", "hook auto-prefix")
	_check(gd, "V.vbox(", "VBox -> V.vbox")
	_check(gd, "V.label(", "Label -> V.label")
	_check(gd, "V.button(", "Button -> V.button")
	_check(gd, "\"onClick\": inc", "event prop (React-canonical name flows through the compiler verbatim)")
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
	_failed = true
