class_name RUIGuitkx
extends RefCounted
## The .guitkx -> .gd compiler entry point (Phase 2, Milestone 2.1). Pure GDScript; run from a
## @tool EditorPlugin file-watcher that writes the sibling .gd (see PHASE_2_GUITKX_PLAN.md 0b â€”
## NOT an import plugin). Compiles a `component`, `hook`, or `module` declaration: setup + static
## markup (elements, attributes, {expr}, nested children, child components, fragments), control-flow
## emit (@if/@elif/@else/@for/@while/@match, lowered inline inside {expr}/lambdas), hook
## auto-prefixing (bare use_* -> Hooks.use_*), and the GUITKX#### diagnostics catalog.
##
## API:  RUIGuitkx.compile(source: String, basename: String) -> { ok, gd, diagnostics }

const L = preload("res://addons/reactive_ui/guitkx/guitkx_lexer.gd")
const Markup = preload("res://addons/reactive_ui/guitkx/guitkx_markup.gd")
const JsxScan = preload("res://addons/reactive_ui/guitkx/guitkx_jsx_scan.gd")

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
			var cn_raw := source.substr(i + 11, le - i - 11)
			var cn_hash := cn_raw.find("#")   # allow a trailing comment on the directive line
			if cn_hash != -1:
				cn_raw = cn_raw.substr(0, cn_hash)
			class_name_override = cn_raw.strip_edges()
			if not _is_valid_identifier(class_name_override):
				diags.append("GUITKX0300: `@class_name` value must be a single valid identifier (got '%s')" % class_name_override)
				return { "ok": false, "gd": "", "diagnostics": diags }
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
			return _compile_module(source, decl["at"], class_name_override, basename, diags)
		_:
			var near := _nearest_decl_keyword(source, i)
			if near.has("word"):
				diags.append("GUITKX0102: unknown declaration '%s' -- did you mean '%s'?" % [near["word"], near["kw"]])
			else:
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

## True if `s` is a single valid GDScript identifier ([A-Za-z_][A-Za-z0-9_]*), non-empty. [BUG-V2]
static func _is_valid_identifier(s: String) -> bool:
	if s.is_empty():
		return false
	for idx in s.length():
		var c := s.unicode_at(idx)
		var okc := (c == 95) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
		if idx > 0:
			okc = okc or (c >= 48 and c <= 57)
		if not okc:
			return false
	return true

## The first top-level identifier + the declaration keyword it most resembles (edit distance <= 3),
## for a "did you mean 'component'?" hint on a misspelled keyword. {} if none is close. [BUG-V1]
static func _nearest_decl_keyword(source: String, from: int) -> Dictionary:
	var i := from
	var n := source.length()
	while i < n:
		var k := L.skip_noncode(source, i)
		if k != i:
			i = k
			continue
		if L._is_ident(source[i]):
			var s := i
			while i < n and L._is_ident(source[i]):
				i += 1
			var word := source.substr(s, i - s)
			var best := ""
			var best_d := 99
			for kw in ["component", "hook", "module"]:
				var d := _edit_distance(word.to_lower(), kw)
				if d < best_d:
					best_d = d
					best = kw
			if best != "" and best_d <= 3:
				return { "word": word, "kw": best }
			return {}
		i += 1
	return {}

## Bounded Levenshtein edit distance (two-row DP).
static func _edit_distance(a: String, b: String) -> int:
	var la := a.length()
	var lb := b.length()
	if la == 0:
		return lb
	if lb == 0:
		return la
	var prev: Array = range(lb + 1)
	var curr: Array = []
	curr.resize(lb + 1)
	for x in range(1, la + 1):
		curr[0] = x
		for y in range(1, lb + 1):
			var cost := 0 if a[x - 1] == b[y - 1] else 1
			curr[y] = mini(mini(prev[y] + 1, curr[y - 1] + 1), prev[y - 1] + cost)
		prev = curr.duplicate()
	return prev[lb]

static func _compile_component(source: String, ci: int, class_name_override: String, basename: String, diags: Array) -> Dictionary:
	var pc := _parse_component_at(source, ci, diags)
	if not pc["ok"]:
		return { "ok": false, "gd": "", "diagnostics": diags }
	if class_name_override == "" and pc["name"] != basename:
		diags.append("GUITKX0103 (warning): component `%s` differs from file name `%s`" % [pc["name"], basename])
	_validate(pc["setup"], pc["root"], diags)
	# A hard-error diagnostic from validation (e.g. GUITKX0108 in a loop body) fails the compile —
	# warnings (containing "(warning)") do not.
	for d in diags:
		if not (d as String).contains("(warning)"):
			return { "ok": false, "gd": "", "diagnostics": diags }
	var cls: String = class_name_override if class_name_override != "" else pc["name"]
	var gd := _emit(cls, pc["name"], pc["params"], pc["setup"], pc["root"], basename, diags)
	return { "ok": true, "gd": gd, "diagnostics": diags }

## Parse ONE component declaration at `ci`. Returns { ok, name, params, setup, root, next }
## (next = index just past the closing brace) or { ok:false } with diagnostics appended.
static func _parse_component_at(source: String, ci: int, diags: Array) -> Dictionary:
	var n := source.length()
	var j := ci + 9
	j = _skip_ws_only(source, j)
	var ns := j
	while j < n and L._is_ident(source[j]):
		j += 1
	var comp_name := source.substr(ns, j - ns)
	if comp_name == "":
		diags.append("GUITKX0300: missing component name")
		return { "ok": false }
	var params := ""
	j = _skip_ws_only(source, j)
	if j < n and source[j] == "(":
		var pc := L.find_matching(source, j)
		if pc == -1:
			diags.append("GUITKX0304: unclosed `(` in component params")
			return { "ok": false }
		params = source.substr(j + 1, pc - j - 1)
		j = pc + 1
	j = _skip_ws_only(source, j)
	if j >= n or source[j] != "{":
		diags.append("GUITKX0303: component body `{ ... }` expected")
		return { "ok": false }
	var bclose := L.find_matching(source, j)
	if bclose == -1:
		diags.append("GUITKX0304: unclosed component body")
		return { "ok": false }
	var body := source.substr(j + 1, bclose - j - 1)
	var split := _split_return(body)
	if split.has("error"):
		diags.append(split["error"])
		return { "ok": false }
	var parser := Markup.new()
	var pr := parser.parse(split["markup_src"], split["m_start"], split["m_end"])
	if pr["error"] != "":
		diags.append(pr["error"])
		return { "ok": false }
	var render_roots := (pr["nodes"] as Array).filter(func(nd): return nd != null)
	if render_roots.size() != 1:
		diags.append("GUITKX0108: a component must return exactly one root element (got %d)" % render_roots.size())
		return { "ok": false }
	return { "ok": true, "name": comp_name, "params": params, "setup": split["setup"], "root": render_roots[0], "next": bclose + 1 }

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
	for h in HOOK_NAMES:   # single source of truth (all 23 hooks), camelCase
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
	if is_loop:
		if nodes.size() > 1:
			# A loop body must have a single root (like a component) so each iteration yields one keyed
			# child. Wrap siblings in a fragment <>...</> with distinct keys. (Parity: Unity UITKX0108.)
			diags.append("GUITKX0108: a @for/@while body must contain exactly one root element (got %d) -- wrap siblings in a fragment <>...</>" % nodes.size())
		elif nodes.size() == 1 and (nodes[0] as Dictionary).get("t", "") == "el":
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
			diags.append("GUITKX0104 (warning): duplicate key '%s' among sibling elements" % k.substr(2))
		seen[k] = true

static func _has_key(el: Dictionary) -> bool:
	for a in el.get("attrs", []):
		if a["name"] == "key":
			return true
	return false

## A comparable signature for an element's `key`, so sibling duplicates are caught for BOTH literal
## (key="x") and expression (key={ str(i) }) keys — two siblings with the SAME key expression collide
## every iteration, while genuinely-different expressions are left alone. Prefixed "s:"/"e:" so a
## string key never false-collides with an expr key. "" = no key.
static func _literal_key(el: Dictionary) -> String:
	for a in el.get("attrs", []):
		if a["name"] == "key":
			if a["kind"] == "str":
				return "s:" + str(a["value"])
			if a["kind"] == "expr":
				return "e:" + str(a["value"]).strip_edges()
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
	# optional `-> ReturnHint` — PRESERVED so callers' `:=` type-inference works; tuple-style
	# `-> (a, b)` is dropped (GDScript has no tuple type — a multi-value hook returns an Array). [audit]
	var ret_hint := ""
	j = _skip_ws_only(source, j)
	if j + 1 < n and source[j] == "-" and source[j + 1] == ">":
		var rh := j + 2
		while j < n and source[j] != "{":
			j += 1
		ret_hint = source.substr(rh, j - rh).strip_edges()
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
	out += "static func %s(%s)%s:\n" % [hook_name, params, _ret_suffix(ret_hint)]
	var body_block := _reindent_setup(_apply_hook_aliases(body))
	out += (body_block + "\n") if body_block != "" else "\tpass\n"
	return { "ok": true, "gd": out, "diagnostics": diags }

## Parse ONE hook declaration at `hi`. Returns { ok, name, params, body, next } or { ok:false }.
static func _parse_hook_at(source: String, hi: int, diags: Array) -> Dictionary:
	var n := source.length()
	var j := hi + 4
	j = _skip_ws_only(source, j)
	var ns := j
	while j < n and L._is_ident(source[j]):
		j += 1
	var hook_name := source.substr(ns, j - ns)
	if hook_name == "":
		diags.append("GUITKX0300: missing hook name")
		return { "ok": false }
	var params := ""
	j = _skip_ws_only(source, j)
	if j < n and source[j] == "(":
		var pc := L.find_matching(source, j)
		if pc == -1:
			diags.append("GUITKX0304: unclosed `(` in hook params")
			return { "ok": false }
		params = source.substr(j + 1, pc - j - 1)
		j = pc + 1
	var ret_hint := ""
	j = _skip_ws_only(source, j)
	if j + 1 < n and source[j] == "-" and source[j + 1] == ">":
		var rh := j + 2
		while j < n and source[j] != "{":
			j += 1
		ret_hint = source.substr(rh, j - rh).strip_edges()
	j = _skip_ws_only(source, j)
	if j >= n or source[j] != "{":
		diags.append("GUITKX0303: hook body `{ ... }` expected")
		return { "ok": false }
	var bclose := L.find_matching(source, j)
	if bclose == -1:
		diags.append("GUITKX0304: unclosed hook body")
		return { "ok": false }
	return { "ok": true, "name": hook_name, "params": params, "ret": ret_hint, "body": source.substr(j + 1, bclose - j - 1), "next": bclose + 1 }

## module Name { component A {…} component B {…} hook use_x {…} } -> one class with one static func
## per declaration. Intra-module <A/> resolves to the bare sibling static func (V.fc(A, …)). [§4]
static func _compile_module(source: String, mi: int, class_name_override: String, basename: String, diags: Array) -> Dictionary:
	var n := source.length()
	var j := mi + 6   # "module"
	j = _skip_ws_only(source, j)
	var ns := j
	while j < n and L._is_ident(source[j]):
		j += 1
	var mod_name := source.substr(ns, j - ns)
	if mod_name == "":
		diags.append("GUITKX0300: `module` requires a name (module Name { ... })")
		return { "ok": false, "gd": "", "diagnostics": diags }
	j = _skip_ws_only(source, j)
	if j >= n or source[j] != "{":
		diags.append("GUITKX0303: module body `{ ... }` expected")
		return { "ok": false, "gd": "", "diagnostics": diags }
	var bclose := L.find_matching(source, j)
	if bclose == -1:
		diags.append("GUITKX0304: unclosed module body")
		return { "ok": false, "gd": "", "diagnostics": diags }
	var body_end := bclose
	var comps: Array = []
	var hooks: Array = []
	var module_comps := {}
	var module_hooks: Array = []
	var i := j + 1
	while i < body_end:
		var d := _find_decl(source, i)
		if d["kind"] == "" or d["at"] >= body_end:
			break
		if d["kind"] == "component":
			var c := _parse_component_at(source, d["at"], diags)
			if not c["ok"]:
				return { "ok": false, "gd": "", "diagnostics": diags }
			if module_comps.has(c["name"]) or c["name"] in module_hooks:
				diags.append("GUITKX0112: duplicate declaration `%s` in module `%s`" % [c["name"], mod_name])
				return { "ok": false, "gd": "", "diagnostics": diags }
			module_comps[c["name"]] = true
			comps.append(c)
			i = c["next"]
		elif d["kind"] == "hook":
			var h := _parse_hook_at(source, d["at"], diags)
			if not h["ok"]:
				return { "ok": false, "gd": "", "diagnostics": diags }
			if module_comps.has(h["name"]) or h["name"] in module_hooks:
				diags.append("GUITKX0112: duplicate declaration `%s` in module `%s`" % [h["name"], mod_name])
				return { "ok": false, "gd": "", "diagnostics": diags }
			module_hooks.append(h["name"])
			hooks.append(h)
			i = h["next"]
		else:
			diags.append("GUITKX0110: nested `module` is not allowed")
			return { "ok": false, "gd": "", "diagnostics": diags }
	if comps.is_empty() and hooks.is_empty():
		diags.append("GUITKX0110: module `%s` has no component or hook declarations" % mod_name)
		return { "ok": false, "gd": "", "diagnostics": diags }
	var cls := class_name_override if class_name_override != "" else mod_name
	var out := "class_name %s\nextends RefCounted\n## AUTO-GENERATED from %s.guitkx -- do not edit.\n\n" % [cls, basename]
	for c in comps:
		_validate(c["setup"], c["root"], diags)
		out += "# component %s\n" % c["name"]
		out += _emit_func(c["name"], c["params"], c["setup"], c["root"], module_comps, module_hooks, diags)
		out += "\n"
	for h in hooks:
		out += "# hook %s\n" % h["name"]
		out += "static func %s(%s)%s:\n" % [h["name"], h["params"], _ret_suffix(h.get("ret", ""))]
		var hb := _reindent_setup(_apply_hook_aliases(h["body"], module_hooks))
		out += (hb + "\n") if hb != "" else "\tpass\n"
		out += "\n"
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
				# `return null` may be a CONDITIONAL guard (e.g. `if not ready: return null`); keep
				# scanning for a later markup return rather than failing the whole compile. [audit]
				i = p + 4
				continue
		i += 1
	return { "error": "GUITKX0102: component has no `return ( ... )` (only `return null`?)" }

# --- emit ---
# Control flow is hoisted into pre-statements (an if/for/while block before the return) that
# assign a fresh `__cfN` local, which the markup then references. This sidesteps both GDScript's
# "lambdas can't hold multi-statement return control-flow" limit AND the helper-method
# locals-capture problem -- the block is inline in render() and sees all setup locals. The
# runtime `V._norm` flattens the `@for` arrays and drops the null `@if` misses for free.
static func _emit(cls: String, comp_name: String, params: String, setup: String, root: Dictionary, basename: String, diags: Array = []) -> String:
	var out := "class_name %s\n" % cls
	out += "extends RefCounted\n"
	out += "## AUTO-GENERATED from %s.guitkx -- do not edit.\n\n" % basename
	out += _emit_func("render", params, setup, root, {}, [], diags)
	return out

# Emit one `static func <name>(props, children) -> RUIVNode:` from params + setup + a markup root.
# `module_comps` maps intra-module component names -> true so <Foo/> emits V.fc(Foo, ...) (bare
# sibling static func) rather than the single-file V.fc(Foo.render, ...).
static func _emit_func(func_name: String, params: String, setup: String, root: Dictionary, module_comps: Dictionary, skip_hooks: Array = [], diags: Array = []) -> String:
	var out := "static func %s(props: Dictionary, children: Array) -> RUIVNode:\n" % func_name
	for p in _parse_params(params):
		if p["default"] != "":
			out += "\tvar %s = props.get(\"%s\", %s)\n" % [p["name"], p["name"], p["default"]]
		else:
			out += "\tvar %s = props.get(\"%s\")\n" % [p["name"], p["name"]]
	var setup_block := _reindent_setup(_apply_hook_aliases(setup, skip_hooks))
	if setup_block != "":
		out += setup_block + "\n"
	# expr_mode: true while emitting a JSX-VALUE substring (markup inside an embedded {expr}/lambda),
	# where control-flow MUST be lowered to an inline expression (ternary / .map) instead of hoisted
	# render-level statements that can't see lambda-local vars. [audit #17]
	var ctx := { "lines": [], "indent": 1, "counter": 0, "module_comps": module_comps, "diags": diags, "expr_mode": false }
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
			return "(%s)" % _splice_expr_markup(nd["code"], ctx)
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

# Text-bearing host factories: a `<Label>text</Label>` / `<Button>Click {x}</Button>` whose children
# are all text/expr folds them into the `.text` prop instead of nesting child Labels (Phase 7.2).
const TEXT_FACTORIES := {
	"label": true, "button": true, "check_box": true, "check_button": true,
	"link_button": true, "menu_button": true, "option_button": true, "rich_text": true,
}

static func _has_attr(nd: Dictionary, name: String) -> bool:
	for a in nd["attrs"]:
		if a["name"] == name:
			return true
	return false

static func _all_text_children(children: Array) -> bool:
	if children.is_empty():
		return false
	for c in children:
		if c == null:
			continue
		if not (c["t"] == "text" or c["t"] == "expr"):
			return false
	return true

static func _merge_text_children(children: Array, ctx: Dictionary) -> String:
	var parts: Array = []
	for c in children:
		if c == null:
			continue
		if c["t"] == "text":
			parts.append(_gd_str(c["value"]))
		else:
			parts.append("str(%s)" % _splice_expr_markup(c["code"], ctx))
	return " + ".join(parts)

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
	# build the props dict + pull out key. `{...spread}` attrs are merged left-to-right (later wins),
	# order-preserving relative to explicit props, via V._spread_all([...]). No spread -> plain literal
	# (unchanged hot path).
	var props_parts: Array = []
	var key_expr := ""
	var has_spread := false
	for a in nd["attrs"]:
		if a.get("kind", "") == "spread":
			has_spread = true
			break
	var segments: Array = []   # only used when has_spread: ordered dict-exprs to merge
	for a in nd["attrs"]:
		if a.get("kind", "") == "spread":
			if not props_parts.is_empty():
				segments.append("{ %s }" % ", ".join(props_parts))
				props_parts = []
			segments.append("(%s)" % a["value"])
			continue
		var name: String = a["name"]
		var valcode := _attr_value_code(a, ctx)
		if name == "key":
			key_expr = valcode
			continue
		props_parts.append("\"%s\": %s" % [name, valcode])
	# Fold all-text/expr children of a text-bearing host into the `text` prop (no nested Labels).
	var children: Array = nd["children"]
	if is_host and TEXT_FACTORIES.has(factory) and not _has_attr(nd, "text") and _all_text_children(children):
		props_parts.append("\"text\": %s" % _merge_text_children(children, ctx))
		children = []
	var props_dict: String
	if has_spread:
		if not props_parts.is_empty():
			segments.append("{ %s }" % ", ".join(props_parts))
		props_dict = "V._spread_all([%s])" % ", ".join(segments)
	else:
		props_dict = "{ %s }" % ", ".join(props_parts) if not props_parts.is_empty() else "{}"
	var children_src := _emit_children_array(children, ctx)
	if is_host:
		var args := props_dict
		if children_src != "[]":
			args += ", " + children_src
		if key_expr != "":
			args += (", []" if children_src == "[]" else "") + ", " + key_expr
		return "V.%s(%s)" % [factory, args]
	else:
		# child component -> V.fc(Tag.render, ...); a module-local component is a bare sibling
		# static func -> V.fc(Tag, ...) (see _compile_module).
		var fn := tag if (ctx.get("module_comps", {}) as Dictionary).has(tag) else (tag + ".render")
		var args2 := "%s, %s" % [fn, props_dict]
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
	if ctx.get("expr_mode", false):
		return _emit_if_inline(nd, ctx)
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
	if ctx.get("expr_mode", false):
		if kind == "for":
			return _emit_for_inline(nd, ctx)
		return _expr_ctrl_unsupported(ctx, "@while")   # a while-loop can't be an expression
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
	if ctx.get("expr_mode", false):
		return _expr_ctrl_unsupported(ctx, "@match")   # a match-statement can't be an expression
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

# --- inline (expression-context) control-flow lowering [audit #17] ---
# Used when control-flow appears inside a JSX-VALUE ({expr} / lambda return), where hoisted
# render-level statements would reference out-of-scope lambda locals. `@if`/`@elif`/`@else` become a
# (possibly nested) ternary; `@for` becomes `.map`. Bodies recurse through _emit_body with expr_mode
# still on, so nested control-flow inlines too.

static func _emit_if_inline(nd: Dictionary, ctx: Dictionary) -> String:
	var branches: Array = nd["branches"]
	var acc := "null"
	if nd["else_body"] != null:
		acc = _emit_body(nd["else_body"], ctx)
	for i in range(branches.size() - 1, -1, -1):
		var br: Dictionary = branches[i]
		var be := _emit_body(br["body_markup"], ctx)
		acc = "(%s if (%s) else %s)" % [be, br["cond"], acc]
	return acc

static func _emit_for_inline(nd: Dictionary, ctx: Dictionary) -> String:
	# header is "x in xs" -> `(xs).map(func(x): return body)`. The iterable must be array-like (Array
	# or range()); for non-array iterables lift the @for to the top-level markup instead.
	var split := _split_for_header(str(nd["header"]))
	if split.is_empty():
		return _expr_ctrl_unsupported(ctx, "@for (could not parse the loop header)")
	var be := _emit_body(nd["body_markup"], ctx)
	return "(%s).map(func(%s): return %s)" % [split["iter"], split["var"], be]

static func _split_for_header(header: String) -> Dictionary:
	var at := header.find(" in ")
	if at < 0:
		return {}
	var v := header.substr(0, at).strip_edges()
	var it := header.substr(at + 4).strip_edges()
	if v == "" or it == "":
		return {}
	return { "var": v, "iter": it }

static func _expr_ctrl_unsupported(ctx: Dictionary, what: String) -> String:
	var msg := "GUITKX0113: %s cannot be used inside an embedded {expression} / JSX-value (it can't be lowered to an expression). Lift it to the top-level markup return, or use .map() for lists." % what
	if ctx.has("diags") and ctx["diags"] is Array:
		(ctx["diags"] as Array).append(msg)
	push_warning("[guitkx] " + msg)
	return "null"

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

static func _attr_value_code(a: Dictionary, ctx: Dictionary) -> String:
	match a["kind"]:
		"str":
			return _gd_str(a["value"])
		"expr":
			return _splice_expr_markup(a["value"], ctx)
		"bool":
			return "true"
	return "null"

# --- JSX-as-value: lower markup nested inside an embedded GDScript expression (Phase 4 §1) ---
# `cond if c else <A/>`, `is_open and <Panel/>`, `{ items.map(func(it): return <Row/>) }`.
static func _splice_expr_markup(expr: String, ctx: Dictionary) -> String:
	var ranges := JsxScan.find_markup_ranges(expr, 0, expr.length())
	if ranges.is_empty():
		return expr   # fast path: no nested markup, emit the expression verbatim
	var out := ""
	var prev := 0
	for r in ranges:
		var rs: int = r["start"]
		if rs < prev:
			continue   # nested inside an already-emitted range
		var markup := _emit_markup_substring(expr, rs, r["end"], ctx)
		var op: String = r["op"]
		if op == "and" or op == "&&":
			# desugar `LHS and <A/>` -> `(V.a() if (LHS) else null)`
			var op_pos: int = r["op_pos"]
			var lhs_start := _find_lhs_start(expr, prev, op_pos)
			out += expr.substr(prev, lhs_start - prev)
			var lhs := expr.substr(lhs_start, op_pos - lhs_start).strip_edges()
			out += "(%s if (%s) else null)" % [markup, lhs]
		else:
			out += expr.substr(prev, rs - prev)
			out += markup
		prev = r["end"]
	out += expr.substr(prev)
	return out

# Re-parse a markup substring [start,end) of `src` and emit it via the normal node emitter (so
# nested attrs/children/control-flow + further nested markup all lower). Single root expected.
# KNOWN LIMITATION [audit #17]: control-flow (@if/@for/@while/@match) nested inside a JSX-VALUE that
# sits in a LAMBDA body (e.g. `items.map(func(it): return <>@if (it.ok) { … }</>)`) hoists its
# `if/for` pre-statements to render() top-level, where the lambda's locals (`it`) are out of scope.
# Lift `@while`/`@match` to the top-level markup return (they can't be expressions); `@if`/`@elif`/
# `@else` and `@for` ARE lowered inline here (ternary / .map), so they work inside lambdas. [audit #17]
static func _emit_markup_substring(src: String, start: int, end: int, ctx: Dictionary) -> String:
	var parser := Markup.new()
	var pr := parser.parse(src, start, end)
	if pr["error"] != "":
		return "null"
	var nodes: Array = (pr["nodes"] as Array).filter(func(x): return x != null)
	if nodes.is_empty():
		return "null"
	# Mark this whole subtree as an expression context: control-flow inside it must lower to an
	# inline expression (no hoisted render-level statements that lambda locals can't reach).
	var prev_expr: bool = ctx.get("expr_mode", false)
	ctx["expr_mode"] = true
	var result: String
	if nodes.size() == 1:
		result = _emit_expr(nodes[0], ctx)
	else:
		var parts: Array = []
		for nx in nodes:
			parts.append(_emit_expr(nx, ctx))
		result = "V.fragment([%s])" % ", ".join(parts)
	ctx["expr_mode"] = prev_expr
	return result

# The start of the `and`/`&&` left operand: the last depth-0 lower-precedence boundary
# (or / , / ; / if / else) at or after `from`, else `from`.
static func _find_lhs_start(src: String, from: int, op_pos: int) -> int:
	var lhs := from
	var i := from
	var depth := 0
	while i < op_pos:
		var j := L.skip_noncode(src, i)
		if j != i:
			i = j
			continue
		var c := src[i]
		if c == "(" or c == "[":
			depth += 1
		elif c == ")" or c == "]":
			depth -= 1
		elif depth == 0:
			if c == "," or c == ";":
				lhs = i + 1
			elif i == from or not L._is_ident(src[i - 1]):
				if L.keyword_at(src, i, "or"):
					lhs = i + 2
				elif L.keyword_at(src, i, "if"):
					lhs = i + 2
				elif L.keyword_at(src, i, "else"):
					lhs = i + 4
		i += 1
	return lhs

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

const HOOK_NAMES := ["useState", "useReducer", "useRef", "useMemo", "useCallback", "useImperativeHandle",
	"useEffect", "useLayoutEffect", "createContext", "useContext", "provideContext", "useDeferredValue",
	"useTransition", "useStableCallback", "useStableFunc", "useStableAction", "useSafeArea", "useSignal",
	"useSignalKey", "useTween", "useTweenValue", "useAnimate", "useSfx"]

## Auto-prefix bare hook CALLS to Hooks.* (useState(...) -> Hooks.useState(...)). Single
## token-boundary pass that skips strings/comments (via skip_noncode), only matches a hook name at
## a real token start that is immediately CALLED (followed by `(`), and leaves already-qualified
## `Hooks.use_*` and look-alike identifiers/strings (my_use_state, "useState()") untouched.
## `skip` lists names to NOT prefix (module-local hooks, see _compile_module).
static func _apply_hook_aliases(setup: String, skip: Array = []) -> String:
	var out := ""
	var i := 0
	var n := setup.length()
	while i < n:
		var j := L.skip_noncode(setup, i)
		if j != i:
			out += setup.substr(i, j - i)   # copy string/comment verbatim
			i = j
			continue
		# Only auto-prefix a FREE hook identifier — never a member call like `counter.useState(...)`
		# (a preceding `.` is a non-identifier boundary, so guard against it explicitly). [audit]
		if i == 0 or (not L._is_ident(setup[i - 1]) and setup[i - 1] != "."):
			var matched := ""
			for h in HOOK_NAMES:
				if h in skip:
					continue
				if L.keyword_at(setup, i, h) and _is_call_at(setup, i + h.length()):
					matched = h
					break
			if matched != "":
				var already := i >= 6 and setup.substr(i - 6, 6) == "Hooks."
				out += matched if already else ("Hooks." + matched)
				i += matched.length()
				continue
		out += setup[i]
		i += 1
	return out

# True if, skipping spaces/tabs from `at`, the next char is `(` (i.e. the name is being called).
static func _is_call_at(s: String, at: int) -> bool:
	var n := s.length()
	while at < n and (s[at] == " " or s[at] == "\t"):
		at += 1
	return at < n and s[at] == "("


## Render a `-> ReturnType` suffix for a generated function signature. Empty when there is no hint;
## tuple-style `-> (a, b)` is dropped (GDScript has no tuple type — see _compile_hook).
static func _ret_suffix(ret: String) -> String:
	ret = ret.strip_edges()
	if ret == "" or ret.begins_with("("):
		return ""
	return " -> " + ret

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
