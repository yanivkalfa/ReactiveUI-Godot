class_name RUISignal
extends RefCounted
## A reactive value store that lives OUTSIDE the component tree — the analogue of
## ReactiveUIToolKit's `Signal`. Components subscribe via `Hooks.use_signal(...)` and
## re-render when the value (or a selected slice of it) changes.
##
## NOTE: named RUISignal (not `Signal`) because Godot already uses "signal" for its own
## event mechanism. Create one anywhere and share it: `var counter := RUISignal.new(0)`.

var _value
var _subs: Array = []   ## Array[Callable] — notified on change

func _init(initial = null) -> void:
	_value = initial

func get_value():
	return _value

## Set a new value; notifies subscribers only if it actually changed (value equality).
func set_value(v) -> void:
	if v == _value:
		return
	_value = v
	for s in _subs.duplicate():   # duplicate: a subscriber may unsubscribe during notify
		if s is Callable and s.is_valid():
			s.call(v)

## Functional update: `sig.update(func(old): return old + 1)`.
func update(fn: Callable) -> void:
	set_value(fn.call(_value))

## Subscribe; returns an unsubscribe Callable.
func subscribe(cb: Callable) -> Callable:
	_subs.append(cb)
	return func(): _subs.erase(cb)
