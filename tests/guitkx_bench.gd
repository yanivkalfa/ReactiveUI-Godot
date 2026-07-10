extends SceneTree
## G-10 measurement harness: times the compiler stack over the largest real component
## (doom_game_screen.guitkx). Not pass/fail -- run before/after scanner work and compare.
## Record (this machine, headless, Godot 4.7, 12.4 KB source):
##   pre-G-10 baseline:          compile 71.96 ms | skip_noncode walk 4.58 ms | fmm 6.33 ms
##   lexer unicode_at (stage 1): compile 59.27 ms | walk 2.62 ms (-43%)       | fmm 4.04 ms (-36%)
##   + markup loops + G-08:      compile ~58 ms   | walk ~2.65 ms             | (fmm micro is GC-noisy)
## Remaining per the G-10 recipe: guitkx.gd hot scanners + the editor tokenizer/highlighter.
func _initialize():
	var src := FileAccess.get_file_as_string("res://examples/demos/doom/doom_game_screen.guitkx")
	if src == "":
		print("no source"); quit(1); return
	var kb := src.length() / 1024.0
	# Warm-up
	for w in range(3):
		RUIGuitkx.compile(src, "DoomGameScreen")
	# Macro: full compile (per-save cost)
	var n := 30
	var t0 := Time.get_ticks_usec()
	for k in range(n):
		RUIGuitkx.compile(src, "DoomGameScreen")
	var compile_ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
	# Micro: skip_noncode walk over the whole file (the shared primitive every matcher calls)
	var reps := 200
	t0 = Time.get_ticks_usec()
	var acc := 0
	for r in range(reps):
		var i := 0
		var L := src.length()
		while i < L:
			var j: int = RUIGuitkxLexer.skip_noncode(src, i)
			if j != i: i = j
			else: i += 1
			acc += 1
	var walk_ms := (Time.get_ticks_usec() - t0) / 1000.0 / reps
	# Micro 2: find_matching_markup on the component body (the G-23 matcher)
	var body_open := src.find("{", src.find("component "))
	t0 = Time.get_ticks_usec()
	for r in range(reps):
		RUIGuitkxLexer.find_matching_markup(src, body_open)
	var fmm_ms := (Time.get_ticks_usec() - t0) / 1000.0 / reps
	print("file %.1f KB | compile %.2f ms (%.3f ms/KB) | skip_noncode walk %.3f ms | find_matching_markup %.3f ms" % [
		kb, compile_ms, compile_ms / kb, walk_ms, fmm_ms])
	quit(0)
