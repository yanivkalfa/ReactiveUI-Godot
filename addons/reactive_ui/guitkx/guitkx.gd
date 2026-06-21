class_name RUIGuitkx
extends RefCounted
## The .guitkx -> .gd compiler entry point (Phase 2, Milestone 2.1). Pure GDScript; run from a
## @tool EditorPlugin file-watcher that writes the sibling .gd (see PHASE_2_GUITKX_PLAN.md 0b â€”
## NOT an import plugin). This is the walking skeleton: a `component` with setup + static markup
## (elements, attributes, {expr}, nested children, child components, fragments). Control-flow
## emit (@if/@for/@while/@match), hooks/module files, and the full diagnostics catalog are the
## next iterations; the markup parser already recognizes the control-flow directives.
##
## API:  RUIGuitkx.compile(source: String, basename: String) -> { ok, gd, diagnostics }

const L = preload("res://addons/reactive_ui/guitkx/guitkx_lexer.gd")
const Markup = preload("res://addons/reactive_ui/guitkx/guitkx_markup.gd")

## PascalCase/markup tag -> V.* host factory. Hand-authored Godot control catalog (the analog of
## uitkx's reflected V map / s_fallbackMap). A tag here = host element; anything else PascalCase = component.
const HOST_TAGS := {
	"Control": "control", "VBox": "vbox", "VBoxContainer": "vbox", "HBox": "hbox", "HBoxContainer": "hbox",
	"Grid": "grid", "GridContainer": "grid", "Margin": "margin", "MarginContainer": "margin",
	"Panel": "panel", "PanelContainer": "panel", "Center": "center", "CenterContainer": "center",
	"Scroll": "scroll", "ScrollContainer": "scroll", "Tabs": "tabs", "TabContainer": "tabs",
	"Label": "label", "RichText": "rich_text", "RichTextLabel": "rich_text", "ColorRect": "color_rect",
	"TextureRect": "texture_rect", "HSeparator": "h_separator", "VSeparator": "v_separator",
	"Button": "button", "CheckBox": "check_box", "CheckButton": "check_button", "OptionButton": "option_button",
	"MenuButton": "menu_button", "LinkButton": "link_button", "TextureButton": "texture_button",
	"LineEdit": "line_edit", "TextEdit": "text_edit", "CodeEdit": "code_edit", "SpinBox": "spin_box",
	"HSlider": "h_slider", "VSlider": "v_slider", "ProgressBar": "progress_bar", "ItemList": "item_list",
	"Tree": "tree", "TabBar": "tab_bar",
}

static func compile(source: String, basename: String = "Component") -> Dictionary:
	var diags: Array = []
	# 1. Preamble: optional `@class_name X` (other directives skipped for the skeleton).
	var class_name_override := ""
	var i := 0
	var n := source.length()
	while i < n:
		i = _skip_ws_and_comments(source, i)
		if source.substr(i, 11) == "@class_name":
			var le := source.find("\n", i)
			if le == -1: le = n
			class_name_override = source.substr(i + 11, le - i - 11).strip_edges()
			i = le
			continue
		break
	# 2. Detect the declaration kind (component | hook | module) and dispatch.
	var decl := _find_decl(source, i)
	match decl["kind"]:
		"component":
			return _compile_component(source, decl["at"], class_name_override, basename, diags)
		"hook":
			return _compile_hook(source, decl["at"], class_name_override, basename, diags)
		"module":
			diags.append("GUITKX0103: `module` files are not supported yet (use one component or hook per file)")
			return { "ok": false, "gd": "", "diagnostics": diags }
		_:
			diags.append("GUITKX0102: no `component`, `hook`, or `module` declaration found")
			return { "ok": false, "gd": "", "diagnostics": diags }

## Find the first top-level declaration keyword (skipping strings/comments).
static func _find_decl(source: String, from: int) -> Dictionary:
	var n := source.length()
	var i := from
	while i < n:
		var k := L.skip_noncode(source, i)
		if k != i:
			i = k
			continue
		if L.keyword_at(source, i, "component"):
			return { "kind": "component", "at": i }
		if L.keyword_at(source, i, "hook"):
			return { "kind": "hook", "at": i }
		if L.keyword_at(source, i, "module"):
			return { "kind": "module", "at": i }
		i += 1
	return { "kind": "", "at": -1 }

static func _compile_component(source: String, ci: int, class_name_override: String, basename: String, diags: Array) -> Dictionary:
	var n := source.length()
	var j := ci + 9
	j = _skip_ws_only(source, j)
	# component name
	var ns := j
	while j < n and L._is_ident(source[j]):
		j += 1
	var comp_name := source.substr(ns, j - ns)
	if comp_name == "":
		diags.append("GUITKX0300: missing component name")
		return { "ok": false, "gd": "", "diagnostics": diags }
	# optional (params)
	var params := ""
	j = _skip_ws_only(source, j)
	if j < n and source[j] == "(":
		var pc := L.find_matching(source, j)
		if pc == -1:
			diags.append("GUITKX0304: unclosed `(` in component params")
			return { "ok": false, "gd": "", "diagnostics": diags }
		params = source.substr(j + 1, pc - j - 1)
		j = pc + 1
	# body `{ ... }`
	j = _skip_ws_only(source, j)
	if j >= n or source[j] != "{":
		diags.append("GUITKX0303: component body `{ ... }` expected")
		return { "ok": false, "gd": "", "diagnostics": diags }
	var bclose := L.find_matching(source, j)
	if bclose == -1:
		diags.append("GUITKX0304: unclosed component body")
		return { "ok": false, "gd": "", "diagnostics": diags }
	var body := source.substr(j + 1, bclose - j - 1)
	# split body into setup + `return ( markup )`
	var split := _split_return(body)
	if split.has("error"):
		diags.append(split["error"])
		return { "ok": false, "gd": "", "diagnostics": diags }
	var setup: String = split["setup"]
	var markup_src: String = split["markup_src"]
	var m_start: int = split["m_start"]
	var m_end: int = split["m_end"]
	# parse the markup window
	var parser := Markup.new()
	var pr := parser.parse(markup_src, m_start, m_end)
	if pr["error"] != "":
		diags.append(pr["error"])
		return { "ok": false, "gd": "", "diagnostics": diags }
	var roots: Array = pr["nodes"]
	var render_roots := roots.filter(func(nd): return nd != null)
	if render_roots.size() != 1:
		diags.append("GUITKX0108: a component must return exactly one root element (got %d)" % render_roots.size())
		return { "ok": false, "gd": "", "diagnostics": diags }
	# name-vs-filename advisory
	if class_name_override == "" and comp_name != basename:
		diags.append("GUITKX0103 (warning): component `%s` differs from file name `%s`" % [comp_name, basename])
	# semantic validation (rules of hooks, duplicate keys, keyless loop children)
	_validate(setup, render_roots[0], diags)
	var cls := class_name_override if class_name_override != "" else comp_name
	var gd := _emit(cls, comp_name, params, setup, render_roots[0], basename)
	return { "ok": true, "gd": gd, "diagnostics": diags }

# --- semantic validation (warnings; they don't fail the compile) ---
static func _validate(setup: String, root: Dictionary, diags: Array) -> void:
	_validate_hooks(setup, diags)
	_validate_node(root, diags)

## Rules of hooks (heuristic): a hook call indented deeper than the shallowest setup statement is
## inside an if/for/while/match block, i.e. called conditionally. [GUITKX0013]
static func _validate_hooks(setup: String, diags: Array) -> void:
	var lines := setup.split("\n")
	var base := -1
	for l in lines:
		if (l as String).strip_edges() == "":
			continue
		var w := _leading_ws(l).length()
		if base == -1 or w < base:
			base = w
	if base == -1:
		return
	for l in lines:
		if (l as String).strip_edges() == "":
			continue
		if _line_calls_hook(l as String) and _leading_ws(l).length() > base:
			diags.append("GUITKX0013 (warning): hook called conditionally/in a block -- hooks must run unconditionally at the top of setup")
			return

static func _line_calls_hook(s: String) -> bool:
	for h in ["use_state", "use_reducer", "use_ref", "use_memo", "use_callback", "use_effect",
		"use_layout_effect", "use_context", "use_signal", "use_tween_value", "use_tween"]:
		if (h + "(") in s:
			return true
	return false

static func _validate_node(nd, diags: Array) -> void:
	if nd == null or not (nd is Dictionary):
		return
	match nd.get("t", ""):
		"el", "frag":
			_check_dup_keys(nd.get("children", []), diags)
			for c in nd.get("children", []):
				_validate_node(c, diags)
		"if":
			for br in nd["branches"]:
				_validate_body(br["body_markup"], diags, false)
			if nd["else_body"] != null:
				_validate_body(nd["else_body"], diags, false)
		"for", "while":
			_validate_body(nd["body_markup"], diags, true)
		"match":
			for c in nd.get("cases", []):
				_validate_body(c["body_markup"], diags, false)
			if nd.get("default_body") != null:
				_validate_body(nd["default_body"], diags, false)

static func _validate_body(body_src: String, diags: Array, is_loop: bool) -> void:
	var parser := Markup.new()
	var pr := parser.parse(body_src, 0, body_src.length())
	if pr["error"] != "":
		return
	var nodes: Array = (pr["nodes"] as Array).filter(func(x): return x != null)
	if is_loop and nodes.size() == 1 and (nodes[0] as Dictionary).get("t", "") == "el":
		if not _has_key(nodes[0]):
			diags.append("GUITKX0106 (warning): element in @for/@while has no `key` -- add key= so reordered children reconcile correctly")
	for nx in nodes:
		_validate_node(nx, diags)

static func _check_dup_keys(children: Array, diags: Array) -> void:
	var seen := {}
	for c in children:
		if c == null or not (c is Dictionary) or (c as Dictionary).get("t", "") != "el":
			continue
		var k := _literal_key(c)
		if k == "":
			continue
		if seen.has(k):
			diags.append("GUITKX0104 (warning): duplicate key '%s' among sibling elements" % k)
		seen[k] = true

static func _has_key(el: Dictionary) -> bool:
	for a in el.get("attrs", []):
		if a["name"] == "key":
			return true
	return false

static func _literal_key(el: Dictionary) -> String:
	for a in el.get("attrs", []):
		if a["name"] == "key" and a["kind"] == "str":
			return a["value"]
	return ""

## hook file: `hook name(params) [-> (...)] { body }` -> a class with one static function. The
## body is plain GDScript (hook calls auto-prefixed); the `-> (tuple)` hint is dropped (GDScript
## has no tuple type -- a multi-value hook returns an Array).
static func _compile_hook(source: String, hi: int, class_name_override: String, basename: String, diags: Array) -> Dictionary:
	var n := source.length()
	var j := hi + 4   # "hook"
	j = _skip_ws_only(source, j)
	var ns := j
	while j < n and L._is_ident(source[j]):
		j += 1
	var hook_name := source.substr(ns, j - ns)
	if hook_name == "":
		diags.append("GUITKX0300: missing hook name")
		return { "ok": false, "gd": "", "diagnostics": diags }
	var params := ""
	j = _skip_ws_only(source, j)
	if j < n and source[j] == "(":
		var pc := L.find_matching(source, j)
		if pc == -1:
			diags.append("GUITKX0304: unclosed `(` in hook params")
			return { "ok": false, "gd": "", "diagnostics": diags }
		params = source.substr(j + 1, pc - j - 1)
		j = pc + 1
	# optional `-> ReturnHint` (dropped)
	j = _skip_ws_only(source, j)
	if j + 1 < n and source[j] == "-" and source[j + 1] == ">":
		j += 2
		while j < n and source[j] != "{":
			j += 1
	# body
	j = _skip_ws_only(source, j)
	if j >= n or source[j] != "{":
		diags.append("GUITKX0303: hook body `{ ... }` expected")
		return { "ok": false, "gd": "", "diagnostics": diags }
	var bclose := L.find_matching(source, j)
	if bclose == -1:
		diags.append("GUITKX0304: unclosed hook body")
		return { "ok": false, "gd": "", "diagnostics": diags }
	var body := source.substr(j + 1, bclose - j - 1)
	var cls := class_name_override if class_name_override != "" else basename
	var out := "class_name %s\nextends RefCounted\n## AUTO-GENERATED from %s.guitkx -- do not edit.\n\n" % [cls, basename]
	out += "static func %s(%s):\n" % [hook_name, params]
	var body_block := _reindent_setup(_apply_hook_aliases(body))
	out += (body_block + "\n") if body_block != "" else "\tpass\n"
	return { "ok": true, "gd": out, "diagnostics": diags }

# --- body splitter: find the top-level `return ( ... )` ---
static func _split_return(body: String) -> Dictionary:
	var n := body.length()
	var i := 0
	while i < n:
		var k := L.skip_noncode(body, i)
		if k != i:
			i = k
			continue
		if L.keyword_at(body, i, "return"):
			var p := i + 6
			p = _skip_ws_only(body, p)
			if p < n and body[p] == "(":
				var close := L.find_matching(body, p)
				if close == -1:
					return { "error": "GUITKX0304: unclosed `(` after return" }
				var setup := body.substr(0, i)
				return { "setup": setup, "markup_src": body, "m_start": p + 1, "m_end": close }
			elif p < n and body[p] == "<":
				# bare `return <Tag.../>;`
				var setup2 := body.substr(0, i)
				return { "setup": setup2, "markup_src": body, "m_start": p, "m_end": n }
			elif L.keyword_at(body, p, "null"):
				return { "error": "GUITKX0102: component returns null (nothing to render)" }
		i += 1
	return { "error": "GUITKX0102: component has no `return ( ... )`" }

# --- emit ---
# Control flow is hoisted into pre-statements (an if/for/while block before the return) that
# assign a fresh `__cfN` local, which the markup then references. This sidesteps both GDScript's
# "lambdas can't hold multi-statement return control-flow" limit AND the helper-method
# locals-capture problem -- the block is inline in render() and sees all setup locals. The
# runtime `V._norm` flattens the `@for` arrays and drops the null `@if` misses for free.
static func _emit(cls: String, comp_name: String, params: String, setup: String, root: Dictionary, basename: String) -> String:
	var out := ""
	out += "class_name %s\n" % cls
	out += "extends RefCounted\n"
	out += "## AUTO-GENERATED from %s.guitkx -- do not edit.\n\n" % basename
	out += "static func render(props: Dictionary, children: Array) -> RUIVNode:\n"
	# prop unpacking from params
	for p in _parse_params(params):
		if p["default"] != "":
			out += "\tvar %s = props.get(\"%s\", %s)\n" % [p["name"], p["name"], p["default"]]
		else:
			out += "\tvar %s = props.get(\"%s\")\n" % [p["name"], p["name"]]
	# setup (verbatim, hook auto-prefix) -- dedented to its source common indent, re-indented 1 tab
	var setup_block := _reindent_setup(_apply_hook_aliases(setup))
	if setup_block != "":
		out += setup_block + "\n"
	# emit the markup, collecting any control-flow pre-statements into ctx.lines
	var ctx := { "lines": [], "indent": 1, "counter": 0 }
	var root_expr := _emit_expr(root, ctx)
	if root["t"] == "for" or root["t"] == "while":
		root_expr = "V.fragment(%s)" % root_expr   # a root-level loop yields an Array -> wrap
	for ln in ctx["lines"]:
		out += ln + "\n"
	out += "\treturn %s\n" % root_expr
	return out

static func _emit_expr(nd: Dictionary, ctx: Dictionary) -> String:
	match nd["t"]:
		"el":
			return _emit_element(nd, ctx)
		"frag":
			return "V.fragment(%s)" % _emit_children_array(nd["children"], ctx)
		"expr":
			return "(%s)" % nd["code"]
		"text":
			return "V.label({ \"text\": %s })" % _gd_str(nd["value"])
		"if":
			return _emit_if(nd, ctx)
		"for":
			return _emit_loop(nd, ctx, "for")
		"while":
			return _emit_loop(nd, ctx, "while")
		"match":
			return _emit_match(nd, ctx)
		_:
			return "null  # TODO emit %s" % nd["t"]
	return "null"

static func _emit_element(nd: Dictionary, ctx: Dictionary) -> String:
	var tag: String = nd["tag"]
	var is_host := false
	var factory := ""
	if tag[0] >= "a" and tag[0] <= "z":
		is_host = true
		factory = tag   # lowercase/snake tag IS the V factory name
	elif HOST_TAGS.has(tag):
		is_host = true
		factory = HOST_TAGS[tag]
	# build the props dict + pull out key
	var props_parts: Array = []
	var key_expr := ""
	for a in nd["attrs"]:
		var name: String = a["name"]
		var valcode := _attr_value_code(a)
		if name == "key":
			key_expr = valcode
			continue
		props_parts.append("\"%s\": %s" % [name, valcode])
	var props_dict := "{ %s }" % ", ".join(props_parts) if not props_parts.is_empty() else "{}"
	var children_src := _emit_children_array(nd["children"], ctx)
	if is_host:
		var args := props_dict
		if children_src != "[]":
			args += ", " + children_src
		if key_expr != "":
			args += (", []" if children_src == "[]" else "") + ", " + key_expr
		return "V.%s(%s)" % [factory, args]
	else:
		# child component -> V.fc(Tag.render, props[, children[, key]])
		var args2 := "%s.render, %s" % [tag, props_dict]
		if children_src != "[]":
			args2 += ", " + children_src
		if key_expr != "":
			args2 += (", []" if children_src == "[]" else "") + ", " + key_expr
		return "V.fc(%s)" % args2

static func _emit_children_array(children: Array, ctx: Dictionary) -> String:
	var parts: Array = []
	for c in children:
		if c == null:
			continue
		parts.append(_emit_expr(c, ctx))
	if parts.is_empty():
		return "[]"
	return "[%s]" % ", ".join(parts)

# Parse a control-flow branch/loop body (raw markup string) and emit its single root expression
# (or a fragment of several, or null when empty). Nested control flow recurses through _emit_expr,
# so its pre-statements land at the caller's current indent (inside the branch/loop).
static func _emit_body(body_src: String, ctx: Dictionary) -> String:
	var parser := Markup.new()
	var pr := parser.parse(body_src, 0, body_src.length())
	if pr["error"] != "":
		return "null  # body parse error: %s" % pr["error"]
	var nodes: Array = (pr["nodes"] as Array).filter(func(x): return x != null)
	if nodes.is_empty():
		return "null"
	if nodes.size() == 1:
		return _emit_expr(nodes[0], ctx)
	var parts: Array = []
	for nx in nodes:
		parts.append(_emit_expr(nx, ctx))
	return "V.fragment([%s])" % ", ".join(parts)

static func _emit_if(nd: Dictionary, ctx: Dictionary) -> String:
	var id := _fresh(ctx)
	_line(ctx, "var %s = null" % id)
	var branches: Array = nd["branches"]
	for i in branches.size():
		var br: Dictionary = branches[i]
		var kw := "if" if i == 0 else "elif"
		_line(ctx, "%s %s:" % [kw, br["cond"]])
		ctx["indent"] += 1
		var be := _emit_body(br["body_markup"], ctx)
		_line(ctx, "%s = %s" % [id, be])
		ctx["indent"] -= 1
	if nd["else_body"] != null:
		_line(ctx, "else:")
		ctx["indent"] += 1
		var ee := _emit_body(nd["else_body"], ctx)
		_line(ctx, "%s = %s" % [id, ee])
		ctx["indent"] -= 1
	return id

static func _emit_loop(nd: Dictionary, ctx: Dictionary, kind: String) -> String:
	var id := _fresh(ctx)
	_line(ctx, "var %s: Array = []" % id)
	if kind == "for":
		_line(ctx, "for %s:" % nd["header"])
	else:
		_line(ctx, "while %s:" % nd["header"])
	ctx["indent"] += 1
	var be := _emit_body(nd["body_markup"], ctx)
	_line(ctx, "%s.append(%s)" % [id, be])
	ctx["indent"] -= 1
	return id

static func _emit_match(nd: Dictionary, ctx: Dictionary) -> String:
	var id := _fresh(ctx)
	_line(ctx, "var %s = null" % id)
	var cases: Array = nd["cases"]
	if cases.is_empty() and nd["default_body"] == null:
		return id   # empty @match -> always null (GDScript forbids a branchless match)
	_line(ctx, "match %s:" % nd["subject"])
	ctx["indent"] += 1
	for c in cases:
		_line(ctx, "%s:" % c["value"])
		ctx["indent"] += 1
		var be := _emit_body(c["body_markup"], ctx)
		_line(ctx, "%s = %s" % [id, be])
		ctx["indent"] -= 1
	if nd["default_body"] != null:
		_line(ctx, "_:")
		ctx["indent"] += 1
		var de := _emit_body(nd["default_body"], ctx)
		_line(ctx, "%s = %s" % [id, de])
		ctx["indent"] -= 1
	ctx["indent"] -= 1
	return id

# Dedent a setup block to its common leading-whitespace prefix, then re-indent every line one tab
# (so source indentation inside render's body becomes a single render-body indent level).
static func _reindent_setup(code: String) -> String:
	var lines: Array = Array(code.split("\n"))
	while not lines.is_empty() and (lines[0] as String).strip_edges() == "":
		lines.pop_front()
	while not lines.is_empty() and (lines[-1] as String).strip_edges() == "":
		lines.pop_back()
	if lines.is_empty():
		return ""
	var prefix := ""
	var have := false
	for l in lines:
		if (l as String).strip_edges() == "":
			continue
		var lead := _leading_ws(l)
		if not have:
			prefix = lead
			have = true
		else:
			prefix = _common_prefix(prefix, lead)
	var out_lines: Array = []
	for l in lines:
		if (l as String).strip_edges() == "":
			out_lines.append("")
		else:
			out_lines.append("\t" + (l as String).substr(prefix.length()))
	return "\n".join(out_lines)

static func _leading_ws(s: String) -> String:
	var i := 0
	while i < s.length() and (s[i] == "\t" or s[i] == " "):
		i += 1
	return s.substr(0, i)

static func _common_prefix(a: String, b: String) -> String:
	var i := 0
	var m: int = min(a.length(), b.length())
	while i < m and a[i] == b[i]:
		i += 1
	return a.substr(0, i)

static func _line(ctx: Dictionary, s: String) -> void:
	ctx["lines"].append("\t".repeat(ctx["indent"]) + s)

static func _fresh(ctx: Dictionary) -> String:
	var id := "__cf%d" % ctx["counter"]
	ctx["counter"] += 1
	return id

static func _attr_value_code(a: Dictionary) -> String:
	match a["kind"]:
		"str":
			return _gd_str(a["value"])
		"expr":
			return a["value"]
		"bool":
			return "true"
	return "null"

# --- helpers ---
static func _parse_params(params: String) -> Array:
	# split on top-level commas; each "name[: Type][ = default]"
	var out: Array = []
	if params.strip_edges() == "":
		return out
	for chunk in _split_top_commas(params):
		var c: String = str(chunk).strip_edges()
		if c == "":
			continue
		var name: String = c
		var default: String = ""
		var eq := _find_top(c, "=")
		if eq != -1:
			default = c.substr(eq + 1).strip_edges()
			name = c.substr(0, eq).strip_edges()
		var colon := name.find(":")
		if colon != -1:
			name = name.substr(0, colon).strip_edges()
		out.append({ "name": name, "default": default })
	return out

static func _split_top_commas(s: String) -> Array:
	var out: Array = []
	var start := 0
	var i := 0
	var n := s.length()
	while i < n:
		var k := L.skip_noncode(s, i)
		if k != i:
			i = k
			continue
		var c := s[i]
		if c == "(" or c == "{" or c == "[":
			var close := L.find_matching(s, i)
			i = (close + 1) if close != -1 else n
			continue
		if c == ",":
			out.append(s.substr(start, i - start))
			start = i + 1
		i += 1
	out.append(s.substr(start))
	return out

static func _find_top(s: String, ch: String) -> int:
	var i := 0
	var n := s.length()
	while i < n:
		var k := L.skip_noncode(s, i)
		if k != i:
			i = k
			continue
		var c := s[i]
		if c == "(" or c == "{" or c == "[":
			var close := L.find_matching(s, i)
			i = (close + 1) if close != -1 else n
			continue
		if c == ch:
			return i
		i += 1
	return -1

static func _apply_hook_aliases(setup: String) -> String:
	# Auto-prefix bare hook calls to Hooks.* (use_state( -> Hooks.use_state(). Naive substring
	# pass like uitkx's ApplyHookAliases; the Hooks.Hooks. fixup undoes double-prefixing.
	var hooks := ["use_state", "use_reducer", "use_ref", "use_memo", "use_callback", "use_effect",
		"use_layout_effect", "use_context", "use_signal", "use_tween", "use_tween_value"]
	var s := setup
	for h in hooks:
		s = s.replace(h + "(", "Hooks." + h + "(")
	s = s.replace("Hooks.Hooks.", "Hooks.")
	return s


static func _gd_str(v: String) -> String:
	return "\"%s\"" % v.replace("\\", "\\\\").replace("\"", "\\\"")

static func _skip_ws_only(s: String, i: int) -> int:
	var n := s.length()
	while i < n and (s[i] == " " or s[i] == "\t" or s[i] == "\n" or s[i] == "\r"):
		i += 1
	return i

static func _skip_ws_and_comments(s: String, i: int) -> int:
	while true:
		i = _skip_ws_only(s, i)
		var k := L.skip_noncode(s, i)
		if k == i:
			return i
		i = k
	return i
