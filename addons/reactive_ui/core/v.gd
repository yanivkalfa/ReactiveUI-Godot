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

## An error boundary. props: { "fallback": vnode, "on_error": Callable, "reset_key": any }.
## NOTE: GDScript can't catch render crashes; the boundary shows `fallback` when activated
## imperatively and resets when `reset_key` changes. See reconciler `_begin_error_boundary`.
static func error_boundary(props := {}, children = null, key = null) -> RUIVNode:
	return RUIVNode.make_error_boundary(props, _norm(children), key)

# --- router ---

## Provides router context to its subtree. props: { "history": RUIHistory, "initial": "/" }.
static func router(props := {}, children = null, key = null) -> RUIVNode:
	return fc(RUIRouter.provider, props, children, key)

## Renders the best-matching route. props: { "routes": [ { "path", "component" }, ... ] }.
static func routes(props := {}, key = null) -> RUIVNode:
	return fc(RUIRouter.routes, props, [], key)

## A navigation button. props: { "to": "/path", "text": "...", "button_props": {...} }.
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

## Normalize children: accept a single vnode or an Array, flatten one nested level
## (so `[a, [b, c]]` from conditional/mapped output works), and drop nulls.
static func _norm(children) -> Array:
	if children == null:
		return _EMPTY
	if not (children is Array):
		return [children]
	if children.is_empty():
		return _EMPTY
	var out: Array = []
	for c in children:
		if c == null:
			continue
		if c is Array:
			for cc in c:
				if cc != null:
					out.append(cc)
		else:
			out.append(c)
	return out
