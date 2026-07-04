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
	_test_t14_last_return()
	_test_t15_unknown_tags()
	_test_t25_hook_contexts()
	_test_t26_naming()
	_test_t27_diag_ports()
	_test_t23_uss()
	_test_t35_parser_bugs()
	_test_severity_table()
	_test_p2_markup_features()
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
	_test_cold_open_recovery()
	_test_phase_d_bodies()
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
	# 0.7.2 anchor regression (field capture 2026-07-04): diagnostics from setup-VALUE markup must
	# anchor in the ORIGINAL source. Aliasing used to run BEFORE the splice, so every inserted
	# `Hooks.` prefix (6 chars) shifted every later diagnostic -- two useState calls pushed a 0105
	# onto the CLOSING tag (the dock said 8:33 instead of 8:21). Splice first, alias second.
	var a_src := "component AnchorProbe() {\n" + \
		"\tvar n = useState(0)\n" + \
		"\tvar m = useState(1)\n" + \
		"\tvar c = (<Nope></Nope>)\n" + \
		"\treturn ( <VBox>{ c }<Label text={ str(n[0] + m[0]) } /></VBox> )\n}\n"
	var ra := RUIGuitkx.compile(a_src, "AnchorProbe", ["DemoBox"])
	_check_true(not ra["ok"], "unknown component in a setup value fails the compile")
	var a_found := false
	for da in (ra["diagnostics"] as Array):
		if str((da as Dictionary).get("code", "")) == "GUITKX0105":
			a_found = true
			_check_true(int((da as Dictionary).get("offset", -1)) == a_src.find("<Nope>") + 1,
				"0105 anchors on the OPENING tag name in the original source (got %d, want %d)" % [int((da as Dictionary).get("offset", -1)), a_src.find("<Nope>") + 1])
	_check_true(a_found, "0105 reported for the unknown setup-value component")
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
		"\t\t\t{ items.map(func(it): return <>@if (it.ok) { return ( <Label text={ it.name } /> ) }</>) }\n" + \
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
		"\treturn ( <VBox>{ true and <>@for (x in items) { return ( <Label text={ x } /> ) }</> }</VBox> )\n}\n"
	var res_for := RUIGuitkx.compile(src_for, "CFF")
	_check_true(res_for["ok"] and "items).map(func(x)" in str(res_for["gd"]), "@for in expression lowers to .map")

	# @match inside a JSX-value can't be an expression -> GUITKX0026, and since T1.1 an emit-time
	# error FAILS the compile (no diagnostic with error severity may coexist with ok:true).
	var src_m := "component CFM(x: int = 0) {\n" + \
		"\treturn ( <VBox>{ true and <>@match (x) { @case (0) { return ( <Label/> ) } }</> }</VBox> )\n}\n"
	var res_m := RUIGuitkx.compile(src_m, "CFM")
	_check_true(_has_code(res_m, "GUITKX0026"), "@match in expression emits GUITKX0026")
	_check_true(not res_m["ok"], "T1.1: emit-time 0113 fails the compile")
	_check_true(res_m["gd"] == "", "T1.1: failed compile ships no generated code")

func _test_module_dup_across_kinds() -> void:
	# [audit #7] component + hook with the SAME name in a module must fail (would emit duplicate funcs).
	var src := "module M {\n" + \
		"component Foo() { return ( <Label/> ) }\n" + \
		"hook Foo() { return 1 }\n}\n"
	var res := RUIGuitkx.compile(src, "M")
	_check_true(not res["ok"], "module component+hook same name rejected")
	_check_true(_has_code(res, "GUITKX2505"), "duplicate-decl diagnostic emitted")

func _test_p1_error_gates() -> void:
	# T1.2: malformed markup inside an @if body -> the INNER parser's error code, positioned exactly
	# on the broken tag, and (T1.1) ok:false. Previously: silent `null  # body parse error` emission.
	var src_if := "component B() {\n" + \
		"\treturn (\n\t\t<VBox>\n\t\t\t@if (true) { return ( <Broken> ) }\n\t\t</VBox>\n\t)\n}\n"
	var r := RUIGuitkx.compile(src_if, "B")
	_check_true(not r["ok"], "T1.2: broken @if body fails the compile")
	_check_diag_at(r, "GUITKX0301", src_if, "<Broken>", "T1.2: 0301 lands on the unclosed tag in the @if body")

	# T1.2: broken markup in a @for body.
	var src_for := "component F(xs: Array = []) {\n" + \
		"\treturn ( <VBox>@for (x in xs) { return ( <Row };&& ) }</VBox> )\n}\n"
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
		"\t\treturn ( <VBox>@for (i in 3) { return ( <Label key={ str(i) } /> <Label key={ str(i) + \"b\" } /> ) }</VBox> )\n" + \
		"\t}\n}\n"
	var r4 := RUIGuitkx.compile(src_mod, "M2")
	_check_true(not r4["ok"], "T1.1: module-member validation error fails the module compile")
	_check_true(_has_code(r4, "GUITKX0108"), "T1.1: the member's 0108 is the reported error")

func _test_t14_last_return() -> void:
	# T1.4 (Unity useLastReturn parity): the LAST top-level markup return is the component's window.
	# Phase C: an EARLIER top-level markup return is LEGAL -- lowered in place -- and everything
	# after it (including the final return) is dimmed unreachable, exactly like Unity's Site-B dim.
	var two_src := "component U2() {\n\treturn ( <Label /> )\n\tvar x = 5\n\treturn ( <Button /> )\n}\n"
	var two := RUIGuitkx.compile(two_src, "U2")
	_check_true(bool(two["ok"]), "Phase C: an early top-level markup return compiles (got %s)" % str(two["diagnostics"]))
	_check_true(_has_code(two, "GUITKX0107"), "Phase C: code after the unconditional early return dims unreachable (got %s)" % str(two["diagnostics"]))
	_check_true("return V.label" in str(two["gd"]), "Phase C: the early return's markup is lowered in place, got:\n%s" % str(two["gd"]))

	# Phase C: a markup return INSIDE an if: block is legal and lowered in place -- and its markup
	# is now REALLY parsed, so mismatched tags get the precise 0302 instead of a blanket 2102.
	var early_bad_src := "component S(weird: bool = false) {\n" + \
		"\tif weird:\n\t\treturn <s></a>\n" + \
		"\treturn (\n\t\t<vbox><label text=\"ok\" /></vbox>\n\t)\n}\n"
	var early_bad := RUIGuitkx.compile(early_bad_src, "S")
	_check_true(not early_bad["ok"], "Phase C: a BROKEN early markup return still fails the compile")
	_check_true(_has_code(early_bad, "GUITKX0302"), "Phase C: the early return's markup is parsed for real (0302 mismatched tag, got %s)" % str(early_bad["diagnostics"]))

	# Phase C, the t04 shape: a CONDITIONAL early markup return compiles to scope-correct GDScript
	# -- its lowered `return` sits INSIDE the `if weird:` block, at the block's indent.
	var early_src := "component S2(weird: bool = false) {\n" + \
		"\tif weird:\n\t\treturn ( <label text=\"early\" /> )\n" + \
		"\treturn (\n\t\t<vbox><label text=\"ok\" /></vbox>\n\t)\n}\n"
	var early := RUIGuitkx.compile(early_src, "S2")
	_check_true(bool(early["ok"]), "Phase C: a conditional early markup return compiles (got %s)" % str(early["diagnostics"]))
	_check_true("\n\t\treturn V.label" in str(early["gd"]), "Phase C: the early return is lowered at ITS OWN indent (inside the if block), got:\n%s" % str(early["gd"]))
	_check_true(not _has_code(early, "GUITKX0107"), "Phase C: a CONDITIONAL early return dims nothing (got %s)" % str(early["diagnostics"]))

	# Phase C runtime proof: both paths of the compiled guard actually render (the whole point).
	var sc := GDScript.new()
	sc.source_code = str(early["gd"]).replace("class_name S2\n", "")
	var lerr := sc.reload()
	_check_true(lerr == OK, "Phase C runtime: the lowered .gd parses+compiles (err %s):\n%s" % [str(lerr), str(early["gd"])])
	if lerr == OK:
		var inst = sc.new()
		var r_early = inst.render({ "weird": true }, [])
		var r_main = inst.render({ "weird": false }, [])
		_check_true(r_early is RUIVNode and str((r_early as RUIVNode).props.get("text", "")) == "early", "Phase C runtime: weird=true renders the early label (got %s)" % str(r_early))
		_check_true(r_main is RUIVNode and (r_main as RUIVNode).props.get("text", null) == null, "Phase C runtime: weird=false renders the main vbox root (got %s)" % str(r_main))

	# A PLAIN parenthesized return inside a setup lambda is legal GDScript -- never flagged.
	var lambda_src := "component L() {\n" + \
		"\tvar f = func():\n\t\treturn (1 + 2)\n" + \
		"\treturn ( <Label text={ str(f.call()) } /> )\n}\n"
	var lam := RUIGuitkx.compile(lambda_src, "L")
	_check_true(bool(lam["ok"]), "T1.4: lambda `return (expr)` is not hijacked nor flagged (got %s)" % str(lam["diagnostics"]))
	_check_true("1 + 2" in str(lam["gd"]), "T1.4: lambda body stays in setup verbatim")

	# Unity 2102 fallback: a top-level return that is not `return (`/`return <`/`return null`.
	var malformed_src := "component M() {\n\treturn V.label({})\n}\n"
	var mal := RUIGuitkx.compile(malformed_src, "M")
	_check_true(not mal["ok"], "T1.4: malformed top-level return fails")
	_check_diag_at(mal, "GUITKX2102", malformed_src, "return V.label({})", "T1.4: malformed-return 2102 position")

	# Unity LooksLikeMarkupRoot parity: `return ( plain_expr )` is 2102 -- the window must hold
	# an element, fragment, @directive, or {expr}.
	var plain_src := "component P() {\n\treturn ( 1 + 2 )\n}\n"
	var plain := RUIGuitkx.compile(plain_src, "P")
	_check_true(not plain["ok"] and _has_code(plain, "GUITKX2102"), "T1.4: non-markup return window is 2102 (got %s)" % str(plain["diagnostics"]))

	# G9: a body that is ONLY an @for block (no return at all) must error missing-return.
	var g9_src := "component G9() {\n\t@for (i in 25) {\n\t\treturn ( <label text={ str(i) } /> )\n\t}\n}\n"
	var g9 := RUIGuitkx.compile(g9_src, "G9")
	_check_true(not g9["ok"] and _has_code(g9, "GUITKX2101"), "T1.4/G9: @for-only body errors missing-return (got %s)" % str(g9["diagnostics"]))

	# A `{expr}` root stays legal (LooksLikeMarkupRoot accepts `{`).
	var expr_src := "component E(items: Array = []) {\n\treturn ( { items.map(func(i): return <label text={ str(i) } />) } )\n}\n"
	var expr := RUIGuitkx.compile(expr_src, "E")
	_check_true(bool(expr["ok"]), "T1.4: {expr} root still compiles (got %s)" % str(expr["diagnostics"]))

func _test_t25_hook_contexts() -> void:
	# T2.5 (Unity 0013-0016): four contexts, each its own code, all ERRORS.
	var base := "component H(c: bool = true, xs: Array = []) {\n%s\treturn ( <label text=\"x\" /> )\n}\n"
	var rl := RUIGuitkx.compile(base % "\tfor x in xs:\n\t\tvar s = useState(0)\n", "H")
	_check_true(not rl["ok"] and _has_code(rl, "GUITKX0014"), "T2.5: hook in loop = 0014 (got %s)" % str(rl["diagnostics"]))
	var rm := RUIGuitkx.compile(base % "\tmatch c:\n\t\ttrue:\n\t\t\tvar s = useState(0)\n", "H")
	_check_true(not rm["ok"] and _has_code(rm, "GUITKX0015"), "T2.5: hook in match = 0015 (got %s)" % str(rm["diagnostics"]))
	var rf := RUIGuitkx.compile(base % "\tvar f = func():\n\t\tvar s = useState(0)\n", "H")
	_check_true(not rf["ok"] and _has_code(rf, "GUITKX0016"), "T2.5: hook in lambda = 0016 (got %s)" % str(rf["diagnostics"]))
	var ri := RUIGuitkx.compile(base % "\tif c: var s = useState(0)\n", "H")
	_check_true(not ri["ok"] and _has_code(ri, "GUITKX0013"), "T2.5: single-line if hook = 0013 (got %s)" % str(ri["diagnostics"]))

	# (d) markup-expression context: attr expr + child expr.
	var ra := RUIGuitkx.compile("component A() {\n\treturn ( <label text={ str(useState(0)[0]) } /> )\n}\n", "A")
	_check_true(not ra["ok"] and _has_code(ra, "GUITKX0016"), "T2.5: hook call in attr expr = 0016 (got %s)" % str(ra["diagnostics"]))
	var rc := RUIGuitkx.compile("component B() {\n\treturn ( <vbox>{ useState(0)[0] }</vbox> )\n}\n", "B")
	_check_true(not rc["ok"] and _has_code(rc, "GUITKX0016"), "T2.5: hook call in child expr = 0016 (got %s)" % str(rc["diagnostics"]))

	# NEGATIVES: top-level hook, hook RESULT in attr, look-alike identifier, member call.
	var ok_src := "component OK(c: bool = true) {\n" + \
		"\tvar s = useState(0)\n" + \
		"\tvar my_useState_thing = 1\n" + \
		"\tvar obj_call = s\n" + \
		"\treturn ( <label text={ str(s[0]) } on_pressed={ s[1] } /> )\n}\n"
	var rok := RUIGuitkx.compile(ok_src, "OK")
	_check_true(bool(rok["ok"]), "T2.5: top-level hook + result-in-attr stay clean (got %s)" % str(rok["diagnostics"]))

	# hook DECLARATION bodies are validated too (hooks compose hooks -- unconditionally).
	var rhb := RUIGuitkx.compile("hook use_bad(c: bool = false) {\n\tif c:\n\t\tvar s = useState(0)\n\treturn 1\n}\n", "use_bad")
	_check_true(not rhb["ok"] and _has_code(rhb, "GUITKX0013"), "T2.5: hook body validated (got %s)" % str(rhb["diagnostics"]))

func _test_t27_diag_ports() -> void:
	# T2.7 / Unity 0018: an effect hook with only a callback runs every render -- warn.
	var src18 := "component E() {\n\tuseEffect(func(): print(\"hi\"))\n\treturn ( <label text=\"x\" /> )\n}\n"
	var r18 := RUIGuitkx.compile(src18, "E")
	_check_true(bool(r18["ok"]), "T2.7: missing-deps effect still compiles")
	_check_diag_at(r18, "GUITKX0018", src18, "useEffect", "T2.7: 0018 lands on the call")
	var ok18 := RUIGuitkx.compile("component E2() {\n\tuseEffect(func(): print(\"hi\"), [])\n\treturn ( <label text=\"x\" /> )\n}\n", "E2")
	_check_true(bool(ok18["ok"]) and not _has_code(ok18, "GUITKX0018"), "T2.7: deps array satisfies 0018 (got %s)" % str(ok18["diagnostics"]))

	# T2.7 / Unity 0019: the loop variable used DIRECTLY as the key.
	var src19 := "component K(xs: Array = []) {\n\treturn ( <vbox>@for (x in xs) { return ( <label key={ x } text={ str(x) } /> ) }</vbox> )\n}\n"
	var r19 := RUIGuitkx.compile(src19, "K")
	_check_true(bool(r19["ok"]) and _has_code(r19, "GUITKX0019"), "T2.7: direct binder key warns 0019 (got %s)" % str(r19["diagnostics"]))
	var ok19 := RUIGuitkx.compile("component K2(xs: Array = []) {\n\treturn ( <vbox>@for (x in xs) { return ( <label key={ str(x) } text={ str(x) } /> ) }</vbox> )\n}\n", "K2")
	_check_true(not _has_code(ok19, "GUITKX0019"), "T2.7: derived key stays clean")

	# T2.7 / Unity 0111: a component parameter never referenced anywhere in the body.
	var src111 := "component U(used: int = 1, dead: int = 2, _ignored: int = 3) {\n\treturn ( <label text={ str(used) } /> )\n}\n"
	var r111 := RUIGuitkx.compile(src111, "U")
	_check_true(bool(r111["ok"]), "T2.7: unused param still compiles")
	_check_diag_at(r111, "GUITKX0111", src111, "dead", "T2.7: 0111 lands on the unused param")
	_check_true(str(_diag(r111, "GUITKX0111").get("message", "")).contains("dead"), "T2.7: only `dead` flagged (underscore exempt)")

	# T2.7 / Unity 0120/0121: res:// string literals in asset attributes must exist / match type.
	var src120 := "component A() {\n\treturn ( <texture_rect texture=\"res://no/such/file.png\" /> )\n}\n"
	var r120 := RUIGuitkx.compile(src120, "A")
	_check_true(not r120["ok"] and _has_code(r120, "GUITKX0120"), "T2.7: missing asset errors 0120 (got %s)" % str(r120["diagnostics"]))
	var src121 := "component B() {\n\treturn ( <texture_rect texture=\"res://project.godot\" /> )\n}\n"
	var r121 := RUIGuitkx.compile(src121, "B")
	_check_true(not r121["ok"] and _has_code(r121, "GUITKX0121"), "T2.7: wrong-type asset errors 0121 (got %s)" % str(r121["diagnostics"]))

func _test_severity_table() -> void:
	# T3.2: one severity per code, everywhere -- vocabulary.json `severities` is the single source and
	# this tripwire pins every D.make() literal in the compiler to it.
	var vocab: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://addons/reactive_ui/guitkx/vocabulary.json"))
	var sev_table: Dictionary = vocab.get("severities", {})
	_check_true(not sev_table.is_empty(), "T3.2: severities table present")
	var src := FileAccess.get_file_as_string("res://addons/reactive_ui/guitkx/guitkx.gd")
	var re := RegEx.new()
	re.compile("D\\.make\\(\"(GUITKX\\d+)\", D\\.(ERROR|WARNING|HINT)")
	var names := { "ERROR": "error", "WARNING": "warning", "HINT": "hint" }
	var checked := 0
	for m in re.search_all(src):
		var code := m.get_string(1)
		var sev := str(names[m.get_string(2)])
		if not sev_table.has(code):
			_fail("T3.2: %s missing from the severity table" % code)
			continue
		_check_true(str(sev_table[code]) == sev, "T3.2: %s severity matches the table (site %s vs table %s)" % [code, sev, sev_table[code]])
		checked += 1
	_check_true(checked >= 25, "T3.2: table-driven check saw %d sites" % checked)
	for lc in vocab.get("live", []):
		_check_true(sev_table.has(lc), "T3.2: live code %s has a severity" % str(lc))

func _test_t35_parser_bugs() -> void:
	# T3.5: a commented `#elif` is NOT a ghost branch anymore -- it falls to literal text.
	var src06 := "component X(c: bool = true) {\n\treturn (\n\t\t<vbox>\n\t\t\t@if (c) { return ( <label text=\"a\" /> ) }\n\t\t\t#elif (false) { <label text=\"b\" /> }\n\t\t</vbox>\n\t)\n}\n"
	var r06 := RUIGuitkx.compile(src06, "X")
	_check_true(bool(r06["ok"]) and not ("elif false" in str(r06["gd"])), "T3.5: #elif is not a ghost branch (got %s)" % str(r06["diagnostics"]))

	# digit / dotted tags are parse errors now (used to emit nonsense silently).
	_check_true(not RUIGuitkx.compile("component X() {\n\treturn ( <9foo/> )\n}\n", "X")["ok"], "T3.5: digit tag errors")
	var rdot := RUIGuitkx.compile("component X() {\n\treturn ( <Foo.Bar/> )\n}\n", "X")
	_check_true(not rdot["ok"] and _has_code(rdot, "GUITKX0300"), "T3.5: dotted tag errors (got %s)" % str(rdot["diagnostics"]))

	# unterminated attribute string errors at the quote (used to truncate silently).
	var r09 := RUIGuitkx.compile("component X() {\n\treturn (\n\t\t<label text=\"oops\n\t)\n}\n", "X")
	_check_true(not r09["ok"] and _has_code(r09, "GUITKX0300"), "T3.5: unterminated attr string errors (got %s)" % str(r09["diagnostics"]))

	# directive keywords need a token boundary.
	var rb := RUIGuitkx.compile("@class_nameFoo\ncomponent A() {\n\treturn ( <label text=\"x\" /> )\n}\n", "A")
	_check_true(not rb["ok"] and _has_code(rb, "GUITKX2105"), "T3.5: @class_nameFoo is junk, not a directive (got %s)" % str(rb["diagnostics"]))

	# jsx_scan: markup after `or` desugars (used to emit the raw markup as invalid GDScript).
	var ror := RUIGuitkx.compile("component O(ready: bool = false) {\n\treturn ( <vbox>{ ready or <label text=\"waiting\" /> }</vbox> )\n}\n", "O")
	_check_true(bool(ror["ok"]), "T3.5: `or <markup>` compiles (got %s)" % str(ror["diagnostics"]))
	_check_true("if not (ready) else null" in str(ror["gd"]), "T3.5: or-desugar emitted")

func _test_t23_uss() -> void:
	# T2.3 (Unity @uss): preloads a Theme and applies it to the root element's `theme` prop.
	var src := "@uss \"res://tests/assets/test_theme.tres\"\ncomponent T() {\n\treturn ( <vbox><label text=\"x\" /></vbox> )\n}\n"
	var r := RUIGuitkx.compile(src, "T")
	_check_true(bool(r["ok"]), "T2.3: @uss compiles (got %s)" % str(r["diagnostics"]))
	_check(str(r["gd"]), "const __THEME := preload(\"res://tests/assets/test_theme.tres\")", "T2.3: theme preload emitted")
	_check(str(r["gd"]), "\"theme\": __THEME", "T2.3: root element receives the theme prop")

	# @theme alias behaves identically.
	var ra := RUIGuitkx.compile("@theme \"res://tests/assets/test_theme.tres\"\ncomponent T2() {\n\treturn ( <vbox><label text=\"x\" /></vbox> )\n}\n", "T2")
	_check_true(bool(ra["ok"]) and "__THEME" in str(ra["gd"]), "T2.3: @theme alias works")

	# an explicit root theme wins -- no injection.
	var re3 := RUIGuitkx.compile("@uss \"res://tests/assets/test_theme.tres\"\ncomponent T3(t: Theme = null) {\n\treturn ( <vbox theme={ t }><label text=\"x\" /></vbox> )\n}\n", "T3")
	_check_true(bool(re3["ok"]) and not ("__THEME }" in str(re3["gd"])) and str(re3["gd"]).count("\"theme\"") == 1, "T2.3: explicit theme not overridden")

	# missing path -> 0120; wrong type -> 0121; hook file -> 2210; two directives -> 2210.
	var rm := RUIGuitkx.compile("@uss \"res://no/such/theme.tres\"\ncomponent T4() {\n\treturn ( <label text=\"x\" /> )\n}\n", "T4")
	_check_true(not rm["ok"] and _has_code(rm, "GUITKX0120"), "T2.3: missing theme errors 0120 (got %s)" % str(rm["diagnostics"]))
	var rt2 := RUIGuitkx.compile("@uss \"res://project.godot\"\ncomponent T5() {\n\treturn ( <label text=\"x\" /> )\n}\n", "T5")
	_check_true(not rt2["ok"] and _has_code(rt2, "GUITKX0121"), "T2.3: non-Theme errors 0121 (got %s)" % str(rt2["diagnostics"]))
	var rh2 := RUIGuitkx.compile("@uss \"res://tests/assets/test_theme.tres\"\nhook use_x() {\n\treturn 1\n}\n", "use_x")
	_check_true(not rh2["ok"] and _has_code(rh2, "GUITKX2210"), "T2.3: @uss in a hook file errors 2210 (got %s)" % str(rh2["diagnostics"]))
	var rd := RUIGuitkx.compile("@uss \"res://tests/assets/test_theme.tres\"\n@uss \"res://tests/assets/test_theme.tres\"\ncomponent T6() {\n\treturn ( <label text=\"x\" /> )\n}\n", "T6")
	_check_true(not rd["ok"] and _has_code(rd, "GUITKX2210"), "T2.3: second @uss errors (got %s)" % str(rd["diagnostics"]))

func _test_t26_naming() -> void:
	# T2.6 (Unity 2100): component names are PascalCase -- they become the generated class_name.
	var src := "component my_widget() {\n\treturn ( <label text=\"x\" /> )\n}\n"
	var r := RUIGuitkx.compile(src, "my_widget")
	_check_true(not r["ok"], "T2.6: lowercase component name fails")
	_check_diag_at(r, "GUITKX2100", src, "my_widget", "T2.6: 2100 lands on the name")

	# T2.6 (Unity 2203): hooks should be use_-prefixed -- warning, still compiles.
	var src_h := "hook make_thing() {\n\treturn 1\n}\n"
	var rh := RUIGuitkx.compile(src_h, "make_thing")
	_check_true(bool(rh["ok"]), "T2.6: non-use_ hook still compiles")
	_check_diag_at(rh, "GUITKX2203", src_h, "make_thing", "T2.6: 2203 lands on the hook name")

	# T2.6: real content BEFORE the first declaration errors instead of being silently skipped.
	var src_j := "var oops = 1\ncomponent A() {\n\treturn ( <label text=\"x\" /> )\n}\n"
	var rj := RUIGuitkx.compile(src_j, "A")
	_check_true(not rj["ok"], "T2.6: junk before the declaration fails")
	_check_diag_at(rj, "GUITKX2105", src_j, "var oops = 1", "T2.6: leading-junk 2105 position")
	_check_true(bool(RUIGuitkx.compile("# header\ncomponent A() {\n\treturn ( <label text=\"x\" /> )\n}\n", "A")["ok"]), "T2.6: leading comments stay legal")

func _test_p2_markup_features() -> void:
	# T2.1: all four comment forms parse, emit nothing, and don't count as roots/children.
	var src := "component C() {\n" + \
		"\treturn (\n" + \
		"\t\t// leading note\n" + \
		"\t\t<vbox>\n" + \
		"\t\t\t/* block\n\t\t\t   note */\n" + \
		"\t\t\t<label {/* attr note */} text=\"a\" />\n" + \
		"\t\t\t<!-- html-style -->\n" + \
		"\t\t</vbox>\n" + \
		"\t)\n}\n"
	var r := RUIGuitkx.compile(src, "C")
	_check_true(bool(r["ok"]), "T2.1: comments compile (got %s)" % str(r["diagnostics"]))
	var gd_out := str(r["gd"])
	_check_true(not ("note" in gd_out) and not ("<!--" in gd_out), "T2.1: comments emit nothing")

	# T2.2: <Fragment> is the named alias of <> (case-insensitive, Unity PropsResolver parity).
	var src_f := "component F() {\n" + \
		"\treturn (\n\t\t<Fragment>\n\t\t\t<label text=\"a\" />\n\t\t\t<label text=\"b\" />\n\t\t</Fragment>\n\t)\n}\n"
	var rf := RUIGuitkx.compile(src_f, "F")
	_check_true(bool(rf["ok"]), "T2.2: <Fragment> compiles (got %s)" % str(rf["diagnostics"]))
	_check(str(rf["gd"]), "V.fragment([", "T2.2: named fragment emits V.fragment")
	var src_fk := "component FK() {\n\treturn ( <vbox>@for (i in 3) { return ( <Fragment key={ str(i) }><label text={ str(i) } /></Fragment> ) }</vbox> )\n}\n"
	var rfk := RUIGuitkx.compile(src_fk, "FK")
	_check_true(bool(rfk["ok"]), "T2.2: Fragment key compiles (got %s)" % str(rfk["diagnostics"]))
	_check_true(", str(i))" in str(rfk["gd"]), "T2.2: fragment key threads to V.fragment's 2nd arg")
	var rfb := RUIGuitkx.compile("component FB() {\n\treturn ( <Fragment visible><label text=\"x\" /></Fragment> )\n}\n", "FB")
	_check_true(not rfb["ok"] and _has_code(rfb, "GUITKX0109"), "T2.2: non-key Fragment attr errors (got %s)" % str(rfb["diagnostics"]))

	# T2.4: mid-text braces are LITERAL + 0150 migration warning; node-start {expr} still interpolates.
	var src_t := "component T(n: int = 3) {\n\treturn ( <label>Count: {n} items</label> )\n}\n"
	var rt := RUIGuitkx.compile(src_t, "T")
	_check_true(bool(rt["ok"]), "T2.4: literal-brace text compiles (got %s)" % str(rt["diagnostics"]))
	_check_true(_has_code(rt, "GUITKX0150"), "T2.4: 0150 migration warning fires")
	_check_true("Count: {n} items" in str(rt["gd"]), "T2.4: braces stay literal in emission")
	var re2 := RUIGuitkx.compile("component E(n: int = 3) {\n\treturn ( <label>{ n } items</label> )\n}\n", "E")
	_check_true(bool(re2["ok"]) and not _has_code(re2, "GUITKX0150"), "T2.4: node-start expr interpolates without warning (got %s)" % str(re2["diagnostics"]))
	_check_true("str(n)" in str(re2["gd"]), "T2.4: node-start expr emits interpolation")

	# T2.1+T2.4: formatter round-trips comments and literal-brace text (idempotent, no data loss).
	const Fmt2 = preload("res://addons/reactive_ui/guitkx/guitkx_formatter.gd")
	var f1: Dictionary = Fmt2.format(src)
	_check(str(f1["text"]), "// leading note", "T2.1: formatter preserves the leading comment")
	_check(str(f1["text"]), "{/* attr note */}", "T2.1: formatter preserves the attr comment")
	_check(str(f1["text"]), "<!-- html-style -->", "T2.1: formatter preserves the html comment")
	_check_true(str(Fmt2.format(str(f1["text"]))["text"]) == str(f1["text"]), "T2.1: comment formatting is idempotent")
	var ff: Dictionary = Fmt2.format(src_f)
	_check(str(ff["text"]), "<Fragment>", "T2.2: formatter keeps the named Fragment spelling")

func _test_t15_unknown_tags() -> void:
	# T1.5 (G5): a lowercase tag must be a real V.* factory -- it compiles to a verbatim V.<tag>()
	# call, so an unknown one was a guaranteed nonexistent-method failure at runtime.
	var src := "component T() {\n\treturn ( <vbox><lable text=\"x\" /></vbox> )\n}\n"
	var r := RUIGuitkx.compile(src, "T")
	_check_true(not r["ok"], "T1.5: unknown lowercase tag fails the compile")
	_check_diag_at(r, "GUITKX0105", src, "lable", "T1.5: 0105 lands on the tag name")
	_check_true("did you mean <label>" in str(_diag(r, "GUITKX0105").get("message", "")), "T1.5: did-you-mean suggests label (got %s)" % str(_diag(r, "GUITKX0105")))

	# the user's G5 repro: `<s></a>` -- mismatched close, fails, both tags implicated by the parser.
	var g5 := "component S() {\n\treturn ( <s></a> )\n}\n"
	var rg5 := RUIGuitkx.compile(g5, "S")
	_check_true(not rg5["ok"] and _has_code(rg5, "GUITKX0302"), "T1.5/G5: <s></a> mismatched close fails (got %s)" % str(rg5["diagnostics"]))

	# PascalCase components: checked only when the caller supplies known_components.
	var pc_src := "component P() {\n\treturn ( <vbox><Cardd /></vbox> )\n}\n"
	_check_true(bool(RUIGuitkx.compile(pc_src, "P")["ok"]), "T1.5: PascalCase unchecked without a known set")
	var rp := RUIGuitkx.compile(pc_src, "P", ["Card", "Row"])
	_check_true(not rp["ok"], "T1.5: unknown PascalCase fails with a known set")
	_check_diag_at(rp, "GUITKX0105", pc_src, "Cardd", "T1.5: PascalCase 0105 position")
	_check_true("did you mean <Card>" in str(_diag(rp, "GUITKX0105").get("message", "")), "T1.5: suggests Card")
	_check_true(bool(RUIGuitkx.compile("component P2() {\n\treturn ( <vbox><Card /></vbox> )\n}\n", "P2", ["Card"])["ok"]), "T1.5: known PascalCase passes")

	# module-local members are always known, regardless of the external set.
	var mod_src := "module W {\n\tcomponent Card() { return ( <label text=\"c\" /> ) }\n\tcomponent Row() { return ( <hbox><Card /></hbox> ) }\n}\n"
	_check_true(bool(RUIGuitkx.compile(mod_src, "W", ["SomethingElse"])["ok"]), "T1.5: module-local <Card/> resolves")

	# unknown tag nested inside a JSX-value {expr} -- the emit-only path.
	var ex_src := "component E(open: bool = false) {\n\treturn ( <vbox>{ open and <lable text=\"x\" /> }</vbox> )\n}\n"
	var re := RUIGuitkx.compile(ex_src, "E")
	_check_true(not re["ok"] and _has_code(re, "GUITKX0105"), "T1.5: unknown tag inside {expr} caught (got %s)" % str(re["diagnostics"]))

	# codegen integration: known_component_names resolves sibling bindings + @class_name overrides.
	var names: Array = Codegen.known_component_names([])
	_check_true(names is Array, "T1.5: known_component_names runs headless (global classes only)")

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

# Phase D acceptance: the Unity kitchen-sink nesting translated to guitkx -- 4 directive levels
# (@for -> markup -> @if/@else -> @for -> @if -> @for), prep vars at every level, a prep-markup
# variable consumed via {expr}, a `return null` skip-guard, and an @else arm -- compiled, parsed,
# MOUNTED, and the exact rendered Label count asserted (null-skip and branch choice are load-bearing).
func _test_phase_d_bodies() -> void:
	var src := """component Deep(cats: Array = ["A", "B"], n: int = 2, mode: String = "x") {
	var pills = ["x", "y", "z"]
	return (
		<VBox>
			@for (cat in cats) {
				var badge = (
					<HBox>
						<Label text={ cat } />
						@if (mode != "") {
							return ( <Label text={ "[" + mode + "]" } /> )
						}
					</HBox>
				)
				return (
					<VBox key={ cat }>
						{ badge }
						@for (d in n) {
							var frac := float(d) / maxi(1, n - 1)
							return (
								<VBox key={ cat + str(d) }>
									<Label text={ "depth %d %.1f" % [d, frac] } />
									@if (d % 2 == 0) {
										var slot = "even " + cat
										return (
											<HBox>
												<Label text={ slot } />
												@for (tag in pills) {
													if tag == "z" and d == 0:
														return null
													return ( <Label key={ tag } text={ tag } /> )
												}
											</HBox>
										)
									} @else {
										return ( <Label text="odd" /> )
									}
								</VBox>
							)
						}
					</VBox>
				)
			}
		</VBox>
	)
}"""
	var r := RUIGuitkx.compile(src, "Deep")
	if not bool(r["ok"]):
		_fail("phase_d_bodies: compile failed: " + str(r["diagnostics"]))
		return
	var sc := GDScript.new()
	sc.source_code = str(r["gd"]).replace("class_name Deep\n", "")
	if sc.reload() != OK:
		_fail("phase_d_bodies: generated .gd does not parse:\n" + str(r["gd"]))
		return
	var c := Control.new()
	root.add_child(c)
	var inst = sc.new()
	var app := ReactiveRoot.create(c, V.fc(inst.render, {}))
	var count := _count_labels(c)
	# per cat: badge (cat + [mode]) = 2; d=0 even: depth + slot + pills minus z = 4; d=1 odd: depth + odd = 2
	# -> 8 per cat x 2 cats = 16. The z-skip at d=0 and the @else arm are both load-bearing here.
	_check_true(count == 16, "phase D 4-deep render: 16 labels expected, got %d" % count)
	app.unmount()
	c.free()

func _count_labels(node: Node) -> int:
	var n := 1 if node is Label else 0
	for ch in node.get_children():
		n += _count_labels(ch)
	return n

func _test_formatter() -> void:
	const Fmt = preload("res://addons/reactive_ui/guitkx/guitkx_formatter.gd")
	var src := "component  Foo( name: String = \"x\" )  {\n" + \
		"  var s = useState(0)\n" + \
		"  return (\n" + \
		"<VBox>\n" + \
		"<Label text={ name }/>\n" + \
		"@if (s[0] > 0) { return ( <Label text=\"big\" /> ) }\n" + \
		"</VBox>\n" + \
		"  )\n" + \
		"}\n"
	var r1 := Fmt.format(src)
	_check_true(r1["ok"], "formatter ok")
	var f1: String = r1["text"]
	print("--- formatted ---\n" + f1 + "---")
	_check(f1, "component Foo(name: String = \"x\") {", "header canonicalized")
	_check(f1, "    <VBox>", "markup indented (spaces-2 default, Phase D)")
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
	_check_true(RUIGuitkx.host_tags().get("VBoxContainer", "") == "vbox" and RUIGuitkx.host_tags().size() >= 39,
		"host_tags() loaded from vocabulary.json (aliases included, got %d)" % RUIGuitkx.host_tags().size())
	_check_true("useState" in RUIGuitkx.hook_names() and RUIGuitkx.hook_names().size() == 23,
		"hook_names() loaded from vocabulary.json (got %d)" % RUIGuitkx.hook_names().size())
	# …and v_factories must mirror the REAL public V API (reflection tripwire: adding/removing a
	# static func on core/v.gd without updating vocabulary.json fails here with the exact diff).
	var v_script: Script = preload("res://addons/reactive_ui/core/v.gd")
	var reflected: Array = []
	for m in v_script.get_script_method_list():
		var mname: String = m["name"]
		if not mname.begins_with("_") and not (mname in reflected):
			reflected.append(mname)
	reflected.sort()
	var vocab: Array = (RUIGuitkx.v_factories() as Array).duplicate()
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
	# T2.5 (Unity parity): rules-of-hooks violations are ERRORS and fail the compile.
	_check_true(int(_diag(roh, "GUITKX0013").get("severity", -9)) == GDiag.ERROR, "GUITKX0013 is an error")
	_check_true(not roh["ok"], "T2.5: conditional hook fails the compile")
	# duplicate literal keys among siblings — flagged at the SECOND key attribute
	var dk_src := "component Dup() {\n\treturn (\n\t\t<VBox>\n\t\t\t<Label key=\"x\" />\n\t\t\t<Label key=\"x\" />\n\t\t</VBox>\n\t)\n}\n"
	var dk := RUIGuitkx.compile(dk_src, "Dup")
	_check_diag_at(dk, "GUITKX0104", dk_src, "key=\"x\"", "duplicate-key")
	_check_true(int(_diag(dk, "GUITKX0104").get("offset", -1)) > dk_src.find("key=\"x\""), "GUITKX0104 anchors to the SECOND duplicate, not the first")
	# loop child missing key — flagged at the element
	var lk_src := "component LK(items: Array = []) {\n\treturn (\n\t\t<VBox>\n\t\t\t@for (it in items) { return ( <Label text={ it } /> ) }\n\t\t</VBox>\n\t)\n}\n"
	var lk := RUIGuitkx.compile(lk_src, "LK")
	_check_diag_at(lk, "GUITKX0106", lk_src, "<Label text={ it }", "keyless-loop-child")
	# a clean component emits no warnings
	var clean := RUIGuitkx.compile("component Clean() {\n\tvar a = useState(0)\n\treturn ( <Label text={ str(a[0]) } /> )\n}\n", "Clean")
	_check_true(clean["ok"] and (clean["diagnostics"] as Array).is_empty(), "clean component has no diagnostics (got %s)" % str(clean["diagnostics"]))

func _test_loop_single_root() -> void:
	# BUG-V3: a @for/@while body with >1 sibling root is a hard error (single-root; parity Unity UITKX0108)
	var multi := RUIGuitkx.compile("component M(n: int = 3) {\n" + \
		"\treturn (\n\t\t<VBox>\n" + \
		"\t\t\t@for (i in n) {\n\t\t\t\treturn (\n\t\t\t\t<Label key={ str(i) } />\n\t\t\t\t<Label key={ str(i) } />\n\t\t\t\t)\n\t\t\t}\n" + \
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
		"\t\t\t@for (i in n) {\n\t\t\t\treturn (\n\t\t\t\t<>\n\t\t\t\t\t<Label key={ \"a\" + str(i) } />\n\t\t\t\t\t<Label key={ \"b\" + str(i) } />\n\t\t\t\t</>\n\t\t\t\t)\n\t\t\t}\n" + \
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
	_check_true(not typo["ok"] and str(_diag(typo, "GUITKX2101").get("message", "")).contains("did you mean 'component'"), "misspelled keyword suggests component (got %s)" % str(typo["diagnostics"]))
	_check_diag_at(typo, "GUITKX2101", typo_src, "componeent", "misspelled keyword")
	# BUG-V4: a space after `<` is an invalid tag name, not a silent fragment
	var badtag := RUIGuitkx.compile("component B() {\n\treturn ( <  a> )\n}\n", "B")
	_check_true(not badtag["ok"] and _has_code(badtag, "GUITKX0300"), "invalid tag name rejected (got %s)" % str(badtag["diagnostics"]))
	# BUG-V5 (T1.4 semantics): code after the LAST top-level markup return is flagged unreachable
	# (GUITKX0107 warning) at the dead code; the compile still succeeds.
	var unreach_src := "component U() {\n\treturn ( <Label /> )\n\tvar x = 5\n}\n"
	var unreach := RUIGuitkx.compile(unreach_src, "U")
	_check_true(bool(unreach["ok"]), "unreachable code is a warning, not an error (got %s)" % str(unreach["diagnostics"]))
	_check_diag_at(unreach, "GUITKX0107", unreach_src, "var x = 5", "unreachable-after-return")

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
	_check_true(not er["ok"] and _has_code(er, "GUITKX2101"), "no-declaration rejected with GUITKX2101")

func _test_match() -> void:
	var src := "component Status(state: String = \"idle\") {\n" + \
		"\treturn (\n" + \
		"\t\t<VBox>\n" + \
		"\t\t\t@match (state) {\n" + \
		"\t\t\t\t@case (\"loading\") { return ( <Label text=\"Loading...\" /> ) }\n" + \
		"\t\t\t\t@case (\"done\") { return ( <Label text=\"Done!\" /> ) }\n" + \
		"\t\t\t\t@default { return ( <Label text=\"Idle\" /> ) }\n" + \
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
	# The env guard: an UNREADABLE VOCABULARY is a tooling state, not a source regression — the
	# compile must refuse (env_error + GUITKX2507) and compile_file must PRESERVE the sibling .gd
	# and the sidecar (during the editor's first filesystem scan this exact state once wiped every
	# generated demo .gd on a fresh CI clone). The lazy loader then self-heals on the next call.
	var sidecar_before := FileAccess.get_file_as_string(gx + ".diags.json")
	RUIGuitkx._VOCAB = {}
	RUIGuitkx._VOCAB_PATH = "res://addons/reactive_ui/guitkx/__no_such_vocabulary__.json"
	var r_env := Codegen.compile_file(gx)
	_check_true(not r_env["ok"] and bool(r_env.get("env_error", false)), "unreadable vocabulary is an env_error: " + str(r_env))
	_check_true(str((r_env["diagnostics"] as Array)[0]["code"]) == "GUITKX2507", "env_error carries GUITKX2507")
	_check_true(FileAccess.file_exists(gd), "sibling .gd PRESERVED on env_error (never stale-deleted)")
	_check_true(FileAccess.get_file_as_string(gx + ".diags.json") == sidecar_before, "sidecar untouched on env_error")
	RUIGuitkx._VOCAB_PATH = "res://addons/reactive_ui/guitkx/vocabulary.json"
	_check_true(Codegen.compile_file(gx)["ok"], "vocabulary self-heals on the next compile (lazy retry)")
	# T1.1: a file that STOPS compiling must not leave its stale sibling .gd behind (the editor would
	# keep running code that no longer matches the source). compile_file deletes it.
	var f_bad := FileAccess.open(gx, FileAccess.WRITE)
	f_bad.store_string("component Fixture() {\n\treturn ( <Broken> )\n}\n")
	f_bad.close()
	var r_bad := Codegen.compile_file(gx)
	_check_true(not r_bad["ok"], "broken rewrite fails to compile")
	_check_true(not FileAccess.file_exists(gd), "stale sibling .gd deleted on failed compile")
	# 0.7.1: a KNOWN-BROKEN file (sidecar hash-matches the current content and carries an error
	# entry) is NOT stale -- the watch poll must not busy-recompile it every _POLL_SECS -- but its
	# persisted verdict stays visible through sidecar_error_diags (compile_all re-surfaces it on
	# every sweep; the dock dedup is what prevents spam, never silence).
	_check_true(not Codegen.is_stale(gx), "known-broken content is not stale (sidecar hash-match + error entry)")
	_check_true(Codegen.sidecar_error_diags(gx).size() > 0, "sidecar_error_diags surfaces the persisted verdict")
	# fix it again -> the .gd comes back
	var f_fix := FileAccess.open(gx, FileAccess.WRITE)
	f_fix.store_string(src)
	f_fix.close()
	_check_true(Codegen.compile_file(gx)["ok"], "fixed file compiles again")
	_check_true(FileAccess.file_exists(gd), "sibling .gd regenerated after the fix")
	# delete the .gd -> stale again (missing-file branch: the sidecar is CLEAN for this content, so
	# its absence of an error verdict must not mask a manually-removed output)
	DirAccess.remove_absolute(gd)
	_check_true(Codegen.is_stale(gx), "stale again after sibling .gd removed")
	DirAccess.remove_absolute(gx + ".diags.json")
	DirAccess.remove_absolute(gx)
	# has_stale: the watch-poll predicate (0.7.1) -- false while everything is fresh or known-broken,
	# true the moment content changes. Mtimes are whole seconds, so a save landing in the same second
	# as the last compile ties on mtime; the tie is broken by CONTENT (sidecar src_hash), which makes
	# this deterministic where bare `>` silently missed it ("saved it and Godot never recompiled").
	var hs_dir := "res://tests/__has_stale_tmp"
	DirAccess.make_dir_recursive_absolute(hs_dir)
	if Codegen.compiler_changed():
		Codegen.compile_all(hs_dir)   # settle the fingerprint marker so has_stale reflects FILE state
	var hgx := hs_dir + "/probe.guitkx"
	var hf := FileAccess.open(hgx, FileAccess.WRITE)
	hf.store_string("component Probe() {\n\treturn ( <Label text=\"a\" /> )\n}\n")
	hf.close()
	_check_true(Codegen.has_stale(hs_dir), "fresh .guitkx with no sibling .gd reads stale")
	_check_true(Codegen.compile_file(hgx)["ok"], "probe compiles")
	var hf2 := FileAccess.open(hgx, FileAccess.WRITE)   # rewrite lands in the SAME mtime second
	hf2.store_string("component Probe() {\n\treturn ( <Label text=\"b\" /> )\n}\n")
	hf2.close()
	_check_true(Codegen.is_stale(hgx), "a save in the same second as the last compile is stale (mtime tie, hash differs)")
	_check_true(Codegen.compile_file(hgx)["ok"], "probe recompiles")
	var hbad := FileAccess.open(hgx, FileAccess.WRITE)
	hbad.store_string("component Probe() {\n\treturn ( <Broken> )\n}\n")
	hbad.close()
	_check_true(not Codegen.compile_file(hgx)["ok"], "broken probe errors")
	_check_true(not Codegen.has_stale(hs_dir), "known-broken probe does not keep the watch poll hot")
	var hsweep := Codegen.compile_all(hs_dir)
	_check_true((hsweep["errors"] as Array).size() == 1 and (hsweep["compiled"] as Array).is_empty(),
		"sweep re-surfaces the persisted error without recompiling: " + str(hsweep))
	_check_true(int(hsweep.get("total", -1)) == 1, "sweep reports the tracked total")
	DirAccess.remove_absolute(hgx + ".diags.json")
	DirAccess.remove_absolute(hgx)   # (the probe .gd was already T1.1-deleted by the broken compile)

func _test_cold_open_recovery() -> void:
	# R0 (0.6.1): the vocabulary the compiler actually uses is the EMBEDDED const projection
	# (guitkx_vocabulary.gen.gd) -- it must never drift from vocabulary.json, the single source of
	# truth shared verbatim with the LSP. Regenerate with dev/gen_vocabulary.gd after any change.
	var gen = preload("res://addons/reactive_ui/guitkx/guitkx_vocabulary.gen.gd")
	var json_text := FileAccess.get_file_as_string("res://addons/reactive_ui/guitkx/vocabulary.json")
	var parsed = JSON.parse_string(json_text)
	_check_true(parsed is Dictionary, "vocabulary.json parses")
	_check_true(JSON.stringify(parsed) == JSON.stringify(gen.DATA),
		"guitkx_vocabulary.gen.gd in sync with vocabulary.json (regenerate: dev/gen_vocabulary.gd)")
	RUIGuitkx._VOCAB = {}
	_check_true(not RUIGuitkx.vocab().is_empty(), "vocab() serves the embedded const at the default path")
	# Editor static-init reality (2026-07-04, THE "Godot never recompiles" root cause): during the
	# editor's early script indexing `static var` INITIALIZERS may not have run, so _VOCAB_PATH
	# reads as "" (String type default) -- which used to fall into the test-seam file branch, read
	# a file at path "", and hold every compile of every editor session forever. Headless runs
	# initialize statics and were always healthy -- exactly why no suite ever caught it. An empty
	# path must therefore behave as DEFAULT (embedded const, no file read, no hold).
	RUIGuitkx._VOCAB = {}
	RUIGuitkx._VOCAB_PATH = ""
	_check_true(not RUIGuitkx.vocab().is_empty(), "an uninitialized-static ('') vocab path serves the embedded const")
	RUIGuitkx._VOCAB_PATH = RUIGuitkx._VOCAB_PATH_DEFAULT
	RUIGuitkx._VOCAB = {}
	# R2+R3 (0.6.1): a sweep hitting the unreadable-vocabulary environment reports those files as
	# HELD -- not errors (no per-file dock line; the loader's hold warning announced the episode) --
	# and must NOT consume the compiler-changed fingerprint marker: a held forced sweep compiled
	# nothing, so the force has to re-fire next sweep, or old-compiler outputs and sidecars survive
	# every later sweep (the 2026-07-03 zombie-sidecar field capture).
	var dir := "res://tests/__cold_open_tmp"
	DirAccess.make_dir_recursive_absolute(dir)
	var gx := dir + "/held_fixture.guitkx"
	var f := FileAccess.open(gx, FileAccess.WRITE)
	f.store_string("component HeldFixture(msg: String = \"hi\") {\n\treturn ( <Label text={ msg } /> )\n}\n")
	f.close()
	var marker := "res://.godot/rui_guitkx_compiler.fp"
	if FileAccess.file_exists(marker):
		DirAccess.remove_absolute(marker)   # -> compiler_changed() == true: the next sweep is FORCED
	RUIGuitkx._VOCAB = {}
	RUIGuitkx._VOCAB_PATH = "res://addons/reactive_ui/guitkx/__no_such_vocabulary__.json"
	var held_sweep := Codegen.compile_all(dir)
	_check_true((held_sweep["compiled"] as Array).is_empty() and (held_sweep["errors"] as Array).is_empty(),
		"held sweep reports no compiles and NO errors: " + str(held_sweep))
	_check_true((held_sweep["held"] as Array) == [gx], "env-held file lands in held[]: " + str(held_sweep["held"]))
	_check_true(not FileAccess.file_exists(marker), "fingerprint marker NOT consumed by a held forced sweep")
	# Environment recovers (default path -> embedded const): the same sweep now compiles, holds
	# nothing, and the fingerprint marker finally lands.
	RUIGuitkx._VOCAB_PATH = RUIGuitkx._VOCAB_PATH_DEFAULT
	RUIGuitkx._VOCAB = {}
	var ok_sweep := Codegen.compile_all(dir)
	_check_true((ok_sweep["held"] as Array).is_empty() and (ok_sweep["errors"] as Array).is_empty(),
		"recovered sweep holds nothing: " + str(ok_sweep))
	_check_true((ok_sweep["compiled"] as Array).size() == 1, "recovered sweep compiles the previously-held file")
	_check_true(bool(((ok_sweep["compiled"] as Array)[0] as Dictionary).get("gd_ok", false)),
		"sweep entries carry gd_ok (the HMR push filters on it)")
	_check_true(FileAccess.file_exists(marker), "fingerprint marker written once the forced sweep actually ran")
	# The persisted marker must be THIS process's healthily-computed fingerprint — never "" and
	# never a value hashed over scan-window empty reads (compiler_fingerprint returns "" then and
	# _write_fp_marker refuses to persist it).
	_check_true(Codegen.compiler_fingerprint() != "" and FileAccess.get_file_as_string(marker) == Codegen.compiler_fingerprint(),
		"marker holds the readable-sources fingerprint")
	DirAccess.remove_absolute(Codegen.gd_path_for(gx))
	DirAccess.remove_absolute(gx + ".diags.json")
	DirAccess.remove_absolute(gx)
	# 0.6.2: an empty SOURCE read of an existing file is the scan-window flake -- held (outputs
	# kept, env_error), never a compile failure (which would T1.1-delete the healthy sibling .gd).
	var gx2 := dir + "/empty_read.guitkx"
	var f2 := FileAccess.open(gx2, FileAccess.WRITE)
	f2.store_string("component EmptyRead() {\n\treturn ( <Label text=\"x\" /> )\n}\n")
	f2.close()
	var r_ok := Codegen.compile_file(gx2)
	_check_true(bool(r_ok["ok"]) and bool(r_ok.get("gd_parse_ok", false)), "healthy fixture compiles and its generated .gd parses: " + str(r_ok))
	var gd2 := Codegen.gd_path_for(gx2)
	var f3 := FileAccess.open(gx2, FileAccess.WRITE)   # truncate to empty = the flake, simulated
	f3.close()
	var r_empty := Codegen.compile_file(gx2)
	_check_true(not r_empty["ok"] and bool(r_empty.get("env_error", false)), "empty source read is HELD (env), not a compile failure: " + str(r_empty))
	_check_true(FileAccess.file_exists(gd2), "sibling .gd preserved on an empty source read")
	# 0.6.2: an unknown identifier is legal guitkx (a GDScript-level concern), but the generated
	# .gd is parse-checked immediately on a throwaway GDScript (Unity parity: errors surface at
	# compile time in the dock, not on first load at play time).
	var f4 := FileAccess.open(gx2, FileAccess.WRITE)
	f4.store_string("component EmptyRead() {\n\treturn ( <Label text={ str(slisced[0]) } /> )\n}\n")
	f4.close()
	var r_typo := Codegen.compile_file(gx2)
	_check_true(bool(r_typo["ok"]), "unknown identifier still compiles at the guitkx level: " + str(r_typo))
	_check_true(not bool(r_typo.get("gd_parse_ok", true)), "generated .gd parse-check FAILS on the unknown identifier")
	DirAccess.remove_absolute(gd2)
	DirAccess.remove_absolute(gx2 + ".diags.json")
	DirAccess.remove_absolute(gx2)
	DirAccess.remove_absolute(dir)

func _test_control_flow() -> void:
	var src := "component List2(items: Array = [], show_header: bool = true) {\n" + \
		"\treturn (\n" + \
		"\t\t<VBox>\n" + \
		"\t\t\t@if (show_header) { return ( <Label text=\"Header\" /> ) }\n" + \
		"\t\t\t@for (it in items) { return ( <Label text={ str(it) } /> ) }\n" + \
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
