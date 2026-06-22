class_name RUIGuitkxCodegen
extends RefCounted
## Filesystem side of the .guitkx toolchain: find .guitkx files, compile the stale ones, and
## write a SIBLING .gd next to each (Foo.guitkx -> Foo.gd). This is the corrected codegen
## mechanism (PHASE_2_GUITKX_PLAN.md 0b): an EditorImportPlugin can't make preload() a runnable
## class, but a real sibling .gd source file is one Godot's GDScript compiler owns -> genuine
## .new()/render()/hot-reload. The EditorPlugin (plugin.gd) drives this on filesystem changes;
## the logic here is engine-free (pure FileAccess/DirAccess) so it is unit-testable headlessly.

const Compiler = preload("res://addons/reactive_ui/guitkx/guitkx.gd")

## The sibling .gd path for a .guitkx path.
static func gd_path_for(guitkx_path: String) -> String:
	return guitkx_path.get_basename() + ".gd"

## The sibling diagnostics-sidecar path (Foo.guitkx -> Foo.guitkx.diags.json). The LSP reads this to
## surface the compiler's FULL diagnostic catalog in VS Code without a running editor.
static func diags_path_for(guitkx_path: String) -> String:
	return guitkx_path + ".diags.json"

## FNV-1a over code points — MUST stay identical to the LSP's srcHash (diagsSidecar.ts) so the LSP can
## tell whether the sidecar still matches the open buffer (else the diagnostics are stale + suppressed).
static func src_hash(s: String) -> int:
	var h := 2166136261
	for idx in s.length():
		h = (h ^ s.unicode_at(idx)) & 0xFFFFFFFF
		h = (h * 16777619) & 0xFFFFFFFF
	return h

## Split a diagnostic string ("GUITKX0104 (warning): ...") into { code, severity, message }.
static func _parse_diag(s: String) -> Dictionary:
	var end := 0
	while end < s.length() and s[end] != " " and s[end] != ":" and s[end] != "(":
		end += 1
	return { "code": s.substr(0, end), "severity": "warning" if "(warning)" in s else "error", "message": s }

## Write the diagnostics sidecar (ALWAYS — even on compile failure), gated by the source hash so the LSP
## ignores it once the buffer diverges from the last compile.
static func write_diags_sidecar(guitkx_path: String, src: String, diagnostics: Array) -> void:
	var parsed: Array = []
	for d in diagnostics:
		parsed.append(_parse_diag(str(d)))
	var f := FileAccess.open(diags_path_for(guitkx_path), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({ "src_hash": src_hash(src), "diagnostics": parsed }))
		f.close()

## True if the sibling .gd is missing or older than the .guitkx source.
static func is_stale(guitkx_path: String) -> bool:
	var gd_path := gd_path_for(guitkx_path)
	if not FileAccess.file_exists(gd_path):
		return true
	return FileAccess.get_modified_time(guitkx_path) > FileAccess.get_modified_time(gd_path)

## Compile one .guitkx and write its sibling .gd. Returns { ok, path, gd_path?, diagnostics?/error? }.
static func compile_file(guitkx_path: String) -> Dictionary:
	if not FileAccess.file_exists(guitkx_path):
		return { "ok": false, "path": guitkx_path, "error": "file not found" }
	var src := FileAccess.get_file_as_string(guitkx_path)
	var basename := guitkx_path.get_file().get_basename()
	var r: Dictionary = Compiler.compile(src, basename)
	write_diags_sidecar(guitkx_path, src, r["diagnostics"])
	if not r["ok"]:
		return { "ok": false, "path": guitkx_path, "diagnostics": r["diagnostics"] }
	var gd_path := gd_path_for(guitkx_path)
	var f := FileAccess.open(gd_path, FileAccess.WRITE)
	if f == null:
		return { "ok": false, "path": guitkx_path, "error": "cannot write %s (err %d)" % [gd_path, FileAccess.get_open_error()] }
	f.store_string(r["gd"])
	f.close()
	return { "ok": true, "path": guitkx_path, "gd_path": gd_path, "diagnostics": r["diagnostics"] }

## Compile every stale .guitkx under `root`. Returns { compiled:[gd_paths], errors:[{path,...}] }.
static func compile_all(root: String = "res://") -> Dictionary:
	var compiled: Array = []
	var errors: Array = []
	for path in find_all(root):
		if not is_stale(path):
			continue
		var r := compile_file(path)
		if r["ok"]:
			compiled.append({ "path": path, "gd_path": r["gd_path"], "warnings": r["diagnostics"] })
		else:
			errors.append(r)
	return { "compiled": compiled, "errors": errors }

## Recursively collect all .guitkx paths under `dir` (skips Godot's hidden cache dirs).
static func find_all(dir: String = "res://") -> Array:
	var out: Array = []
	_walk(dir, out)
	return out

static func _walk(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name == "." or name == "..":
			name = d.get_next()
			continue
		var p := dir.path_join(name)
		if d.current_is_dir():
			if not name.begins_with("."):   # skip .godot, .git, etc.
				_walk(p, out)
		elif name.get_extension() == "guitkx":
			out.append(p)
		name = d.get_next()
	d.list_dir_end()
