class_name RUIGuitkxCodegen
extends RefCounted
## Filesystem side of the .guitkx toolchain: find .guitkx files, compile the stale ones, and
## write a SIBLING .gd next to each (Foo.guitkx -> Foo.gd). This is the corrected codegen
## mechanism (PHASE_2_GUITKX_PLAN.md 0b): an EditorImportPlugin can't make preload() a runnable
## class, but a real sibling .gd source file is one Godot's GDScript compiler owns -> genuine
## .new()/render()/hot-reload. The EditorPlugin (plugin.gd) drives this on filesystem changes;
## the logic here is engine-free (pure FileAccess/DirAccess) so it is unit-testable headlessly.

const Compiler = preload("res://addons/reactive_ui/guitkx/guitkx.gd")
const Diag = preload("res://addons/reactive_ui/guitkx/guitkx_diag.gd")

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

## Write the diagnostics sidecar (ALWAYS — even on compile failure), gated by the source hash so the LSP
## ignores it once the buffer diverges from the last compile. Schema v2 (T0.2): structured entries
## { code, severity:int (0 err / 1 warn / 2 hint), message (no code prefix), off, len } — `off`/`len`
## are character offsets into the compiled source (off -1 = whole file), so the LSP ranges precisely
## via positionAt(). The reader (diagsSidecar.ts) keeps a v1 fallback for sidecars written pre-T0.2.
static func write_diags_sidecar(guitkx_path: String, src: String, diagnostics: Array) -> void:
	var entries: Array = []
	for d in diagnostics:
		entries.append({
			"code": d.get("code", ""), "severity": int(d.get("severity", Diag.ERROR)),
			"message": d.get("message", ""), "off": int(d.get("offset", -1)), "len": int(d.get("length", 0)),
		})
	var f := FileAccess.open(diags_path_for(guitkx_path), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({ "v": 2, "src_hash": src_hash(src), "diagnostics": entries }))
		f.close()

## True if the sibling .gd is missing or older than the .guitkx source.
static func is_stale(guitkx_path: String) -> bool:
	var gd_path := gd_path_for(guitkx_path)
	if not FileAccess.file_exists(gd_path):
		return true
	return FileAccess.get_modified_time(guitkx_path) > FileAccess.get_modified_time(gd_path)

# --- Compiler-version staleness ----------------------------------------------------------------
# is_stale()'s mtime check cannot see a COMPILER change: after a `git pull` updates the .guitkx
# compiler, every existing .gd is content-stale yet NEWER than its source, so an mtime-only guard
# skips them forever and the editor keeps loading old-compiler output. (CI regenerates every file
# unconditionally, so it stays green and hides this.) We fingerprint the compiler pipeline and, when
# it changes, force a full recompile so a developer's generated .gd never drift from their compiler.

const _COMPILER_SOURCES := [
	"res://addons/reactive_ui/guitkx/guitkx.gd",
	"res://addons/reactive_ui/guitkx/guitkx_markup.gd",
	"res://addons/reactive_ui/guitkx/guitkx_lexer.gd",
	"res://addons/reactive_ui/guitkx/guitkx_jsx_scan.gd",
	"res://addons/reactive_ui/guitkx/guitkx_diag.gd",
]
# Machine-local marker (`.godot` is gitignored + regenerated), holding the fingerprint that last
# generated this project's .gd. A mismatch (or absence) means the compiler moved -> recompile all.
const _FP_MARKER := "res://.godot/rui_guitkx_compiler.fp"
static var _fp_cache := ""

## FNV-1a fingerprint of the compiler pipeline (CRLF-normalised, so line-ending churn does not shift
## it). Changes whenever the generated .gd output could change.
static func compiler_fingerprint() -> String:
	if _fp_cache != "":
		return _fp_cache
	var h := 2166136261
	for p in _COMPILER_SOURCES:
		var s := FileAccess.get_file_as_string(p).replace("\r", "")
		for idx in s.length():
			h = (h ^ s.unicode_at(idx)) & 0xFFFFFFFF
			h = (h * 16777619) & 0xFFFFFFFF
	_fp_cache = "%08x" % h
	return _fp_cache

## True if the compiler changed since the last full compile (or the marker is absent) -> every .gd
## is potentially stale and must be regenerated regardless of mtime.
static func compiler_changed() -> bool:
	var stored := FileAccess.get_file_as_string(_FP_MARKER) if FileAccess.file_exists(_FP_MARKER) else ""
	return stored.strip_edges() != compiler_fingerprint()

static func _write_fp_marker() -> void:
	var f := FileAccess.open(_FP_MARKER, FileAccess.WRITE)
	if f != null:
		f.store_string(compiler_fingerprint())
		f.close()

## Compile one .guitkx and write its sibling .gd. Returns { ok, path, gd_path?, diagnostics?/error? }.
static func compile_file(guitkx_path: String) -> Dictionary:
	if not FileAccess.file_exists(guitkx_path):
		return { "ok": false, "path": guitkx_path, "error": "file not found" }
	var src := FileAccess.get_file_as_string(guitkx_path)
	var basename := guitkx_path.get_file().get_basename()
	var r: Dictionary = Compiler.compile(src, basename)
	write_diags_sidecar(guitkx_path, src, r["diagnostics"])
	# Surface boundary: derive 0-based line/col from each offset ONCE, here, where the source is at
	# hand -- downstream consumers (plugin.gd dock lines, tests) read d.line/d.col without the source.
	for d in r["diagnostics"]:
		if d is Dictionary and int((d as Dictionary).get("offset", -1)) >= 0:
			var lc := Diag.line_col(src, int(d["offset"]))
			d["line"] = lc["line"]
			d["col"] = lc["col"]
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
## When the compiler pipeline changed since the last run, ALL files are treated as stale (their
## previously-generated .gd may encode old-compiler output even though they are newer than the
## source), then the fingerprint marker is refreshed.
static func compile_all(root: String = "res://") -> Dictionary:
	var compiled: Array = []
	var errors: Array = []
	var force := compiler_changed()
	for path in find_all(root):
		if not force and not is_stale(path):
			continue
		var r := compile_file(path)
		if r["ok"]:
			compiled.append({ "path": path, "gd_path": r["gd_path"], "warnings": r["diagnostics"] })
		else:
			errors.append(r)
	if force:
		_write_fp_marker()
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
