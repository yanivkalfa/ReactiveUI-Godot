class_name RUIHmr
extends RefCounted
## Runtime Fast Refresh (Phase H): applies editor-pushed script reloads to the RUNNING game.
##
## The reactive_ui EditorPlugin's watcher compiles `.guitkx` -> sibling `.gd` on save and pushes
## the changed paths into this game over the debugger channel (`rui_hmr:reload`, see
## editor/hmr_debugger.gd). We reload each script IN PLACE -- `source_code` + `reload(true)` on
## the SAME GDScript resource -- so method-reference Callables (`DemoBox.render`) keep their
## identity AND dispatch the new code (H0 spike + godot#85704). Fiber matching is Callable
## equality, so hook state survives for free; the only thing a reload cannot do by itself is
## defeat the reconciler's bailout cache -- RUIReconciler.hmr_refresh_all does that.
##
## Semantics (Unity RefreshRuntime parity):
##   - component script changed        -> targeted: only its fibers re-render (state preserved)
##   - hook/module script changed      -> global: every function fiber re-renders (any component
##                                        may call it -- Unity's TriggerGlobalReRender)
##   - hook SIGNATURE changed (__RUI_HOOK_SIG const, emitted by the compiler since 0.8.0)
##                                     -> that component's state is deliberately RESET
##   - reload failure / empty read     -> per-file isolation: keep old code, report, continue
##
## Inert outside editor runs: registration is gated on EngineDebugger.is_active(), and the
## editor only pushes when a debugger session is attached. Exported builds never see any of it.

static var _registered := false

## Called from RUIReconciler._init (the first mounted root arms HMR). Safe to call repeatedly.
static func ensure_registered() -> void:
	if _registered or not EngineDebugger.is_active():
		return
	_registered = true
	EngineDebugger.register_message_capture("rui_hmr", Callable(RUIHmr, "_on_message"))

## Debugger-channel entry. Messages arrive WITHOUT the "rui_hmr:" prefix. Returning true marks
## the message as handled. The whole reload+re-render pass runs synchronously INSIDE this
## callback: no frame boundary between the script swap and the commit, so live signal handlers
## minted by the old code can never fire in a half-swapped world.
static func _on_message(message: String, data: Array) -> bool:
	if message != "reload":
		return false
	var t0 := Time.get_ticks_msec()
	var res := apply((data[0] as Array) if data.size() > 0 and data[0] is Array else [])
	res["ms"] = Time.get_ticks_msec() - t0
	EngineDebugger.send_message("rui_hmr:status", [res])
	return true

## Reload the given generated .gd paths in place and refresh mounted trees.
## Pure engine + reconciler work -- headless-testable without any debugger session.
## Returns { reloaded:int, reset:int, refreshed:int, global:bool, errors:Array[String] }.
static func apply(paths: Array) -> Dictionary:
	var changed: Array = []   # GDScript resources reloaded in place
	var resets: Array = []    # subset whose hook signature changed -> deliberate state reset
	var errors: Array = []
	var global_rerender := false
	for p in paths:
		var path := str(p)
		if not ResourceLoader.has_cached(path):
			continue   # never loaded by this game -- the next load() reads the new file anyway
		var scr = load(path)
		if not (scr is GDScript):
			continue
		var src := FileAccess.get_file_as_string(path)
		if src.is_empty():
			# The editor may still be mid-write; the next sweep pushes this path again.
			errors.append("%s: source read came back empty -- kept the old code" % path)
			continue
		if src == (scr as GDScript).source_code:
			continue   # byte-identical (e.g. a forced sweep re-wrote it) -- nothing to swap
		var old_sig := _hook_sig(scr)
		(scr as GDScript).source_code = src
		var err: int = (scr as GDScript).reload(true)
		if err != OK:
			# The editor gd_parse_ok-gates what it pushes, so this is rare (disk race / manual
			# edit). Isolate: report and continue with the other files.
			errors.append("%s: in-place reload failed (err %d) -- fix the file and save again" % [path, err])
			continue
		changed.append(scr)
		if _is_module(scr):
			global_rerender = true
		elif _hook_sig(scr) != old_sig:
			resets.append(scr)
	var refreshed := 0
	if not changed.is_empty():
		refreshed = RUIReconciler.hmr_refresh_all(changed, resets, global_rerender)
	return {
		"reloaded": changed.size(), "reset": resets.size(), "refreshed": refreshed,
		"global": global_rerender, "errors": errors,
	}

## The compile-time hook-call fingerprint the guitkx compiler embeds (H4). Read as a script
## CONSTANT -- introspectable without instancing or static dispatch. Absent (hand-written
## component, pre-0.8 output) = "" on both sides of the compare -> never resets.
static func _hook_sig(scr: GDScript) -> String:
	return str(scr.get_script_constant_map().get("__RUI_HOOK_SIG", ""))

## A generated COMPONENT carries `static func render(`; a generated hooks/module file does not.
## Source-text check on purpose: bulletproof for our own generated output, no reflection edge
## cases with static methods.
static func _is_module(scr: GDScript) -> bool:
	return not (scr as GDScript).source_code.contains("static func render(")
