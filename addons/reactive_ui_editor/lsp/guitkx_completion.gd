@tool
class_name GuitkxCompletion
extends RefCounted
## Pure completion-item provider for `.guitkx` markup: given a caret, returns *what* to offer,
## sourced from GuitkxContext + GuitkxSchema (live ClassDB) + GuitkxWorkspace. Deliberately UI-free
## so it is unit-testable headlessly; GuitkxCodeEdit maps the items onto add_code_completion_option.
## Attribute-value and embedded-GDScript contexts yield nothing here (the analyzer layer owns those,
## Phase 4). [Phase 1 -- plans/GODOT_ANALYZER_INTEGRATION_PLAN.md §7]

# Item kinds (the editor maps these to CodeEdit.KIND_*).
const CLASS := "class"
const MEMBER := "member"
const SIGNAL := "signal"
const KEYWORD := "keyword"

## Common built-in constants for `<Type>.<member>` completion inside expressions — a static
## fallback for the most-used ones (mirrors the VS Code server's BUILTIN_MEMBERS; the embedded
## analyzer tier supplies the full set once M3 lands).
const BUILTIN_MEMBERS := {
	"Color": ["WHITE", "BLACK", "TRANSPARENT", "RED", "GREEN", "BLUE", "YELLOW", "CYAN", "MAGENTA",
		"GRAY", "DARK_GRAY", "LIGHT_GRAY", "ORANGE", "PURPLE", "PINK", "BROWN", "GOLD", "LIME_GREEN",
		"SKY_BLUE", "AQUA", "NAVY_BLUE", "TEAL", "MAROON", "SILVER", "CRIMSON"],
	"Vector2": ["ZERO", "ONE", "INF", "LEFT", "RIGHT", "UP", "DOWN"],
	"Vector2i": ["ZERO", "ONE", "MIN", "MAX", "LEFT", "RIGHT", "UP", "DOWN"],
	"Vector3": ["ZERO", "ONE", "INF", "LEFT", "RIGHT", "UP", "DOWN", "FORWARD", "BACK"],
}

## Array of { kind:String, insert:String, display:String } for the caret at char `offset` in `text`.
static func for_caret(text: String, offset: int) -> Array:
	var ctx := GuitkxContext.classify(text, offset)
	match ctx["kind"]:
		GuitkxContext.KIND_TAG:
			return _tags("")
		GuitkxContext.KIND_MARKUP:
			return _tags("<") + _directives(false)
		GuitkxContext.KIND_ATTR:
			return _attributes(str(ctx["tag"]))
		GuitkxContext.KIND_ATTR_VALUE:
			return _attr_values(str(ctx["tag"]), str(ctx.get("attr", "")))
		GuitkxContext.KIND_DIRECTIVE:
			return _directives(true)
		GuitkxContext.KIND_EMBEDDED:
			return _embedded(text, offset)
	return []

static func _item(kind: String, insert: String, display := "") -> Dictionary:
	return { "kind": kind, "insert": insert, "display": display if display != "" else insert }

static func _tags(prefix: String) -> Array:
	var out: Array = []
	for tag in GuitkxSchema.host_tags():
		out.append(_item(CLASS, prefix + tag))
	for comp in GuitkxWorkspace.component_tags():
		out.append(_item(CLASS, prefix + comp))
	return out

static func _attributes(tag: String) -> Array:
	var out: Array = []
	var seen := {}
	# G20 snippet shape: attributes insert their `=` + an empty value pair — `=""` for string-ish
	# properties, `={}` for events and expression values. The editor's confirm steps the caret
	# back INSIDE the pair, and the `"` then arms value completion (enums/bools/style keys).
	for a in GuitkxSchema.structural_attributes():
		var nm := str(a.get("name", ""))
		_push_snippet(out, seen, MEMBER, nm, nm + ("=\"\"" if str(a.get("type", "")) == "String" else "={}"))
	var gclass := GuitkxSchema.godot_class_for(tag)
	for ev in GuitkxSchema.events_for_class(gclass):
		var en := str(ev.get("name", ""))
		_push_snippet(out, seen, SIGNAL, en, en + "={}")
	# The verbatim `on_<signal>` escape hatch (G28): every signal, both spellings offered like the
	# VS Code extension. React aliases stay first; natives dedupe against them by name.
	for s in GuitkxSchema.godot_signals(gclass):
		var sn := "on_" + str(s.get("name", ""))
		_push_snippet(out, seen, SIGNAL, sn, sn + "={}")
	for p in GuitkxSchema.godot_properties(gclass):
		var pn := str(p.get("name", ""))
		_push_snippet(out, seen, MEMBER, pn,
			pn + ("=\"\"" if str(p.get("type", "")) == "String" else "={}"))
	return out

## Value completion inside `attr="|"` or `style={ {"|` (G5/G6): style-dict keys for `style`-family
## attributes; true/false for bool properties; the hint names for enum properties.
static func _attr_values(tag: String, attr: String) -> Array:
	var out: Array = []
	if attr == "style" or attr.ends_with("_style"):
		for k in GuitkxSchema.style_keys():
			out.append(_item(MEMBER, str((k as Dictionary).get("name", "")),
				"%s (%s)" % [str((k as Dictionary).get("name", "")), str((k as Dictionary).get("type", ""))]))
		return out
	var info := GuitkxSchema.property_info(GuitkxSchema.godot_class_for(tag), attr)
	if info.is_empty():
		return out
	match int(info.get("type", TYPE_NIL)):
		TYPE_BOOL:
			out.append(_item(KEYWORD, "true"))
			out.append(_item(KEYWORD, "false"))
		TYPE_INT:
			if int(info.get("hint", 0)) == PROPERTY_HINT_ENUM:
				for part in str(info.get("hint_string", "")).split(",", false):
					# hint_string entries can be "Name" or "Name:value" — offer the name.
					out.append(_item(KEYWORD, str(part).get_slice(":", 0)))
	return out

## Embedded/setup completion without the analyzer (G7/G8): `<Type>.` builtin constants and the
## built-in hook names. The full type-aware layer arrives with the native analyzer (M3).
static func _embedded(text: String, offset: int) -> Array:
	var line_start := 0 if offset <= 0 else text.rfind("\n", offset - 1) + 1
	var before := text.substr(line_start, offset - line_start)
	var re := RegEx.new()
	re.compile("([A-Za-z_][A-Za-z0-9_]*)\\.([A-Za-z_][A-Za-z0-9_]*)?$")
	var m := re.search(before)
	if m != null and BUILTIN_MEMBERS.has(m.get_string(1)):
		var out: Array = []
		for member in BUILTIN_MEMBERS[m.get_string(1)]:
			out.append(_item(MEMBER, str(member)))
		return out
	# Hook names while typing `use…` (Ctrl+Space; letters aren't auto-trigger prefixes).
	var w := ""
	var i := before.length() - 1
	while i >= 0:
		var c := before.unicode_at(i)
		if c == 95 or (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122):
			w = before[i] + w
			i -= 1
			continue
		break
	if w.begins_with("u"):
		var out2: Array = []
		for hook in GuitkxHover.HOOKS:
			out2.append(_item(MEMBER, str(hook)))
		return out2
	return []

# When `at_symbol` is true the caret already has the leading `@` typed, so the inserted text drops it.
static func _directives(at_symbol: bool) -> Array:
	var out: Array = []
	for d in GuitkxSchema.control_flow():
		var nm := str(d.get("directive", ""))
		var base := nm.substr(1) if at_symbol else nm
		out.append(_item(KEYWORD, base + _directive_tail(str(d.get("form", ""))), nm))
	if at_symbol:
		for d in GuitkxSchema.preamble_directives():
			var nm := str(d.get("name", ""))
			out.append(_item(KEYWORD, nm.substr(1) + _directive_tail(str(d.get("form", ""))), nm))
	return out

# G20: derive the snippet tail from the directive's documented form — parenthesised forms
# (@if/@for/@match) get " ()", quoted forms (@uss "path") get ' ""', bare forms (@else) nothing.
# The editor's confirm places the caret inside the pair.
static func _directive_tail(form: String) -> String:
	if form.contains("("):
		return " ()"
	if form.contains("\""):
		return " \"\""
	return ""

static func _push(out: Array, seen: Dictionary, kind: String, name: String) -> void:
	if name == "" or seen.has(name):
		return
	seen[name] = true
	out.append(_item(kind, name))

# Deduped push with a snippet insert distinct from the displayed name (G20).
static func _push_snippet(out: Array, seen: Dictionary, kind: String, name: String, insert: String) -> void:
	if name == "" or seen.has(name):
		return
	seen[name] = true
	out.append(_item(kind, insert, name))
