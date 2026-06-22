class_name V
extends RefCounted
## Factory for building the virtual UI tree. Mirrors ReactiveUIToolKit's `V`.
##
## NOTE: GDScript reserves the lowercase keyword `func`, so the function-component
## factory is `V.fc(...)` ("function component"), not `V.func(...)`.
##
## Usage:
##   V.fc(MyComponent.render, { "title": "Hi" })          # function component
##   V.button({ "text": "OK", "on_pressed": _on_ok })     # host element
##   V.vbox({ "style": { "separation": 8 } }, [ ...kids ]) # container + children
##
## A render function has the signature:  func(props: Dictionary, children: Array) -> RUIVNode | Array

## Function component.
static func fc(render_fn: Callable, props := {}, children = null, key = null) -> RUIVNode:
	return RUIVNode.make_component(render_fn, props, _norm(children), _key(props, key))

## Memoized function component (parity name for ReactiveUIToolKit's V.Memo). Functionally V.fc — every
## function component in this port already bails its re-render when props are unchanged. For a custom
## equality, pass `props.__memo_eq = func(old_props, new_props) -> bool` (consulted by the reconciler).
static func memo(render_fn: Callable, props := {}, children = null, key = null) -> RUIVNode:
	return fc(render_fn, props, children, key)

## Generic host element by Godot class name, e.g. V.h("ProgressBar", {...}).
## INLINED (no make_host/_key/_norm sub-calls, no throwaway `[]` for childless elements) —
## this is the hottest factory path; each GDScript call elided here is ~1 per element per
## frame, i.e. thousands/frame in a big list. [perf]
static func h(type: String, props := {}, children = null, key = null) -> RUIVNode:
	var n := RUIVNode.new()
	n.type = type
	n.props = props
	n.children = _EMPTY if children == null else _norm(children)
	if key != null:
		n.key = key
	elif props.has("key"):
		n.key = props["key"]
	return n

# --- host element factories (the generic `h()` reaches any other Godot Control) ---

# Containers
static func control(props := {}, children = null, key = null) -> RUIVNode: return h("Control", props, children, key)
static func vbox(props := {}, children = null, key = null) -> RUIVNode: return h("VBoxContainer", props, children, key)
static func hbox(props := {}, children = null, key = null) -> RUIVNode: return h("HBoxContainer", props, children, key)
static func grid(props := {}, children = null, key = null) -> RUIVNode: return h("GridContainer", props, children, key)
static func margin(props := {}, children = null, key = null) -> RUIVNode: return h("MarginContainer", props, children, key)
static func panel(props := {}, children = null, key = null) -> RUIVNode: return h("PanelContainer", props, children, key)
static func center(props := {}, children = null, key = null) -> RUIVNode: return h("CenterContainer", props, children, key)
static func scroll(props := {}, children = null, key = null) -> RUIVNode: return h("ScrollContainer", props, children, key)
static func flow_h(props := {}, children = null, key = null) -> RUIVNode: return h("HFlowContainer", props, children, key)
static func flow_v(props := {}, children = null, key = null) -> RUIVNode: return h("VFlowContainer", props, children, key)
static func tabs(props := {}, children = null, key = null) -> RUIVNode: return h("TabContainer", props, children, key)
static func split_h(props := {}, children = null, key = null) -> RUIVNode: return h("HSplitContainer", props, children, key)
static func split_v(props := {}, children = null, key = null) -> RUIVNode: return h("VSplitContainer", props, children, key)
static func aspect(props := {}, children = null, key = null) -> RUIVNode: return h("AspectRatioContainer", props, children, key)
static func foldable(props := {}, children = null, key = null) -> RUIVNode: return h("FoldableContainer", props, children, key)

# Text / display
static func label(props := {}, children = null, key = null) -> RUIVNode: return h("Label", props, children, key)

## A text node: renders a string as a Label. Raw String children are AUTO-WRAPPED to this, so
## `V.vbox({}, ["Score: ", score_str])` and a component returning a bare String both work instead of
## the string being silently dropped. (Godot renders text via Label nodes — this is the text leaf.)
static func text(s, key = null) -> RUIVNode: return h("Label", { "text": str(s) }, null, key)
static func rich_text(props := {}, children = null, key = null) -> RUIVNode: return h("RichTextLabel", props, children, key)
static func color_rect(props := {}, children = null, key = null) -> RUIVNode: return h("ColorRect", props, children, key)
static func texture_rect(props := {}, children = null, key = null) -> RUIVNode: return h("TextureRect", props, children, key)
static func nine_patch(props := {}, children = null, key = null) -> RUIVNode: return h("NinePatchRect", props, children, key)
static func h_separator(props := {}, children = null, key = null) -> RUIVNode: return h("HSeparator", props, children, key)
static func v_separator(props := {}, children = null, key = null) -> RUIVNode: return h("VSeparator", props, children, key)

# Buttons
static func button(props := {}, children = null, key = null) -> RUIVNode: return h("Button", props, children, key)
static func check_box(props := {}, children = null, key = null) -> RUIVNode: return h("CheckBox", props, children, key)
static func check_button(props := {}, children = null, key = null) -> RUIVNode: return h("CheckButton", props, children, key)
static func option_button(props := {}, children = null, key = null) -> RUIVNode: return h("OptionButton", props, children, key)
static func menu_button(props := {}, children = null, key = null) -> RUIVNode: return h("MenuButton", props, children, key)
static func link_button(props := {}, children = null, key = null) -> RUIVNode: return h("LinkButton", props, children, key)
static func texture_button(props := {}, children = null, key = null) -> RUIVNode: return h("TextureButton", props, children, key)

# Inputs
static func line_edit(props := {}, children = null, key = null) -> RUIVNode: return h("LineEdit", props, children, key)
static func text_edit(props := {}, children = null, key = null) -> RUIVNode: return h("TextEdit", props, children, key)
static func code_edit(props := {}, children = null, key = null) -> RUIVNode: return h("CodeEdit", props, children, key)
static func spin_box(props := {}, children = null, key = null) -> RUIVNode: return h("SpinBox", props, children, key)
static func h_slider(props := {}, children = null, key = null) -> RUIVNode: return h("HSlider", props, children, key)
static func v_slider(props := {}, children = null, key = null) -> RUIVNode: return h("VSlider", props, children, key)
static func progress_bar(props := {}, children = null, key = null) -> RUIVNode: return h("ProgressBar", props, children, key)
static func texture_progress(props := {}, children = null, key = null) -> RUIVNode: return h("TextureProgressBar", props, children, key)
static func color_picker(props := {}, children = null, key = null) -> RUIVNode: return h("ColorPicker", props, children, key)
static func color_picker_button(props := {}, children = null, key = null) -> RUIVNode: return h("ColorPickerButton", props, children, key)

# Media (Godot's audio/video are scene nodes — thin host elements; see also use_sfx for one-shots)
static func audio(props := {}, key = null) -> RUIVNode: return h("AudioStreamPlayer", props, null, key)
static func video(props := {}, key = null) -> RUIVNode: return h("VideoStreamPlayer", props, null, key)

# Item-model controls (declarative props; see RUIHost adapters)
static func tab_bar(props := {}, children = null, key = null) -> RUIVNode: return h("TabBar", props, children, key)
static func item_list(props := {}, children = null, key = null) -> RUIVNode: return h("ItemList", props, children, key)
static func tree(props := {}, children = null, key = null) -> RUIVNode: return h("Tree", props, children, key)
static func menu_bar(props := {}, children = null, key = null) -> RUIVNode: return h("MenuBar", props, children, key)

# --- structural vnodes ---

## A fragment groups children without introducing a host node.
static func fragment(children = null, key = null) -> RUIVNode:
	return RUIVNode.make_fragment(_norm(children), key)

## A portal renders its children under `target` instead of the normal parent node.
static func portal(target: Node, children = null, key = null) -> RUIVNode:
	return RUIVNode.make_portal(target, _norm(children), key)

## A Suspense boundary: shows props.fallback until ready (props.ready_signal fires or props.is_ready()
## becomes true), then renders `children`. GDScript can't throw-to-suspend, so readiness is signal/poll
## driven — see RUISuspense.
static func suspense(props := {}, children = null, key = null) -> RUIVNode:
	return fc(RUISuspense.suspense_fn, props, children, key)

## An error boundary. props: { "fallback": vnode, "on_error": Callable, "reset_key": any }.
## NOTE: GDScript can't catch render crashes; the boundary shows `fallback` when activated
## imperatively and resets when `reset_key` changes. See reconciler `_begin_error_boundary`.
static func error_boundary(props := {}, children = null, key = null) -> RUIVNode:
	return RUIVNode.make_error_boundary(props, _norm(children), key)

# --- router ---

## Provides router context to its subtree. props: { "history": RUIHistory, "initial": "/", "basename": "/" }.
static func router(props := {}, children = null, key = null) -> RUIVNode:
	return fc(RUIRouter.provider, props, children, key)

## Renders the best-matching route. Auto-detects the API:
##   • a Dictionary `routes` prop  -> legacy table: { "routes": [ { "path", "component" }, ... ] }
##   • <Route> children            -> ranked first-match switch: V.routes({}, [ V.route({...}), ... ])
static func routes(props := {}, children = null, key = null) -> RUIVNode:
	return fc(RUIRouter.routes, props, children, key)

## A single route. props: { "path": "/users/:id", "element": vnode | "render": func(match), "index": bool,
## "exact": bool, "case_sensitive": bool }. Children may be nested <Route>s rendered via <Outlet/>.
static func route(props := {}, children = null, key = null) -> RUIVNode:
	return fc(RUIRouter.route_fn, props, children, key)

## Renders the matched nested route (or `children` as a fallback). props: { "context": any }.
static func outlet(props := {}, children = null, key = null) -> RUIVNode:
	return fc(RUIRouter.outlet_fn, props, children, key)

## Declarative redirect (navigates from an effect after commit). props: { "to": "/x", "replace": true, "state": any }.
static func navigate(props := {}, key = null) -> RUIVNode:
	return fc(RUIRouter.navigate_fn, props, [], key)

## An active-aware navigation button. props: { "to", "label", "replace", "end", "case_sensitive",
## "style", "active_style", "state", "button_props" }.
static func nav_link(props := {}, children = null, key = null) -> RUIVNode:
	return fc(RUIRouter.nav_link_fn, props, children, key)

## A navigation button. props: { "to": "/path", "text": "...", "replace": bool, "button_props": {...} }.
static func link(props := {}, children = null, key = null) -> RUIVNode:
	return fc(RUIRouter.link, props, children, key)

static func _key(props, key):
	if key != null:
		return key
	if props is Dictionary and props.has("key"):
		return props["key"]
	return null

# A single shared, read-only empty array handed back for childless elements, so the
# ~N leaf vnodes built each frame don't each allocate a throwaway `[]`. The reconciler
# only ever READS children, never mutates them, so sharing one instance is safe. [perf P6]
const _EMPTY: Array = []

## Normalize children: accept a single vnode or an Array, DEEP-flatten nested arrays
## (so `[a, [b, [c, d]]]` from `.map().map()` / nested conditional output works), and drop nulls.
## Only raw Arrays are flattened — vnodes (with their own .children) are appended as-is.
static func _norm(children) -> Array:
	if children == null:
		return _EMPTY
	if children is String:
		return [text(children)]
	if not (children is Array):
		return [children]
	if children.is_empty():
		return _EMPTY
	var out: Array = []
	_flatten_into(children, out)
	return out

# Recursive deep-flatten helper: appends every non-null, non-Array element of `arr` (and of any
# nested Array, to any depth) into `out`. A vnode is never an Array, so subtrees are preserved.
static func _flatten_into(arr: Array, out: Array) -> void:
	for c in arr:
		if c == null:
			continue
		if c is Array:
			_flatten_into(c, out)
		elif c is String:
			out.append(text(c))   # auto-wrap a raw String child as a text Label
		else:
			out.append(c)
