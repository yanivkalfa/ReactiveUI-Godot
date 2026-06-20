class_name DemoPortal
extends RefCounted

static func render(_p: Dictionary, _c: Array) -> RUIVNode:
	var show := Hooks.use_state(true)
	var mounted := Hooks.use_state(false)
	var target := Hooks.use_ref(null)
	var mount_eff := func():
		mounted[1].call(true)
		return Callable()
	Hooks.use_effect(mount_eff, [])
	var content = null
	if show[0] and mounted[0] and target["current"] != null:
		content = V.portal(target["current"], [
			V.vbox({ "style": { "separation": 4 } }, [
				V.label({ "text": "🎯 Portaled content" }),
				V.label({ "text": "declared on the left, mounted on the right", "style": { "font_color": Color(0.7, 0.7, 0.7) } }),
			]),
		])
	return DemoUtil.box("Portal — render into a different subtree", [
		V.button({ "text": "Toggle portal (%s)" % show[0], "on_pressed": func(): show[1].call(not show[0]) }),
		V.hbox({ "style": { "separation": 16 } }, [
			V.vbox({ "style": { "expand_h": true } }, [
				V.label({ "text": "Logical parent (left column):" }),
				content if content != null else V.label({ "text": "(portal hidden)" }),
			]),
			V.panel({ "ref": target, "style": { "bg_color": Color(0.13, 0.22, 0.13), "pad": 8, "min_size": Vector2(280, 110) } }, []),
		]),
	])
