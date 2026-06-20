class_name RUIHistory
extends RefCounted
## In-memory navigation history (the engine-agnostic core of the router). Holds a stack
## of location paths and notifies subscribers on change. Ports ReactiveUIToolKit's
## MemoryHistory.

var _stack: Array = ["/"]
var _index := 0
var _subs: Array = []

func _init(initial := "/") -> void:
	_stack = [initial]
	_index = 0

func location() -> String:
	return _stack[_index]

func can_go_back() -> bool:
	return _index > 0

func can_go_forward() -> bool:
	return _index < _stack.size() - 1

func push(path: String) -> void:
	_stack = _stack.slice(0, _index + 1)
	_stack.append(path)
	_index = _stack.size() - 1
	_notify()

func replace(path: String) -> void:
	if _stack[_index] == path:
		return
	_stack[_index] = path
	_notify()

func back() -> void:
	if can_go_back():
		_index -= 1
		_notify()

func forward() -> void:
	if can_go_forward():
		_index += 1
		_notify()

func go(n: int) -> void:
	var prev := _index
	_index = clampi(_index + n, 0, _stack.size() - 1)
	if _index != prev:
		_notify()

func subscribe(cb: Callable) -> Callable:
	_subs.append(cb)
	return func(): _subs.erase(cb)

func _notify() -> void:
	var loc := location()
	for s in _subs.duplicate():
		if s is Callable and s.is_valid():
			s.call(loc)
