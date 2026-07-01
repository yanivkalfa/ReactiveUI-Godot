class_name RUIGuitkxMarkup
extends RefCounted
## Recursive-descent parser: a markup string (the inside of a `return ( ... )`) -> an AST of
## plain Dictionaries. Port of uitkx's UitkxParser (markup half). Control-flow directives
## (@if/@for/@while/@switch) are recognized here and carried as raw body strings for the emitter.
##
## Node shapes (the "t" tag discriminates):
##   { t="el",   tag, attrs:[{name,kind,value}], children:[], line }   kind: "str"|"expr"|"bool"
##   { t="frag", children:[] }
##   { t="text", value }
##   { t="expr", code }
##   { t="if",   branches:[{cond, body_markup}], else_body }           cond/body are raw strings
##   { t="for",  header, body_markup }            (header is the GDScript `x in xs` / for-header)
##   { t="while",header, body_markup }
##   { t="match",subject, cases:[{value, body_markup}], default_body }

const L = preload("res://addons/reactive_ui/guitkx/guitkx_lexer.gd")

var _src: String
var _err: String = ""

## Parse the top-level nodes of a markup window [start, end). Returns { nodes:[...], error:"" }.
func parse(src: String, start: int, end: int) -> Dictionary:
	_src = src
	_err = ""
	var r := _parse_nodes(start, end)
	return { "nodes": r["nodes"], "error": _err }

## Parse sibling nodes in [start, end). Returns { nodes, next } where `next` is the index at which
## parsing stopped — sitting on an unconsumed `</` (the close tag belongs to the caller) or at `end`.
## The caller uses `next` to locate the close tag WITHOUT a second weaker walk (which could be fooled
## by a `<`/`>` inside an embedded {expr}).
func _parse_nodes(start: int, end: int) -> Dictionary:
	var nodes: Array = []
	var i := start
	while i < end and _err == "":
		i = _skip_ws(i, end)
		if i >= end:
			break
		var c := _src[i]
		if c == "<":
			if i + 1 < end and _src[i + 1] == "/":
				break   # a closing tag belongs to the caller
			var r := _parse_element(i, end)
			if _err != "":
				break
			nodes.append(r["node"])
			i = r["next"]
		elif c == "@":
			var r := _parse_directive(i, end)
			if _err != "":
				break
			nodes.append(r["node"])
			i = r["next"]
		elif c == "{":
			var close := L.find_matching(_src, i)
			if close == -1 or close >= end:
				_err = "GUITKX0304: unclosed `{` expression"
				break
			var code := _src.substr(i + 1, close - i - 1).strip_edges()
			nodes.append({ "t": "expr", "code": code })
			i = close + 1
		else:
			var r := _parse_text(i, end)
			if r["node"] != null:
				nodes.append(r["node"])
			i = r["next"]
	return { "nodes": nodes, "next": i }

func _parse_element(open_i: int, end: int) -> Dictionary:
	# open_i points at "<"
	var i := open_i + 1
	var line := _line_of(open_i)
	# tag name (empty -> fragment)
	var name_start := i
	while i < end and _is_tag_char(_src[i]):
		i += 1
	var tag := _src.substr(name_start, i - name_start)
	# attributes up to ">" or "/>"
	var attrs: Array = []
	while i < end:
		i = _skip_ws(i, end)
		if i >= end:
			_err = "GUITKX0303: unexpected EOF in <%s>" % tag
			return { "node": null, "next": end }
		var c := _src[i]
		if c == "/" and i + 1 < end and _src[i + 1] == ">":
			# self-closing
			var nd := _mk_el(tag, attrs, [], line)
			return { "node": nd, "next": i + 2 }
		if c == ">":
			i += 1
			break
		var ar := _parse_attribute(i, end)
		if _err != "":
			return { "node": null, "next": end }
		attrs.append(ar["attr"])
		i = ar["next"]
	# paired: parse children; _parse_nodes consumes every {expr}/nested element through find_matching
	# and stops exactly on the matching "</" (or end), telling us where — no second walk to be fooled.
	var cr := _parse_nodes(i, end)
	if _err != "":
		return { "node": null, "next": end }
	var children: Array = cr["nodes"]
	var j: int = cr["next"]
	if j >= end or _src[j] != "<" or (j + 1 < end and _src[j + 1] != "/"):
		_err = "GUITKX0301: unclosed tag <%s>" % tag
		return { "node": null, "next": end }
	# j points at "</": read the close name to ">" (a close tag holds no {expr}/strings, so find is safe)
	var ce := _src.find(">", j)
	if ce == -1 or ce >= end:
		_err = "GUITKX0303: malformed closing tag for <%s>" % tag
		return { "node": null, "next": end }
	var close_name := _src.substr(j + 2, ce - (j + 2)).strip_edges()
	if close_name != tag:
		_err = "GUITKX0302: mismatched tag </%s> (expected </%s>)" % [close_name, tag]
		return { "node": null, "next": end }
	return { "node": _mk_el(tag, attrs, children, line), "next": ce + 1 }

func _mk_el(tag: String, attrs: Array, children: Array, line: int) -> Dictionary:
	if tag == "":
		return { "t": "frag", "children": children }
	return { "t": "el", "tag": tag, "attrs": attrs, "children": children, "line": line }

func _parse_attribute(start: int, end: int) -> Dictionary:
	var i := start
	# spread attribute `{...expr}` (React `{...obj}`): merged into props at codegen. kind "spread".
	if _src[i] == "{":
		var sclose := L.find_matching(_src, i)
		if sclose == -1 or sclose >= end:
			_err = "GUITKX0304: unclosed `{` in spread attribute"
			return { "attr": null, "next": end }
		var inner := _src.substr(i + 1, sclose - i - 1).strip_edges()
		if not inner.begins_with("..."):
			_err = "GUITKX0300: expected `...spread` or an attribute name"
			return { "attr": null, "next": end }
		return { "attr": { "name": "", "kind": "spread", "value": inner.substr(3).strip_edges() }, "next": sclose + 1 }
	var ns := i
	while i < end and _is_attr_name_char(_src[i]):
		i += 1
	var name := _src.substr(ns, i - ns)
	if name == "":
		_err = "GUITKX0300: unexpected token in attributes"
		return { "attr": null, "next": end }
	i = _skip_ws(i, end)
	if i >= end or _src[i] != "=":
		# boolean shorthand
		return { "attr": { "name": name, "kind": "bool", "value": "true" }, "next": i }
	i += 1   # past "="
	i = _skip_ws(i, end)
	if i >= end:
		_err = "GUITKX0303: missing attribute value for '%s'" % name
		return { "attr": null, "next": end }
	var c := _src[i]
	if c == "\"" or c == "'":
		var se := L._skip_string(_src, i)
		var val := _src.substr(i + 1, se - i - 2)
		return { "attr": { "name": name, "kind": "str", "value": val }, "next": se }
	if c == "{":
		var close := L.find_matching(_src, i)
		if close == -1 or close >= end:
			_err = "GUITKX0304: unclosed `{` in attribute '%s'" % name
			return { "attr": null, "next": end }
		var code := _src.substr(i + 1, close - i - 1).strip_edges()
		return { "attr": { "name": name, "kind": "expr", "value": code }, "next": close + 1 }
	_err = "GUITKX0300: attribute '%s' value must be a string or {expr}" % name
	return { "attr": null, "next": end }

func _parse_text(start: int, end: int) -> Dictionary:
	var i := start
	while i < end and _src[i] != "<" and _src[i] != "{":
		i += 1
	var raw := _src.substr(start, i - start)
	if raw.strip_edges() == "":
		return { "node": null, "next": i }   # whitespace-only collapses to nothing
	return { "node": { "t": "text", "value": raw.strip_edges() }, "next": i }

# --- control-flow directives (bodies kept as raw markup strings; emitter lowers them) ---
func _parse_directive(at: int, end: int) -> Dictionary:
	if L.keyword_at(_src, at + 1, "if"):
		return _parse_if(at, end)
	if L.keyword_at(_src, at + 1, "for"):
		return _parse_loop(at, end, "for", 4)
	if L.keyword_at(_src, at + 1, "while"):
		return _parse_loop(at, end, "while", 6)
	if L.keyword_at(_src, at + 1, "match"):
		return _parse_match(at, end)
	_err = "GUITKX0305: unknown @directive"
	return { "node": null, "next": end }

func _read_paren(i: int, end: int) -> Dictionary:
	i = _skip_ws(i, end)
	if i >= end or _src[i] != "(":
		_err = "GUITKX0306: directive expects `(...)`"
		return { "text": "", "next": end }
	var close := L.find_matching(_src, i)
	if close == -1 or close >= end:
		_err = "GUITKX0304: unclosed `(` in directive"
		return { "text": "", "next": end }
	return { "text": _src.substr(i + 1, close - i - 1).strip_edges(), "next": close + 1 }

func _read_brace_body(i: int, end: int) -> Dictionary:
	i = _skip_ws(i, end)
	if i >= end or _src[i] != "{":
		_err = "GUITKX0303: directive expects `{ ... }` body"
		return { "text": "", "next": end }
	var close := L.find_matching(_src, i)
	if close == -1 or close >= end:
		_err = "GUITKX0304: unclosed `{` directive body"
		return { "text": "", "next": end }
	return { "text": _src.substr(i + 1, close - i - 1), "next": close + 1 }

func _parse_if(at: int, end: int) -> Dictionary:
	var branches: Array = []
	var else_body = null
	var i := at + 3   # past "@if"
	var p := _read_paren(i, end)
	if _err != "": return { "node": null, "next": end }
	var b := _read_brace_body(p["next"], end)
	if _err != "": return { "node": null, "next": end }
	branches.append({ "cond": p["text"], "body_markup": b["text"] })
	i = b["next"]
	while true:
		var k := _skip_ws(i, end)
		if k + 5 <= end and L.keyword_at(_src, k + 1, "elif"):
			var pe := _read_paren(k + 5, end)
			if _err != "": return { "node": null, "next": end }
			var be := _read_brace_body(pe["next"], end)
			if _err != "": return { "node": null, "next": end }
			branches.append({ "cond": pe["text"], "body_markup": be["text"] })
			i = be["next"]
		elif k + 5 <= end and L.keyword_at(_src, k + 1, "else"):
			var bb := _read_brace_body(k + 5, end)
			if _err != "": return { "node": null, "next": end }
			else_body = bb["text"]
			i = bb["next"]
			break
		else:
			break
	return { "node": { "t": "if", "branches": branches, "else_body": else_body }, "next": i }

func _parse_loop(at: int, end: int, kind: String, kwlen: int) -> Dictionary:
	var p := _read_paren(at + kwlen, end)
	if _err != "": return { "node": null, "next": end }
	var b := _read_brace_body(p["next"], end)
	if _err != "": return { "node": null, "next": end }
	return { "node": { "t": kind, "header": p["text"], "body_markup": b["text"] }, "next": b["next"] }

func _parse_match(at: int, end: int) -> Dictionary:
	var p := _read_paren(at + 6, end)   # past "@match"
	if _err != "": return { "node": null, "next": end }
	# locate the `{ ... }` body and walk its @case/@default arms
	var bi := _skip_ws(p["next"], end)
	if bi >= end or _src[bi] != "{":
		_err = "GUITKX0303: @match expects `{ ... }` with @case/@default arms"
		return { "node": null, "next": end }
	var bclose := L.find_matching(_src, bi)
	if bclose == -1 or bclose >= end:
		_err = "GUITKX0304: unclosed @match body"
		return { "node": null, "next": end }
	var cases: Array = []
	var default_body = null
	var j := bi + 1
	while j < bclose:
		j = _skip_ws(j, bclose)
		if j >= bclose:
			break
		if _src[j] == "@" and L.keyword_at(_src, j + 1, "case"):
			var cp := _read_paren(j + 5, bclose)
			if _err != "": return { "node": null, "next": end }
			var cb := _read_brace_body(cp["next"], bclose)
			if _err != "": return { "node": null, "next": end }
			cases.append({ "value": cp["text"], "body_markup": cb["text"] })
			j = cb["next"]
		elif _src[j] == "@" and L.keyword_at(_src, j + 1, "default"):
			var db := _read_brace_body(j + 8, bclose)
			if _err != "": return { "node": null, "next": end }
			default_body = db["text"]
			j = db["next"]
		else:
			_err = "GUITKX0306: @match body expects @case (...) { } or @default { }"
			return { "node": null, "next": end }
	return { "node": { "t": "match", "subject": p["text"], "cases": cases, "default_body": default_body }, "next": bclose + 1 }

# --- helpers ---
func _skip_ws(i: int, end: int) -> int:
	while i < end and (_src[i] == " " or _src[i] == "\t" or _src[i] == "\n" or _src[i] == "\r"):
		i += 1
	# also skip {/* ... */}-style guitkx comments? guitkx uses GDScript `#` only inside exprs.
	return i

func _is_tag_char(c: String) -> bool:
	return c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")

func _is_attr_name_char(c: String) -> bool:
	return _is_tag_char(c) or c == "-" or c == "."

func _line_of(idx: int) -> int:
	return _src.substr(0, idx).count("\n") + 1
