@tool
class_name GuitkxRefs
extends RefCounted
## Project-wide component references + rename edits (parity plan G2/G3, port of the VS Code
## server's refs.ts semantics): boundary-aware tag scanning (a `x < Name` comparison is not a
## reference; strings/comments are skipped via the lexer), declaration + @class_name tokens
## included, and a collision-refusing rename that edits every file atomically.

## All references to component `tag` inside `text`: [{offset, length, kind}] where kind is
## "open" | "close" | "decl" | "class_name". Offsets point at the NAME, not the `<`.
static func tag_refs_in(text: String, tag: String) -> Array:
	var out: Array = []
	var n := text.length()
	var i := 0
	while i < n:
		var j: int = RUIGuitkxLexer.skip_noncode(text, i)
		if j > i:
			i = j
			continue
		if text[i] != "<":
			i += 1
			continue
		var k := i + 1
		var kind := "open"
		if k < n and text[k] == "/":
			kind = "close"
			k += 1
		var s := k
		while k < n and _is_ident(text.unicode_at(k)):
			k += 1
		if k == s:
			i += 1
			continue
		if kind == "open":
			# Comparison guard (same as the scan-diags tier): `x <Name` is an expression.
			var p := i - 1
			while p >= 0 and (text[p] == " " or text[p] == "\t"):
				p -= 1
			if p >= 0 and (_is_ident(text.unicode_at(p)) or text[p] == ")" or text[p] == "]" or text[p] == "\"" or text[p] == "'"):
				i = k
				continue
		if text.substr(s, k - s) == tag:
			out.append({ "offset": s, "length": tag.length(), "kind": kind })
		i = k
	# Declaration + @class_name tokens (the rename must move these too).
	for m in _decl_re().search_all(text):
		if m.get_string(2) == tag:
			out.append({ "offset": m.get_start(2), "length": tag.length(), "kind": "decl" })
	var cm := _cn_re().search(text)
	if cm != null and cm.get_string(1) == tag:
		out.append({ "offset": cm.get_start(1), "length": tag.length(), "kind": "class_name" })
	out.sort_custom(func(a, b): return int(a["offset"]) < int(b["offset"]))
	return out

## Every reference across the project: [{path, offset, length, kind, line, preview}].
static func project_refs(tag: String) -> Array:
	var out: Array = []
	for p in GuitkxWorkspace.all_paths():
		var text := FileAccess.get_file_as_string(str(p))
		if text.is_empty():
			continue
		for r in tag_refs_in(text, tag):
			var lc: Dictionary = RUIGuitkxDiag.line_col(text, int(r["offset"]))
			var line := int(lc.get("line", 0))
			var ls := 0 if line == 0 else text.rfind("\n", int(r["offset"]) - 1) + 1
			var le := text.find("\n", int(r["offset"]))
			if le == -1:
				le = text.length()
			out.append({
				"path": str(p), "offset": int(r["offset"]), "length": int(r["length"]),
				"kind": str(r["kind"]), "line": line,
				"preview": text.substr(ls, le - ls).strip_edges(),
			})
	return out

## Rename gate + edit set. Returns { ok, reason, edits: {path: [{offset,length}]} }.
## Refuses: invalid identifier, host-tag collision, existing component/global-class collision,
## unknown source component — exactly the VS Code server's gate.
static func rename_edits(old_tag: String, new_tag: String) -> Dictionary:
	if not GuitkxWorkspace.is_component(old_tag):
		return { "ok": false, "reason": "'%s' is not a project component." % old_tag, "edits": {} }
	if not new_tag.is_valid_identifier() or new_tag.is_empty() or not (new_tag[0] >= "A" and new_tag[0] <= "Z"):
		return { "ok": false, "reason": "'%s' is not a valid PascalCase component name." % new_tag, "edits": {} }
	if GuitkxSchema.is_host_tag(new_tag):
		return { "ok": false, "reason": "'%s' is a host element tag." % new_tag, "edits": {} }
	if GuitkxWorkspace.is_component(new_tag):
		return { "ok": false, "reason": "a component named '%s' already exists." % new_tag, "edits": {} }
	for gc in ProjectSettings.get_global_class_list():
		if str(gc.get("class", "")) == new_tag:
			return { "ok": false, "reason": "a global class named '%s' already exists." % new_tag, "edits": {} }
	var edits := {}
	for r in project_refs(old_tag):
		var p := str(r["path"])
		if not edits.has(p):
			edits[p] = []
		(edits[p] as Array).append({ "offset": int(r["offset"]), "length": int(r["length"]) })
	if edits.is_empty():
		return { "ok": false, "reason": "no references found for '%s'." % old_tag, "edits": {} }
	return { "ok": true, "reason": "", "edits": edits }

## Splice `replacement` into `text` at each edit (descending order keeps earlier offsets valid).
static func apply_edits_to_text(text: String, edits: Array, replacement: String) -> String:
	var sorted := edits.duplicate()
	sorted.sort_custom(func(a, b): return int(a["offset"]) > int(b["offset"]))
	for e in sorted:
		var off := int(e["offset"])
		text = text.substr(0, off) + replacement + text.substr(off + int(e["length"]))
	return text

static func _decl_re() -> RegEx:
	var re := RegEx.new()
	re.compile("(?m)^[ \\t]*(component|module)[ \\t]+([A-Za-z_][A-Za-z0-9_]*)")
	return re

static func _cn_re() -> RegEx:
	var re := RegEx.new()
	re.compile("(?m)^[ \\t]*@class_name[ \\t]+([A-Za-z_][A-Za-z0-9_]*)")
	return re

static func _is_ident(c: int) -> bool:
	return c == 95 or (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
