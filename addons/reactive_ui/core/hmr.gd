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
	if message != "reload" and message != "rui_hmr:reload":   # engine versions differ on prefix stripping
		return false
	var t0 := Time.get_ticks_msec()
	var paths: Array = (data[0] as Array) if data.size() > 0 and data[0] is Array else []
	var bindings: Dictionary = (data[1] as Dictionary) if data.size() > 1 and data[1] is Dictionary else {}
	# Ack BEFORE doing anything: its presence in the editor Output proves delivery + capture,
	# so a crash inside apply() can never masquerade as "the message never arrived".
	EngineDebugger.send_message("rui_hmr:ack", [paths.size()])
	var res := apply(paths, bindings)
	res["ms"] = Time.get_ticks_msec() - t0
	EngineDebugger.send_message("rui_hmr:status", [res])
	return true

## Reload the given generated .gd paths in place and refresh mounted trees. `bindings` is the
## project's class->generated-.gd map (from the sweep) used to hot-LINK brand-new components.
## Pure engine + reconciler work -- headless-testable without any debugger session.
## Returns { reloaded:int, reset:int, refreshed:int, linked:int, global:bool, errors:Array[String] }.
static func apply(paths: Array, bindings: Dictionary = {}) -> Dictionary:
	var changed: Array = []   # GDScript resources reloaded in place
	var resets: Array = []    # subset whose hook signature changed -> deliberate state reset
	var errors: Array = []
	var outcomes := {}        # path -> what happened (the editor prints this when nothing reloads)
	var linked := 0           # reloads that succeeded via new-component const injection
	var global_rerender := false
	for p in paths:
		var path := str(p)
		if not ResourceLoader.has_cached(path):
			outcomes[path] = "uncached"   # never loaded by this game -- next load() reads the new file
			continue
		var scr = load(path)
		if not (scr is GDScript):
			outcomes[path] = "not-a-script"
			continue
		var src := FileAccess.get_file_as_string(path)
		if src.is_empty():
			# The editor may still be mid-write; the next sweep pushes this path again.
			outcomes[path] = "empty-read"
			errors.append("%s: source read came back empty -- kept the old code" % path)
			continue
		if src == (scr as GDScript).source_code:
			outcomes[path] = "identical"   # e.g. a forced sweep re-wrote the same bytes
			continue
		var old_sig := _hook_sig(scr)
		(scr as GDScript).source_code = src
		var err: int = (scr as GDScript).reload(true)
		if err != OK:
			# The editor gd_parse_ok-gates what it pushes, so a failure here almost always means
			# the file references a GLOBAL CLASS this game has never seen -- Godot registers
			# class_names at LAUNCH, so a component created after F5 is unresolvable by name.
			# Retry with `const X = preload(path)` spliced in for every unregistered binding the
			# source mentions: a local const resolves exactly like the global would, the new
			# script loads fresh from disk, and the session (with all its state) survives.
			var patched := _inject_unregistered_bindings(src, bindings)
			if patched != src:
				(scr as GDScript).source_code = patched
				err = (scr as GDScript).reload(true)
				if err == OK:
					linked += 1
					outcomes[path] = "linked"
			if err != OK:
				(scr as GDScript).source_code = src   # leave the honest disk bytes in memory
				outcomes[path] = "failed err %d" % err
				errors.append("%s: in-place reload failed (err %d) -- fix the file and save again (or restart the run if it references classes from outside the guitkx pipeline)" % [path, err])
				continue
		else:
			outcomes[path] = "reloaded"
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
		"linked": linked, "global": global_rerender, "errors": errors, "outcomes": outcomes,
	}

## `const X = preload("<path>")` lines for every pushed binding that (a) this game does NOT
## know as a global class (launch-frozen map), (b) the source actually mentions, and (c) is not
## the file's OWN class (self-preload would cycle). Spliced right after the `extends` line.
## After the next restart the globals register and this returns the source untouched.
static func _inject_unregistered_bindings(src: String, bindings: Dictionary) -> String:
	if bindings.is_empty():
		return src
	var globals := {}
	for gc in ProjectSettings.get_global_class_list():
		globals[str(gc.get("class", ""))] = true
	var consts := ""
	for cls in bindings:
		var cname := str(cls)
		if globals.has(cname) or not src.contains(cname) or src.contains("class_name " + cname):
			continue
		consts += "const %s = preload(\"%s\")\n" % [cname, str(bindings[cls])]
	if consts == "":
		return src
	# `const` must come AFTER the extends header (class_name/extends lead the file).
	var ext_at := -1
	if src.begins_with("extends "):
		ext_at = 0
	else:
		var nl := src.find("\nextends ")
		if nl != -1:
			ext_at = nl + 1
	if ext_at == -1:
		return consts + src   # headerless script -- consts may lead
	var line_end := src.find("\n", ext_at)
	if line_end == -1:
		return src
	return src.substr(0, line_end + 1) + consts + src.substr(line_end + 1)

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
