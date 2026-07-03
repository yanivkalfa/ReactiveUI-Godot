@tool
extends EditorPlugin
## The library is plain GDScript exposing global `class_name`s (V, Hooks, ReactiveRoot, ...), so
## it is usable as soon as the files exist -- enabling this plugin is optional for the RUNTIME.
## The plugin's job is the .guitkx toolchain: it watches the project filesystem and compiles each
## `Foo.guitkx` to a sibling `Foo.gd` (see RUIGuitkxCodegen). On compile it nudges the editor's
## EditorFileSystem so the generated script is picked up and hot-reloaded.
##
## RECOMPILE TRIGGERS (why more than filesystem_changed):
##   `.guitkx` is not a Godot-recognised resource type, so editing ONLY a `.guitkx` in an external
##   editor (VS Code) does not reliably flip EditorFileSystem's "changed" flag -> `filesystem_changed`
##   may not fire when you tab back, so the file never recompiled until a full editor restart. We ALSO
##   recompile on editor FOCUS-IN (NOTIFICATION_APPLICATION_FOCUS_IN): every time you return to Godot
##   from your editor, stale `.guitkx` are recompiled. is_stale() (mtime) keeps this cheap when nothing
##   changed. Diagnostics are DE-DUPLICATED (see _report): Godot's Errors dock is append-only (no engine
##   API clears it), so without dedup a persistently-broken file -- which stays stale and recompiles on
##   every focus-in -- would spam the dock with identical errors. We push each distinct error once and
##   print a green "resolved" line when a file starts compiling clean again.

const Codegen = preload("res://addons/reactive_ui/guitkx/guitkx_codegen.gd")
const Diag = preload("res://addons/reactive_ui/guitkx/guitkx_diag.gd")

var _efs: EditorFileSystem
var _busy := false
# path -> the joined diagnostic string last reported for it, so we push_error/push_warning only when a
# file's diagnostics actually CHANGE (Godot's dock never clears; re-pushing on every focus-in = spam).
var _last_diags: Dictionary = {}
# Compiler-environment retry: when a sweep returns HELD files (vocabulary unreadable — the editor's
# first-scan window), "retrying on the next compile" must not wait for a user edit or focus change,
# or a cold open stays uncompiled until someone touches a file (field capture 2026-07-03: 3.5 hours).
# One pending timer at a time; retries are cheap (a held sweep attempts one read per file and stops),
# announced once per episode, and end the moment a sweep runs unheld.
const _ENV_RETRY_SECS := 2.0
var _env_retry_pending := false
var _env_retry_announced := false

func _enter_tree() -> void:
	_efs = EditorInterface.get_resource_filesystem()
	_compile_all()
	if _efs and not _efs.filesystem_changed.is_connected(_on_fs_changed):
		_efs.filesystem_changed.connect(_on_fs_changed)

func _exit_tree() -> void:
	if _efs and _efs.filesystem_changed.is_connected(_on_fs_changed):
		_efs.filesystem_changed.disconnect(_on_fs_changed)
	_efs = null

func _notification(what: int) -> void:
	# Tab back into the Godot editor -> recompile any changed .guitkx. This is the reliable trigger:
	# it does not depend on Godot deciding a `.guitkx`-only edit counts as a filesystem change.
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_compile_all()

func _on_fs_changed() -> void:
	# The mtime staleness guard makes this self-terminating: writing a .gd makes it newer than its
	# .guitkx, so the next filesystem_changed finds nothing stale and stops. _busy guards re-entry.
	_compile_all()

func _compile_all() -> void:
	if _efs == null or _busy:
		return
	_busy = true
	var res: Dictionary = Codegen.compile_all("res://")
	for entry in res["compiled"]:
		_efs.update_file(entry["gd_path"])
		# A file that previously errored now compiles clean -> announce it and forget its stale errors
		# (we can't wipe the dock, but a clear "resolved" line tells the user the fix landed).
		if _last_diags.has(entry["path"]):
			print_rich("[color=green][guitkx] %s: compile errors resolved.[/color]" % entry["path"])
			_last_diags.erase(entry["path"])
		print("[guitkx] compiled -> ", entry["gd_path"])
		_report_warnings(entry["path"], entry["warnings"])
	for e in res["errors"]:
		_report_error(e)
	# HELD files (compiler environment not ready) are NOT errors: no per-file dock line — the
	# loader's one-per-episode hold warning already announced it — just a scheduled retry so the
	# sweep re-runs by itself once the environment recovers.
	var held: Array = res.get("held", [])
	if held.is_empty():
		_env_retry_announced = false
	else:
		_schedule_env_retry(held.size())
	_busy = false

# One-shot deferred re-sweep while compiles are held. Bound method (not a lambda): if the plugin
# is freed before the timer fires, Godot drops the connection with the object.
func _schedule_env_retry(count: int) -> void:
	if _env_retry_pending:
		return
	_env_retry_pending = true
	if not _env_retry_announced:
		_env_retry_announced = true
		print("[guitkx] %d file(s) waiting for the compiler environment -- retrying every %.0fs until it recovers" % [count, _ENV_RETRY_SECS])
	get_tree().create_timer(_ENV_RETRY_SECS).timeout.connect(_on_env_retry_timeout)

func _on_env_retry_timeout() -> void:
	_env_retry_pending = false
	_compile_all()

# push_error only when THIS file's error set differs from what we last reported for it.
# One dock line PER diagnostic, "path:LINE:COL: CODE: message" (1-based, from the offsets the
# compiler threads through every diagnostic since T0.2) -- not a joined array string.
func _report_error(e: Dictionary) -> void:
	var path: String = e["path"]
	var lines := _diag_lines(path, e.get("diagnostics", []))
	if lines.is_empty():
		lines = ["%s: %s" % [path, str(e.get("error", "?"))]]
	var body := "\n".join(lines)
	if _last_diags.get(path, "") == "E:" + body:
		return
	_last_diags[path] = "E:" + body
	for ln in lines:
		push_error("[guitkx] " + ln)

func _report_warnings(path: String, warnings: Array) -> void:
	for ln in _diag_lines(path, warnings):
		push_warning("[guitkx] " + ln)

# Render structured diagnostics to per-line dock strings; line/col were derived at the codegen
# surface boundary (compile_file), so no source re-read is needed here.
func _diag_lines(path: String, diags: Array) -> Array:
	var out: Array = []
	for d in diags:
		if d is Dictionary and (d as Dictionary).has("code"):
			var dd := d as Dictionary
			var loc := ""
			if dd.has("line"):
				loc = "%d:%d: " % [int(dd["line"]) + 1, int(dd.get("col", 0)) + 1]
			var sev := int(dd.get("severity", Diag.ERROR))
			var sev_tag := "" if sev == Diag.ERROR else " (%s)" % Diag.severity_name(sev)
			out.append("%s:%s%s%s: %s" % [path, loc, dd.get("code", ""), sev_tag, dd.get("message", "")])
		else:
			out.append("%s: %s" % [path, str(d)])
	return out
