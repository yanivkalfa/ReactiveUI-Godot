class_name DemoKeyedTile
extends RefCounted
## AUTO-GENERATED from demos_keyed_keyed_tile.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var id = props.get("id")
	var col = Hooks.useRef(null)
	if col["current"] == null:
		col["current"] = Color(randf() * 0.5 + 0.3, randf() * 0.5 + 0.3, randf() * 0.5 + 0.3)
	return V.panel({ "style": {"bg_color": col["current"], "corner_radius": 6, "min_size": Vector2(54, 54)} }, [V.center({}, [V.label({ "text": str(id), "style": {"font_size": 22, "font_color": Color.WHITE} })])])
