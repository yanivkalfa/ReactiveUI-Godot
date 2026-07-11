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
static func write_diags_sidecar(guitkx_path: String, src: String, diagnostics: Array, refs: Dictionary = {}) -> void:
	var entries: Array = []
	for d in diagnostics:
		entries.append({
			"code": d.get("code", ""), "severity": int(d.get("severity", Diag.ERROR)),
			"message": d.get("message", ""), "off": int(d.get("offset", -1)), "len": int(d.get("length", 0)),
		})
	# `refs` (component class -> generated .gd path this compile resolved through V.comp) lets
	# the sweep flag DANGLING references when a component's file later vanishes (GUITKX2107).
	var payload := JSON.stringify({ "v": 2, "src_hash": src_hash(src), "diagnostics": entries, "refs": refs })
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
	if src_t > gd_t:
		# Mtime-newer is only stale when the CONTENT isn't already reported broken: a re-save of
		# a file with a standing error verdict (e.g. GUITKX2107 after deleting a component it
		# references) bumps the mtime but changes nothing -- treating it as stale made the poll
		# sweep every 2s forever, because the error branch re-surfaces without compiling and the
		# .gd mtime never advances (field capture 2026-07-04). A REAL edit hash-mismatches the
		# sidecar, so sidecar_error_diags returns [] and the file compiles normally.
		return sidecar_error_diags(guitkx_path).is_empty()
	if src_t < gd_t:
		return false
	return not _sidecar_hash_matches(guitkx_path)

## Raw sidecar payload for `guitkx_path` ({} when absent/unparseable) -- the refs/2107 logic
## reads it once per sweep; sidecar_error_diags keeps its own focused reader.
static func _read_sidecar_raw(guitkx_path: String) -> Dictionary:
	var sc := diags_path_for(guitkx_path)
	if not FileAccess.file_exists(sc):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(sc))
	return parsed if parsed is Dictionary else {}

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
	var paths: Array = []
	var gd_paths: Array = []
	var sc_paths: Array = []
	_walk(root, paths, gd_paths, sc_paths)
	for path in paths:
		if is_stale(path):
			return true
	for sc in sc_paths:
		if not FileAccess.file_exists(str(sc).trim_suffix(".diags.json")):
			return true   # sourceless sidecar -- cleanup work for the sweep
	# Orphaned outputs count as stale work too: a rename/delete must be cleaned up by the next
	# poll tick, not whenever an unrelated save happens to trigger a sweep. Cheap: the header
	# read only happens for .gd files that have NO sibling .guitkx (rare).
	var sources := {}
	for p in paths:
		sources[p] = true
	for gd in gd_paths:
		if _is_orphaned_output(gd, sources):
			return true
	# Dangling references make the poll hot too: deleting a component's whole FOLDER removes its
	# outputs with it -- no orphan is left behind to notice, and dependents aren't mtime-stale,
	# so nothing above fires (field capture 2026-07-04: the 2107 only landed when a save or a
	# focus change happened to cause a sweep). The dependents' sidecars still record what they
	# reference; a state MISMATCH is sweep work in either direction: unflagged-but-missing needs
	# the 2107 flag, flagged-but-restored needs the heal recompile. Matching states settle the
	# poll. Cost: one small JSON read per tracked file, same order as the mtime pass above.
	for path in paths:
		var raw := _read_sidecar_raw(str(path))
		if raw.is_empty():
			continue
		var refs: Dictionary = raw.get("refs", {})
		if refs.is_empty():
			continue
		var flagged := false
		for e in (raw.get("diagnostics", []) as Array):
			if e is Dictionary and str((e as Dictionary).get("code", "")) == "GUITKX2107":
				flagged = true
				break
		var missing := false
		for cls in refs:
			if not FileAccess.file_exists(str(refs[cls])):
				missing = true
				break
		if missing != flagged:
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

## The class name a .guitkx compiles to: the @class_name override, else the first EXPORTED
## declaration's name, else the first declaration's name. The preamble scan is ORDER-AGNOSTIC — it
## skips `import` lines and `@uss`/`@theme` as well as `@class_name`, mirroring compile()'s loop —
## because 0.10.0 allows `@class_name` BEFORE or AFTER imports, and a scan that broke at the first
## non-`@class_name` token would miss a `@class_name` sitting after an import and silently rebind the
## file to its first decl (every identity table — V.comp paths, GUITKX2106 arbitration, the HMR link
## table, the workspace index — keys on this, so the fix lands here first). A naive whole-file find()
## would also let a COMMENT mentioning @class_name shadow the real binding.
static func _binding_name(src: String) -> String:
	var n := src.length()
	var i := 0
	var override := ""
	while i < n:
		i = Compiler._skip_ws_and_comments(src, i)
		if i >= n:
			break
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
		# Skip an `import { ... } from "spec"` — brace-matched so a multi-line import is skipped whole,
		# with a line-end fallback if the form is malformed (compile() reports that separately).
		if Compiler.L.keyword_at(src, i, "import"):
			i = _skip_import_span(src, i)
			continue
		# Skip `@uss`/`@theme` directive lines.
		if src.substr(i, 4) == "@uss" or src.substr(i, 6) == "@theme":
			var le2 := src.find("\n", i)
			i = n if le2 == -1 else le2
			continue
		break
	if override != "":
		return override
	var d: Dictionary = Compiler._find_decl(src, 0)
	if d["kind"] == "":
		return ""
	# `at` is the decl KEYWORD (past any `export` prefix); the name follows the keyword + whitespace.
	i = int(d["at"])
	while i < n and (src[i] >= "a" and src[i] <= "z"):
		i += 1   # the decl keyword
	while i < n and (src[i] == " " or src[i] == "\t"):
		i += 1
	var s := i
	while i < n and (src[i] == "_" or (src[i] >= "a" and src[i] <= "z") or (src[i] >= "A" and src[i] <= "Z") or (src[i] >= "0" and src[i] <= "9")):
		i += 1
	return src.substr(s, i - s)

## Advance past an `import` statement starting at `i` (the `import` keyword). Brace-matched so a
## multi-line `import { ... }` is consumed whole; falls back to end-of-line if the form is malformed.
static func _skip_import_span(src: String, i: int) -> int:
	var n := src.length()
	var line_end := src.find("\n", i)
	if line_end == -1:
		line_end = n
	var j := Compiler._skip_ws_and_comments(src, i + 6)
	if j >= n or src[j] != "{":
		return line_end
	var bclose := Compiler.L.find_matching(src, j)
	if bclose == -1:
		return line_end
	# past `}` -> `from` -> the specifier string's closing quote
	var k := Compiler._skip_ws_and_comments(src, bclose + 1)
	if not Compiler.L.keyword_at(src, k, "from"):
		return maxi(line_end, bclose + 1)
	k = Compiler._skip_ws_only(src, k + 4)   # ws-only: skip_noncode would leap the specifier string
	if k >= n or (src[k] != "\"" and src[k] != "'"):
		return maxi(line_end, k)
	var qe := src.find(src[k], k + 1)
	return maxi(line_end, (bclose + 1) if qe == -1 else (qe + 1))

## B1 (0.6.0 field triage): one hold notice per environment-not-ready EPISODE, not one red line per
## file per sweep -- the per-file GUITKX2507 env_error result still records the hold for callers.
static var _env_hold := false

## One read pass over `paths`: every class binding, the winners map (class -> generated .gd
## path -- doubles as the HMR link table AND the emitter's V.comp path source), the dupe losers
## (GUITKX2106), and the full known-component name list (bindings + project global classes).
## Shared by compile_all and the build/CI helpers so every caller emits IDENTICAL output.
static func project_bindings(paths: Array) -> Dictionary:
	var by_class := {}
	var sources := {}   # path -> source text (read ONCE; reused by dupe + dangling-ref checks)
	for p in paths:
		var src := FileAccess.get_file_as_string(str(p))
		sources[str(p)] = src
		var b := _binding_name(src)
		if b == "":
			continue
		if not by_class.has(b):
			by_class[b] = []
		(by_class[b] as Array).append(p)
	var known: Array = by_class.keys()
	for gc in ProjectSettings.get_global_class_list():
		var gn := str(gc.get("class", ""))
		if gn != "" and not known.has(gn):
			known.append(gn)
	var dupe_losers := {}
	var bindings := {}
	for cls in by_class:
		var binders: Array = by_class[cls]
		binders.sort()
		var winner = binders[0]
		if binders.size() > 1:
			winner = null
			for p3 in binders:
				if FileAccess.file_exists(gd_path_for(str(p3))):
					winner = p3
					break
			if winner == null:
				winner = binders[0]
			for p3 in binders:
				if p3 != winner:
					dupe_losers[p3] = { "class": cls, "winner": winner }
		bindings[cls] = gd_path_for(str(winner))
	return { "known": known, "bindings": bindings, "losers": dupe_losers, "sources": sources }

## Compile one .guitkx and write its sibling .gd. Returns { ok, path, gd_path?, diagnostics?/error? }.
## `component_paths` (class -> generated .gd) makes the emitter reference guitkx siblings by
## PATH (V.comp) -- pass project_bindings()["bindings"] for output identical to the watcher's.
static func compile_file(guitkx_path: String, known_components: Array = [], component_paths: Dictionary = {}) -> Dictionary:
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
	var r: Dictionary = Compiler.compile(src, basename, known_components, component_paths)
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
	write_diags_sidecar(guitkx_path, src, r["diagnostics"], r.get("refs", {}))
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
	var all_paths: Array = []
	var gd_candidates: Array = []
	var sc_candidates: Array = []
	_walk(root, all_paths, gd_candidates, sc_candidates)
	# T1.5: resolve the project's component-class universe ONCE per pass so every file's PascalCase
	# tags are checked against it -- and, in the same single read pass, detect DUPLICATE bindings.
	# GUITKX2106 (0.8.1): copy-pasting a .guitkx creates a second source binding the same class
	# INSTANTLY (the watch poll compiles the copy before the user renames it, field capture
	# 2026-07-04) -- two outputs would declare the same class_name and poison global resolution.
	# Rule: the INCUMBENT (the path whose sibling .gd already exists; else the first
	# lexicographically) keeps compiling; every other binder errors (sidecar + dock), gets NO
	# output, and any stale output it has is removed -- the project can never hold two .gd files
	# for one class, and it converges the moment the copy is renamed.
	var pb := project_bindings(all_paths)
	var known: Array = pb["known"]
	var dupe_losers: Dictionary = pb["losers"]
	var bindings: Dictionary = pb["bindings"]   # class -> .gd path: V.comp emission + HMR link table
	# Orphan cleanup FIRST -- generated outputs whose .guitkx was deleted or renamed. Without
	# this, the stale .gd keeps its class_name registered and (after a rename) DUPLICATES the
	# new file's class. Running BEFORE the compile loop means the dangling-reference check
	# (GUITKX2107, below) sees the vanished component's .gd already gone in the SAME sweep --
	# the deletion event itself produces the dependents' errors, not some later unrelated sweep.
	var removed: Array = []
	var source_set := {}
	for p in all_paths:
		source_set[p] = true
	for gd in gd_candidates:
		if _is_orphaned_output(gd, source_set):
			_remove_orphaned_output(gd)
			removed.append(gd)
	# Sourceless sidecars leak separately (a GUITKX2106 dupe-loser never had a .gd): the name
	# pattern `<src>.guitkx.diags.json` is ours by construction, so no header check is needed.
	for sc in sc_candidates:
		var sc_src := str(sc).trim_suffix(".diags.json")
		if not source_set.has(sc_src) and not FileAccess.file_exists(sc_src):
			DirAccess.remove_absolute(str(sc))
			removed.append(str(sc))
	for path in all_paths:
		if dupe_losers.has(path):
			var dl: Dictionary = dupe_losers[path]
			var dsrc := FileAccess.get_file_as_string(path)
			if dsrc.is_empty():
				held.append(path)   # scan-window read flake -- never a verdict
				continue
			var dat := maxi(0, dsrc.find(str(dl["class"])))
			var diag := { "code": "GUITKX2106", "severity": 0, "offset": dat, "length": str(dl["class"]).length(),
				"message": "class `%s` is already bound by %s -- rename this component (a copied file compiles immediately, so rename before editing further)" % [dl["class"], dl["winner"]] }
			var dlc := Diag.line_col(dsrc, dat)
			diag["line"] = dlc["line"]
			diag["col"] = dlc["col"]
			write_diags_sidecar(path, dsrc, [diag])
			var dupe_gd := gd_path_for(path)
			if FileAccess.file_exists(dupe_gd):
				DirAccess.remove_absolute(dupe_gd)
				push_error("[guitkx] %s: duplicate class binding -- removed its %s (rename the component)" % [path, dupe_gd.get_file()])
			errors.append({ "ok": false, "path": path, "diagnostics": [diag] })
			continue
		# GUITKX2107 (dangling references): the file itself is unchanged (not mtime-stale), but a
		# component it references may have VANISHED -- deleted or renamed, its .gd orphan-swept.
		# Without this check the only symptom would be a runtime load failure at the next launch.
		# The sidecar stores the class->path refs of the last compile; a missing path is a loud
		# error (dock + sidecar -> VS Code squiggle at the dangling tag), and once every ref
		# exists again (component restored / reference edited away is mtime-stale anyway) a
		# recompile HEALS the sidecar.
		var heal_2107 := false
		if not force:
			var src_now := str((pb["sources"] as Dictionary).get(path, ""))
			var sc_raw := _read_sidecar_raw(path)
			if not src_now.is_empty() and not sc_raw.is_empty() and int(sc_raw.get("src_hash", -1)) == src_hash(src_now):
				var refs: Dictionary = sc_raw.get("refs", {})
				var missing := {}
				for cls in refs:
					if not FileAccess.file_exists(str(refs[cls])):
						missing[cls] = refs[cls]
				var had_2107 := false
				for e in (sc_raw.get("diagnostics", []) as Array):
					if e is Dictionary and str((e as Dictionary).get("code", "")) == "GUITKX2107":
						had_2107 = true
						break
				if not missing.is_empty():
					if not had_2107:
						var dgs: Array = []
						for cls in missing:
							var rat := maxi(0, src_now.find("<" + str(cls)))
							var rlc := Diag.line_col(src_now, rat)
							dgs.append({ "code": "GUITKX2107", "severity": 0, "offset": rat, "length": str(cls).length() + 1,
								"line": rlc["line"], "col": rlc["col"],
								"message": "component `%s` no longer exists (its file was deleted or renamed) -- remove or update this reference, or restore the component (expected %s)" % [str(cls), str(missing[cls])] })
						write_diags_sidecar(path, src_now, dgs, refs)
						push_error("[guitkx] %s: dangling component reference(s): %s" % [path, ", ".join(missing.keys())])
						errors.append({ "ok": false, "path": path, "diagnostics": dgs })
					else:
						errors.append({ "ok": false, "path": path, "diagnostics": sidecar_error_diags(path) })
					continue
				elif had_2107:
					heal_2107 = true   # everything it references exists again -- recompile to clear
		if not force and not heal_2107:
			# Known-broken content (sidecar hash-match + error): skip the recompile -- the verdict
			# cannot change -- but keep SURFACING it, so a fresh session's first sweep re-reports.
			var cached := sidecar_error_diags(path)
			if not cached.is_empty():
				errors.append({ "ok": false, "path": path, "diagnostics": cached })
				continue
			if not is_stale(path):
				continue
		var r := compile_file(path, known, bindings)
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
	return { "compiled": compiled, "errors": errors, "held": held, "total": all_paths.size(), "removed": removed, "bindings": bindings }

## Recursively collect all .guitkx paths under `dir` (skips Godot's hidden cache dirs).
static func find_all(dir: String = "res://") -> Array:
	var out: Array = []
	_walk(dir, out, [], [])
	return out

static func _walk(dir: String, out: Array, gd_out: Array, sc_out: Array) -> void:
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
				_walk(p, out, gd_out, sc_out)
		elif name.get_extension() == "guitkx":
			out.append(p)
		elif name.get_extension() == "gd":
			gd_out.append(p)   # orphan-cleanup candidates (see _is_orphaned_output)
		elif name.ends_with(".guitkx.diags.json"):
			sc_out.append(p)   # sidecar orphans: ours by name pattern, removable when sourceless
		name = d.get_next()
	d.list_dir_end()

## True when `gd_path` is one of OUR generated outputs whose source .guitkx no longer exists —
## the leak a rename/delete used to leave behind forever (field capture 2026-07-04: renaming
## components/deep_tree.guitkx left components/deep_tree.gd declaring `class_name DemoDeepTree`,
## a DUPLICATE of the real demo's global class — instant project-wide resolution chaos).
## The AUTO-GENERATED header marker is the authority: hand-written scripts are never touched.
## An empty read (the editor scan window) is never treated as an orphan verdict.
static func _is_orphaned_output(gd_path: String, sources: Dictionary) -> bool:
	var src := gd_path.get_basename() + ".guitkx"
	if sources.has(src) or FileAccess.file_exists(src):
		return false
	# The marker sits in the first three lines of every generated file; read no more than that —
	# this runs for every sibling-less .gd (all hand-written scripts) on every sweep/poll.
	var f := FileAccess.open(gd_path, FileAccess.READ)
	if f == null:
		return false
	var head := ""
	for _i in 3:
		head += f.get_line() + "\n"
		if f.eof_reached():
			break
	f.close()
	if head.strip_edges().is_empty():
		return false
	return head.contains("## AUTO-GENERATED from") and head.contains(".guitkx -- do not edit.")

## Delete an orphan's whole output family: the .gd, its .uid, and the vanished source's sidecar
## (+ .uid). Returns the paths actually removed (for the plugin's dock lines).
static func _remove_orphaned_output(gd_path: String) -> void:
	DirAccess.remove_absolute(gd_path)
	var src := gd_path.get_basename() + ".guitkx"
	for extra in [gd_path + ".uid", src + ".diags.json", src + ".uid"]:
		if FileAccess.file_exists(extra):
			DirAccess.remove_absolute(extra)
