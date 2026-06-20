class_name DemoUtil
extends RefCounted
## Shared helpers for the demo gallery. (Mirrors a `module`/`*.style` file in the
## ReactiveUIToolkit samples — shared static helpers used across demos.)

## A titled content box every demo wraps itself in.
static func box(title: String, kids: Array) -> RUIVNode:
	var content: Array = [
		V.label({ "text": title, "style": { "font_size": 24, "font_color": Color(0.55, 0.8, 1.0) } }),
		V.h_separator({}),
	]
	content.append_array(kids)
	return V.margin({ "style": { "margin": 20 } }, [V.vbox({ "style": { "separation": 12 } }, content)])
