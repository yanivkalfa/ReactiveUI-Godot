class_name RUIRouter
extends RefCounted
## React-Router-style routing built on the reactive core (context + hooks). Components
## are static render functions, used via the V.router/routes/link helpers.
##
##   V.router({ "history": h }, [ app ])        # provides router context to its subtree
##   V.routes({ "routes": [                      # picks the best match for the location
##       { "path": "/",          "component": HomePage },
##       { "path": "/users/:id", "component": UserPage },
##       { "path": "*",          "component": NotFound },
##   ]})
##   V.link({ "to": "/users/1", "text": "User 1" })
##
## In any descendant component:
##   RUIRouter.use_navigate()  -> func(path, replace := false)
##   RUIRouter.use_location()  -> current path String
##   RUIRouter.use_params()    -> { "id": "1", ... } for the matched route

const NAV_CTX := "__rui_router_nav"   # stable { navigate, history }
const LOC_CTX := "__rui_router_loc"   # volatile current location string
const PARAMS_CTX := "__rui_route_params"

# --- provider ---
static func provider(props: Dictionary, children: Array):
	var history: RUIHistory = props.get("history")
	if history == null:
		history = RUIHistory.new(str(props.get("initial", "/")))
	var loc_state = Hooks.use_state(history.location())
	var location = loc_state[0]
	var set_location: Callable = loc_state[1]

	var sub_effect := func():
		return history.subscribe(func(path): set_location.call(path))
	Hooks.use_effect(sub_effect, [history])

	var navigate := Hooks.use_callback(func(path, replace = false):
		if replace: history.replace(str(path))
		else: history.push(str(path)), [history])

	# Two contexts so a location change doesn't re-render navigate-only consumers. The nav
	# context is memoized (stable identity) and provides navigate/history; only LOC_CTX
	# churns on navigation. [audit M4]
	var nav_ctx := Hooks.use_memo(func(): return { "navigate": navigate, "history": history }, [history])
	Hooks.provide_context(NAV_CTX, nav_ctx)
	Hooks.provide_context(LOC_CTX, location)
	return children

# --- routes ---
static func routes(props: Dictionary, _children: Array):
	var route_list: Array = props.get("routes", [])
	var location = use_location()
	var matched = RUIRouteMatcher.match_routes(route_list, location)
	if matched == null:
		return []
	Hooks.provide_context(PARAMS_CTX, matched["params"])
	var comp = matched["route"].get("component")
	if comp is Callable:
		return V.fc(comp, { "params": matched["params"] })
	if comp is RUIVNode:
		return comp
	return []

# --- link ---
static func link(props: Dictionary, _children: Array):
	var to := str(props.get("to", "/"))
	var navigate := use_navigate()
	var extra: Dictionary = props.get("button_props", {})
	var btn := { "text": str(props.get("text", to)), "on_pressed": func(): navigate.call(to) }
	for k in extra:
		btn[k] = extra[k]
	return V.button(btn)

# --- hooks ---
static func use_router():
	var nav = Hooks.use_context(NAV_CTX)
	if nav == null:
		return null
	return { "location": Hooks.use_context(LOC_CTX), "navigate": nav["navigate"], "history": nav["history"] }

static func use_location() -> String:
	var loc = Hooks.use_context(LOC_CTX)
	return str(loc) if loc != null else "/"

static func use_navigate() -> Callable:
	var nav = Hooks.use_context(NAV_CTX)
	if nav != null:
		return nav["navigate"]
	return func(_p, _replace = false): pass

static func use_params() -> Dictionary:
	var p = Hooks.use_context(PARAMS_CTX)
	return p if p != null else {}
