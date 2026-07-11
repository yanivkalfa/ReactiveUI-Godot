@tool
class_name GuitkxWorkspace
extends RefCounted
## Project-wide index of user `.guitkx` components: tag name -> declaring file + offset. Powers
## user-component tag completion (`<MyComp`) and go-to-definition. Port of the markup half of
## ide-extensions/lsp-server/src/workspaceIndex.ts (declaration scan only; no embedded analysis).
## [Phase 1 -- plans/GODOT_ANALYZER_INTEGRATION_PLAN.md §7]

# tag name (the referenceable identity: @class_name override, else the declaration name) ->
#   { path:String, offset:int, name:String, kind:String }
static var _index: Dictionary = {}
static var _paths: Array = []   # every .guitkx seen by the scan (incl. hook-only files w/o tags)
static var _scanned := false

static var _decl_re: RegEx = null
static var _cn_re: RegEx = null

static func _res() -> void:
	if _decl_re == null:
		_decl_re = RegEx.new()
		# `(?:export[ \t]+)?` — a top-level declaration may carry an `export` visibility prefix (0.10.0
		# imports leg); the prefix is non-capturing so groups stay 1=kind, 2=name.
		_decl_re.compile("(?m)^[ \\t]*(?:export[ \\t]+)?(component|hook|module)[ \\t]+([A-Za-z_][A-Za-z0-9_]*)")
	if _cn_re == null:
		_cn_re = RegEx.new()
		_cn_re.compile("(?m)^[ \\t]*@class_name[ \\t]+([A-Za-z_][A-Za-z0-9_]*)")

## Scan the whole project once (idempotent). Call again via rescan() to force a refresh.
static func ensure_scanned() -> void:
	if _scanned:
		return
	_scanned = true
	_res()
	_paths = _collect_guitkx("res://")
	for path in _paths:
		var text := FileAccess.get_file_as_string(path)
		if text != "":
			_index_source(path, text)

static func rescan() -> void:
	_scanned = false
	_index.clear()
	_paths.clear()
	ensure_scanned()

## Re-index a single file (call on save so completion stays fresh without a full rescan).
static func reindex(path: String, text: String) -> void:
	_res()
	# drop stale entries pointing at this path, then re-add
	for tag in _index.keys():
		if (_index[tag] as Dictionary).get("path", "") == path:
			_index.erase(tag)
	_index_source(path, text)
	if not _paths.has(path):
		_paths.append(path)
	_scanned = true

## Every .guitkx in the project (the last scan's file list, kept fresh by reindex/rescan).
## Feeds RUIGuitkxCodegen.project_bindings() for the editor's cross-file diagnostics.
static func all_paths() -> Array:
	ensure_scanned()
	return _paths

## All indexed user-component tag names (PascalCase identities), sorted.
static func component_tags() -> Array:
	ensure_scanned()
	var keys := _index.keys()
	keys.sort()
	return keys

static func is_component(tag: String) -> bool:
	ensure_scanned()
	return _index.has(tag)

## { path, offset, name, kind } for a tag, or {} if unknown.
static func lookup(tag: String) -> Dictionary:
	ensure_scanned()
	return _index.get(tag, {})

# --- internals ---------------------------------------------------------------------------------

static func _index_source(path: String, text: String) -> void:
	# @class_name override (preamble) gives the primary component its referenceable identity.
	var override := ""
	var override_off := -1
	var cn := _cn_re.search(text)
	if cn != null:
		override = cn.get_string(1)
		override_off = cn.get_start(1)
	var first := true
	for m in _decl_re.search_all(text):
		var kind := m.get_string(1)
		var name := m.get_string(2)
		var name_off := m.get_start(2)
		if kind == "hook":
			first = false
			continue  # hooks are not tags
		var tag := name
		var off := name_off
		if first and override != "":
			tag = override
			off = override_off
		first = false
		_index[tag] = { "path": path, "offset": off, "name": name, "kind": kind }

static func _collect_guitkx(root: String) -> Array:
	var out: Array = []
	# Honor `.gdignore`, exactly like the watcher's codegen walk — tests/contract/fixtures (and any
	# user-ignored folder) contains deliberately-broken/duplicate declarations that must never
	# reach the component index, hover, goto-def, or the known-components universe. [field capture:
	# hover resolved <DemoBox> to the contract FIXTURE copy]
	if FileAccess.file_exists(root.path_join(".gdignore")):
		return out
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full := root.path_join(entry)
			if dir.current_is_dir():
				# Skip engine/vcs/node dirs and Godot-ignored (~-suffixed) folders.
				if not (entry.begins_with(".") or entry == "node_modules" or entry.ends_with("~")):
					out.append_array(_collect_guitkx(full))
			elif entry.get_extension() == "guitkx":
				out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return out
