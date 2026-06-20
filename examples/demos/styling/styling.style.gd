class_name DemoStylingStyle
extends RefCounted
## Shared style constants for the styling demo — the GDScript analogue of a
## `Foo.style.uitkx` file (a module of reusable Style values).

static var PANEL := { "bg_color": Color(0.16, 0.17, 0.24), "corner_radius": 10, "border_width": 2, "border_color": Color(0.4, 0.5, 0.85), "pad": 16 }
static var SQUARE_RED := { "bg_color": Color(0.9, 0.35, 0.35), "corner_radius": 30, "min_size": Vector2(60, 60) }
static var SQUARE_GREEN := { "bg_color": Color(0.35, 0.85, 0.45), "corner_radius": 8, "min_size": Vector2(60, 60) }
static var SQUARE_BLUE := { "bg_color": Color(0.4, 0.55, 0.95), "min_size": Vector2(60, 60) }
static var OUTLINED := { "font_size": 24, "colors": { "font_color": Color(1, 1, 1), "font_outline_color": Color(0.2, 0.2, 0.6) }, "constants": { "outline_size": 4 } }
