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
		GuitkxContext.KIND_DIRECTIVE:
			return _directives(true)
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
	for a in GuitkxSchema.structural_attributes():
		_push(out, seen, MEMBER, str(a.get("name", "")))
	var gclass := GuitkxSchema.godot_class_for(tag)
	for ev in GuitkxSchema.events_for_class(gclass):
		_push(out, seen, SIGNAL, str(ev.get("name", "")))
	for p in GuitkxSchema.godot_properties(gclass):
		_push(out, seen, MEMBER, str(p.get("name", "")))
	return out

# When `at_symbol` is true the caret already has the leading `@` typed, so the inserted text drops it.
static func _directives(at_symbol: bool) -> Array:
	var out: Array = []
	for d in GuitkxSchema.control_flow():
		var nm := str(d.get("directive", ""))
		out.append(_item(KEYWORD, nm.substr(1) if at_symbol else nm, nm))
	if at_symbol:
		for d in GuitkxSchema.preamble_directives():
			var nm := str(d.get("name", ""))
			out.append(_item(KEYWORD, nm.substr(1), nm))
	return out

static func _push(out: Array, seen: Dictionary, kind: String, name: String) -> void:
	if name == "" or seen.has(name):
		return
	seen[name] = true
	out.append(_item(kind, name))
