@tool
extends EditorDebuggerPlugin
## Editor side of runtime Fast Refresh (Phase H). plugin.gd registers one instance via
## add_debugger_plugin; after every sweep that compiled files it calls push_reload with the
## generated .gd paths, and we forward them to every RUNNING game session over the debugger
## protocol ("rui_hmr:reload"). The game side (core/hmr.gd) reloads the scripts in place,
## re-renders the affected components, and replies on "rui_hmr:status", which we print into
## the editor Output right next to the sweep lines -- the full save->screen loop is visible
## in one place.
##
## No session (nothing running, or run-without-debugger)? push_reload is a no-op. Godot's own
## "Synchronize Script Changes" can never do this job: it only fires for saves made in the
## built-in script editor, and every .gd in this pipeline is written by the compiler
## (godot#72825) -- hence this channel.

## Push freshly-compiled generated .gd paths into every live play session. `bindings` is the
## project's full class -> generated-.gd map: the game uses it to hot-LINK components whose
## global class_name was created after launch (unresolvable by name until the next run).
func push_reload(gd_paths: Array, bindings: Dictionary = {}) -> void:
	if gd_paths.is_empty():
		return
	var pushed := 0
	for s in get_sessions():
		var session := s as EditorDebuggerSession
		if session != null and session.is_active():
			session.send_message("rui_hmr:reload", [gd_paths, bindings])
			pushed += 1
	# ALWAYS say what happened -- "-> 0 session(s)" means no debugger-attached game was running
	# (not launched via F5, or already closed), which is otherwise indistinguishable from a
	# push that vanished (field capture 2026-07-04: a silent log hid exactly this question).
	print("[guitkx] hmr push: %d script(s) -> %d session(s)" % [gd_paths.size(), pushed])

func _has_capture(capture: String) -> bool:
	return capture == "rui_hmr"

## The game's post-reload report. Engine versions differ on whether the prefix is stripped for
## editor-side captures, so accept both spellings.
func _capture(message: String, data: Array, _session_id: int) -> bool:
	if message != "status" and message != "rui_hmr:status":
		return false
	var d: Dictionary = data[0] if (data.size() > 0 and data[0] is Dictionary) else {}
	var errs: Array = d.get("errors", [])
	if int(d.get("reloaded", 0)) > 0:
		var line := "[guitkx] hot-reloaded %d script(s) -> %d component(s) re-rendered in %d ms" % [
			int(d.get("reloaded", 0)), int(d.get("refreshed", 0)), int(d.get("ms", 0))]
		if int(d.get("reset", 0)) > 0:
			line += " (%d state reset: hook shape changed)" % int(d.get("reset", 0))
		if int(d.get("linked", 0)) > 0:
			line += " (%d new component(s) linked live)" % int(d.get("linked", 0))
		if bool(d.get("global", false)):
			line += " (global re-render: a hooks module changed)"
		print_rich("[color=cyan]%s[/color]" % line)
	for e in errs:
		push_warning("[guitkx] hmr: %s" % str(e))
	return true
