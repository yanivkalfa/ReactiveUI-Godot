@tool
class_name GuitkxOutline
extends RefCounted
## Document outline (parity plan G12): the file's declarations — components ◆, hooks ƒ, modules ▣
## and their members — as [{name, kind, offset}], offset at the declaration NAME. Pure text scan
## (the same declaration grammar the workspace index and compiler use), headless-testable.

static func outline_of(text: String) -> Array:
	var out: Array = []
	var decl := RegEx.new()
	decl.compile("(?m)^([ \\t]*)(component|hook|module)[ \\t]+([A-Za-z_][A-Za-z0-9_]*)")
	var fn := RegEx.new()
	fn.compile("(?m)^[ \\t]+(?:static[ \\t]+)?func[ \\t]+([A-Za-z_][A-Za-z0-9_]*)")
	var in_module_span := []  # [start, end] ranges of module bodies (member funcs belong to them)
	for m in decl.search_all(text):
		out.append({
			"name": m.get_string(3), "kind": m.get_string(2), "offset": m.get_start(3),
		})
		if m.get_string(2) == "module":
			in_module_span.append(m.get_start(0))
	# Module member functions (only meaningful inside a module body; single-component files have
	# their hooks/handlers as part of the component and stay un-listed to keep the tree signal-rich).
	if not in_module_span.is_empty():
		for f in fn.search_all(text):
			if f.get_start(0) > int(in_module_span[0]):
				out.append({ "name": f.get_string(1), "kind": "func", "offset": f.get_start(1) })
	out.sort_custom(func(a, b): return int(a["offset"]) < int(b["offset"]))
	return out
