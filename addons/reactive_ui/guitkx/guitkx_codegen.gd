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
	var payload := JSON.stringify({ "v": 2, "src_hash": src_hash(src), "diagnostics": entries })
	var sc_path := diags_path_for(guitkx_path)
	if FileAccess.file_exists(sc_path) and FileAccess.get_file_as_string(sc_path) == payload:
		return   # identical verdict -- don't churn the file (the LSP watches sidecars for changes)
	var f := FileAccess.open(sc_path, FileAccess.WRITE)
	if f != null:
		f.store_string(payload)
		f.close()

## True if the sibling .gd is missing or older than the .guitkx source. A zero mtime (the editor
## scan-window flake) counts as STALE -- erring toward a compile attempt is safe (the empty-read
## hold in compile_file guards it), while trusting `0 > 0` once let a stale demo survive a cold
## open uncompiled (field capture 2026-07-03).
## Mtimes are WHOLE SECONDS, so a save landing in the same second as the last .gd write is
## invisible to `>` -- that file silently skipped recompiles until its next edit ("saved it and
## Godot never recompiled", field capture 2026-07-04). An mtime TIE is therefore broken by
## CONTENT: the sidecar stores the src_hash of exactly what the last compile saw -- hash-equal
## means settled (no busy-recompile spin inside the second), different means a missed save.
## A file whose last compile ERRORED has no sibling .gd at all (T1.1 deletes it); its sidecar
## remembers the verdict instead: same src_hash + an error entry means "this exact content was
## already compiled and reported broken" -> NOT stale, or the watch poll would busy-recompile
## broken files every couple of seconds forever. Any edit hash-mismatches and it goes stale.
static func is_stale(guitkx_path: String) -> bool:
	var gd_path := gd_path_for(guitkx_path)
	if not FileAccess.file_exists(gd_path):
		return sidecar_error_diags(guitkx_path).is_empty()
	var src_t := FileAccess.get_modified_time(guitkx_path)
	var gd_t := FileAccess.get_modified_time(gd_path)
	if src_t == 0 or gd_t == 0:
		return true
	if src_t != gd_t:
		return src_t > gd_t
	return not _sidecar_hash_matches(guitkx_path)

## True when the sidecar's stored src_hash matches the CURRENT source bytes -- i.e. the last
## compile (clean or errored, both write the sidecar) saw exactly this content. A missing,
## foreign, or pre-v2 sidecar reads as false (-> stale: one recompile writes it and settles).
static func _sidecar_hash_matches(guitkx_path: String) -> bool:
	var sc := diags_path_for(guitkx_path)
	if not FileAccess.file_exists(sc):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(sc))
	if not (parsed is Dictionary):
		return false
	var src := FileAccess.get_file_as_string(guitkx_path)
	if src.is_empty():
		return false
	return int((parsed as Dictionary).get("src_hash", -1)) == src_hash(src)

## The persisted error verdict for the CURRENT content of `path`, or [] when none applies: the
## sidecar must exist, hash-match the source (the same bytes the failed compile saw), and carry
## at least one error-severity entry. compile_all uses this to skip pointless recompiles of
## known-broken files while still RE-SURFACING their errors on every sweep -- a fresh editor
## session must re-report a persistently-broken file (the dock dedup is what prevents spam,
## never silence). line/col are re-derived from the stored offsets, same as a fresh compile.
static func sidecar_error_diags(guitkx_path: String) -> Array:
	var sc := diags_path_for(guitkx_path)
	if not FileAccess.file_exists(sc):
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(sc))
	if not (parsed is Dictionary):
		return []
	var d := parsed as Dictionary
	var src := FileAccess.get_file_as_string(guitkx_path)
	if src.is_empty() or int(d.get("src_hash", -1)) != src_hash(src):
		return []
	var out: Array = []
	var has_error := false
	for e in (d.get("diagnostics", []) as Array):
		if not (e is Dictionary):
			continue
		var ed := (e as Dictionary).duplicate()
		if int(ed.get("severity", 1)) == Diag.ERROR:
			has_error = true
		var off := int(ed.get("off", -1))
		if off >= 0:
			var lc := Diag.line_col(src, off)
			ed["line"] = lc["line"]
			ed["col"] = lc["col"]
			ed["offset"] = off
			ed["length"] = int(ed.get("len", 0))
		out.append(ed)
	return out if has_error else []

## Cheap watch-poll predicate: does ANY .guitkx under `root` need a sweep? Read-only and
## early-exiting -- a dir walk plus one or two mtime reads per file; source reads happen only
## for the rare .gd-less (known-broken) files. A changed compiler pipeline is stale by definition.
static func has_stale(root: String = "res://") -> bool:
	if compiler_changed():
		return true
	for path in find_all(root):
		if is_stale(path):
			return true
	return false

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
	"res://addons/reactive_ui/guitkx/vocabulary.json",
	"res://addons/reactive_ui/guitkx/guitkx_vocabulary.gen.gd",
]
# Machine-local marker (`.godot` is gitignored + regenerated), holding the fingerprint that last
# generated this project's .gd. A mismatch (or absence) means the compiler moved -> recompile all.
const _FP_MARKER := "res://.godot/rui_guitkx_compiler.fp"
static var _fp_cache := ""

## FNV-1a fingerprint of the compiler pipeline (CRLF-normalised, so line-ending churn does not shift
## it). Changes whenever the generated .gd output could change. Returns "" — UNKNOWABLE — when any
## source reads back empty: inside the editor's first-scan window FileAccess reads return empty, and
## a fingerprint hashed over empty sources once got PERSISTED, making every later healthy session
## look like a compiler change (caught by _test_cold_open_recovery). Never cached while unknowable.
static func compiler_fingerprint() -> String:
	if _fp_cache != "":
		return _fp_cache
	var h := 2166136261
	for p in _COMPILER_SOURCES:
		var s := FileAccess.get_file_as_string(p).replace("\r", "")
		if s.is_empty():
			return ""
		for idx in s.length():
			h = (h ^ s.unicode_at(idx)) & 0xFFFFFFFF
			h = (h * 16777619) & 0xFFFFFFFF
	_fp_cache = "%08x" % h
	return _fp_cache

## True if the compiler changed since the last full compile (or the marker is absent) -> every .gd
## is potentially stale and must be regenerated regardless of mtime. An UNKNOWABLE fingerprint
## (scan window) forces too — the safe direction: a wasted sweep is cheap, stale-compiler outputs
## surviving an upgrade is the zombie-sidecar capture — and _write_fp_marker will refuse to
## persist until the sources are actually readable, so the force keeps re-firing.
static func compiler_changed() -> bool:
	var fp := compiler_fingerprint()
	if fp == "":
		return true
	var stored := FileAccess.get_file_as_string(_FP_MARKER) if FileAccess.file_exists(_FP_MARKER) else ""
	return stored.strip_edges() != fp

static func _write_fp_marker() -> void:
	var fp := compiler_fingerprint()
	if fp == "":
		return   # unknowable inside the scan window -- never persist garbage; retry next sweep
	var f := FileAccess.open(_FP_MARKER, FileAccess.WRITE)
	if f != null:
		f.store_string(fp)
		f.close()

## T1.5: the PascalCase component names resolvable in this project -- each .guitkx's binding
## (@class_name override, else its first declaration's name) plus every global script class.
## Passed into compile() so `<UnknownComp/>` errors with a did-you-mean instead of emitting a
## call to a class that does not exist.
static func known_component_names(guitkx_paths: Array) -> Array:
	var names := {}
	for p in guitkx_paths:
		var src := FileAccess.get_file_as_string(str(p))
		var b := _binding_name(src)
		if b != "":
			names[b] = true
	for gc in ProjectSettings.get_global_class_list():
		names[str(gc.get("class", ""))] = true
	names.erase("")
	return names.keys()

## The class name a .guitkx compiles to: the @class_name override, else the first declaration's name.
## The override scan mirrors compile()'s preamble loop (ws/comment-skipped, file start only) -- a
## naive whole-file find() would let a COMMENT mentioning @class_name shadow the real binding and
## produce false unknown-component errors in sibling files.
static func _binding_name(src: String) -> String:
	var n := src.length()
	var i := 0
	var override := ""
	while i < n:
		i = Compiler._skip_ws_and_comments(src, i)
		if src.substr(i, 11) == "@class_name":
			var le := src.find("\n", i)
			if le == -1:
				le = n
			var raw := src.substr(i + 11, le - i - 11)
			var hash_at := raw.find("#")
			if hash_at != -1:
				raw = raw.substr(0, hash_at)
			override = raw.strip_edges()
			i = le
			continue
		break
	if override != "":
		return override
	var d: Dictionary = Compiler._find_decl(src, 0)
	if d["kind"] == "":
		return ""
	i = int(d["at"])
	while i < n and (src[i] >= "a" and src[i] <= "z"):
		i += 1   # the decl keyword
	while i < n and (src[i] == " " or src[i] == "\t"):
		i += 1
	var s := i
	while i < n and (src[i] == "_" or (src[i] >= "a" and src[i] <= "z") or (src[i] >= "A" and src[i] <= "Z") or (src[i] >= "0" and src[i] <= "9")):
		i += 1
	return src.substr(s, i - s)

## B1 (0.6.0 field triage): one hold notice per environment-not-ready EPISODE, not one red line per
## file per sweep -- the per-file GUITKX2507 env_error result still records the hold for callers.
static var _env_hold := false

## Compile one .guitkx and write its sibling .gd. Returns { ok, path, gd_path?, diagnostics?/error? }.
static func compile_file(guitkx_path: String, known_components: Array = []) -> Dictionary:
	if not FileAccess.file_exists(guitkx_path):
		return { "ok": false, "path": guitkx_path, "error": "file not found" }
	var src := FileAccess.get_file_as_string(guitkx_path)
	if src.is_empty():
		# 0.6.2: an EMPTY read of an existing file is the editor scan-window flake (the same
		# failure the vocabulary and fingerprint reads had) -- NEVER a compile input: compiling
		# "" fails and T1.1 would delete the sibling .gd of a perfectly healthy file. Same hold
		# semantics as an unreadable vocabulary: keep outputs, land in held[], let the retry
		# sweep pick it up. (A genuinely empty .guitkx has nothing to compile anyway.)
		if not _env_hold:
			_env_hold = true
			push_warning("[guitkx] %s read back empty (editor scan window?) -- holding, outputs kept, retrying" % guitkx_path)
		return { "ok": false, "env_error": true, "path": guitkx_path, "diagnostics": [
			{ "code": "GUITKX2507", "severity": 0, "message": "source read came back empty (editor scan window) -- retrying", "offset": -1, "length": 0 },
		] }
	var basename := guitkx_path.get_file().get_basename()
	var r: Dictionary = Compiler.compile(src, basename, known_components)
	if bool(r.get("env_error", false)):
		# The compiler environment isn't ready (vocabulary unreadable — e.g. the editor's first
		# filesystem scan). NOT a source regression: keep the existing sibling .gd AND the last
		# sidecar; the next pass self-heals once the vocabulary loads. Deleting here is exactly
		# how a transient tooling state once wiped every generated demo .gd on a fresh CI clone.
		if not _env_hold:
			_env_hold = true
			push_warning("[guitkx] compiler not ready (vocabulary.json unreadable) -- keeping existing outputs for every affected file, retrying; further files are silent until it recovers")
		return { "ok": false, "env_error": true, "path": guitkx_path, "diagnostics": r["diagnostics"] }
	if _env_hold:
		_env_hold = false
		print("[guitkx] compiler environment recovered -- compiles resume")
	write_diags_sidecar(guitkx_path, src, r["diagnostics"])
	# Surface boundary: derive 0-based line/col from each offset ONCE, here, where the source is at
	# hand -- downstream consumers (plugin.gd dock lines, tests) read d.line/d.col without the source.
	for d in r["diagnostics"]:
		if d is Dictionary and int((d as Dictionary).get("offset", -1)) >= 0:
			var lc := Diag.line_col(src, int(d["offset"]))
			d["line"] = lc["line"]
			d["col"] = lc["col"]
	if not r["ok"]:
		# T1.1: never leave a stale sibling .gd (from an older successful compile) next to a broken
		# .guitkx -- the editor would silently keep running code that no longer matches the source.
		var stale_gd := gd_path_for(guitkx_path)
		if FileAccess.file_exists(stale_gd):
			DirAccess.remove_absolute(stale_gd)
			push_error("[guitkx] %s no longer compiles -- removed stale %s (fix the errors to regenerate it)" % [guitkx_path, stale_gd])
		return { "ok": false, "path": guitkx_path, "diagnostics": r["diagnostics"] }
	var gd_path := gd_path_for(guitkx_path)
	var f := FileAccess.open(gd_path, FileAccess.WRITE)
	if f == null:
		return { "ok": false, "path": guitkx_path, "error": "cannot write %s (err %d)" % [gd_path, FileAccess.get_open_error()] }
	f.store_string(r["gd"])
	f.close()
	# 0.6.2: parse the generated script IMMEDIATELY on a throwaway GDScript -- Unity parity: uitkx's
	# generated C# fails the Roslyn compile in the console at once, while a generated .gd otherwise
	# parses only when something first loads it, so an unknown identifier in an expression stayed
	# invisible until play. GDScript.new() (not ResourceLoader) keeps the resource cache clean; the
	# class_name line is stripped so the throwaway cannot collide with the scanned global class.
	var chk := GDScript.new()
	var chk_src: String = r["gd"]
	if chk_src.begins_with("class_name "):
		chk_src = chk_src.substr(chk_src.find("\n") + 1)
	chk.source_code = chk_src
	var gd_parse_ok := chk.reload() == OK
	if not gd_parse_ok:
		push_error("[guitkx] %s: the generated %s has GDScript errors (see the parser messages above) -- likely an unknown identifier or type error in an expression; fix the .guitkx source" % [guitkx_path, gd_path.get_file()])
	return { "ok": true, "path": guitkx_path, "gd_path": gd_path, "diagnostics": r["diagnostics"], "gd_parse_ok": gd_parse_ok }

## Compile every stale .guitkx under `root`. Returns { compiled:[...], errors:[...], held:[paths],
## total:int (all tracked .guitkx, for the plugin's sweep summary) }.
## `held` = files skipped because the compiler ENVIRONMENT wasn't ready (env_error: unreadable
## vocabulary) — a tooling state, not source errors: callers must not report them per file (the
## loader's one-per-episode hold line already announced the episode) and should re-run the sweep
## once the environment recovers instead of waiting for a user edit (plugin.gd's retry timer).
## When the compiler pipeline changed since the last run, ALL files are treated as stale (their
## previously-generated .gd may encode old-compiler output even though they are newer than the
## source); the fingerprint marker is refreshed ONLY when nothing was held — a held forced sweep
## compiled nothing, and consuming the marker anyway would let old-compiler outputs and sidecars
## survive every later sweep (exactly the 2026-07-03 zombie-sidecar field capture).
static func compile_all(root: String = "res://") -> Dictionary:
	var compiled: Array = []
	var errors: Array = []
	var held: Array = []
	var force := compiler_changed()
	var all_paths := find_all(root)
	# T1.5: resolve the project's component-class universe ONCE per pass so every file's PascalCase
	# tags are checked against it.
	var known := known_component_names(all_paths)
	for path in all_paths:
		if not force:
			# Known-broken content (sidecar hash-match + error): skip the recompile -- the verdict
			# cannot change -- but keep SURFACING it, so a fresh session's first sweep re-reports.
			var cached := sidecar_error_diags(path)
			if not cached.is_empty():
				errors.append({ "ok": false, "path": path, "diagnostics": cached })
				continue
			if not is_stale(path):
				continue
		var r := compile_file(path, known)
		if r["ok"]:
			# gd_ok: the generated script also PARSES (the throwaway GDScript.new check). The
			# HMR push filters on it -- never hot-load a script the engine would reject.
			compiled.append({ "path": path, "gd_path": r["gd_path"], "warnings": r["diagnostics"], "gd_ok": bool(r.get("gd_parse_ok", true)) })
		elif bool(r.get("env_error", false)):
			held.append(path)
		else:
			errors.append(r)
	if force and held.is_empty():
		_write_fp_marker()
	return { "compiled": compiled, "errors": errors, "held": held, "total": all_paths.size() }

## Recursively collect all .guitkx paths under `dir` (skips Godot's hidden cache dirs).
static func find_all(dir: String = "res://") -> Array:
	var out: Array = []
	_walk(dir, out)
	return out

static func _walk(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	# Honor Godot's `.gdignore` convention: a directory holding one is invisible to the asset DB,
	# so the codegen must not compile .guitkx inside it either (e.g. tests/contract/fixtures, which
	# contains DELIBERATELY-broken parser fixtures).
	if FileAccess.file_exists(dir.path_join(".gdignore")):
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
