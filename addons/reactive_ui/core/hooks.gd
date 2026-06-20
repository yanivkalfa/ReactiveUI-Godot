class_name Hooks
extends RefCounted
## React-style hooks over the fiber reconciler. State lives in the current fiber's
## RUIComponentState; a static pointer (`_cur`) is set around each component render by
## the reconciler via `_begin`/`_end`.
##
## RULES OF HOOKS: call hooks only at the top level of a render function — never in
## `if`/loops/nested lambdas. The positional-slot model relies on a stable call order.
##
## Ported from ReactiveUIToolKit's Hooks. Storage model: a positional array of slots
## plus separate cursors for state-hooks, passive effects, and layout effects; context
## reads are kept OUT of the slot array (so use_context can't perturb hook order).

static var _cur: RUIComponentState = null

# --------------------------------------------------------------------------
# Render-phase plumbing (called by the reconciler only)
# --------------------------------------------------------------------------

static func _begin(state: RUIComponentState) -> void:
	_cur = state
	state.hook_index = 0
	state.effect_index = 0
	state.layout_index = 0
	state.context_deps = []
	state.is_rendering = true

static func _end() -> void:
	if _cur != null:
		_cur.is_rendering = false
	_cur = null

# --------------------------------------------------------------------------
# State
# --------------------------------------------------------------------------

## use_state(initial) -> [value, setter]. `setter` accepts a value OR an updater
## Callable `(old) -> new`. Setter identity is stable across renders; setting an equal
## value bails out (no re-render).
static func use_state(initial = null) -> Array:
	var s := _cur
	var i := s.hook_index
	s.hook_index += 1
	if i >= s.hooks.size():
		s.hooks.append({ "kind": "state", "value": initial, "setter": _make_setter(s, i) })
	var slot: Dictionary = s.hooks[i]
	return [slot["value"], slot["setter"]]

static func _make_setter(state: RUIComponentState, i: int) -> Callable:
	return func(update):
		if i >= state.hooks.size():   # state torn down (unmounted) — ignore late calls [audit C3]
			return
		var slot: Dictionary = state.hooks[i]
		var prev = slot["value"]
		var next = update.call(prev) if (update is Callable) else update
		if _equal(prev, next):
			return
		slot["value"] = next
		if state.on_state_updated.is_valid():
			state.on_state_updated.call()

## use_reducer(reducer, initial) -> [state, dispatch]. `reducer(state, action)->state`.
## `dispatch` identity is stable; the reducer closure is refreshed every render.
static func use_reducer(reducer: Callable, initial = null) -> Array:
	var s := _cur
	var i := s.hook_index
	s.hook_index += 1
	if i >= s.hooks.size():
		var slot := { "kind": "reducer", "value": initial, "reducer": reducer }
		slot["dispatch"] = _make_dispatch(s, i)
		s.hooks.append(slot)
	else:
		s.hooks[i]["reducer"] = reducer
	var slot2: Dictionary = s.hooks[i]
	return [slot2["value"], slot2["dispatch"]]

static func _make_dispatch(state: RUIComponentState, i: int) -> Callable:
	return func(action):
		if i >= state.hooks.size():
			return
		var slot: Dictionary = state.hooks[i]
		var prev = slot["value"]
		var next = slot["reducer"].call(prev, action)
		if _equal(prev, next):
			return
		slot["value"] = next
		if state.on_state_updated.is_valid():
			state.on_state_updated.call()

# --------------------------------------------------------------------------
# Refs / memo / callbacks
# --------------------------------------------------------------------------

## use_ref(initial) -> { "current": initial }  (stable box; never re-created; mutating
## `.current` does NOT trigger a re-render).
static func use_ref(initial = null) -> Dictionary:
	var s := _cur
	var i := s.hook_index
	s.hook_index += 1
	if i >= s.hooks.size():
		s.hooks.append({ "kind": "ref", "box": { "current": initial } })
	return s.hooks[i]["box"]

## use_memo(factory, deps) -> cached value, recomputed only when deps change (shallow).
static func use_memo(factory: Callable, deps: Array = []) -> Variant:
	var s := _cur
	var i := s.hook_index
	s.hook_index += 1
	if i >= s.hooks.size():
		var v = factory.call()
		s.hooks.append({ "kind": "memo", "value": v, "deps": deps.duplicate() })
		return v
	var slot: Dictionary = s.hooks[i]
	if _deps_changed(slot["deps"], deps):
		slot["value"] = factory.call()
		slot["deps"] = deps.duplicate()
	return slot["value"]

## use_callback(cb, deps) -> a stable Callable while deps are unchanged.
static func use_callback(cb: Callable, deps: Array = []) -> Callable:
	return use_memo(func(): return cb, deps)

## use_imperative_handle(factory, deps) -> handle, recomputed only when deps change.
static func use_imperative_handle(factory: Callable, deps: Array = []) -> Variant:
	return use_memo(factory, deps)

# --------------------------------------------------------------------------
# Effects (recorded during render, run during commit)
# --------------------------------------------------------------------------

## use_effect(effect, deps): passive effect, runs AFTER commit (two-pass: all cleanups
## then all setups). `deps == null` => every commit; `[]` => once on mount; `[a,b]` =>
## when a dep changes. `effect()` may return a Callable cleanup.
static func use_effect(effect: Callable, deps = null) -> void:
	var s := _cur
	var i := s.effect_index
	s.effect_index += 1
	if i >= s.effects.size():
		s.effects.append({ "factory": effect, "deps": deps, "last_deps": null, "cleanup": null })
	else:
		s.effects[i]["factory"] = effect
		s.effects[i]["deps"] = deps

## use_layout_effect(effect, deps): runs SYNCHRONOUSLY during commit (pre-paint),
## cleanup-then-setup per fiber. Same dep semantics as use_effect.
static func use_layout_effect(effect: Callable, deps = null) -> void:
	var s := _cur
	var i := s.layout_index
	s.layout_index += 1
	if i >= s.layout_effects.size():
		s.layout_effects.append({ "factory": effect, "deps": deps, "last_deps": null, "cleanup": null })
	else:
		s.layout_effects[i]["factory"] = effect
		s.layout_effects[i]["deps"] = deps

# --------------------------------------------------------------------------
# Context
# --------------------------------------------------------------------------

## use_context(key) -> nearest provided value (walking up the fiber tree), or null.
## Does NOT consume a hook slot. Records the read so context changes can re-render.
static func use_context(key: String):
	var s := _cur
	var fiber: RUIFiber = s.fiber
	fiber.reads_context = true
	var val = _resolve_context(fiber, key)
	s.context_deps.append({ "key": key, "value": val })
	return val

static func _resolve_context(fiber: RUIFiber, key: String):
	var f := fiber
	while f != null:
		if f.provided_context != null and f.provided_context.has(key):
			return f.provided_context[key]
		f = f.parent
	return null

## provide_context(key, value): expose `value` under `key` to this fiber's subtree.
## On change, marks consuming descendants dirty so they re-render even through bailouts.
static func provide_context(key: String, value) -> void:
	var fiber: RUIFiber = _cur.fiber
	if fiber.provided_context == null:
		fiber.provided_context = {}
	var changed := true
	var alt := fiber.alternate
	if alt != null and alt.provided_context != null and alt.provided_context.has(key):
		changed = not _equal(alt.provided_context[key], value)
	fiber.provided_context[key] = value
	if changed and alt != null and alt.child != null:
		_propagate_context_change(key, alt.child)

## DFS over the committed subtree marking consumers of `key` dirty. Returns whether
## anything was marked (so intermediate ancestors get subtree_has_updates). Stops at a
## nested provider that shadows the same key.
static func _propagate_context_change(key: String, first: RUIFiber) -> bool:
	var any := false
	var f := first
	while f != null:
		if f.provided_context != null and f.provided_context.has(key):
			f = f.sibling
			continue
		var self_marked := false
		if f.reads_context and f.state != null:
			for dep in f.state.context_deps:
				if dep["key"] == key:
					f.has_pending_update = true
					self_marked = true
					any = true
					break
		if f.child != null:
			var children_marked := _propagate_context_change(key, f.child)
			if children_marked:
				any = true
				if not self_marked:
					f.subtree_has_updates = true
		f = f.sibling
	return any

# --------------------------------------------------------------------------
# Concurrency shims (synchronous renderer — no-ops that still occupy stable slots)
# --------------------------------------------------------------------------

## use_deferred_value(value) -> value (returned immediately; no concurrent deferral).
static func use_deferred_value(value, _deps = null):
	var s := _cur
	var i := s.hook_index
	s.hook_index += 1
	if i >= s.hooks.size():
		s.hooks.append({ "kind": "deferred" })
	return value

## use_transition() -> [is_pending(false), start_transition]. start runs the action now.
static func use_transition() -> Array:
	var s := _cur
	var i := s.hook_index
	s.hook_index += 1
	if i >= s.hooks.size():
		s.hooks.append({ "kind": "transition" })
	var start := func(action: Callable):
		if action.is_valid():
			action.call()
	return [false, start]

# --------------------------------------------------------------------------
# Stable callbacks (stable identity, always invoke the latest closure body)
# --------------------------------------------------------------------------

## use_stable_callback(cb) / use_stable_func(cb): 0-arg, stable identity.
static func use_stable_callback(cb: Callable) -> Callable:
	var s := _cur
	var i := s.hook_index
	s.hook_index += 1
	if i >= s.hooks.size():
		var slot := { "kind": "stable", "cb": cb }
		slot["wrapper"] = func():
			var c: Callable = s.hooks[i]["cb"]
			return c.call() if c.is_valid() else null
		s.hooks.append(slot)
		return s.hooks[i]["wrapper"]
	s.hooks[i]["cb"] = cb
	return s.hooks[i]["wrapper"]

static func use_stable_func(cb: Callable) -> Callable:
	return use_stable_callback(cb)

## use_stable_action(cb): 1-arg, stable identity.
static func use_stable_action(cb: Callable) -> Callable:
	var s := _cur
	var i := s.hook_index
	s.hook_index += 1
	if i >= s.hooks.size():
		var slot := { "kind": "stable", "cb": cb }
		slot["wrapper"] = func(a):
			var c: Callable = s.hooks[i]["cb"]
			return c.call(a) if c.is_valid() else null
		s.hooks.append(slot)
		return s.hooks[i]["wrapper"]
	s.hooks[i]["cb"] = cb
	return s.hooks[i]["wrapper"]

# --------------------------------------------------------------------------
# Platform
# --------------------------------------------------------------------------

## use_safe_area() -> { left, top, right, bottom } device safe-area insets (pixels).
static func use_safe_area() -> Dictionary:
	var s := _cur
	var i := s.hook_index
	s.hook_index += 1
	if i >= s.hooks.size():
		s.hooks.append({ "kind": "safe_area" })
	var rect := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	return {
		"left": rect.position.x,
		"top": rect.position.y,
		"right": maxi(0, screen.x - (rect.position.x + rect.size.x)),
		"bottom": maxi(0, screen.y - (rect.position.y + rect.size.y)),
	}

## use_signal(signal, selector?, comparer?) -> selected value. Subscribes to a RUISignal
## and re-renders when the (optionally selected) value changes. Unsubscribes on unmount.
static func use_signal(sig: RUISignal, selector = null, comparer = null):
	var s := _cur
	var i := s.hook_index
	s.hook_index += 1
	if i >= s.hooks.size():
		var slot := { "kind": "signal", "sig": sig }
		slot["value"] = selector.call(sig.get_value()) if (selector is Callable) else sig.get_value()
		slot["unsub"] = sig.subscribe(_make_signal_sub(s, i, sig, selector, comparer))
		s.hooks.append(slot)
		return slot["value"]
	return s.hooks[i]["value"]

static func _make_signal_sub(state: RUIComponentState, i: int, sig: RUISignal, selector, comparer) -> Callable:
	return func(_v):
		if i >= state.hooks.size():   # unsubscribed/torn down between emit and dispatch [audit C3]
			return
		var slot: Dictionary = state.hooks[i]
		var nv = selector.call(sig.get_value()) if (selector is Callable) else sig.get_value()
		var same: bool = comparer.call(slot["value"], nv) if (comparer is Callable) else slot["value"] == nv
		if not same:
			slot["value"] = nv
			if state.on_state_updated.is_valid():
				state.on_state_updated.call()

## use_tween(ref, property, to, duration, deps): smoothly tweens a mounted node's
## property via Godot's Tween when deps change. `ref` is a use_ref box whose `current`
## is the target node (wire it with the "ref" prop). Kills the tween on change/unmount.
static func use_tween(ref: Dictionary, property: String, to, duration: float, deps: Array = []) -> void:
	var eff := func():
		var node = ref.get("current")
		if node == null or not is_instance_valid(node) or not node.is_inside_tree():
			return func(): pass
		var tw: Tween = node.create_tween()
		tw.tween_property(node, property, to, duration)
		return func():
			if is_instance_valid(tw):
				tw.kill()
	use_effect(eff, deps)

## use_tween_value(from, to, duration, on_update, deps): drives on_update(value) each
## frame as a value interpolates (Tween.tween_method). Animate without re-rendering by
## setting a node property inside on_update.
static func use_tween_value(from, to, duration: float, on_update: Callable, deps: Array = []) -> void:
	var eff := func():
		var loop = Engine.get_main_loop()
		if not (loop is SceneTree):
			return func(): pass
		var tw: Tween = loop.create_tween()
		tw.tween_method(on_update, from, to, duration)
		return func():
			if is_instance_valid(tw):
				tw.kill()
	use_effect(eff, deps)

# use_sfx / use_animate -> later (Godot AudioStreamPlayer / AnimationPlayer)
# use_ui_document_root -> Godot has no UIDocument; resolve the mount viewport if needed.

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

## Shallow dependency comparison. null on either side => "changed" (always run).
static func _deps_changed(prev, next) -> bool:
	if prev == null or next == null:
		return true
	if prev.size() != next.size():
		return true
	for i in prev.size():
		if not _equal(prev[i], next[i]):
			return true
	return false

static func _equal(a, b) -> bool:
	return a == b
