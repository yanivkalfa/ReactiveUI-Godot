class_name DemoGallery
extends RefCounted
## AUTO-GENERATED from demos_gallery.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var sel = Hooks.useState(0)
	var demos := DemoGalleryTable.entries()
	var buttons: Array = []
	for i in demos.size():
		var idx := i
		var is_sel: bool = sel[0] == i
		buttons.append(V.button({
			"text": demos[i]["title"],
			"onClick": func(): sel[1].call(idx),
			"style": {
				"expand_h": true,
				"bg_color": Color(0.2, 0.4, 0.7) if is_sel else Color(0.18, 0.18, 0.22),
				"corner_radius": 4, "pad": 6,
			},
		}))
	return V.hbox({ "style": {"fill": true} }, [V.panel({ "style": {"bg_color": Color(0.1, 0.1, 0.12), "min_width": 210} }, [V.margin({ "style": {"margin": 8} }, [V.vbox({ "style": {"separation": 4, "expand_v": true} }, [V.label({ "text": "Reactive UI", "style": {"font_size": 22, "font_color": Color(0.0, 0.9, 0.75)} }), V.label({ "text": "Godot demo gallery", "style": {"font_color": Color(0.6, 0.6, 0.6)} }), V.h_separator({}), V.scroll({ "horizontal_scroll_mode": ScrollContainer.SCROLL_MODE_DISABLED, "style": {"expand_v": true} }, [V.vbox({ "style": {"separation": 4} }, [(buttons)])])])])]), V.panel({ "style": {"bg_color": Color(0.13, 0.13, 0.16), "expand_h": true, "expand_v": true} }, [(V.fc(demos[sel[0]]["fn"]))])])
