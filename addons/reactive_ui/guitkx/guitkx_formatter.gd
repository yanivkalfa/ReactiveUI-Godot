class_name RUIGuitkxFormatter
extends RefCounted
## Canonical-form formatter for .guitkx (Phase 5). Pure + FileAccess-free so it is headlessly
## unit-testable. AST-driven re-emit (NOT regex post-processing): re-parse via the single parser of
## record (guitkx_markup.gd), then re-emit. On ANY parse error -> return the source VERBATIM (never
## corrupt). Embedded GDScript (setup / control-flow bodies are markup; {expr} text) is left
## byte-identical except base-indent normalization of setup — a from-scratch GDScript re-indenter is
## unsound (no closing token), so we only re-anchor the outer indent and preserve internal structure.
##
## API:  RUIGuitkxFormatter.format(source: String, opts := {}) -> { ok, text, changed }

const L = preload("res://addons/reactive_ui/guitkx/guitkx_lexer.gd")
const Markup = preload("res://addons/reactive_ui/guitkx/guitkx_markup.gd")
const Compiler = preload("res://addons/reactive_ui/guitkx/guitkx.gd")

const DEFAULTS := {
	"printWidth": 100,
	"indentStyle": "tab",        # "tab" | "space"
	"indentSize": 4,             # spaces per level when indentStyle == "space"
	"singleAttributePerLine": false,
	"insertSpaceBeforeSelfClose": true,
}

static func format(source: String, opts := {}) -> Dictionary:
	var o := DEFAULTS.duplicate()
	for k in opts:
		o[k] = opts[k]
	var text := _format_or_verbatim(source, o)
	return { "ok": true, "text": text, "changed": text != source }

static func _format_or_verbatim(source: String, o: Dictionary) -> String:
	# 1. preamble: an optional `@class_name X` line (the only Godot preamble directive)
	var n := source.length()
	var i := 0
	var class_name_line := ""
	while i < n:
		i = _skip_ws_nl(source, i)
		if source.substr(i, 11) == "@class_name":
			var le := source.find("\n", i)
			if le == -1: le = n
			class_name_line = source.substr(i, le - i).strip_edges()
			i = le
			continue
		break
	# 2. declaration
	var decl: Dictionary = Compiler._find_decl(source, i)
	var diags: Array = []
	var out := ""
	if class_name_line != "":
		out += class_name_line + "\n\n"
	match decl["kind"]:
		"component":
			var pc: Dictionary = Compiler._parse_component_at(source, decl["at"], diags)
			if not pc["ok"]:
				return source
			out += _fmt_component(pc["name"], pc["params"], pc["setup"], pc["root"], o)
		"hook":
			var ph: Dictionary = Compiler._parse_hook_at(source, decl["at"], diags)
			if not ph["ok"]:
				return source
			out += _fmt_hook(ph["name"], ph["params"], ph["body"], o)
		"module":
			var m := _fmt_module(source, decl["at"], o, diags)
			if m == null:
				return source
			out += m
		_:
			return source   # nothing to format
	# normalize trailing whitespace -> exactly one newline
	out = out.rstrip(" \t\n") + "\n"
	return out

# --- declarations ---

static func _fmt_component(comp_name: String, params: String, setup: String, root: Dictionary, o: Dictionary) -> String:
	var out := "component %s%s {\n" % [comp_name, _fmt_params(params)]
	out += _fmt_setup(setup, 1, o)
	out += _pad(1, o) + "return (\n"
	out += _fmt_node(root, 2, o)
	out += _pad(1, o) + ")\n"
	out += "}\n"
	return out

static func _fmt_hook(hook_name: String, params: String, body: String, o: Dictionary) -> String:
	var out := "hook %s%s {\n" % [hook_name, _fmt_params(params)]
	out += _fmt_setup(body, 1, o)
	out += "}\n"
	return out

static func _fmt_module(source: String, mi: int, o: Dictionary, diags: Array) -> Variant:
	var n := source.length()
	var j := mi + 6
	j = _skip_ws_only(source, j)
	var ns := j
	while j < n and L._is_ident(source[j]):
		j += 1
	var mod_name := source.substr(ns, j - ns)
	j = _skip_ws_only(source, j)
	if j >= n or source[j] != "{":
		return null
	var bclose := L.find_matching(source, j)
	if bclose == -1:
		return null
	var out := "module %s {\n" % mod_name
	var i := j + 1
	var first := true
	while i < bclose:
		var d: Dictionary = Compiler._find_decl(source, i)
		if d["kind"] == "" or d["at"] >= bclose:
			break
		if not first:
			out += "\n"
		first = false
		if d["kind"] == "component":
			var c: Dictionary = Compiler._parse_component_at(source, d["at"], diags)
			if not c["ok"]:
				return null
			out += _indent_block(_fmt_component(c["name"], c["params"], c["setup"], c["root"], o), 1, o)
			i = c["next"]
		elif d["kind"] == "hook":
			var h: Dictionary = Compiler._parse_hook_at(source, d["at"], diags)
			if not h["ok"]:
				return null
			out += _indent_block(_fmt_hook(h["name"], h["params"], h["body"], o), 1, o)
			i = h["next"]
		else:
			return null
	out += "}\n"
	return out

# --- markup ---

static func _fmt_node(nd: Dictionary, indent: int, o: Dictionary) -> String:
	match nd["t"]:
		"el":
			return _fmt_element(nd, indent, o)
		"frag":
			var inner := _fmt_children(nd["children"], indent + 1, o)
			return "%s<>\n%s%s</>\n" % [_pad(indent, o), inner, _pad(indent, o)]
		"text":
			return "%s%s\n" % [_pad(indent, o), (nd["value"] as String).strip_edges()]
		"expr":
			return "%s{ %s }\n" % [_pad(indent, o), (nd["code"] as String).strip_edges()]
		"if":
			return _fmt_if(nd, indent, o)
		"for":
			return _fmt_loop(nd, indent, o, "for")
		"while":
			return _fmt_loop(nd, indent, o, "while")
		"match":
			return _fmt_match(nd, indent, o)
		_:
			return ""
	return ""

static func _fmt_element(nd: Dictionary, indent: int, o: Dictionary) -> String:
	var pad := _pad(indent, o)
	var tag: String = nd["tag"]
	var attr_strs: Array = []
	for a in nd["attrs"]:
		attr_strs.append(_fmt_attr(a))
	var children: Array = (nd["children"] as Array).filter(func(x): return x != null)
	var self_close := children.is_empty()
	var attr_inline := " ".join(attr_strs)
	# single-line candidate
	var head := "<%s" % tag
	if not attr_strs.is_empty():
		head += " " + attr_inline
	var single_close := (" />" if o["insertSpaceBeforeSelfClose"] else "/>") if self_close else ">"
	var single := head + single_close
	var wrap: bool = o["singleAttributePerLine"] and attr_strs.size() > 1
	if not wrap and pad.length() + single.length() > int(o["printWidth"]) and attr_strs.size() > 1:
		wrap = true
	var out := ""
	if not wrap:
		if self_close:
			return pad + single + "\n"
		out += pad + single + "\n"
	else:
		out += pad + "<%s\n" % tag
		var apad := _pad(indent + 1, o)
		for k in attr_strs.size():
			var last := k == attr_strs.size() - 1
			if last and self_close:
				out += apad + attr_strs[k] + (" />" if o["insertSpaceBeforeSelfClose"] else "/>") + "\n"
			elif last:
				out += apad + attr_strs[k] + "\n" + pad + ">\n"
			else:
				out += apad + attr_strs[k] + "\n"
		if self_close:
			return out
	# children + close tag
	out += _fmt_children(children, indent + 1, o)
	out += pad + "</%s>\n" % tag
	return out

static func _fmt_children(children: Array, indent: int, o: Dictionary) -> String:
	var out := ""
	for c in children:
		if c == null:
			continue
		out += _fmt_node(c, indent, o)
	return out

static func _fmt_attr(a: Dictionary) -> String:
	match a["kind"]:
		"str":
			return "%s=\"%s\"" % [a["name"], a["value"]]
		"expr":
			return "%s={ %s }" % [a["name"], (a["value"] as String).strip_edges()]
		"bool":
			return a["name"]
	return a["name"]

# --- control flow (bodies are raw markup strings; re-parse + format) ---

static func _fmt_if(nd: Dictionary, indent: int, o: Dictionary) -> String:
	var pad := _pad(indent, o)
	var out := ""
	var branches: Array = nd["branches"]
	for k in branches.size():
		var br: Dictionary = branches[k]
		var kw := "@if" if k == 0 else "@elif"
		if k == 0:
			out += "%s%s (%s) {\n" % [pad, kw, (br["cond"] as String).strip_edges()]
		else:
			out = out.rstrip("\n") + " %s (%s) {\n" % [kw, (br["cond"] as String).strip_edges()]
		out += _fmt_body(br["body_markup"], indent + 1, o)
		out += pad + "}\n"
	if nd["else_body"] != null:
		out = out.rstrip("\n") + " @else {\n"
		out += _fmt_body(nd["else_body"], indent + 1, o)
		out += pad + "}\n"
	return out

static func _fmt_loop(nd: Dictionary, indent: int, o: Dictionary, kw: String) -> String:
	var pad := _pad(indent, o)
	var out := "%s@%s (%s) {\n" % [pad, kw, (nd["header"] as String).strip_edges()]
	out += _fmt_body(nd["body_markup"], indent + 1, o)
	out += pad + "}\n"
	return out

static func _fmt_match(nd: Dictionary, indent: int, o: Dictionary) -> String:
	var pad := _pad(indent, o)
	var out := "%s@match (%s) {\n" % [pad, (nd["subject"] as String).strip_edges()]
	for c in nd.get("cases", []):
		out += "%s@case (%s) {\n" % [_pad(indent + 1, o), (c["value"] as String).strip_edges()]
		out += _fmt_body(c["body_markup"], indent + 2, o)
		out += _pad(indent + 1, o) + "}\n"
	if nd.get("default_body") != null:
		out += "%s@default {\n" % _pad(indent + 1, o)
		out += _fmt_body(nd["default_body"], indent + 2, o)
		out += _pad(indent + 1, o) + "}\n"
	out += pad + "}\n"
	return out

# Re-parse a raw control-flow body string and format its nodes; verbatim re-indent fallback on error.
static func _fmt_body(body_src: String, indent: int, o: Dictionary) -> String:
	var parser := Markup.new()
	var pr := parser.parse(body_src, 0, body_src.length())
	if pr["error"] != "":
		return _reanchor(body_src, indent, o)
	var nodes: Array = (pr["nodes"] as Array).filter(func(x): return x != null)
	var out := ""
	for nx in nodes:
		out += _fmt_node(nx, indent, o)
	return out

# --- embedded GDScript (setup) — structure-preserving base-indent normalization only ---

static func _fmt_setup(setup: String, indent: int, o: Dictionary) -> String:
	var s := setup.strip_edges()
	if s == "":
		return ""
	return _reanchor(setup, indent, o)

# Dedent to the common leading whitespace, then re-anchor to `indent`, preserving internal relative
# indentation byte-for-byte. (Exactly _reindent_setup's contract — never restructures GDScript.)
static func _reanchor(code: String, indent: int, o: Dictionary) -> String:
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
		prefix = lead if not have else _common_prefix(prefix, lead)
		have = true
	var pad := _pad(indent, o)
	var out := ""
	for l in lines:
		if (l as String).strip_edges() == "":
			out += "\n"
		else:
			out += pad + (l as String).substr(prefix.length()) + "\n"
	return out

# --- helpers ---

static func _fmt_params(params: String) -> String:
	var p := params.strip_edges()
	return "" if p == "" else "(%s)" % p

static func _indent_block(block: String, indent: int, o: Dictionary) -> String:
	var pad := _pad(indent, o)
	var out := ""
	for l in block.split("\n"):
		out += ("" if (l as String) == "" else pad + l) + "\n"
	return out.rstrip("\n") + "\n"

static func _pad(indent: int, o: Dictionary) -> String:
	if o["indentStyle"] == "space":
		return " ".repeat(indent * int(o["indentSize"]))
	return "\t".repeat(indent)

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

static func _skip_ws_only(s: String, i: int) -> int:
	var n := s.length()
	while i < n and (s[i] == " " or s[i] == "\t" or s[i] == "\n" or s[i] == "\r"):
		i += 1
	return i

static func _skip_ws_nl(s: String, i: int) -> int:
	while true:
		i = _skip_ws_only(s, i)
		var k := L.skip_noncode(s, i)
		if k == i:
			return i
		i = k
	return i
