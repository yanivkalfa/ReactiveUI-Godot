extends SceneTree
## Milestone 2.1 compiler test: (1) compile-text checks on a hook-using component, and
## (2) an end-to-end runtime test — compile a hook-free component, write the generated .gd,
## load it, mount it through the reconciler, and verify the real Godot node tree.

const Codegen = preload("res://addons/reactive_ui/guitkx/guitkx_codegen.gd")
const GDiag = preload("res://addons/reactive_ui/guitkx/guitkx_diag.gd")

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
	_test_p1_error_gates()
	_test_t13_single_decl()
	_test_return_null_guard()
	_test_jsx_value()
	_test_diagnostics()
	_test_loop_single_root()
	_test_decl_validation()
	_test_codegen_staleness()
	_test_indent_robustness()
	_test_outlier_indent()
	_test_deep_flatten()
	_test_scanner_fixtures()
	_test_markup_corpus()
	_test_vocabulary()
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

	# @match inside a JSX-value can't be an expression -> GUITKX0113, and since T1.1 an emit-time
	# error FAILS the compile (no diagnostic with error severity may coexist with ok:true).
	var src_m := "component CFM(x: int = 0) {\n" + \
		"\treturn ( <VBox>{ true and <>@match (x) { @case (0) { <Label/> } }</> }</VBox> )\n}\n"
	var res_m := RUIGuitkx.compile(src_m, "CFM")
	_check_true(_has_code(res_m, "GUITKX0113"), "@match in expression emits GUITKX0113")
	_check_true(not res_m["ok"], "T1.1: emit-time 0113 fails the compile")
	_check_true(res_m["gd"] == "", "T1.1: failed compile ships no generated code")

func _test_module_dup_across_kinds() -> void:
	# [audit #7] component + hook with the SAME name in a module must fail (would emit duplicate funcs).
	var src := "module M {\n" + \
		"component Foo() { return ( <Label/> ) }\n" + \
		"hook Foo() { return 1 }\n}\n"
	var res := RUIGuitkx.compile(src, "M")
	_check_true(not res["ok"], "module component+hook same name rejected")
	_check_true(_has_code(res, "GUITKX0112"), "duplicate-decl diagnostic emitted")

func _test_p1_error_gates() -> void:
	# T1.2: malformed markup inside an @if body -> the INNER parser's error code, positioned exactly
	# on the broken tag, and (T1.1) ok:false. Previously: silent `null  # body parse error` emission.
	var src_if := "component B() {\n" + \
		"\treturn (\n\t\t<VBox>\n\t\t\t@if (true) { <Broken> }\n\t\t</VBox>\n\t)\n}\n"
	var r := RUIGuitkx.compile(src_if, "B")
	_check_true(not r["ok"], "T1.2: broken @if body fails the compile")
	_check_diag_at(r, "GUITKX0301", src_if, "<Broken>", "T1.2: 0301 lands on the unclosed tag in the @if body")

	# T1.2: broken markup in a @for body.
	var src_for := "component F(xs: Array = []) {\n" + \
		"\treturn ( <VBox>@for (x in xs) { <Row };&& }</VBox> )\n}\n"
	var r2 := RUIGuitkx.compile(src_for, "F")
	_check_true(not r2["ok"], "T1.2: broken @for body fails the compile")

	# T1.2: broken markup nested inside a JSX-value {expr} -- no validation pass ever reaches it,
	# so the emit-time parse is its only chance to be seen.
	var src_ex := "component C(open: bool = false) {\n" + \
		"\treturn ( <VBox>{ open and <Broken> }</VBox> )\n}\n"
	var r3 := RUIGuitkx.compile(src_ex, "C")
	_check_true(not r3["ok"], "T1.2: broken nested-expr markup fails the compile")
	_check_diag_at(r3, "GUITKX0301", src_ex, "<Broken>", "T1.2: nested-expr 0301 lands on the broken tag")

	# T1.1: a module member whose loop body has 2 roots (validation ERROR 0108) fails the module --
	# previously _compile_module had no gate at all and shipped the broken class.
	var src_mod := "module M2 {\n" + \
		"\tcomponent A() {\n" + \
		"\t\treturn ( <VBox>@for (i in 3) { <Label key={ str(i) } /> <Label key={ str(i) + \"b\" } /> }</VBox> )\n" + \
		"\t}\n}\n"
	var r4 := RUIGuitkx.compile(src_mod, "M2")
	_check_true(not r4["ok"], "T1.1: module-member validation error fails the module compile")
	_check_true(_has_code(r4, "GUITKX0108"), "T1.1: the member's 0108 is the reported error")

func _test_t13_single_decl() -> void:
	# T1.3: content after the single top-level declaration errors (Unity UITKX2105 parity) --
	# a second component used to be dropped silently while the LSP still indexed the ghost.
	var src := "component A() {\n\treturn ( <Label /> )\n}\n\ncomponent B() {\n\treturn ( <Label /> )\n}\n"
	var r := RUIGuitkx.compile(src, "A")
	_check_true(not r["ok"], "T1.3: second top-level declaration fails the compile")
	_check_diag_at(r, "GUITKX2105", src, "component B() {", "T1.3: 2105 lands on the second declaration")

	# trailing comments after the declaration stay legal.
	var src_c := "component A() {\n\treturn ( <Label /> )\n}\n# trailing note\n"
	_check_true(RUIGuitkx.compile(src_c, "A")["ok"], "T1.3: trailing comments after the declaration are fine")

	# hook files too (the hook path now parses via _parse_hook_at and knows where it ends).
	var src_h := "hook use_x() {\n\treturn 1\n}\nstray text\n"
	var r_h := RUIGuitkx.compile(src_h, "use_x")
	_check_true(not r_h["ok"], "T1.3: trailing junk after a hook fails the compile")
	_check_diag_at(r_h, "GUITKX2105", src_h, "stray text", "T1.3: hook trailing 2105 lands on the junk")

	# junk BETWEEN module members used to vanish silently (_find_decl skipped it).
	var src_m := "module M {\n\tcomponent A() { return ( <Label /> ) }\n\tvar oops = 1\n\thook use_y() { return 2 }\n}\n"
	var r_m := RUIGuitkx.compile(src_m, "M")
	_check_true(not r_m["ok"], "T1.3: junk between module members fails the compile")
	_check_diag_at(r_m, "GUITKX2105", src_m, "var oops = 1", "T1.3: module junk 2105 lands on the junk")

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

func _test_vocabulary() -> void:
	# T0.3: vocabulary.json is the single source of truth. The compiler tables must come from it…
	_check_true(RUIGuitkx.HOST_TAGS.get("VBoxContainer", "") == "vbox" and RUIGuitkx.HOST_TAGS.size() >= 39,
		"HOST_TAGS loaded from vocabulary.json (aliases included, got %d)" % RUIGuitkx.HOST_TAGS.size())
	_check_true("useState" in RUIGuitkx.HOOK_NAMES and RUIGuitkx.HOOK_NAMES.size() == 23,
		"HOOK_NAMES loaded from vocabulary.json (got %d)" % RUIGuitkx.HOOK_NAMES.size())
	# …and v_factories must mirror the REAL public V API (reflection tripwire: adding/removing a
	# static func on core/v.gd without updating vocabulary.json fails here with the exact diff).
	var v_script: Script = preload("res://addons/reactive_ui/core/v.gd")
	var reflected: Array = []
	for m in v_script.get_script_method_list():
		var mname: String = m["name"]
		if not mname.begins_with("_") and not (mname in reflected):
			reflected.append(mname)
	reflected.sort()
	var vocab: Array = (RUIGuitkx.V_FACTORIES as Array).duplicate()
	vocab.sort()
	_check_true(str(reflected) == str(vocab),
		"vocabulary.v_factories mirrors core/v.gd public statics\n  reflected: %s\n  vocabulary: %s" % [str(reflected), str(vocab)])

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

# First diagnostic with `code` from a compile() result, or {} — T0.2 structured-diag test helper.
func _diag(r: Dictionary, code: String) -> Dictionary:
	for d in r.get("diagnostics", []):
		if d is Dictionary and (d as Dictionary).get("code", "") == code:
			return d
	return {}

func _has_code(r: Dictionary, code: String) -> bool:
	return not _diag(r, code).is_empty()

## Assert a diagnostic exists AND its offset points exactly at `needle` in `src` (T0.2 precision).
func _check_diag_at(r: Dictionary, code: String, src: String, needle: String, label: String) -> void:
	var d := _diag(r, code)
	_check_true(not d.is_empty(), "%s: %s present (got %s)" % [label, code, str(r.get("diagnostics", []))])
	if d.is_empty():
		return
	var off := int(d.get("offset", -1))
	_check_true(off >= 0 and src.substr(off, needle.length()) == needle,
		"%s: %s offset lands on '%s' (offset %d -> '%s')" % [label, code, needle, off, src.substr(maxi(0, off), needle.length())])

func _test_diagnostics() -> void:
	# rules of hooks: a hook called inside an if-block in setup — flagged AT the offending line
	var roh_src := "component Bad(c: bool = true) {\n\tvar a = useState(0)\n\tif c:\n\t\tvar b = useState(1)\n\treturn ( <Label /> )\n}\n"
	var roh := RUIGuitkx.compile(roh_src, "Bad")
	_check_diag_at(roh, "GUITKX0013", roh_src, "var b = useState(1)", "rules-of-hooks")
	_check_true(int(_diag(roh, "GUITKX0013").get("severity", -9)) == GDiag.WARNING, "GUITKX0013 is a warning")
	# duplicate literal keys among siblings — flagged at the SECOND key attribute
	var dk_src := "component Dup() {\n\treturn (\n\t\t<VBox>\n\t\t\t<Label key=\"x\" />\n\t\t\t<Label key=\"x\" />\n\t\t</VBox>\n\t)\n}\n"
	var dk := RUIGuitkx.compile(dk_src, "Dup")
	_check_diag_at(dk, "GUITKX0104", dk_src, "key=\"x\"", "duplicate-key")
	_check_true(int(_diag(dk, "GUITKX0104").get("offset", -1)) > dk_src.find("key=\"x\""), "GUITKX0104 anchors to the SECOND duplicate, not the first")
	# loop child missing key — flagged at the element
	var lk_src := "component LK(items: Array = []) {\n\treturn (\n\t\t<VBox>\n\t\t\t@for (it in items) { <Label text={ it } /> }\n\t\t</VBox>\n\t)\n}\n"
	var lk := RUIGuitkx.compile(lk_src, "LK")
	_check_diag_at(lk, "GUITKX0106", lk_src, "<Label text={ it }", "keyless-loop-child")
	# a clean component emits no warnings
	var clean := RUIGuitkx.compile("component Clean() {\n\tvar a = useState(0)\n\treturn ( <Label text={ str(a[0]) } /> )\n}\n", "Clean")
	_check_true(clean["ok"] and (clean["diagnostics"] as Array).is_empty(), "clean component has no diagnostics (got %s)" % str(clean["diagnostics"]))

func _test_loop_single_root() -> void:
	# BUG-V3: a @for/@while body with >1 sibling root is a hard error (single-root; parity Unity UITKX0108)
	var multi := RUIGuitkx.compile("component M(n: int = 3) {\n" + \
		"\treturn (\n\t\t<VBox>\n" + \
		"\t\t\t@for (i in n) {\n\t\t\t\t<Label key={ str(i) } />\n\t\t\t\t<Label key={ str(i) } />\n\t\t\t}\n" + \
		"\t\t</VBox>\n\t)\n}\n", "M")
	_check_true(not multi["ok"] and _has_code(multi, "GUITKX0108"), "loop body with 2 roots fails with GUITKX0108 (got %s)" % str(multi["diagnostics"]))
	_check_true(int(_diag(multi, "GUITKX0108").get("offset", -1)) >= 0, "GUITKX0108 carries a position even through the nested loop-body re-parse")
	# BUG-V3: duplicate EXPRESSION keys among siblings are caught (not only literal key="..." keys)
	var dupe := RUIGuitkx.compile("component D() {\n" + \
		"\treturn (\n\t\t<VBox>\n\t\t\t<Label key={ str(0) } />\n\t\t\t<Label key={ str(0) } />\n\t\t</VBox>\n\t)\n}\n", "D")
	_check_true(_has_code(dupe, "GUITKX0104"), "duplicate expr key caught with GUITKX0104 (got %s)" % str(dupe["diagnostics"]))
	# valid: a fragment root wrapping distinctly-keyed siblings inside the loop compiles cleanly
	var okc := RUIGuitkx.compile("component OK(n: int = 3) {\n" + \
		"\treturn (\n\t\t<VBox>\n" + \
		"\t\t\t@for (i in n) {\n\t\t\t\t<>\n\t\t\t\t\t<Label key={ \"a\" + str(i) } />\n\t\t\t\t\t<Label key={ \"b\" + str(i) } />\n\t\t\t\t</>\n\t\t\t}\n" + \
		"\t\t</VBox>\n\t)\n}\n", "OK")
	_check_true(okc["ok"], "loop with fragment-wrapped distinct-key siblings compiles (got %s)" % str(okc["diagnostics"]))

func _test_decl_validation() -> void:
	# BUG-V2: an invalid @class_name value (multiple tokens) is rejected with GUITKX0300
	var badcn_src := "@class_name Foo Bar\ncomponent X() { return ( <Label /> ) }\n"
	var badcn := RUIGuitkx.compile(badcn_src, "X")
	_check_true(not badcn["ok"], "invalid @class_name rejected (got %s)" % str(badcn["diagnostics"]))
	_check_diag_at(badcn, "GUITKX0300", badcn_src, "@class_name", "invalid @class_name")
	# a valid @class_name is accepted, and a trailing comment on the directive line is tolerated
	var okcn := RUIGuitkx.compile("@class_name MyThing  # ok\ncomponent X() { return ( <Label /> ) }\n", "X")
	_check_true(okcn["ok"], "valid @class_name accepted (got %s)" % str(okcn["diagnostics"]))
	# BUG-V1: a misspelled declaration keyword yields a did-you-mean hint, anchored at the typo'd word
	var typo_src := "componeent X() { return ( <Label /> ) }\n"
	var typo := RUIGuitkx.compile(typo_src, "X")
	_check_true(not typo["ok"] and str(_diag(typo, "GUITKX0102").get("message", "")).contains("did you mean 'component'"), "misspelled keyword suggests component (got %s)" % str(typo["diagnostics"]))
	_check_diag_at(typo, "GUITKX0102", typo_src, "componeent", "misspelled keyword")
	# BUG-V4: a space after `<` is an invalid tag name, not a silent fragment
	var badtag := RUIGuitkx.compile("component B() {\n\treturn ( <  a> )\n}\n", "B")
	_check_true(not badtag["ok"] and _has_code(badtag, "GUITKX0300"), "invalid tag name rejected (got %s)" % str(badtag["diagnostics"]))
	# BUG-V5: code after the markup return is flagged unreachable (GUITKX0114 warning) at the dead code
	var unreach_src := "component U() {\n\treturn ( <Label /> )\n\tvar x = 5\n\treturn ( <Button /> )\n}\n"
	var unreach := RUIGuitkx.compile(unreach_src, "U")
	_check_true(bool(unreach["ok"]), "unreachable code is a warning, not an error (got %s)" % str(unreach["diagnostics"]))
	_check_diag_at(unreach, "GUITKX0114", unreach_src, "var x = 5", "unreachable-after-return")

# The stale-.gd disease: a sibling .gd that is NEWER than its source but was produced by an OLD
# compiler must still be regenerated. Guards guitkx_codegen's compiler-version staleness mechanism —
# the mtime-only guard silently skipped such files, so old-compiler output (e.g. an unprefixed
# useState) persisted after a pull while CI (which recompiles unconditionally) stayed green.
func _test_codegen_staleness() -> void:
	var CG := preload("res://addons/reactive_ui/guitkx/guitkx_codegen.gd")
	var fp: String = CG.compiler_fingerprint()
	_check_true(fp.length() == 8 and fp != "00000000", "compiler fingerprint is a stable non-zero hash (got %s)" % fp)
	_check_true(fp == CG.compiler_fingerprint(), "compiler fingerprint is deterministic")
	if DirAccess.open("res://.godot") == null:
		return  # the marker lives in .godot (present after an editor import scan); skip the round-trip otherwise
	var mk := "res://.godot/rui_guitkx_compiler.fp"
	var had := FileAccess.file_exists(mk)
	var prev := FileAccess.get_file_as_string(mk) if had else ""
	_write_file(mk, "deadbeef")
	_check_true(CG.compiler_changed(), "a mismatched marker -> compiler_changed() true (forces full regen)")
	_write_file(mk, fp)
	_check_true(not CG.compiler_changed(), "a matching marker -> compiler_changed() false (mtime guard resumes)")
	if had:
		_write_file(mk, prev)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(mk))

func _write_file(path: String, s: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(s)
		f.close()

# A tab + spaces renders identically to tabs in every editor (so the author can't see the difference)
# but differs byte-wise. The compiler must normalize such mixed indentation (depth-based reindent)
# into VALID GDScript instead of emitting a broken .gd ("unindent doesn't match") or a false
# GUITKX0013 -- while still catching a genuine hook-in-a-block.
func _test_indent_robustness() -> void:
	var mixed := "component X {\n\t\tvar a = useState(0)\n\t  var b = useState(0)\n\treturn ( <Label /> )\n}\n"
	var r := RUIGuitkx.compile(mixed, "X")
	_check_true(r["ok"] and not _has_code(r, "GUITKX0013"), "mixed tab/space setup compiles, no false GUITKX0013 (got %s)" % str(r["diagnostics"]))
	var s := GDScript.new()
	s.source_code = (r["gd"] as String).replace("class_name X\n", "")
	_check_true(s.reload() == OK, "mixed tab/space setup generates VALID GDScript")
	var pure_space := RUIGuitkx.compile("component X {\n    var a = useState(0)\n    return ( <Label /> )\n}\n", "X")
	var s2 := GDScript.new()
	s2.source_code = (pure_space["gd"] as String).replace("class_name X\n", "")
	_check_true(s2.reload() == OK, "pure-space setup also generates VALID GDScript")
	var bad := RUIGuitkx.compile("component X {\n\tvar a = useState(0)\n\tif a[0]:\n\t\tvar b = useState(0)\n\treturn ( <Label /> )\n}\n", "X")
	_check_true(_has_code(bad, "GUITKX0013"), "a genuine hook-in-a-block still warns")

# One outlier-SHALLOW setup line must not shift the rest of the block: with a min-depth anchor,
# `var b` at column 0 made every OTHER line emit one level too deep (over-indented with no preceding
# `:` = "expected an expression" + the class-level diagnostic cascade). The reindent anchors to the
# FIRST non-blank line and clamps shallower lines up to body level. [BUG: G1]
func _test_outlier_indent() -> void:
	var src := "component X {\n\tvar a = useState(0)\nvar b = 1\n\tif a[0]:\n\t\tb += 1\n\treturn ( <Label /> )\n}\n"
	var r := RUIGuitkx.compile(src, "X")
	_check_true(r["ok"], "outlier-shallow setup line still compiles (got %s)" % str(r["diagnostics"]))
	var gd: String = r["gd"]
	_check(gd, "\n\tvar a = Hooks.useState(0)", "normal setup lines stay at body level")
	_check(gd, "\n\tvar b = 1", "outlier line clamps up to body level")
	_check(gd, "\n\t\tb += 1", "nested depth is preserved")
	var s := GDScript.new()
	s.source_code = gd.replace("class_name X\n", "")
	_check_true(s.reload() == OK, "outlier-shallow setup generates VALID GDScript")
	# A leading over-indented comment must not become the anchor (comments are legal at any depth):
	# anchoring on it dedented the if-body out of its block -- invalid .gd + formatter corruption.
	var cmt := RUIGuitkx.compile("component X {\n\t\t# note\n\tvar a = useState(0)\n\tif a[0]:\n\t\ta[1].call(1)\n\treturn ( <Label /> )\n}\n", "X")
	_check_true(cmt["ok"], "leading over-indented comment still compiles (got %s)" % str(cmt["diagnostics"]))
	var cgd: String = cmt["gd"]
	_check(cgd, "\n\tif a[0]:", "code anchors at body level, not at the comment")
	_check(cgd, "\n\t\ta[1].call(1)", "the if body stays nested under its if")
	var cs := GDScript.new()
	cs.source_code = cgd.replace("class_name X\n", "")
	_check_true(cs.reload() == OK, "comment-led setup generates VALID GDScript")
	# A comment-only hook body must still produce a valid func (comments are not statements).
	var ch := RUIGuitkx.compile("hook use_todo() {\n\t# TODO: implement\n}\n", "UseTodo")
	_check_true(ch["ok"], "comment-only hook body compiles")
	var chs := GDScript.new()
	chs.source_code = (ch["gd"] as String).replace("class_name UseTodo\n", "")
	_check_true(chs.reload() == OK, "comment-only hook body generates VALID GDScript (trailing pass)")

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
	_check_true(not er["ok"] and _has_code(er, "GUITKX0102"), "no-declaration rejected with GUITKX0102")

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
	# T1.1: a file that STOPS compiling must not leave its stale sibling .gd behind (the editor would
	# keep running code that no longer matches the source). compile_file deletes it.
	var f_bad := FileAccess.open(gx, FileAccess.WRITE)
	f_bad.store_string("component Fixture() {\n\treturn ( <Broken> )\n}\n")
	f_bad.close()
	var r_bad := Codegen.compile_file(gx)
	_check_true(not r_bad["ok"], "broken rewrite fails to compile")
	_check_true(not FileAccess.file_exists(gd), "stale sibling .gd deleted on failed compile")
	# fix it again -> the .gd comes back
	var f_fix := FileAccess.open(gx, FileAccess.WRITE)
	f_fix.store_string(src)
	f_fix.close()
	_check_true(Codegen.compile_file(gx)["ok"], "fixed file compiles again")
	_check_true(FileAccess.file_exists(gd), "sibling .gd regenerated after the fix")
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
