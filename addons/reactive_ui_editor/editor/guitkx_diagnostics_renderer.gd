@tool
class_name GuitkxDiagnosticsRenderer
extends RefCounted
## Turns the .guitkx compiler's STRUCTURED diagnostics into on-CodeEdit visuals (a gutter icon + a
## faint line tint) and structured records for the Problems panel.
##
## Since T0.2, RUIGuitkx.compile() returns diagnostics as Dictionaries
## { code, severity, message, offset, length } with `offset` a character position into the compiled
## source -- so the line is EXACT (offset -> line via RUIGuitkxDiag.line_col), no token-search
## guessing. A diagnostic with offset -1 ("whole file") anchors to line 0.

const Diag = preload("res://addons/reactive_ui/guitkx/guitkx_diag.gd")

## Clear all prior diagnostic decorations from `gutter` and reset line backgrounds.
static func clear(code_edit: CodeEdit, gutter: int) -> void:
	for l in code_edit.get_line_count():
		code_edit.set_line_gutter_icon(l, gutter, null)
		code_edit.set_line_gutter_metadata(l, gutter, null)
		code_edit.set_line_gutter_clickable(l, gutter, false)
		code_edit.set_line_background_color(l, Color(0, 0, 0, 0))

## Render diagnostics onto the CodeEdit; returns the structured records for the Problems panel:
## { code, severity ("error"|"warning"|"hint"), message, line (0-based), col (0-based) }.
static func render(code_edit: CodeEdit, gutter: int, diagnostics: Array,
		err_icon: Texture2D, warn_icon: Texture2D) -> Array:
	clear(code_edit, gutter)
	var text := code_edit.text
	var line_count := code_edit.get_line_count()
	var records: Array = []
	for d in diagnostics:
		if not (d is Dictionary):
			continue
		var dd := d as Dictionary
		var off := int(dd.get("offset", -1))
		var lc := Diag.line_col(text, off) if off >= 0 else { "line": 0, "col": 0 }
		var ln := clampi(int(lc["line"]), 0, maxi(0, line_count - 1))
		var sev := int(dd.get("severity", Diag.ERROR))
		var rec := {
			"code": dd.get("code", ""), "severity": Diag.severity_name(sev),
			"message": str(dd.get("message", "")), "line": ln, "col": int(lc["col"]),
		}
		records.append(rec)
		var is_err := sev == Diag.ERROR
		var icon := err_icon if is_err else warn_icon
		if icon != null:
			code_edit.set_line_gutter_icon(ln, gutter, icon)
			code_edit.set_line_gutter_clickable(ln, gutter, true)
		code_edit.set_line_gutter_metadata(ln, gutter, rec)
		code_edit.set_line_background_color(ln,
			Color(0.8, 0.2, 0.2, 0.10) if is_err else Color(0.85, 0.7, 0.15, 0.08))
	return records
