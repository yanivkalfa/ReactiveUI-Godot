class_name RUIGuitkxMigrate
extends RefCounted
## The 0.10.0 import-migration CODEMOD (§M6). Rewrites every `.guitkx` in place so the tree satisfies
## strict cross-file resolution: (a) prefix `export ` onto EVERY top-level declaration (export-
## everything is the shipped default -- privacy is opt-in going forward), and (b) synthesize one
## `import { … } from "…"` line per OTHER file this one references. Idempotent + re-runnable, so an
## in-flight branch self-migrates on rebase. Pure/static + FileAccess-only (headless CI runner).
##
## Reference discovery is a FRESH source scan (never sidecar/edge-derived, which only record markup
## tags): every referenceable name = a top-level decl of ANOTHER `.guitkx` file; a name is imported
## when this file uses it as a markup tag (`<Name`) or a qualified reference (`Name.` / `Name(`).
## Hand-written `class_name` scripts (DoomTypes, …) and host/ClassDB elements are NOT `.guitkx` decls,
## so they are never in the referenceable set -- they stay ambient, import-free (rule 7).

const Compiler = preload("res://addons/reactive_ui/guitkx/guitkx.gd")
const Config = preload("res://addons/reactive_ui/guitkx/guitkx_config.gd")
const Resolve = preload("res://addons/reactive_ui/guitkx/guitkx_resolve.gd")
const L = preload("res://addons/reactive_ui/guitkx/guitkx_lexer.gd")

## Migrate every `.guitkx` under `root`. Returns { changed:[paths], scanned:int }.
static func migrate_all(root: String = "res://") -> Dictionary:
	var paths := _find_guitkx(root)
	var sources := {}
	var referenceable := {}   # decl name -> owning .guitkx path (the import universe)
	for p in paths:
		var src := FileAccess.get_file_as_string(p)
		sources[p] = src
		for dm in Compiler._enumerate_decls(src, 0):
			var nm := str(dm["name"])
			if nm != "" and not referenceable.has(nm):
				referenceable[nm] = p
	var changed: Array = []
	for p in paths:
		var res := migrate_source(p, str(sources[p]), referenceable)
		if res["changed"]:
			var f := FileAccess.open(p, FileAccess.WRITE)
			if f != null:
				f.store_string(str(res["source"]))
				f.close()
				changed.append(p)
	return { "changed": changed, "scanned": paths.size() }

## Compute the migrated source for one file (no write). `referenceable` = name -> owning path.
static func migrate_source(guitkx_path: String, src: String, referenceable: Dictionary) -> Dictionary:
	var decls := Compiler._enumerate_decls(src, 0)
	if decls.is_empty():
		return { "changed": false, "source": src }
	var own := {}
	for dm in decls:
		own[str(dm["name"])] = true
	# 1. Which OTHER files' names does this file reference?  target path -> sorted [names]
	# (the SAME canonical scan strict resolution uses, so the migrated tree is 2305-free by construction)
	var used := Resolve.referenced_names(src, referenceable, own)
	var already := {}
	for im in Compiler.scan_imports(src):
		for nm in (im["names"] as Array):
			already[str(nm["name"])] = true
	var by_file := {}
	for name in used:
		if already.has(name):
			continue   # idempotent: don't re-import an already-imported name
		var tp := str(referenceable[name])
		if not by_file.has(tp):
			by_file[tp] = []
		(by_file[tp] as Array).append(name)
	# 2. Build the new import lines (names sorted, targets sorted by specifier).
	var root := Config.root_for(guitkx_path)
	var import_lines: Array = []
	var specs := by_file.keys()
	specs.sort()
	for tp in specs:
		var names: Array = by_file[tp]
		names.sort()
		import_lines.append("import { %s } from \"%s\"" % [", ".join(names), _specifier(guitkx_path, str(tp), root)])
	import_lines.sort()
	# 3. Prefix `export ` on every not-yet-exported top-level decl (reverse order: offsets stay valid).
	var out := src
	for di in range(decls.size() - 1, -1, -1):
		var dm: Dictionary = decls[di]
		if not bool(dm["export"]):
			var at := int(dm["at"])   # the decl keyword (start == at when unexported)
			out = out.substr(0, at) + "export " + out.substr(at)
	# 4. Insert the import block at the first decl's start (after any @directives, before the decl).
	if not import_lines.is_empty():
		# Insert at the first decl's START (the `export` prefix when present, else the keyword), NOT its
		# keyword `at`. For an unexported decl start==at; for an ALREADY-exported first decl `at` points
		# PAST the existing `export `, so inserting there would split `export … component` into
		# `export import { … } … component` -- invalid + non-idempotent (BH-03). `start` is correct for
		# both, and step 3's reverse-order export insertions never move an earlier decl's start.
		var insert_at := int(decls[0]["start"])
		var block := "\n".join(import_lines) + "\n\n"
		out = out.substr(0, insert_at) + block + out.substr(insert_at)
	return { "changed": out != src, "source": out }

## Referenceable names actually USED in `src` (markup tag `<Name`, or qualified `Name.` / `Name(`),
## excluding this file's own decls. Lexer-aware: strings/comments are skipped.
static func _scan_references(src: String, referenceable: Dictionary, own: Dictionary) -> Dictionary:
	var out := {}
	var i := 0
	var n := src.length()
	while i < n:
		var k := L.skip_noncode(src, i)
		if k != i:
			i = k
			continue
		var c := src.unicode_at(i)
		if L._is_ident_code(c) and (c < 48 or c > 57) and (i == 0 or not L._is_ident_code(src.unicode_at(i - 1))):
			var s := i
			while i < n and L._is_ident_code(src.unicode_at(i)):
				i += 1
			var word := src.substr(s, i - s)
			if referenceable.has(word) and not own.has(word):
				var prev_lt := s > 0 and src[s - 1] == "<"
				var nxt := _next_nonspace(src, i)
				if prev_lt or nxt == "." or nxt == "(":
					out[word] = true
			continue
		i += 1
	return out

static func _next_nonspace(src: String, i: int) -> String:
	var n := src.length()
	while i < n and (src[i] == " " or src[i] == "\t"):
		i += 1
	return src[i] if i < n else ""

## The import specifier from `guitkx_path` to `target`: `./name` when siblings, else `~/`-rooted
## (root-relative, extensionless).
## Delegate to the compiler's CANONICAL specifier rule so the codemod can never write a specifier the
## resolver would resolve differently (or fail to resolve) -- the BH-13 path-boundary bug and the
## BH-14 out-of-root mis-rooting both lived in the old copy here.
static func _specifier(guitkx_path: String, target: String, root: String) -> String:
	return Compiler.import_specifier(guitkx_path, target, root)

static func _find_guitkx(root: String) -> Array:
	var out: Array = []
	_walk(root, out)
	out.sort()
	return out

static func _walk(dir: String, out: Array) -> void:
	if FileAccess.file_exists(dir.path_join(".gdignore")):
		return
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name != "." and name != "..":
			var p := dir.path_join(name)
			if d.current_is_dir():
				if not (name.begins_with(".") or name == "node_modules" or name.ends_with("~")):
					_walk(p, out)
			elif name.get_extension() == "guitkx":
				out.append(p)
		name = d.get_next()
	d.list_dir_end()
