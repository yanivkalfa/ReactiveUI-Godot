class_name DemoRouter
extends RefCounted

static func render(_p: Dictionary, _c: Array) -> RUIVNode:
	return V.router({ "initial": "/" }, [V.fc(DemoRouter.inner)])

static func inner(_p: Dictionary, _c: Array) -> RUIVNode:
	var nav := RUIRouter.use_navigate()
	var loc := RUIRouter.use_location()
	return DemoUtil.box("Router — pages, params, navigation", [
		V.hbox({ "style": { "separation": 8 } }, [
			V.button({ "text": "Home", "on_pressed": func(): nav.call("/") }),
			V.button({ "text": "User 7", "on_pressed": func(): nav.call("/users/7") }),
			V.button({ "text": "About", "on_pressed": func(): nav.call("/about") }),
			V.button({ "text": "Broken link", "on_pressed": func(): nav.call("/nope") }),
		]),
		V.label({ "text": "location: %s" % loc, "style": { "font_color": Color(0.6, 0.8, 1.0) } }),
		V.panel({ "style": { "bg_color": Color(0.18, 0.18, 0.22), "corner_radius": 6, "pad": 14 } }, [
			V.routes({ "routes": [
				{ "path": "/", "component": DemoRouter.home },
				{ "path": "/users/:id", "component": DemoRouter.user },
				{ "path": "/about", "component": DemoRouter.about },
				{ "path": "*", "component": DemoRouter.not_found },
			] }),
		]),
	])

static func home(_p: Dictionary, _c: Array) -> RUIVNode: return V.label({ "text": "🏠  Home page" })
static func about(_p: Dictionary, _c: Array) -> RUIVNode: return V.label({ "text": "ℹ️  About this library" })
static func not_found(_p: Dictionary, _c: Array) -> RUIVNode: return V.label({ "text": "🚫  404 — no route matched" })
static func user(_p: Dictionary, _c: Array) -> RUIVNode:
	return V.label({ "text": "👤  User #%s  (from the :id route param)" % str(RUIRouter.use_params().get("id")) })
