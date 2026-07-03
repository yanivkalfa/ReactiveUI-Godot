class_name DemoPortal
extends RefCounted
## AUTO-GENERATED from demos_portal_portal.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var show = Hooks.useState(true)
	var mounted = Hooks.useState(false)
	var target = Hooks.useRef(null)
	var mount_eff = func():
		mounted[1].call(true)
		return Callable()
	Hooks.useEffect(mount_eff, [])
	var content = null
	if show[0] and mounted[0] and target["current"] != null:
		content = V.portal(target["current"], [
			V.vbox({ "style": { "separation": 4 } }, [
				V.label({ "text": "🎯 Portaled content" }),
				V.label({ "text": "declared on the left, mounted on the right", "style": { "font_color": Color(0.7, 0.7, 0.7) } }),
			]),
		])
	return V.fc(DemoBox.render, { "title": "Portal — render into a different subtree" }, [V.button({ "text": "Toggle portal (%s)" % show[0], "onClick": func(): show[1].call(not show[0]) }), V.hbox({ "style": {"separation": 16} }, [V.vbox({ "style": {"expand_h": true} }, [V.label({ "text": "Logical parent (left column):" }), (content if content != null else V.label({ "text": "(portal hidden)" }))]), V.panel({ "ref": target, "style": {"bg_color": Color(0.13, 0.22, 0.13), "pad": 8, "min_size": Vector2(280, 110)} })])])
