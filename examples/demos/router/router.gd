class_name DemoRouter
extends RefCounted
## Showcases the component-tree router: V.routes(children) ranked switch, a layout <Route> with a
## nested <Outlet/>, :id params, a "*" catch-all, and active-aware V.nav_link styling.

const ACTIVE := { "font_color": Color(1.0, 0.85, 0.3) }
const IDLE := { "font_color": Color(0.7, 0.7, 0.8) }

static func render(_p: Dictionary, _c: Array) -> RUIVNode:
	return V.router({ "initial": "/" }, [V.fc(DemoRouter.inner)])

static func inner(_p: Dictionary, _c: Array) -> RUIVNode:
	var loc := RUIRouter.use_location()
	return DemoUtil.box("Router — nested routes, outlet, active links", [
		V.hbox({ "style": { "separation": 12 } }, [
			V.nav_link({ "to": "/", "label": "Home", "end": true, "style": IDLE, "active_style": ACTIVE }),
			V.nav_link({ "to": "/users", "label": "Users", "style": IDLE, "active_style": ACTIVE }),
			V.nav_link({ "to": "/about", "label": "About", "style": IDLE, "active_style": ACTIVE }),
			V.nav_link({ "to": "/nope", "label": "Broken", "style": IDLE, "active_style": ACTIVE }),
		]),
		V.label({ "text": "location: %s" % loc, "style": { "font_color": Color(0.6, 0.8, 1.0) } }),
		V.panel({ "style": { "bg_color": Color(0.18, 0.18, 0.22), "corner_radius": 6, "pad": 14 } }, [
			V.routes({}, [
				V.route({ "path": "/", "element": V.label({ "text": "🏠  Home page" }) }),
				V.route({ "path": "/users", "element": DemoRouter._users_layout() }, [
					V.route({ "index": true, "element": V.label({ "text": "← pick a user" }) }),
					V.route({ "path": ":id", "render": DemoRouter.user }),
				]),
				V.route({ "path": "/about", "element": V.label({ "text": "ℹ️  About this library" }) }),
				V.route({ "path": "*", "element": V.label({ "text": "🚫  404 — no route matched" }) }),
			]),
		]),
	])

static func _users_layout() -> RUIVNode:
	return V.vbox({ "style": { "separation": 8 } }, [
		V.hbox({ "style": { "separation": 8 } }, [
			V.label({ "text": "Users:", "style": { "font_color": Color(0.8, 0.8, 0.9) } }),
			V.nav_link({ "to": "/users/1", "label": "#1", "style": IDLE, "active_style": ACTIVE }),
			V.nav_link({ "to": "/users/2", "label": "#2", "style": IDLE, "active_style": ACTIVE }),
			V.nav_link({ "to": "/users/3", "label": "#3", "style": IDLE, "active_style": ACTIVE }),
		]),
		V.outlet(),   # the matched nested route renders here
	])

static func user(m: RUIRouteMatch) -> RUIVNode:
	return V.label({ "text": "👤  User #%s  (from the :id route param)" % str(m.params.get("id")) })
