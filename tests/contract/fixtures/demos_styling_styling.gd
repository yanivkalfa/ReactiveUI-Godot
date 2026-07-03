class_name DemoStyling
extends RefCounted
## AUTO-GENERATED from demos_styling_styling.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	return V.fc(DemoBox.render, { "title": "Styling — StyleBoxFlat + theme channels" }, [V.panel({ "style": DemoStylingStyle.PANEL }, [V.vbox({ "style": {"separation": 4} }, [V.label({ "text": "Styled panel", "style": {"font_size": 22, "font_color": Color(0.6, 0.8, 1.0)} }), V.label({ "text": "bg + corner radius + border, all from one StyleBoxFlat (styles live in styling.style.gd)", "style": {"font_color": Color(0.7, 0.7, 0.7)} })])]), V.hbox({ "style": {"separation": 10} }, [V.panel({ "style": DemoStylingStyle.SQUARE_RED }), V.panel({ "style": DemoStylingStyle.SQUARE_GREEN }), V.panel({ "style": DemoStylingStyle.SQUARE_BLUE })]), V.label({ "text": "Theme channels reach any item:", "style": {"font_color": Color(0.7, 0.7, 0.7)} }), V.label({ "text": "outlined text", "style": DemoStylingStyle.OUTLINED })])
