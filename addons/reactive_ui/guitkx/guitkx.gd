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
##
## DIAGNOSTICS (T0.2): every entry in `diagnostics` is a structured Dictionary from RUIGuitkxDiag —
## { code, severity, message, offset, length } with `offset`/`length` in characters into the ORIGINAL
## .guitkx source (offset -1 = whole file). Render with RUIGuitkxDiag.format(); never string-sniff.
## Internally, markup-node offsets are relative to the string their parser saw; `base` values thread
## the absolute position of that string's index 0 so nested re-parses compose (see _cbase).

const L = preload("res://addons/reactive_ui/guitkx/guitkx_lexer.gd")
const Markup = preload("res://addons/reactive_ui/guitkx/guitkx_markup.gd")
const JsxScan = preload("res://addons/reactive_ui/guitkx/guitkx_jsx_scan.gd")
const D = preload("res://addons/reactive_ui/guitkx/guitkx_diag.gd")

## Language vocabulary — SINGLE SOURCE OF TRUTH is vocabulary.json (T0.3), shared verbatim with the
## LSP (schema.ts/virtualDoc.ts consume the byte-identical copy shipped in the extension; tests on
## both sides enforce the sync, and a reflection tripwire pins v_factories to core/v.gd's statics).
static var _VOCAB: Dictionary = _load_vocabulary()
## PascalCase/markup tag -> V.* host factory (the analog of uitkx's reflected V map). A tag here =
## host element; anything else PascalCase = component.
static var HOST_TAGS: Dictionary = _VOCAB["host_tags"]
## The auto-prefixable hook names (bare useX( -> Hooks.useX(), camelCase.
static var HOOK_NAMES: Array = _VOCAB["hooks"]
## Public V.* factory names (lowercase-tag namespace) — reserved for T1.5 unknown-tag validation.
static var V_FACTORIES: Array = _VOCAB["v_factories"]

static func _load_vocabulary() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://addons/reactive_ui/guitkx/vocabulary.json"))
	if parsed is Dictionary and (parsed as Dictionary).has("host_tags") and (parsed as Dictionary).has("hooks"):
		return parsed
	# assert() is stripped from release exports, so fail LOUDLY but non-fatally: the compiler is
	# editor tooling and must never crash a game that accidentally loads this script.
	push_error("[guitkx] vocabulary.json missing or invalid -- the compiler cannot classify tags/hooks without it")
	return { "host_tags": {}, "hooks": [], "v_factories": [], "directives": [] }

## `known_components`: PascalCase class names resolvable as components in this project (sibling
## .guitkx bindings + global script classes) -- the plugin/codegen supplies them so <UnknownComp/>
## errors (T1.5). Empty (headless/test callers) = the PascalCase check is skipped; lowercase tags
## are always checked against the vocabulary.
static func compile(source: String, basename: String = "Component", known_components: Array = []) -> Dictionary:
	var diags: Array = []
	var known := {}
	for kc in known_components:
		known[str(kc)] = true
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
				diags.append(D.make("GUITKX0300", D.ERROR, "`@class_name` value must be a single valid identifier (got '%s')" % class_name_override, i, le - i))
				return { "ok": false, "gd": "", "diagnostics": diags }
			i = le
			continue
		break
	# 2. Detect the declaration kind (component | hook | module) and dispatch.
	var decl := _find_decl(source, i)
	# T2.6: _find_decl SKIPS anything before the keyword -- real content there (a stray statement, a
	# misspelled directive) used to vanish silently. Same 2105 family as trailing junk (T1.3).
	if decl["kind"] != "":
		var lead_junk := _first_real(source, i, int(decl["at"]))
		if lead_junk != -1:
			var jle := source.find("\n", lead_junk)
			if jle == -1 or jle > int(decl["at"]):
				jle = int(decl["at"])
			diags.append(D.make("GUITKX2105", D.ERROR, "invalid content before the `%s` declaration" % decl["kind"], lead_junk, maxi(1, jle - lead_junk)))
	var r: Dictionary
	match decl["kind"]:
		"component":
			r = _compile_component(source, decl["at"], class_name_override, basename, diags, known)
		"hook":
			r = _compile_hook(source, decl["at"], class_name_override, basename, diags)
		"module":
			r = _compile_module(source, decl["at"], class_name_override, basename, diags, known)
		_:
			var near := _nearest_decl_keyword(source, i)
			if near.has("word"):
				diags.append(D.make("GUITKX0102", D.ERROR, "unknown declaration '%s' -- did you mean '%s'?" % [near["word"], near["kw"]], near["at"], (near["word"] as String).length()))
			else:
				diags.append(D.make("GUITKX0102", D.ERROR, "no `component`, `hook`, or `module` declaration found"))
			return { "ok": false, "gd": "", "diagnostics": diags }
	# Invariant (T1.1): an error-severity diagnostic can NEVER coexist with ok:true, no matter which
	# code path appended it (validation, emit, or a future one) -- broken output must not ship.
	if r.get("ok", false) and D.has_error(r.get("diagnostics", [])):
		r["ok"] = false
		r["gd"] = ""
	return r

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
				return { "word": word, "kw": best, "at": s }
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

static func _compile_component(source: String, ci: int, class_name_override: String, basename: String, diags: Array, known: Dictionary = {}) -> Dictionary:
	var pc := _parse_component_at(source, ci, diags)
	if not pc["ok"]:
		return { "ok": false, "gd": "", "diagnostics": diags }
	_error_on_trailing(source, int(pc["next"]), "component", diags)
	_validate_unused_params(pc["params"], int(pc.get("params_at", -1)), source.substr(int(pc["body_at"]), int(pc["next"]) - 1 - int(pc["body_at"])), diags)
	if class_name_override == "" and pc["name"] != basename:
		diags.append(D.make("GUITKX0103", D.WARNING, "component `%s` differs from file name `%s`" % [pc["name"], basename], pc["name_at"], (pc["name"] as String).length()))
	_validate(pc["setup"], pc["root"], diags, pc["body_at"])
	# A hard-error diagnostic from validation (e.g. GUITKX0108 in a loop body) fails the compile —
	# warnings/hints do not.
	if D.has_error(diags):
		return { "ok": false, "gd": "", "diagnostics": diags }
	var cls: String = class_name_override if class_name_override != "" else pc["name"]
	var gd := _emit(cls, pc["name"], pc["params"], pc["setup"], pc["root"], basename, diags, pc["body_at"], known)
	# T1.1: errors appended DURING emit (GUITKX0113 undesugarable control-flow, nested-body parse
	# errors) must fail the compile too -- the pre-emit gate above cannot see them.
	if D.has_error(diags):
		return { "ok": false, "gd": "", "diagnostics": diags }
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
		diags.append(D.make("GUITKX0300", D.ERROR, "missing component name", j))
		return { "ok": false }
	# T2.6 (Unity UITKX2100): component names are PascalCase -- they become the generated class_name
	# and the <Tag/> other files reference. Parsing continues so further diagnostics still surface.
	if not (comp_name[0] >= "A" and comp_name[0] <= "Z"):
		diags.append(D.make("GUITKX2100", D.ERROR, "component name `%s` must be PascalCase" % comp_name, ns, comp_name.length()))
	var params := ""
	var params_at := -1
	j = _skip_ws_only(source, j)
	if j < n and source[j] == "(":
		var pc := L.find_matching(source, j)
		if pc == -1:
			diags.append(D.make("GUITKX0304", D.ERROR, "unclosed `(` in component params", j, 1))
			return { "ok": false }
		params = source.substr(j + 1, pc - j - 1)
		params_at = j + 1
		j = pc + 1
	j = _skip_ws_only(source, j)
	if j >= n or source[j] != "{":
		diags.append(D.make("GUITKX0303", D.ERROR, "component body `{ ... }` expected", mini(j, n - 1)))
		return { "ok": false }
	var bclose := L.find_matching(source, j)
	if bclose == -1:
		diags.append(D.make("GUITKX0304", D.ERROR, "unclosed component body", j, 1))
		return { "ok": false }
	var body := source.substr(j + 1, bclose - j - 1)
	var body_at := j + 1   # absolute offset of body[0] in `source`; rebases body-relative offsets
	var split := _split_return(body)
	# T1.4: demoted returns (early top-level ones, and markup-shaped statement-level ones) are errors
	# regardless of whether a final markup return was also found.
	for b in split.get("bad", []):
		diags.append(D.make("GUITKX2102", D.ERROR, b["msg"], body_at + int(b["at"]), maxi(1, int(b["to"]) - int(b["at"]))))
	if split.has("error"):
		diags.append(D.rebase(split["error"], body_at))
		return { "ok": false }
	# T1.4 (Unity LooksLikeMarkupRoot parity): the chosen return's content must BE markup -- an
	# element, `<>` fragment, @directive, or `{expr}` -- not a plain parenthesized value. Markup
	# comments before the root are skipped, exactly like Unity's TrySkipNonCodeSpan.
	var mfirst := _first_markup_real(body, int(split["m_start"]), int(split["m_end"]))
	if mfirst == -1 or not (body[mfirst] == "<" or body[mfirst] == "@" or body[mfirst] == "{"):
		diags.append(D.make("GUITKX2102", D.ERROR, "`return` must return markup (an element, `<>` fragment, @directive, or `{expr}`)", body_at + int(split.get("chosen_at", int(split["m_start"]))), 6))
		return { "ok": false }
	# BUG-V5: any real code after the markup return is unreachable (the compiler drops it).
	var unreach_first := _first_real(body, int(split["m_end"]) + 1, body.length())
	if unreach_first != -1:
		var unreach_last := _last_real(body, int(split["m_end"]) + 1, body.length())
		diags.append(D.make("GUITKX0114", D.WARNING, "unreachable code after the component's markup return -- a component has a single return; later statements are ignored", body_at + unreach_first, unreach_last - unreach_first + 1))
	var parser := Markup.new()
	var pr := parser.parse(split["markup_src"], split["m_start"], split["m_end"])
	if pr["error"] != "":
		diags.append(D.make(pr["error_code"], D.ERROR, pr["error_msg"], body_at + maxi(0, int(pr["error_at"])), 1))
		return { "ok": false }
	# comments emit nothing, so they are not render roots (T2.1)
	var render_roots := (pr["nodes"] as Array).filter(func(nd): return nd != null and (nd as Dictionary).get("t", "") != "comment")
	if render_roots.size() != 1:
		var extra_at: int = int(render_roots[1]["at"]) if render_roots.size() > 1 else int(split["m_start"])
		diags.append(D.make("GUITKX0108", D.ERROR, "a component must return exactly one root element (got %d)" % render_roots.size(), body_at + extra_at, 1))
		return { "ok": false }
	# window_nodes = ALL window nodes incl. comments (T2.1) -- the formatter re-emits them in order;
	# root = the single render root the emitter compiles.
	return { "ok": true, "name": comp_name, "name_at": ns, "params": params, "params_at": params_at, "setup": split["setup"], "root": render_roots[0], "window_nodes": pr["nodes"], "body_at": body_at, "next": bclose + 1 }

# --- semantic validation (warnings; they don't fail the compile) ---
# `base` = absolute offset (in the original source) of index 0 of the string the node offsets/setup
# offsets are relative to (-1 = unknown -> diagnostics fall back to whole-file).
static func _validate(setup: String, root: Dictionary, diags: Array, base: int = -1) -> void:
	_validate_hooks(setup, diags, base)
	_validate_effect_deps(setup, diags, base)
	_validate_node(root, diags, base)

## Compose a child base: rebase `rel` (an offset within the current string) onto `base`.
static func _cbase(base: int, rel: int) -> int:
	return -1 if (base < 0 or rel < 0) else base + rel

## Rules of hooks (T2.5, Unity 0013-0016): hooks must run unconditionally at the top level of setup.
## Deterministic block-opener STACK over the lines (replacing the old one-shot indent heuristic):
## a hook call under an if/elif/else block is 0013, for/while 0014, match 0015, and a func():
## lambda/callback 0016. Depth is measured in LEVELS (tab+spaces mixes stay invisible-safe, same
## _indent_unit/_indent_depth as emission). Runs on component setup, hook declaration bodies, and
## module members alike; every violating call is reported (not just the first).
static func _validate_hooks(setup: String, diags: Array, base_off: int = -1) -> void:
	var lines := setup.split("\n")
	var unit := _indent_unit(lines)
	var stack: Array = []   # [{ depth, kind }] of enclosing block openers
	var off := 0
	for l in lines:
		var s := l as String
		var t := s.strip_edges()
		if t == "" or t.begins_with("#"):
			off += s.length() + 1
			continue
		var d := _indent_depth(s, unit)
		while not stack.is_empty() and int(stack[-1]["depth"]) >= d:
			stack.pop_back()
		var call_at := _find_hook_call(s)
		if call_at != -1:
			var kind := ""
			if not stack.is_empty():
				kind = str(stack[-1]["kind"])
			elif ":" in s and s.find(":") < call_at:
				# single-line `if x: use_y()` / `var f = func(): use_y()` -- the opener must PRECEDE
				# the call, else `useEffect(func(): ...)` (outer call, legal) would false-flag.
				kind = _block_opener_kind(t.substr(0, t.find(":") + 1))
			if kind != "":
				var code := "GUITKX0013"
				var what := "conditionally (inside an if/else block)"
				if kind == "for" or kind == "while":
					code = "GUITKX0014"
					what = "inside a loop"
				elif kind == "match":
					code = "GUITKX0015"
					what = "inside a match branch"
				elif kind == "func":
					code = "GUITKX0016"
					what = "inside a callback/lambda"
				var lead := _leading_ws(s).length()
				diags.append(D.make(code, D.ERROR, "hook called %s -- hooks must run unconditionally at the top of setup" % what, _cbase(base_off, off + lead), t.length()))
		if t.ends_with(":"):
			var kind2 := _block_opener_kind(t)
			if kind2 != "":
				stack.append({ "depth": d, "kind": kind2 })
		off += s.length() + 1

## T2.7 (Unity UITKX0111): a declared component parameter never referenced in the body (setup or
## markup). Underscore-prefixed names are deliberately-unused by GDScript convention and stay quiet.
static func _validate_unused_params(params: String, params_at: int, body: String, diags: Array) -> void:
	if params.strip_edges() == "":
		return
	for p in _parse_params(params):
		var name := str(p["name"])
		if name == "" or name.begins_with("_"):
			continue
		if _find_ident(body, name) == -1:
			var at := _find_ident(params, name)
			diags.append(D.make("GUITKX0111", D.WARNING, "component parameter `%s` is never used" % name, (params_at + at) if (params_at >= 0 and at >= 0) else -1, name.length()))

## First token-boundary occurrence of identifier `name` in `s` (strings/comments skipped), or -1.
static func _find_ident(s: String, name: String) -> int:
	var i := 0
	var n := s.length()
	while i < n:
		var j := L.skip_noncode(s, i)
		if j != i:
			i = j
			continue
		if (i == 0 or not L._is_ident(s[i - 1])) and L.keyword_at(s, i, name):
			return i
		i += 1
	return -1

## T2.7 (Unity UITKX0018, source-gen-only there too): an effect hook called with ONLY a callback --
## no dependency array -- runs on every render; almost always a mistake. Warning at the call.
static func _validate_effect_deps(setup: String, diags: Array, base_off: int = -1) -> void:
	var i := 0
	var n := setup.length()
	while i < n:
		var j := L.skip_noncode(setup, i)
		if j != i:
			i = j
			continue
		var boundary := i == 0 or (not L._is_ident(setup[i - 1]) and setup[i - 1] != ".")
		var hooks_member := i >= 6 and setup.substr(i - 6, 6) == "Hooks."   # Hooks.useEffect counts
		if boundary or hooks_member:
			var matched := ""
			for h in ["useEffect", "useLayoutEffect"]:
				if L.keyword_at(setup, i, h):
					matched = h
					break
			if matched != "":
				var p := i + matched.length()
				while p < n and (setup[p] == " " or setup[p] == "\t"):
					p += 1
				if p < n and setup[p] == "(":
					var close := L.find_matching(setup, p)
					if close != -1:
						var inner := setup.substr(p + 1, close - p - 1)
						if inner.strip_edges() != "" and _split_top_commas(inner).size() == 1:
							diags.append(D.make("GUITKX0018", D.WARNING, "%s has no dependency array -- it will run on every render; pass [] (or deps) as the second argument" % matched, _cbase(base_off, i), matched.length()))
						i = close + 1
						continue
				i += matched.length()
				continue
		i += 1

## Classify a `...:`-terminated line as a hook-blocking block opener ("" = not one, e.g. a dict key).
static func _block_opener_kind(t: String) -> String:
	for kw in ["if", "elif", "else", "for", "while", "match"]:
		if t == kw + ":" or t.begins_with(kw + " ") or t.begins_with(kw + "("):
			return "if" if (kw == "elif" or kw == "else") else kw
	if t.begins_with("func") or "func(" in t or "func (" in t:
		return "func"
	return ""

## Token-boundary hook-call detection (a `my_useState(` look-alike or `obj.useState(` member call is
## NOT a hook call). Shared by setup-line scanning and markup {expr} checks (0016).
static func _expr_calls_hook(code: String) -> bool:
	return _find_hook_call(code) != -1

## Offset of the first token-boundary hook CALL in `code`, or -1.
static func _find_hook_call(code: String) -> int:
	var i := 0
	var n := code.length()
	while i < n:
		var j := L.skip_noncode(code, i)
		if j != i:
			i = j
			continue
		if i == 0 or (not L._is_ident(code[i - 1]) and code[i - 1] != "."):
			for h in HOOK_NAMES:
				if L.keyword_at(code, i, h) and _is_call_at(code, i + h.length()):
					return i
		i += 1
	return -1

static func _validate_node(nd, diags: Array, base: int = -1) -> void:
	if nd == null or not (nd is Dictionary):
		return
	match nd.get("t", ""):
		"el", "frag":
			# T2.5 (Unity 0016): a hook CALL inside a markup attribute expression runs per-render out
			# of hook order -- using a hook RESULT there is fine, only the call is flagged.
			# T2.7 (Unity 0120/0121): a `res://` STRING literal in an asset-taking attribute must
			# exist and load as the expected resource type.
			for a in nd.get("attrs", []):
				var ad := a as Dictionary
				if ad.get("kind", "") == "expr" and _expr_calls_hook(str(ad["value"])):
					diags.append(D.make("GUITKX0016", D.ERROR, "hook called inside a markup expression -- call it in setup and reference the result", _cbase(base, int(ad.get("vat", -1))), maxi(1, str(ad["value"]).length())))
				elif ad.get("kind", "") == "str" and str(ad.get("name", "")) in ["texture", "icon", "theme"] and str(ad["value"]).begins_with("res://"):
					var ap := str(ad["value"])
					if not FileAccess.file_exists(ap):
						diags.append(D.make("GUITKX0120", D.ERROR, "asset not found: %s" % ap, _cbase(base, int(ad.get("vat", -1))), ap.length()))
					else:
						var want := "Theme" if str(ad["name"]) == "theme" else "Texture2D"
						if not ResourceLoader.exists(ap, want):
							diags.append(D.make("GUITKX0121", D.ERROR, "asset is not a %s: %s" % [want, ap], _cbase(base, int(ad.get("vat", -1))), ap.length()))
			_check_dup_keys(nd.get("children", []), diags, base)
			for c in nd.get("children", []):
				_validate_node(c, diags, base)
		"expr":
			if _expr_calls_hook(str(nd.get("code", ""))):
				diags.append(D.make("GUITKX0016", D.ERROR, "hook called inside a markup expression -- call it in setup and reference the result", _cbase(base, int(nd.get("vat", -1))), maxi(1, str(nd.get("code", "")).length())))
		"text":
			# T2.4 migration warning: braces inside text are LITERAL since the Unity-parity text model
			# landed -- surface it so a pre-T2.4 `Count: {n}` habit doesn't silently render "{n}".
			if "{" in str(nd.get("value", "")):
				diags.append(D.make("GUITKX0150", D.WARNING, "braces inside text are literal -- interpolate with a leading `{expr}` node or a `text={ ... }` attribute instead", _cbase(base, int(nd.get("at", -1))), (str(nd.get("value", "")) as String).length()))
		"if":
			for br in nd["branches"]:
				_validate_body(br["body_markup"], diags, false, _cbase(base, br["body_at"]))
			if nd["else_body"] != null:
				_validate_body(nd["else_body"], diags, false, _cbase(base, nd["else_body_at"]))
		"for":
			# T2.7 (Unity UITKX0019): the loop binder threads down so `key={ binder }` can warn.
			var fh := _split_for_header(str(nd["header"]))
			_validate_body(nd["body_markup"], diags, true, _cbase(base, nd["body_at"]), str(fh.get("var", "")))
		"while":
			_validate_body(nd["body_markup"], diags, true, _cbase(base, nd["body_at"]))
		"match":
			for c in nd.get("cases", []):
				_validate_body(c["body_markup"], diags, false, _cbase(base, c["body_at"]))
			if nd.get("default_body") != null:
				_validate_body(nd["default_body"], diags, false, _cbase(base, nd["default_body_at"]))

static func _validate_body(body_src: String, diags: Array, is_loop: bool, base: int = -1, binder: String = "") -> void:
	var parser := Markup.new()
	var pr := parser.parse(body_src, 0, body_src.length())
	if pr["error"] != "":
		# T1.2: a malformed control-flow body is a compile ERROR carrying the inner parser's own code
		# and position -- never a silent skip (Unity parity: codegen fails on every parser error).
		diags.append(D.make(pr["error_code"], D.ERROR, pr["error_msg"], _cbase(base, maxi(0, int(pr["error_at"]))), 1))
		return
	var nodes: Array = (pr["nodes"] as Array).filter(func(x): return x != null and (x as Dictionary).get("t", "") != "comment")
	if is_loop:
		if nodes.size() > 1:
			# A loop body must have a single root (like a component) so each iteration yields one keyed
			# child. Wrap siblings in a fragment <>...</> with distinct keys. (Parity: Unity UITKX0108.)
			diags.append(D.make("GUITKX0108", D.ERROR, "a @for/@while body must contain exactly one root element (got %d) -- wrap siblings in a fragment <>...</>" % nodes.size(), _cbase(base, int(nodes[1]["at"])), _node_len(nodes[1])))
		elif nodes.size() == 1 and (nodes[0] as Dictionary).get("t", "") == "el":
			if not _has_key(nodes[0]):
				diags.append(D.make("GUITKX0106", D.WARNING, "element in @for/@while has no `key` -- add key= so reordered children reconcile correctly", _cbase(base, int(nodes[0]["at"])), _node_len(nodes[0])))
			elif binder != "":
				# T2.7 (Unity UITKX0019): the loop variable used DIRECTLY as the key -- positional keys
				# defeat reconciliation on reorder; derive the key from a stable id on the item.
				var ka := _key_attr(nodes[0])
				if str(ka.get("kind", "")) == "expr" and str(ka.get("value", "")).strip_edges() == binder:
					diags.append(D.make("GUITKX0019", D.WARNING, "loop variable `%s` used directly as the key -- use a stable unique identifier from the item instead" % binder, _cbase(base, int(ka.get("at", -1))), maxi(1, int(ka.get("end", 0)) - int(ka.get("at", 0)))))
	for nx in nodes:
		_validate_node(nx, diags, base)

## Squiggle width for a node-anchored diagnostic: `<Tag` for elements, 1 char otherwise.
static func _node_len(nd: Dictionary) -> int:
	if nd.get("t", "") == "el":
		return 1 + (nd.get("tag", "") as String).length()
	return 1

static func _check_dup_keys(children: Array, diags: Array, base: int = -1) -> void:
	var seen := {}
	for c in children:
		if c == null or not (c is Dictionary) or (c as Dictionary).get("t", "") != "el":
			continue
		var k := _literal_key(c)
		if k == "":
			continue
		if seen.has(k):
			var ka := _key_attr(c)
			var at: int = int(ka.get("at", -1))
			var alen: int = maxi(1, int(ka.get("end", 0)) - at) if at >= 0 else 1
			diags.append(D.make("GUITKX0104", D.WARNING, "duplicate key '%s' among sibling elements" % k.substr(2), _cbase(base, at), alen))
		seen[k] = true

## The `key` attribute Dictionary of an element ({} when absent).
static func _key_attr(el: Dictionary) -> Dictionary:
	for a in el.get("attrs", []):
		if a["name"] == "key":
			return a
	return {}

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
	var a := _key_attr(el)
	if a.is_empty():
		return ""
	if a["kind"] == "str":
		return "s:" + str(a["value"])
	if a["kind"] == "expr":
		return "e:" + str(a["value"]).strip_edges()
	return ""

## hook file: `hook name(params) [-> (...)] { body }` -> a class with one static function. The
## body is plain GDScript (hook calls auto-prefixed); the `-> (tuple)` hint is dropped (GDScript
## has no tuple type -- a multi-value hook returns an Array). Parsing is _parse_hook_at (T1.3
## de-duplicated the inline copy) so this path also knows where the declaration ENDS.
static func _compile_hook(source: String, hi: int, class_name_override: String, basename: String, diags: Array) -> Dictionary:
	var ph := _parse_hook_at(source, hi, diags)
	if not ph["ok"]:
		return { "ok": false, "gd": "", "diagnostics": diags }
	_error_on_trailing(source, int(ph["next"]), "hook", diags)
	# T2.5: rules-of-hooks apply inside hook declaration bodies too (hooks compose hooks -- still
	# unconditionally, at the top level).
	_validate_hooks(ph["body"], diags, int(ph["body_at"]))
	_validate_effect_deps(ph["body"], diags, int(ph["body_at"]))
	if D.has_error(diags):
		return { "ok": false, "gd": "", "diagnostics": diags }
	var cls := class_name_override if class_name_override != "" else basename
	var out := "class_name %s\nextends RefCounted\n## AUTO-GENERATED from %s.guitkx -- do not edit.\n\n" % [cls, basename]
	out += "static func %s(%s)%s:\n" % [ph["name"], ph["params"], _ret_suffix(str(ph.get("ret", "")))]
	var body_block := _reindent_setup(_apply_hook_aliases(ph["body"]))
	if body_block != "":
		out += body_block + "\n"
	if not _has_statement(body_block):
		out += "\tpass\n"
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
		diags.append(D.make("GUITKX0300", D.ERROR, "missing hook name", j))
		return { "ok": false }
	# T2.6 (Unity UITKX2203, snake-case adaptation): hook names start with `use_` so call sites read
	# as hooks and the auto-prefixing/lint machinery can recognize them. Warning -- helpers compile.
	if not hook_name.begins_with("use_"):
		diags.append(D.make("GUITKX2203", D.WARNING, "hook name `%s` should start with `use_`" % hook_name, ns, hook_name.length()))
	var params := ""
	j = _skip_ws_only(source, j)
	if j < n and source[j] == "(":
		var pc := L.find_matching(source, j)
		if pc == -1:
			diags.append(D.make("GUITKX0304", D.ERROR, "unclosed `(` in hook params", j, 1))
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
		diags.append(D.make("GUITKX0303", D.ERROR, "hook body `{ ... }` expected", mini(j, n - 1)))
		return { "ok": false }
	var bclose := L.find_matching(source, j)
	if bclose == -1:
		diags.append(D.make("GUITKX0304", D.ERROR, "unclosed hook body", j, 1))
		return { "ok": false }
	return { "ok": true, "name": hook_name, "name_at": ns, "params": params, "ret": ret_hint, "body": source.substr(j + 1, bclose - j - 1), "body_at": j + 1, "next": bclose + 1 }

## module Name { component A {…} component B {…} hook use_x {…} } -> one class with one static func
## per declaration. Intra-module <A/> resolves to the bare sibling static func (V.fc(A, …)). [§4]
static func _compile_module(source: String, mi: int, class_name_override: String, basename: String, diags: Array, known: Dictionary = {}) -> Dictionary:
	var n := source.length()
	var j := mi + 6   # "module"
	j = _skip_ws_only(source, j)
	var ns := j
	while j < n and L._is_ident(source[j]):
		j += 1
	var mod_name := source.substr(ns, j - ns)
	if mod_name == "":
		diags.append(D.make("GUITKX0300", D.ERROR, "`module` requires a name (module Name { ... })", j))
		return { "ok": false, "gd": "", "diagnostics": diags }
	j = _skip_ws_only(source, j)
	if j >= n or source[j] != "{":
		diags.append(D.make("GUITKX0303", D.ERROR, "module body `{ ... }` expected", mini(j, n - 1)))
		return { "ok": false, "gd": "", "diagnostics": diags }
	var bclose := L.find_matching(source, j)
	if bclose == -1:
		diags.append(D.make("GUITKX0304", D.ERROR, "unclosed module body", j, 1))
		return { "ok": false, "gd": "", "diagnostics": diags }
	var body_end := bclose
	_error_on_trailing(source, bclose + 1, "module", diags)
	var comps: Array = []
	var hooks: Array = []
	var module_comps := {}
	var module_hooks: Array = []
	var i := j + 1
	while i < body_end:
		var d := _find_decl(source, i)
		# T1.3: _find_decl SKIPS anything that isn't a declaration keyword -- content between members
		# used to vanish silently. Real (non-ws, non-comment) text there is an error, not a skip.
		var scan_to: int = mini(int(d["at"]), body_end) if d["kind"] != "" else body_end
		var junk := _first_real(source, i, scan_to)
		if junk != -1:
			var jle := source.find("\n", junk)
			jle = body_end if (jle == -1 or jle > body_end) else jle
			diags.append(D.make("GUITKX2105", D.ERROR, "invalid content in module `%s` -- only `component` and `hook` declarations are allowed here" % mod_name, junk, maxi(1, jle - junk)))
			return { "ok": false, "gd": "", "diagnostics": diags }
		if d["kind"] == "" or d["at"] >= body_end:
			break
		if d["kind"] == "component":
			var c := _parse_component_at(source, d["at"], diags)
			if not c["ok"]:
				return { "ok": false, "gd": "", "diagnostics": diags }
			if module_comps.has(c["name"]) or c["name"] in module_hooks:
				diags.append(D.make("GUITKX0112", D.ERROR, "duplicate declaration `%s` in module `%s`" % [c["name"], mod_name], c["name_at"], (c["name"] as String).length()))
				return { "ok": false, "gd": "", "diagnostics": diags }
			module_comps[c["name"]] = true
			comps.append(c)
			i = c["next"]
		elif d["kind"] == "hook":
			var h := _parse_hook_at(source, d["at"], diags)
			if not h["ok"]:
				return { "ok": false, "gd": "", "diagnostics": diags }
			if module_comps.has(h["name"]) or h["name"] in module_hooks:
				diags.append(D.make("GUITKX0112", D.ERROR, "duplicate declaration `%s` in module `%s`" % [h["name"], mod_name], h["name_at"], (h["name"] as String).length()))
				return { "ok": false, "gd": "", "diagnostics": diags }
			module_hooks.append(h["name"])
			hooks.append(h)
			i = h["next"]
		else:
			diags.append(D.make("GUITKX0110", D.ERROR, "nested `module` is not allowed", d["at"], 6))
			return { "ok": false, "gd": "", "diagnostics": diags }
	if comps.is_empty() and hooks.is_empty():
		diags.append(D.make("GUITKX0110", D.ERROR, "module `%s` has no component or hook declarations" % mod_name, mi, 6))
		return { "ok": false, "gd": "", "diagnostics": diags }
	# T1.1: validate every member BEFORE emitting anything -- a hard error in ANY member (e.g.
	# GUITKX0108 multi-root in a loop body) fails the whole module, exactly like a single-file compile.
	for c in comps:
		_validate(c["setup"], c["root"], diags, c["body_at"])
		_validate_unused_params(c["params"], int(c.get("params_at", -1)), source.substr(int(c["body_at"]), int(c["next"]) - 1 - int(c["body_at"])), diags)
	for h in hooks:
		_validate_hooks(h["body"], diags, int(h["body_at"]))   # T2.5: member hook bodies too
		_validate_effect_deps(h["body"], diags, int(h["body_at"]))
	if D.has_error(diags):
		return { "ok": false, "gd": "", "diagnostics": diags }
	var cls := class_name_override if class_name_override != "" else mod_name
	var out := "class_name %s\nextends RefCounted\n## AUTO-GENERATED from %s.guitkx -- do not edit.\n\n" % [cls, basename]
	for c in comps:
		out += "# component %s\n" % c["name"]
		out += _emit_func(c["name"], c["params"], c["setup"], c["root"], module_comps, module_hooks, diags, c["body_at"], known)
		out += "\n"
	for h in hooks:
		out += "# hook %s\n" % h["name"]
		out += "static func %s(%s)%s:\n" % [h["name"], h["params"], _ret_suffix(h.get("ret", ""))]
		var hb := _reindent_setup(_apply_hook_aliases(h["body"], module_hooks))
		if hb != "":
			out += hb + "\n"
		if not _has_statement(hb):
			out += "\tpass\n"
		out += "\n"
	# T1.1: emit-time errors (GUITKX0113, nested-body parse errors) fail the module compile as well.
	if D.has_error(diags):
		return { "ok": false, "gd": "", "diagnostics": diags }
	return { "ok": true, "gd": out, "diagnostics": diags }

# --- body splitter: choose the LAST top-level markup return (T1.4, Unity useLastReturn parity) ---
# "Top-level" is the GDScript equivalent of Unity's brace-depth-0: the `return` is the FIRST token on
# its line AND the line's indent depth is <= the body's anchor depth (the same anchor rule as
# _reindent_setup, so the split agrees with emission). Everything before the chosen return is setup;
# statement-level returns (inside if:/for:/lambdas) are legal GDScript and stay there UNLESS they are
# markup-shaped -- GDScript setup can never contain markup, so those are collected in `bad` and the
# caller reports GUITKX2102. Earlier TOP-LEVEL candidates also land in `bad`: they would make the
# chosen markup return unreachable in the generated .gd (Unity's C# compiler catches that for it;
# Godot must catch it here).
#
# Returns { setup, markup_src, m_start, m_end, chosen_at, bad } on success or { error: Diag, bad }
# -- `bad` = [{ at, to, msg }] is ALWAYS processed by the caller, even alongside an error.
static func _split_return(body: String) -> Dictionary:
	var n := body.length()
	# indent geometry (unit + anchor) over the body's lines -- mirrored in formatGuitkx.ts/virtualDoc.ts.
	var lines: Array = Array(body.split("\n"))
	var unit := _indent_unit(lines)
	var anchor := -1
	var anchor_any := -1
	for l in lines:
		var t := (l as String).strip_edges()
		if t == "":
			continue
		var d := _indent_depth(l as String, unit)
		if anchor_any == -1:
			anchor_any = d
		if not t.begins_with("#"):
			anchor = d
			break
	if anchor == -1:
		anchor = anchor_any
	var bad: Array = []
	var chosen := {}           # { at, p, shape ("paren"|"bare"), close }
	var malformed_at := -1     # first top-level `return <other>` (not (, <, null) -- Unity 2102 fallback
	var i := 0
	while i < n:
		var k := L.skip_noncode(body, i)
		if k != i:
			i = k
			continue
		if L.keyword_at(body, i, "return"):
			var p := i + 6
			p = _skip_ws_only(body, p)
			# position class: first token on its line at depth <= anchor == top-level
			var ls := 0 if i == 0 else body.rfind("\n", i - 1) + 1
			var lead := body.substr(ls, i - ls)
			var top_level := lead.strip_edges() == "" and _indent_depth(lead, unit) <= anchor
			var eol := body.find("\n", i)
			if eol == -1:
				eol = n
			if p < n and body[p] == "(":
				var close := L.find_matching(body, p)
				if close == -1:
					# an unclosed `(` swallows the rest of the body -- nothing after it can be scanned
					return { "error": D.make("GUITKX0304", D.ERROR, "unclosed `(` after return", p, 1), "bad": bad }
				if top_level:
					if not chosen.is_empty():
						bad.append(_bad_return(chosen, body, n))
					chosen = { "at": i, "p": p, "shape": "paren", "close": close }
				elif _paren_holds_markup(body, p + 1, close):
					bad.append({ "at": i, "to": eol, "msg": "a conditional/early `return` cannot return markup (setup is plain GDScript) -- return null and branch with @if/@match in the markup" })
				i = close + 1
				continue
			elif p < n and body[p] == "<":
				# bare `return <Tag.../>` -- markup by construction (`<` cannot start a GDScript expression)
				if top_level:
					if not chosen.is_empty():
						bad.append(_bad_return(chosen, body, n))
					chosen = { "at": i, "p": p, "shape": "bare", "close": -1 }
				else:
					bad.append({ "at": i, "to": eol, "msg": "a conditional/early `return` cannot return markup (setup is plain GDScript) -- return null and branch with @if/@match in the markup" })
				i = eol
				continue
			elif L.keyword_at(body, p, "null"):
				# `return null` is the sanctioned CONDITIONAL guard (top-level or nested); skip it.
				i = p + 4
				continue
			elif top_level and malformed_at == -1:
				malformed_at = i
			i = eol if top_level else i + 6
			continue
		i += 1
	if chosen.is_empty():
		if malformed_at != -1:
			var meol := body.find("\n", malformed_at)
			if meol == -1:
				meol = n
			return { "error": D.make("GUITKX2102", D.ERROR, "`return` must return markup using `return ( <...> )`", malformed_at, maxi(1, meol - malformed_at)), "bad": bad }
		return { "error": D.make("GUITKX0102", D.ERROR, "component has no `return ( ... )` (only `return null`?)"), "bad": bad }
	var setup := body.substr(0, int(chosen["at"]))
	if chosen["shape"] == "paren":
		return { "setup": setup, "markup_src": body, "m_start": int(chosen["p"]) + 1, "m_end": int(chosen["close"]), "chosen_at": int(chosen["at"]), "bad": bad }
	return { "setup": setup, "markup_src": body, "m_start": int(chosen["p"]), "m_end": n, "chosen_at": int(chosen["at"]), "bad": bad }

## A demoted earlier-top-level candidate -> `bad` entry (it would return before the final markup
## return, making the component's output unreachable in the generated .gd).
static func _bad_return(cand: Dictionary, body: String, n: int) -> Dictionary:
	var at: int = int(cand["at"])
	var to: int = body.find("\n", at)
	if to == -1:
		to = n
	return { "at": at, "to": to, "msg": "a component's setup cannot `return` before the final markup return -- use a `return null` guard or branch with @if in the markup" }

## True when a parenthesized return's content [from,to) starts with markup (`<` element or `@`
## directive) -- neither can begin a legal GDScript expression, so this never false-flags a plain
## parenthesized value like `return (x + 1)` in a setup lambda.
static func _paren_holds_markup(body: String, from: int, to: int) -> bool:
	var f := _first_real(body, from, to)
	return f != -1 and (body[f] == "<" or body[f] == "@")

## T1.3: any real (non-ws, non-comment) content after the single top-level declaration is an error
## (Unity UITKX2105 parity: "Invalid top-level statement after function-style component declaration").
## A second `component`/`hook` used to be dropped SILENTLY while the LSP still indexed it -- completion
## offered a component that did not exist in the generated .gd. Squiggle = first junk char to its EOL.
static func _error_on_trailing(source: String, from: int, kind: String, diags: Array) -> void:
	var first := _first_real(source, from, source.length())
	if first == -1:
		return
	var le := source.find("\n", first)
	if le == -1:
		le = source.length()
	diags.append(D.make("GUITKX2105", D.ERROR, "invalid top-level content after the `%s` declaration -- one declaration per file (wrap several in `module Name { ... }`)" % kind, first, maxi(1, le - first)))

## First real char in [from, to) skipping whitespace AND MARKUP comments (`//`, `/* */`, `<!-- -->`)
## -- for checks over markup windows (Unity's LooksLikeMarkupRoot skips comments the same way).
## An UNCLOSED comment returns its own start so the markup parser reports it precisely.
static func _first_markup_real(s: String, from: int, to: int) -> int:
	var i := from
	while i < to:
		var c := s[i]
		if c == " " or c == "\t" or c == "\n" or c == "\r":
			i += 1
			continue
		if c == "/" and i + 1 < to and s[i + 1] == "/":
			var le := s.find("\n", i)
			i = to if (le == -1 or le > to) else le
			continue
		if c == "/" and i + 1 < to and s[i + 1] == "*":
			var bce := s.find("*/", i + 2)
			if bce == -1 or bce + 2 > to:
				return i
			i = bce + 2
			continue
		if c == "<" and i + 3 < to and s.substr(i, 4) == "<!--":
			var hce := s.find("-->", i + 4)
			if hce == -1 or hce + 3 > to:
				return i
			i = hce + 3
			continue
		return i
	return -1

## First / last offset of real (non-ws, non-comment) code in [from, to), or -1.
static func _first_real(s: String, from: int, to: int) -> int:
	var i := from
	while i < to:
		var k := L.skip_noncode(s, i)
		if k != i:
			i = k
			continue
		var c := s[i]
		if not (c == " " or c == "\t" or c == "\n" or c == "\r"):
			return i
		i += 1
	return -1

static func _last_real(s: String, from: int, to: int) -> int:
	var i := from
	var last := -1
	while i < to:
		var k := L.skip_noncode(s, i)
		if k != i:
			i = k
			continue
		var c := s[i]
		if not (c == " " or c == "\t" or c == "\n" or c == "\r"):
			last = i
		i += 1
	return last

static func _line_at(s: String, offset: int) -> int:
	var line := 0
	var lim := mini(offset, s.length())
	for idx in lim:
		if s[idx] == "\n":
			line += 1
	return line

## Line ranges [start_line, end_line] (0-based, inclusive) of real unreachable code after each
## component's markup return, for the editor to dim/flag. Reuses _split_return. [BUG-V5/V6]
static func unreachable_line_ranges(source: String) -> Array:
	var ranges: Array = []
	var n := source.length()
	var i := 0
	while i < n:
		var k := L.skip_noncode(source, i)
		if k != i:
			i = k
			continue
		if L.keyword_at(source, i, "component"):
			# skip name + optional (params) to reach the body `{`
			var j := i + 9
			while j < n and (source[j] == " " or source[j] == "\t"):
				j += 1
			while j < n and L._is_ident(source[j]):
				j += 1
			while j < n and (source[j] == " " or source[j] == "\t"):
				j += 1
			if j < n and source[j] == "(":
				var pcl := L.find_matching(source, j)
				if pcl == -1:
					break
				j = pcl + 1
			while j < n and (source[j] == " " or source[j] == "\t" or source[j] == "\n" or source[j] == "\r"):
				j += 1
			if j >= n or source[j] != "{":
				i += 9
				continue
			var bclose := L.find_matching(source, j)
			if bclose == -1:
				break
			var body := source.substr(j + 1, bclose - j - 1)
			var split := _split_return(body)
			if not split.has("error"):
				var f := _first_real(body, split["m_end"] + 1, body.length())
				if f != -1:
					var lst := _last_real(body, split["m_end"] + 1, body.length())
					ranges.append([_line_at(source, j + 1 + f), _line_at(source, j + 1 + lst)])
			i = bclose + 1
			continue
		i += 1
	return ranges

# --- emit ---
# Control flow is hoisted into pre-statements (an if/for/while block before the return) that
# assign a fresh `__cfN` local, which the markup then references. This sidesteps both GDScript's
# "lambdas can't hold multi-statement return control-flow" limit AND the helper-method
# locals-capture problem -- the block is inline in render() and sees all setup locals. The
# runtime `V._norm` flattens the `@for` arrays and drops the null `@if` misses for free.
static func _emit(cls: String, comp_name: String, params: String, setup: String, root: Dictionary, basename: String, diags: Array = [], base: int = -1, known: Dictionary = {}) -> String:
	var out := "class_name %s\n" % cls
	out += "extends RefCounted\n"
	out += "## AUTO-GENERATED from %s.guitkx -- do not edit.\n\n" % basename
	out += _emit_func("render", params, setup, root, {}, [], diags, base, known)
	return out

# Emit one `static func <name>(props, children) -> RUIVNode:` from params + setup + a markup root.
# `module_comps` maps intra-module component names -> true so <Foo/> emits V.fc(Foo, ...) (bare
# sibling static func) rather than the single-file V.fc(Foo.render, ...).
static func _emit_func(func_name: String, params: String, setup: String, root: Dictionary, module_comps: Dictionary, skip_hooks: Array = [], diags: Array = [], base: int = -1, known: Dictionary = {}) -> String:
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
	# base: absolute source offset of index 0 of the string the CURRENT node offsets are relative to
	# (swapped around every nested re-parse via _swap_base, so emit-time diagnostics carry positions).
	var ctx := { "lines": [], "indent": 1, "counter": 0, "module_comps": module_comps, "diags": diags, "expr_mode": false, "base": base, "known_components": known }
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
			return _emit_fragment(nd, ctx)
		"comment":
			return "null"   # comments emit nothing (children arrays skip them; defensive for roots)
		"expr":
			var prev := _swap_base(ctx, _cbase(int(ctx.get("base", -1)), int(nd.get("vat", -1))))
			var spliced := "(%s)" % _splice_expr_markup(nd["code"], ctx)
			_swap_base(ctx, prev)
			return spliced
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

## T2.2: a fragment node -- `<>...</>` or the named `<Fragment ...>` alias. The named form may carry
## `key` (V.fragment's second arg, Unity parity) and `{/* comments */}`; any other attribute is an
## error (Unity silently drops them; silent drops are against this compiler's charter).
static func _emit_fragment(nd: Dictionary, ctx: Dictionary) -> String:
	var key_expr := ""
	for a in nd.get("attrs", []):
		var kind := str((a as Dictionary).get("kind", ""))
		if kind == "comment":
			continue
		if a["name"] == "key":
			key_expr = _attr_value_code(a, ctx)
			continue
		if ctx.has("diags") and ctx["diags"] is Array:
			(ctx["diags"] as Array).append(D.make("GUITKX0107", D.ERROR, "<%s> accepts only `key` -- move '%s' onto a real element" % [str(nd.get("named", "Fragment")), a["name"]], _cbase(int(ctx.get("base", -1)), int(a.get("at", -1))), maxi(1, (a["name"] as String).length())))
	var children := _emit_children_array(nd["children"], ctx)
	if key_expr != "":
		return "V.fragment(%s, %s)" % [children, key_expr]
	return "V.fragment(%s)" % children

static func _has_attr(nd: Dictionary, name: String) -> bool:
	for a in nd["attrs"]:
		if a["name"] == name:
			return true
	return false

static func _all_text_children(children: Array) -> bool:
	if children.is_empty():
		return false
	for c in children:
		if c == null or c["t"] == "comment":
			continue
		if not (c["t"] == "text" or c["t"] == "expr"):
			return false
	return true

## T1.5: report an unknown tag (GUITKX0105) at the tag name, with a did-you-mean when a factory,
## host alias, module member, or known component is within edit distance 2 (Unity parity).
static func _unknown_tag(ctx: Dictionary, nd: Dictionary, tag: String) -> void:
	if not (ctx.has("diags") and ctx["diags"] is Array):
		return
	var at := _cbase(int(ctx.get("base", -1)), int(nd.get("at", -1)))
	if at >= 0:
		at += 1   # nd.at is the `<`; anchor the squiggle on the name
	var candidates: Array = V_FACTORIES.duplicate()
	candidates.append_array(HOST_TAGS.keys())
	candidates.append_array((ctx.get("module_comps", {}) as Dictionary).keys())
	candidates.append_array((ctx.get("known_components", {}) as Dictionary).keys())
	var best := ""
	var best_d := 3
	for c in candidates:
		var d := _edit_distance(tag.to_lower(), str(c).to_lower())
		if d < best_d:
			best_d = d
			best = str(c)
	var msg := "unknown element <%s>" % tag
	if best != "":
		msg += " -- did you mean <%s>?" % best
	(ctx["diags"] as Array).append(D.make("GUITKX0105", D.ERROR, msg, at, tag.length()))

## Swap ctx["base"] (the absolute offset of the current offset-domain's index 0), returning the old
## value so callers restore it after a nested re-parse. See the T0.2 note at the top of the file.
static func _swap_base(ctx: Dictionary, base: int) -> int:
	var prev: int = int(ctx.get("base", -1))
	ctx["base"] = base
	return prev

static func _merge_text_children(children: Array, ctx: Dictionary) -> String:
	var parts: Array = []
	for c in children:
		if c == null or c["t"] == "comment":
			continue
		if c["t"] == "text":
			parts.append(_gd_str(c["value"]))
		else:
			var prev := _swap_base(ctx, _cbase(int(ctx.get("base", -1)), int(c.get("vat", -1))))
			parts.append("str(%s)" % _splice_expr_markup(c["code"], ctx))
			_swap_base(ctx, prev)
	return " + ".join(parts)

static func _emit_element(nd: Dictionary, ctx: Dictionary) -> String:
	var tag: String = nd["tag"]
	var is_host := false
	var factory := ""
	if tag[0] >= "a" and tag[0] <= "z":
		is_host = true
		factory = tag   # lowercase/snake tag IS the V factory name
		# T1.5 (G5): a lowercase tag must BE a real V.* factory -- it is emitted verbatim as V.<tag>(),
		# so an unknown one used to become a nonexistent-method call in the generated .gd. This is the
		# single chokepoint every element passes through (main tree, control-flow bodies, {expr}-nested).
		if not V_FACTORIES.has(tag):
			_unknown_tag(ctx, nd, tag)
	elif HOST_TAGS.has(tag):
		is_host = true
		factory = HOST_TAGS[tag]
	else:
		# PascalCase component reference: resolvable only with project knowledge -- the plugin passes
		# the known component classes (sibling .guitkx bindings + global script classes) into
		# compile(); an empty known-set (headless/test callers) skips the check.
		var known: Dictionary = ctx.get("known_components", {})
		if not known.is_empty() and not (ctx.get("module_comps", {}) as Dictionary).has(tag) and not known.has(tag):
			_unknown_tag(ctx, nd, tag)
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
		if c == null or c["t"] == "comment":
			continue
		parts.append(_emit_expr(c, ctx))
	if parts.is_empty():
		return "[]"
	return "[%s]" % ", ".join(parts)

# Parse a control-flow branch/loop body (raw markup string) and emit its single root expression
# (or a fragment of several, or null when empty). Nested control flow recurses through _emit_expr,
# so its pre-statements land at the caller's current indent (inside the branch/loop).
# `base` = absolute source offset of body_src[0] (-1 unknown); swapped in for the nested parse.
static func _emit_body(body_src: String, ctx: Dictionary, base: int = -1) -> String:
	var parser := Markup.new()
	var pr := parser.parse(body_src, 0, body_src.length())
	if pr["error"] != "":
		# T1.2: reachable only for bodies validation never re-parses (control flow nested in a JSX-value
		# {expr}); append the parser's diagnostic so the T1.1 post-emit gate fails the compile.
		if ctx.has("diags") and ctx["diags"] is Array:
			(ctx["diags"] as Array).append(D.make(pr["error_code"], D.ERROR, pr["error_msg"], _cbase(base, maxi(0, int(pr["error_at"]))), 1))
		return "null"
	var nodes: Array = (pr["nodes"] as Array).filter(func(x): return x != null and (x as Dictionary).get("t", "") != "comment")
	if nodes.is_empty():
		return "null"
	var prev := _swap_base(ctx, base)
	var result: String
	if nodes.size() == 1:
		result = _emit_expr(nodes[0], ctx)
	else:
		var parts: Array = []
		for nx in nodes:
			parts.append(_emit_expr(nx, ctx))
		result = "V.fragment([%s])" % ", ".join(parts)
	_swap_base(ctx, prev)
	return result

static func _emit_if(nd: Dictionary, ctx: Dictionary) -> String:
	if ctx.get("expr_mode", false):
		return _emit_if_inline(nd, ctx)
	var nb: int = int(ctx.get("base", -1))
	var id := _fresh(ctx)
	_line(ctx, "var %s = null" % id)
	var branches: Array = nd["branches"]
	for i in branches.size():
		var br: Dictionary = branches[i]
		var kw := "if" if i == 0 else "elif"
		_line(ctx, "%s %s:" % [kw, br["cond"]])
		ctx["indent"] += 1
		var be := _emit_body(br["body_markup"], ctx, _cbase(nb, int(br["body_at"])))
		_line(ctx, "%s = %s" % [id, be])
		ctx["indent"] -= 1
	if nd["else_body"] != null:
		_line(ctx, "else:")
		ctx["indent"] += 1
		var ee := _emit_body(nd["else_body"], ctx, _cbase(nb, int(nd["else_body_at"])))
		_line(ctx, "%s = %s" % [id, ee])
		ctx["indent"] -= 1
	return id

static func _emit_loop(nd: Dictionary, ctx: Dictionary, kind: String) -> String:
	if ctx.get("expr_mode", false):
		if kind == "for":
			return _emit_for_inline(nd, ctx)
		return _expr_ctrl_unsupported(ctx, "@while", nd)   # a while-loop can't be an expression
	var nb: int = int(ctx.get("base", -1))
	var id := _fresh(ctx)
	_line(ctx, "var %s: Array = []" % id)
	if kind == "for":
		_line(ctx, "for %s:" % nd["header"])
	else:
		_line(ctx, "while %s:" % nd["header"])
	ctx["indent"] += 1
	var be := _emit_body(nd["body_markup"], ctx, _cbase(nb, int(nd["body_at"])))
	_line(ctx, "%s.append(%s)" % [id, be])
	ctx["indent"] -= 1
	return id

static func _emit_match(nd: Dictionary, ctx: Dictionary) -> String:
	if ctx.get("expr_mode", false):
		return _expr_ctrl_unsupported(ctx, "@match", nd)   # a match-statement can't be an expression
	var nb: int = int(ctx.get("base", -1))
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
		var be := _emit_body(c["body_markup"], ctx, _cbase(nb, int(c["body_at"])))
		_line(ctx, "%s = %s" % [id, be])
		ctx["indent"] -= 1
	if nd["default_body"] != null:
		_line(ctx, "_:")
		ctx["indent"] += 1
		var de := _emit_body(nd["default_body"], ctx, _cbase(nb, int(nd["default_body_at"])))
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
	var nb: int = int(ctx.get("base", -1))
	var branches: Array = nd["branches"]
	var acc := "null"
	if nd["else_body"] != null:
		acc = _emit_body(nd["else_body"], ctx, _cbase(nb, int(nd["else_body_at"])))
	for i in range(branches.size() - 1, -1, -1):
		var br: Dictionary = branches[i]
		var be := _emit_body(br["body_markup"], ctx, _cbase(nb, int(br["body_at"])))
		acc = "(%s if (%s) else %s)" % [be, br["cond"], acc]
	return acc

static func _emit_for_inline(nd: Dictionary, ctx: Dictionary) -> String:
	# header is "x in xs" -> `(xs).map(func(x): return body)`. The iterable must be array-like (Array
	# or range()); for non-array iterables lift the @for to the top-level markup instead.
	var split := _split_for_header(str(nd["header"]))
	if split.is_empty():
		return _expr_ctrl_unsupported(ctx, "@for (could not parse the loop header)", nd)
	var be := _emit_body(nd["body_markup"], ctx, _cbase(int(ctx.get("base", -1)), int(nd["body_at"])))
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

static func _expr_ctrl_unsupported(ctx: Dictionary, what: String, nd: Dictionary = {}) -> String:
	var msg := "%s cannot be used inside an embedded {expression} / JSX-value (it can't be lowered to an expression). Lift it to the top-level markup return, or use .map() for lists." % what
	if ctx.has("diags") and ctx["diags"] is Array:
		var at := _cbase(int(ctx.get("base", -1)), int(nd.get("at", -1)))
		(ctx["diags"] as Array).append(D.make("GUITKX0113", D.ERROR, msg, at, 6))
	return "null"

## Re-indent a setup block into the generated func body. DEPTH-based (not raw-character-based): a tab
## counts as one indent unit and the space-unit is inferred, so a source that MIXES tabs and spaces --
## invisible in most editors, since `\t  ` renders like `\t\t` -- still yields consistent, valid
## GDScript instead of a downstream "unindent doesn't match". Anchored to the FIRST non-blank
## NON-COMMENT line (which in valid GDScript is at the body's base level), NOT the shallowest: a
## min-depth anchor let a single outlier-shallow line raise every other line one level (a statement
## over-indented with no preceding `:` -- invalid generated GDScript). Comments are skipped when
## PICKING the anchor -- GDScript allows a comment at any indentation, so anchoring on a stray
## over-indented leading comment would mis-shift real code -- but they are emitted by depth like any
## line. A line shallower than the anchor clamps to one tab.
static func _reindent_setup(code: String) -> String:
	var lines: Array = Array(code.split("\n"))
	while not lines.is_empty() and (lines[0] as String).strip_edges() == "":
		lines.pop_front()
	while not lines.is_empty() and (lines[-1] as String).strip_edges() == "":
		lines.pop_back()
	if lines.is_empty():
		return ""
	var unit := _indent_unit(lines)
	var anchor := -1
	var anchor_any := -1
	var depths: Array = []
	for l in lines:
		var t := (l as String).strip_edges()
		if t == "":
			depths.append(-1)
			continue
		var d := _indent_depth(l as String, unit)
		depths.append(d)
		if anchor_any == -1:
			anchor_any = d
		if anchor == -1 and not t.begins_with("#"):
			anchor = d
	if anchor == -1:
		anchor = anchor_any  # comment-only block
	var out_lines: Array = []
	for i in lines.size():
		if int(depths[i]) == -1:
			out_lines.append("")
		else:
			var level: int = 1 + maxi(0, int(depths[i]) - anchor)
			out_lines.append("\t".repeat(level) + _strip_leading_ws(lines[i] as String))
	return "\n".join(out_lines)

## True when the block contains at least one real statement line (not blank, not a `#` comment) --
## a generated func body of only comments/blanks needs a trailing `pass` to be valid GDScript.
static func _has_statement(block: String) -> bool:
	for l in block.split("\n"):
		var t := (l as String).strip_edges()
		if t != "" and not t.begins_with("#"):
			return true
	return false

static func _leading_ws(s: String) -> String:
	var i := 0
	while i < s.length() and (s[i] == "\t" or s[i] == " "):
		i += 1
	return s.substr(0, i)

static func _strip_leading_ws(s: String) -> String:
	return s.substr(_leading_ws(s).length())

## Inferred space-indent width: the smallest positive run of leading spaces seen across `lines` (1 if
## the source uses only tabs). Lets a tab weigh the same as one such space-run in _indent_depth.
static func _indent_unit(lines: Array) -> int:
	var unit := 0
	for l in lines:
		var s := l as String
		var sp := 0
		for i in s.length():
			var c := s[i]
			if c == " ":
				sp += 1
			elif c == "\t":
				continue
			else:
				break
		if sp > 0 and (unit == 0 or sp < unit):
			unit = sp
	return unit if unit > 0 else 1

## Indentation depth of a line in whole levels: a tab = `unit` columns, a space = 1 column, rounded.
static func _indent_depth(s: String, unit: int) -> int:
	var cols := 0
	for i in s.length():
		var c := s[i]
		if c == "\t":
			cols += unit
		elif c == " ":
			cols += 1
		else:
			break
	return int(round(float(cols) / float(unit)))

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
			var prev := _swap_base(ctx, _cbase(int(ctx.get("base", -1)), int(a.get("vat", -1))))
			var code := _splice_expr_markup(a["value"], ctx)
			_swap_base(ctx, prev)
			return code
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
		var re: int = r["end"]
		if re == -1:
			# T1.2: unbalanced markup owns the rest of the expression; parsing it below yields the
			# markup parser's own precise error (e.g. 0301 unclosed tag) instead of emitting the raw
			# text as (invalid) GDScript.
			re = expr.length()
		var markup := _emit_markup_substring(expr, rs, re, ctx)
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
		prev = re
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
		# T1.2: markup nested inside an embedded {expr} has no validation pass at all -- this is its
		# only parse; surface the error (offsets are relative to src[0] = the expr string ctx.base maps).
		if ctx.has("diags") and ctx["diags"] is Array:
			(ctx["diags"] as Array).append(D.make(pr["error_code"], D.ERROR, pr["error_msg"], _cbase(int(ctx.get("base", -1)), maxi(0, int(pr["error_at"]))), 1))
		return "null"
	var nodes: Array = (pr["nodes"] as Array).filter(func(x): return x != null and (x as Dictionary).get("t", "") != "comment")
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
