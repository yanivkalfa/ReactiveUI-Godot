@tool
class_name GuitkxDiagnosticsRenderer
extends RefCounted
## Turns the .guitkx compiler's diagnostic STRINGS into on-CodeEdit visuals (a gutter icon + a faint
## line tint) and structured records for the Problems panel.
##
## Ground-truth constraint: RUIGuitkx.compile() returns diagnostics as plain human-readable strings
## like "GUITKX0104 (warning): duplicate key 'x' among sibling elements" — there is NO line/column in
## them. So the line is RECOVERED best-effort: if the message quotes an identifier ('x'), we anchor to
## the first source line that contains it; otherwise we anchor to line 0. Precise ranges are a known
## limitation until the compiler threads positions into diagnostics.

## Parse a single diagnostic string into { "code", "severity" ("error"|"warning"), "message" }.
static func parse_diagnostic(d: String) -> Dictionary:
	var severity := "warning" if d.contains("(warning)") else "error"
	var cut := d.length()
	for ch in [" ", ":", "("]:
		var idx := d.find(ch)
		if idx != -1 and idx < cut:
			cut = idx
	var code := d.substr(0, cut).strip_edges()
	return {"code": code, "severity": severity, "message": d}

## Clear all prior diagnostic decorations from `gutter` and reset line backgrounds.
static func clear(code_edit: CodeEdit, gutter: int) -> void:
	for l in code_edit.get_line_count():
		code_edit.set_line_gutter_icon(l, gutter, null)
		code_edit.set_line_gutter_metadata(l, gutter, null)
		code_edit.set_line_gutter_clickable(l, gutter, false)
		code_edit.set_line_background_color(l, Color(0, 0, 0, 0))

## Render diagnostics onto the CodeEdit; returns the structured records (with a best-effort "line").
static func render(code_edit: CodeEdit, gutter: int, diagnostics: Array,
		err_icon: Texture2D, warn_icon: Texture2D) -> Array:
	clear(code_edit, gutter)
	var line_count := code_edit.get_line_count()
	var src_lines: Array = []
	for l in line_count:
		src_lines.append(code_edit.get_line(l))
	var records: Array = []
	for d in diagnostics:
		var rec := parse_diagnostic(str(d))
		var ln := clampi(_anchor_line(rec["message"], src_lines), 0, maxi(0, line_count - 1))
		rec["line"] = ln
		records.append(rec)
		var is_err: bool = rec["severity"] == "error"
		var icon := err_icon if is_err else warn_icon
		if icon != null:
			code_edit.set_line_gutter_icon(ln, gutter, icon)
			code_edit.set_line_gutter_clickable(ln, gutter, true)
		code_edit.set_line_gutter_metadata(ln, gutter, rec)
		code_edit.set_line_background_color(ln,
			Color(0.8, 0.2, 0.2, 0.10) if is_err else Color(0.85, 0.7, 0.15, 0.08))
	return records

# Best-effort line anchor: first source line containing the first single-quoted token in the message.
static func _anchor_line(message: String, src_lines: Array) -> int:
	var token := _first_quoted(message)
	if token != "":
		for i in src_lines.size():
			if String(src_lines[i]).contains(token):
				return i
	return 0

static func _first_quoted(message: String) -> String:
	var a := message.find("'")
	if a == -1:
		return ""
	var b := message.find("'", a + 1)
	if b == -1 or b <= a + 1:
		return ""
	return message.substr(a + 1, b - a - 1)
