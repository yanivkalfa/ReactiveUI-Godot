class_name RUIHost
extends RefCounted
## The Godot "host config" — the ONLY layer that knows about concrete Godot node
## APIs. The reconciler talks to nodes exclusively through here, mirroring how
## ReactiveUIToolKit isolates `PropsApplier` / element adapters from the reconciler.
## Swapping this file (plus `RUIStyle`) is what would, in principle, retarget the
## same reconciler at a different host.
##
## Prop conventions on a host vnode's props Dictionary:
##   "style"        -> handed to RUIStyle
##   "ref"          -> a Callable(node) or a { "current": ... } box, receives the node
##   "on_<signal>"  -> a Callable connected to the node's "<signal>" (e.g. on_pressed -> "pressed")
##   "key"          -> reconciliation key (consumed by V; never applied)
##   anything else  -> set directly as a node property (text, editable, disabled, ...)

const RESERVED := { "key": true, "ref": true, "style": true, "classes": true, "children": true, "items": true }  # O(1) lookup [perf #4]

static func create_node(type: String) -> Node:
	if not ClassDB.class_exists(type):
		push_error("[reactive_ui] Unknown host element type: '%s'. Falling back to Control." % type)
		return Control.new()
	return ClassDB.instantiate(type)

## Where children of `node` should be parented. Unlike Unity's VisualElement (which
## auto-redirects Add() into contentContainer), Godot has no such indirection, so the
## reconciler calls this on every append/insert/reorder. Default: the node itself.
## Phase 1.3 overrides this per-element (e.g. ScrollContainer / TabContainer sinks).
static func resolve_child_host(node: Node) -> Node:
	# Most Godot controls take direct children (no Unity-style contentContainer indirection). A custom
	# scene can expose an inner content node via `node.set_meta("rui_content", <inner>)`; children then
	# parent there instead. Default: the node itself.
	if node.has_meta("rui_content"):
		var content = node.get_meta("rui_content")
		if content is Node and is_instance_valid(content):
			return content
	return node

## Apply the prop delta (`old_props` -> `new_props`) onto an existing/new node.
## NOTE: a *removed* plain prop (present last render, absent this render) is NOT reset to its default
## — Godot has no generic per-prop default to restore to without surprises. Treat props React-style:
## pass every prop you want set on every render; conditionally-applied props should toggle to an
## explicit value rather than being omitted. Events/refs/styles ARE cleaned up on removal. [audit #23]
static func apply_props(node: Node, old_props: Dictionary, new_props: Dictionary) -> void:
	# 1. Disconnect events that disappeared (skip entirely if the node has no events). [perf #4]
	if node.has_meta("__rui_events"):
		for k in old_props:   # iterate keys directly — no .keys() array allocation [perf]
			if _is_event(k) and not new_props.has(k):
				_disconnect_event(node, k)

	# 2. Apply new / changed props.
	for k in new_props:   # iterate keys directly — no .keys() array allocation [perf]
		if RESERVED.has(k):
			continue
		if _is_event(k):
			var old_cb = old_props.get(k)
			var new_cb = new_props[k]
			if old_cb != new_cb:
				_disconnect_event(node, k)
				_connect_event(node, k, new_cb)
			continue
		var val = new_props[k]
		if not old_props.has(k) or old_props[k] != val:
			_set_prop(node, k, val)

	# 3. ref (called every commit so the latest node is exposed).
	if new_props.has("ref"):
		var r = new_props["ref"]
		if r is Callable and r.is_valid():
			r.call(node)
		elif r is Dictionary and r.has("current"):
			r["current"] = node

	# 4. style + USS-style `classes` — skip the whole machinery when neither side has either. [perf #4]
	var os = old_props.get("style")
	var ns = new_props.get("style")
	var oc = old_props.get("classes")
	var nc = new_props.get("classes")
	if os != null or ns != null or oc != null or nc != null:
		RUIStyle.apply(node, _effective_style(old_props), _effective_style(new_props))

	# 5. declarative item-model controls (stateful adapters) — dispatched through an extensible
	#    registry so userland can register adapters for custom controls (see register_item_adapter).
	_apply_item_model(node, old_props, new_props)

## Resolve a host element's effective style: merge the styles of its `classes` (left-to-right via
## RUIStyleSheet) then overlay its inline `style` (which wins). A plain dictionary merge — no CSS
## cascade/specificity (decision #3). Returns {} when there's nothing to apply.
static func _effective_style(props: Dictionary) -> Dictionary:
	var classes = props.get("classes")
	var inline = props.get("style")
	if classes == null and inline == null:
		return {}
	if classes == null:
		return inline if inline is Dictionary else {}
	var merged := {}
	if classes is Array:
		for c in classes:
			var cs = RUIStyleSheet.resolve(str(c))
			if cs is Dictionary:
				for k in cs:
					merged[k] = cs[k]
	if inline is Dictionary:
		for k in inline:
			merged[k] = inline[k]
	return merged

## Set a node property. Controlled text inputs are special-cased: setting `text` every
## render (from state) would reset the caret to 0 mid-typing, so we skip when the node's
## value already matches (the common controlled-input case) and otherwise preserve the
## caret. This is a general UX fix for any LineEdit/TextEdit driven by state.
static func _set_prop(node: Node, key: String, val) -> void:
	if key == "text" and node is LineEdit:
		var le := node as LineEdit
		if le.text == val:
			return
		var c := le.caret_column
		le.text = str(val)
		le.caret_column = mini(c, le.text.length())
		return
	if key == "text" and node is TextEdit:
		var te := node as TextEdit
		if te.text == val:
			return
		var ln := te.get_caret_line()
		var col := te.get_caret_column()
		te.text = str(val)
		te.set_caret_line(mini(ln, maxi(0, te.get_line_count() - 1)))
		te.set_caret_column(col)
		return
	node.set(key, val)

static func _is_event(key: String) -> bool:
	return key.begins_with("on_")

static func _signal_name(key: String) -> String:
	return key.substr(3)  # strip "on_"

static func _connect_event(node: Node, key: String, cb) -> void:
	if not (cb is Callable) or not cb.is_valid():
		return
	var sig := _signal_name(key)
	if not node.has_signal(sig):
		push_warning("[reactive_ui] %s has no signal '%s' (for prop '%s')." % [node.get_class(), sig, key])
		return
	if not node.is_connected(sig, cb):   # guard against a stale meta/connection divergence [audit C1]
		node.connect(sig, cb)
	var m: Dictionary = node.get_meta("__rui_events", {})
	m[key] = cb
	node.set_meta("__rui_events", m)

static func _disconnect_event(node: Node, key: String) -> void:
	var m: Dictionary = node.get_meta("__rui_events", {})
	if not m.has(key):
		return
	var sig := _signal_name(key)
	var cb = m[key]
	if cb is Callable and node.is_connected(sig, cb):
		node.disconnect(sig, cb)
	m.erase(key)
	node.set_meta("__rui_events", m)

# --------------------------------------------------------------------------
# Declarative item-model adapters (stateful controls) + extensible registry
# --------------------------------------------------------------------------
# Each adapter rebuilds a control's items when the `items` prop changes while preserving runtime
# state (selection / current tab / expansion) by item IDENTITY — the "tracker" pattern. The
# registry lets userland plug adapters for custom controls without touching this file.

static var _item_adapters: Array = []   # [ { "match": Callable(node)->bool, "apply": Callable(node, old, new) } ]

## Register a custom item-model adapter. `match_fn(node)->bool` selects nodes; `apply_fn(node,
## old_props, new_props)` mutates them. User adapters take precedence over the built-ins.
static func register_item_adapter(match_fn: Callable, apply_fn: Callable) -> void:
	_item_adapters.append({ "match": match_fn, "apply": apply_fn })

static func _ensure_builtin_adapters() -> void:
	if not _item_adapters.is_empty():
		return
	# Order: most-specific first. OptionButton/MenuButton are Buttons; TabBar/ItemList/Tree are Controls.
	_item_adapters.append({ "match": func(n): return n is ItemList, "apply": _apply_item_list })
	_item_adapters.append({ "match": func(n): return n is Tree, "apply": _apply_tree })
	_item_adapters.append({ "match": func(n): return n is TabBar, "apply": _apply_tab_bar })
	_item_adapters.append({ "match": func(n): return n is OptionButton, "apply": _apply_option_button })
	_item_adapters.append({ "match": func(n): return n is PopupMenu, "apply": _apply_popup_menu })

static func _apply_item_model(node: Node, old_props: Dictionary, new_props: Dictionary) -> void:
	_ensure_builtin_adapters()
	for a in _item_adapters:
		if a["match"].call(node):
			a["apply"].call(node, old_props, new_props)
			return

## ItemList: declarative `items` prop (Array of String or { text, icon, disabled }).
## Rebuilds only when the items array changes, preserving the user's selection by index
## (the "tracker" pattern — runtime state survives a re-render). Wire selection changes
## with the normal `on_item_selected` / `on_item_activated` event props.
static func _apply_item_list(node: ItemList, old_props: Dictionary, new_props: Dictionary) -> void:
	if not new_props.has("items"):
		return
	var items: Array = new_props["items"]
	var old_items: Array = old_props.get("items", [])
	if items == old_items:
		return
	# Preserve selection by item IDENTITY (id, else text/value) — not raw index — so it survives
	# reordering/insertion, and honor single vs multi select_mode. Count per id (a MULTISET) so when
	# several items share an id/text we re-select AT MOST the original number, not every duplicate. [audit M2]
	var selected_ids := {}
	for s in node.get_selected_items():
		if s < old_items.size():
			var iid = _item_id(old_items[s])
			selected_ids[iid] = selected_ids.get(iid, 0) + 1
	var single := node.select_mode == ItemList.SELECT_SINGLE
	node.clear()
	for it in items:
		var idx: int
		if it is Dictionary:
			idx = node.add_item(str(it.get("text", "")), it.get("icon"), it.get("selectable", true))
			if it.get("disabled", false):
				node.set_item_disabled(idx, true)
		else:
			idx = node.add_item(str(it))
		var iid2 = _item_id(it)
		if selected_ids.get(iid2, 0) > 0:
			node.select(idx, single)
			selected_ids[iid2] -= 1

static func _item_id(it):
	if it is Dictionary:
		return it.get("id", str(it.get("text", "")))
	return str(it)

## TabBar: declarative `items` (Array of String or { text, icon, disabled }). Rebuilds on change,
## preserving the current tab by item IDENTITY. Wire tab changes with the normal `on_tab_changed` /
## `on_tab_selected` event props.
static func _apply_tab_bar(node: TabBar, old_props: Dictionary, new_props: Dictionary) -> void:
	if not new_props.has("items"):
		return
	var items: Array = new_props["items"]
	var old_items: Array = old_props.get("items", [])
	if items == old_items:
		return
	var cur_id = null
	if node.current_tab >= 0 and node.current_tab < old_items.size():
		cur_id = _item_id(old_items[node.current_tab])
	node.clear_tabs()
	var restore := -1
	for it in items:
		node.add_tab(str(it.get("text", "")) if it is Dictionary else str(it))
		var idx := node.tab_count - 1
		if it is Dictionary:
			if it.get("icon") != null:
				node.set_tab_icon(idx, it.get("icon"))
			if it.get("disabled", false):
				node.set_tab_disabled(idx, true)
		if restore == -1 and cur_id != null and _item_id(it) == cur_id:
			restore = idx   # first match — deterministic when several tabs share text/id [audit]
	if restore >= 0:
		node.current_tab = restore

## OptionButton: declarative `items` (Array of String or { text, icon, disabled, id }). Rebuilds on
## change, preserving the selection by item IDENTITY. Wire changes with `on_item_selected`.
static func _apply_option_button(node: OptionButton, old_props: Dictionary, new_props: Dictionary) -> void:
	if not new_props.has("items"):
		return
	var items: Array = new_props["items"]
	var old_items: Array = old_props.get("items", [])
	if items == old_items:
		return
	var sel_id = null
	if node.selected >= 0 and node.selected < old_items.size():
		sel_id = _item_id(old_items[node.selected])
	node.clear()
	var restore := -1
	for it in items:
		if it is Dictionary:
			node.add_item(str(it.get("text", "")), int(it.get("id", -1)) if it.has("id") else -1)
		else:
			node.add_item(str(it))
		var idx := node.item_count - 1
		if it is Dictionary:
			if it.get("icon") != null:
				node.set_item_icon(idx, it.get("icon"))
			if it.get("disabled", false):
				node.set_item_disabled(idx, true)
		if restore == -1 and sel_id != null and _item_id(it) == sel_id:
			restore = idx   # first match — deterministic when several items share text/id [audit]
	if restore >= 0:
		node.select(restore)

## PopupMenu: declarative `items` (Array of String or { text, id, disabled, checkable, checked,
## separator }). Stateless rebuild (menus carry no persistent selection). Wire with `on_id_pressed`.
static func _apply_popup_menu(node: PopupMenu, old_props: Dictionary, new_props: Dictionary) -> void:
	if not new_props.has("items"):
		return
	var items: Array = new_props["items"]
	var old_items: Array = old_props.get("items", [])
	if items == old_items:
		return
	node.clear()
	for it in items:
		if it is Dictionary:
			if it.get("separator", false):
				node.add_separator(str(it.get("text", "")))
				continue
			if it.get("checkable", false):
				node.add_check_item(str(it.get("text", "")), int(it.get("id", -1)) if it.has("id") else -1)
			else:
				node.add_item(str(it.get("text", "")), int(it.get("id", -1)) if it.has("id") else -1)
			var idx := node.item_count - 1
			if it.get("disabled", false):
				node.set_item_disabled(idx, true)
			if it.has("checked"):
				node.set_item_checked(idx, bool(it["checked"]))
		else:
			node.add_item(str(it))

## Warn (once per node) when a single/limited-child container is given too many children —
## Godot lays out only the first (or first two), so excess children silently break. [audit M1]
static func warn_capacity(node: Node, count: int) -> void:
	if count <= 1 or node.has_meta("__rui_capw"):
		return
	var limit := -1
	if node is SplitContainer:
		limit = 2
	elif node is ScrollContainer or node is AspectRatioContainer or node is CenterContainer \
			or node is PanelContainer or node is MarginContainer or node.is_class("FoldableContainer"):
		limit = 1
	if limit > 0 and count > limit:
		push_warning("[reactive_ui] %s lays out at most %d child(ren) but got %d — wrap them in a VBox/HBox/Grid. (warned once)" % [node.get_class(), limit, count])
		node.set_meta("__rui_capw", true)

## Tree: declarative hierarchical `items` (Array of { id, text, children:[...], collapsed? }).
## Rebuilds on change but PRESERVES the user's expand/collapse state and selection by `id`
## (the tracker pattern) — so re-rendering a tree doesn't reset what the user expanded.
## Wire selection/activation with the normal `on_item_selected` / `on_item_activated` props.
static func _apply_tree(node: Tree, old_props: Dictionary, new_props: Dictionary) -> void:
	if not new_props.has("items"):
		return
	var items: Array = new_props["items"]
	var cols: int = int(new_props.get("columns", 1))
	if node.columns != cols:
		node.columns = cols
	if new_props.has("hide_root"):
		node.hide_root = new_props["hide_root"]
	if items == old_props.get("items") and cols == int(old_props.get("columns", 1)):
		return

	# Capture runtime state (expansion + selection) keyed by id before rebuilding.
	var expanded := {}
	var existing_root := node.get_root()
	if existing_root != null:
		_tree_capture(existing_root, expanded)
	var selected_id = null
	var sel := node.get_selected()
	if sel != null:
		selected_id = sel.get_metadata(0)

	node.clear()
	var groot := node.create_item()
	for it in items:
		_tree_build(node, groot, it, expanded)

	if selected_id != null:
		var found = _tree_find_by_id(node.get_root(), selected_id)
		if found != null:
			found.select(0)

static func _tree_capture(item: TreeItem, out: Dictionary) -> void:
	var id = item.get_metadata(0)
	if id != null:
		out[id] = not item.collapsed
	for child in item.get_children():
		_tree_capture(child, out)

static func _tree_build(tree: Tree, parent: TreeItem, data, expanded: Dictionary) -> void:
	var ti := tree.create_item(parent)
	var id = data.get("id") if data is Dictionary else null
	ti.set_text(0, str(data.get("text", "")) if data is Dictionary else str(data))
	if id != null:
		ti.set_metadata(0, id)
	var collapsed := bool(data.get("collapsed", false)) if data is Dictionary else false
	if id != null and expanded.has(id):
		collapsed = not expanded[id]   # restore captured expansion
	ti.collapsed = collapsed
	if data is Dictionary and data.has("children"):
		for child in data["children"]:
			_tree_build(tree, ti, child, expanded)

static func _tree_find_by_id(item: TreeItem, id):
	if item == null:
		return null
	if item.get_metadata(0) == id:
		return item
	for child in item.get_children():
		var f = _tree_find_by_id(child, id)
		if f != null:
			return f
	return null
