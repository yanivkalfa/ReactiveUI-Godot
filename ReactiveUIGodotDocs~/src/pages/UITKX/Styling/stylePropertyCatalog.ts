/**
 * Complete catalog of every key understood by the RUIStyle style layer
 * (addons/reactive_ui/core/style.gd). Used by StylingPage to render property cards.
 *
 * Godot has no USS/CSS. A `style={ { … } }` Dictionary on any host element is
 * mapped onto Godot Control properties, size flags, and Theme / StyleBox
 * overrides by RUIStyle. This catalog is the authoritative documentation of that
 * vocabulary — it mirrors the STYLE_KEYS array in the LSP schema
 * (ide-extensions/lsp-server/src/schema.ts).
 *
 * There is no version gating: none of these keys are Godot-version-specific in
 * this library, so there is no `sinceGodot` field.
 */

export interface PropertyCard {
  /** snake_case key used in a style Dictionary, e.g. "bg_color". */
  key: string
  /** GDScript / Godot type of the value, e.g. "Color" or "Dictionary". */
  type: string
  /** One-line description of what the key does. */
  description: string
  /** How RUIStyle applies it to Godot (the underlying Control / Theme / StyleBox API). */
  godotMapping: string
  /** Example value as it appears in a style Dictionary literal, e.g. `Color(0.1, 0.1, 0.18)`. */
  example: string
  /** Category for grouping / filtering. */
  category: PropertyCategory
  /** True if this key combines with others into a single StyleBoxFlat / affects several properties. */
  compound?: boolean
}

export type PropertyCategory =
  | 'StyleBox'
  | 'Per-state StyleBox'
  | 'Theme channels'
  | 'Layout & size'
  | 'Transform'
  | 'Text & font'
  | 'Container spacing'
  | 'Misc'

// ---------------------------------------------------------------------------
// The catalog — one entry per RUIStyle key (schema.ts STYLE_KEYS).
// ---------------------------------------------------------------------------

export const STYLE_PROPERTY_CATALOG: PropertyCard[] = [
  // ── StyleBox builder ─────────────────────────────────────────────────
  // bg_color / border_* / corner_radius / pad combine into ONE StyleBoxFlat
  // applied to the control's primary stylebox slot (Panel: "panel",
  // Button: "normal", LineEdit/TextEdit: "normal", ProgressBar: "background").
  {
    key: 'bg_color',
    type: 'Color',
    category: 'StyleBox',
    description: 'Background fill of the control.',
    godotMapping: 'StyleBoxFlat.bg_color on the primary stylebox slot.',
    example: 'Color(0.16, 0.17, 0.24)',
    compound: true,
  },
  {
    key: 'border_color',
    type: 'Color',
    category: 'StyleBox',
    description: 'Border color for all four sides.',
    godotMapping: 'StyleBoxFlat.border_color.',
    example: 'Color(0.4, 0.5, 0.85)',
    compound: true,
  },
  {
    key: 'border_width',
    type: 'int',
    category: 'StyleBox',
    description: 'Border width applied to all four sides.',
    godotMapping: 'StyleBoxFlat.border_width_left/right/top/bottom.',
    example: '2',
    compound: true,
  },
  {
    key: 'corner_radius',
    type: 'int',
    category: 'StyleBox',
    description: 'Corner radius applied to all four corners.',
    godotMapping: 'StyleBoxFlat.corner_radius_top_left/… (all four).',
    example: '10',
    compound: true,
  },
  {
    key: 'pad',
    type: 'float',
    category: 'StyleBox',
    description: 'Content margin (inner padding) on all four sides.',
    godotMapping: 'StyleBoxFlat.content_margin_left/right/top/bottom.',
    example: '16',
    compound: true,
  },

  // ── Per-state StyleBox slots ─────────────────────────────────────────
  // A nested dict builds a StyleBoxFlat for the matching state slot. Godot
  // retains these natively — no hover/press event wiring needed. Available
  // slots vary by control (Button: hover/pressed/disabled/focus;
  // LineEdit: focus/read_only).
  {
    key: 'hover',
    type: 'Dictionary',
    category: 'Per-state StyleBox',
    description: 'StyleBox used while the control is hovered (Button-like controls).',
    godotMapping: 'add_theme_stylebox_override("hover", StyleBoxFlat …).',
    example: '{ "bg_color": Color(0.3, 0.6, 0.9) }',
  },
  {
    key: 'pressed',
    type: 'Dictionary',
    category: 'Per-state StyleBox',
    description: 'StyleBox used while the control is pressed (Button-like controls).',
    godotMapping: 'add_theme_stylebox_override("pressed", StyleBoxFlat …).',
    example: '{ "bg_color": Color(0.2, 0.45, 0.75) }',
  },
  {
    key: 'focus',
    type: 'Dictionary',
    category: 'Per-state StyleBox',
    description: 'StyleBox used while the control is focused (Button / LineEdit / TextEdit).',
    godotMapping: 'add_theme_stylebox_override("focus", StyleBoxFlat …).',
    example: '{ "border_color": Color(0.4, 0.7, 1.0), "border_width": 2 }',
  },
  {
    key: 'disabled',
    type: 'Dictionary',
    category: 'Per-state StyleBox',
    description: 'StyleBox used while the control is disabled (Button-like controls).',
    godotMapping: 'add_theme_stylebox_override("disabled", StyleBoxFlat …).',
    example: '{ "bg_color": Color(0.2, 0.2, 0.2) }',
  },
  {
    key: 'read_only',
    type: 'Dictionary',
    category: 'Per-state StyleBox',
    description: 'StyleBox used while a LineEdit / TextEdit is read-only.',
    godotMapping: 'add_theme_stylebox_override("read_only", StyleBoxFlat …).',
    example: '{ "bg_color": Color(0.12, 0.12, 0.14) }',
  },

  // ── Generic theme channels (100% coverage) ───────────────────────────
  // Reach ANY theme item of ANY control by exact item name. Each is a
  // { name: value } map that becomes add_theme_<kind>_override(name, value).
  {
    key: 'colors',
    type: 'Dictionary',
    category: 'Theme channels',
    description: 'Arbitrary theme color overrides keyed by exact item name.',
    godotMapping: 'add_theme_color_override(name, Color) for each entry.',
    example: '{ "font_color": Color.WHITE, "font_outline_color": Color(0.2, 0.2, 0.6) }',
  },
  {
    key: 'constants',
    type: 'Dictionary',
    category: 'Theme channels',
    description: 'Arbitrary theme constant (int) overrides keyed by item name.',
    godotMapping: 'add_theme_constant_override(name, int) for each entry.',
    example: '{ "outline_size": 4 }',
  },
  {
    key: 'fonts',
    type: 'Dictionary',
    category: 'Theme channels',
    description: 'Arbitrary theme font overrides keyed by item name.',
    godotMapping: 'add_theme_font_override(name, Font) for each entry.',
    example: '{ "font": preload("res://ui/Inter.ttf") }',
  },
  {
    key: 'font_sizes',
    type: 'Dictionary',
    category: 'Theme channels',
    description: 'Arbitrary theme font-size overrides keyed by item name.',
    godotMapping: 'add_theme_font_size_override(name, int) for each entry.',
    example: '{ "font_size": 22 }',
  },
  {
    key: 'icons',
    type: 'Dictionary',
    category: 'Theme channels',
    description: 'Arbitrary theme icon (Texture2D) overrides keyed by item name.',
    godotMapping: 'add_theme_icon_override(name, Texture2D) for each entry.',
    example: '{ "checked": preload("res://ui/check.svg") }',
  },
  {
    key: 'styleboxes',
    type: 'Dictionary',
    category: 'Theme channels',
    description: 'Arbitrary theme StyleBox overrides keyed by item name.',
    godotMapping: 'add_theme_stylebox_override(name, StyleBox) for each entry.',
    example: '{ "panel": my_stylebox }',
  },

  // ── Layout & size flags ──────────────────────────────────────────────
  {
    key: 'min_width',
    type: 'float',
    category: 'Layout & size',
    description: 'Minimum width of the control.',
    godotMapping: 'custom_minimum_size.x.',
    example: '220',
  },
  {
    key: 'min_height',
    type: 'float',
    category: 'Layout & size',
    description: 'Minimum height of the control.',
    godotMapping: 'custom_minimum_size.y.',
    example: '90',
  },
  {
    key: 'min_size',
    type: 'Vector2',
    category: 'Layout & size',
    description: 'Minimum size (width and height at once).',
    godotMapping: 'custom_minimum_size.',
    example: 'Vector2(60, 60)',
  },
  {
    key: 'fill',
    type: 'bool',
    category: 'Layout & size',
    description: 'Anchor the control to fill its parent. Handy for a top-level mount under a plain Control.',
    godotMapping: 'set_anchors_and_offsets_preset(PRESET_FULL_RECT).',
    example: 'true',
  },
  {
    key: 'expand_h',
    type: 'bool',
    category: 'Layout & size',
    description: 'Expand horizontally to consume extra space in a container.',
    godotMapping: 'size_flags_horizontal = SIZE_EXPAND_FILL (or SIZE_FILL if false).',
    example: 'true',
  },
  {
    key: 'expand_v',
    type: 'bool',
    category: 'Layout & size',
    description: 'Expand vertically to consume extra space in a container.',
    godotMapping: 'size_flags_vertical = SIZE_EXPAND_FILL (or SIZE_FILL if false).',
    example: 'true',
  },
  {
    key: 'grow_h',
    type: 'int | String',
    category: 'Layout & size',
    description: 'Horizontal size flags. Accepts a String alias (fill/expand/expand_fill/center/begin/end) or a raw int.',
    godotMapping: 'size_flags_horizontal.',
    example: '"expand_fill"',
  },
  {
    key: 'grow_v',
    type: 'int | String',
    category: 'Layout & size',
    description: 'Vertical size flags. Accepts a String alias or a raw int.',
    godotMapping: 'size_flags_vertical.',
    example: '"center"',
  },
  {
    key: 'h_align',
    type: 'int | String',
    category: 'Layout & size',
    description: 'Alias of grow_h — horizontal size-flag alignment (fill/expand/center/begin/end).',
    godotMapping: 'size_flags_horizontal.',
    example: '"center"',
  },
  {
    key: 'v_align',
    type: 'int | String',
    category: 'Layout & size',
    description: 'Alias of grow_v — vertical size-flag alignment.',
    godotMapping: 'size_flags_vertical.',
    example: '"center"',
  },
  {
    key: 'visible',
    type: 'bool',
    category: 'Layout & size',
    description: 'Whether the control is visible.',
    godotMapping: 'Control.visible.',
    example: 'true',
  },
  {
    key: 'clip',
    type: 'bool',
    category: 'Layout & size',
    description: 'Clip child content to the control bounds.',
    godotMapping: 'Control.clip_contents.',
    example: 'true',
  },
  {
    key: 'mouse_filter',
    type: 'int | String',
    category: 'Layout & size',
    description: 'How the control participates in mouse picking (stop/pass/ignore).',
    godotMapping: 'Control.mouse_filter (MOUSE_FILTER_STOP/PASS/IGNORE).',
    example: '"pass"',
  },
  {
    key: 'z_index',
    type: 'int',
    category: 'Layout & size',
    description: 'Draw order / stacking index relative to siblings.',
    godotMapping: 'CanvasItem.z_index.',
    example: '10',
  },
  {
    key: 'tooltip',
    type: 'String',
    category: 'Layout & size',
    description: 'Tooltip text shown on hover.',
    godotMapping: 'Control.tooltip_text.',
    example: '"Click to save"',
  },

  // ── Transform ────────────────────────────────────────────────────────
  {
    key: 'modulate',
    type: 'Color',
    category: 'Transform',
    description: 'Multiplies the control (and its children) by this color. Drives opacity via the alpha channel.',
    godotMapping: 'CanvasItem.modulate.',
    example: 'Color(1, 1, 1, 0.5)',
  },
  {
    key: 'self_modulate',
    type: 'Color',
    category: 'Transform',
    description: 'Like modulate but affects only this control, not its children.',
    godotMapping: 'CanvasItem.self_modulate.',
    example: 'Color(1, 0.9, 0.9)',
  },
  {
    key: 'rotation',
    type: 'float',
    category: 'Transform',
    description: 'Rotation in degrees (RUIStyle converts to radians for you).',
    godotMapping: 'Control.rotation (via deg_to_rad).',
    example: '45',
  },
  {
    key: 'scale',
    type: 'Vector2',
    category: 'Transform',
    description: 'Scale factor. Values > 1 enlarge, < 1 shrink.',
    godotMapping: 'Control.scale.',
    example: 'Vector2(1.2, 1.2)',
  },
  {
    key: 'pivot',
    type: 'Vector2',
    category: 'Transform',
    description: 'Pivot point for rotation and scale.',
    godotMapping: 'Control.pivot_offset.',
    example: 'Vector2(30, 30)',
  },

  // ── Text & font ──────────────────────────────────────────────────────
  {
    key: 'color',
    type: 'Color',
    category: 'Text & font',
    description: 'Text color (alias of font_color).',
    godotMapping: 'add_theme_color_override("font_color", Color).',
    example: 'Color.WHITE',
  },
  {
    key: 'font_color',
    type: 'Color',
    category: 'Text & font',
    description: 'Text color.',
    godotMapping: 'add_theme_color_override("font_color", Color).',
    example: 'Color(0.6, 0.8, 1.0)',
  },
  {
    key: 'font',
    type: 'Font',
    category: 'Text & font',
    description: 'Font resource for text rendering.',
    godotMapping: 'add_theme_font_override("font", Font).',
    example: 'preload("res://ui/Inter.ttf")',
  },
  {
    key: 'font_size',
    type: 'int',
    category: 'Text & font',
    description: 'Font size in pixels.',
    godotMapping: 'add_theme_font_size_override("font_size", int).',
    example: '22',
  },
  {
    key: 'outline_color',
    type: 'Color',
    category: 'Text & font',
    description: 'Text outline color.',
    godotMapping: 'add_theme_color_override("font_outline_color", Color).',
    example: 'Color(0.2, 0.2, 0.6)',
  },
  {
    key: 'outline_size',
    type: 'int',
    category: 'Text & font',
    description: 'Text outline thickness in pixels.',
    godotMapping: 'add_theme_constant_override("outline_size", int).',
    example: '4',
  },

  // ── Container spacing (theme constants) ──────────────────────────────
  {
    key: 'separation',
    type: 'int',
    category: 'Container spacing',
    description: 'Gap between children in a box container (VBox / HBox).',
    godotMapping: 'add_theme_constant_override("separation", int).',
    example: '8',
  },
  {
    key: 'h_separation',
    type: 'int',
    category: 'Container spacing',
    description: 'Horizontal gap between children (GridContainer, FlowContainer).',
    godotMapping: 'add_theme_constant_override("h_separation", int).',
    example: '10',
  },
  {
    key: 'v_separation',
    type: 'int',
    category: 'Container spacing',
    description: 'Vertical gap between children (GridContainer, FlowContainer).',
    godotMapping: 'add_theme_constant_override("v_separation", int).',
    example: '10',
  },
  {
    key: 'margin',
    type: 'int',
    category: 'Container spacing',
    description: 'Inner margin on all four sides of a MarginContainer.',
    godotMapping: 'add_theme_constant_override("margin_left/top/right/bottom", int).',
    example: '12',
    compound: true,
  },
]

// ---------------------------------------------------------------------------
// Category ordering for the page
// ---------------------------------------------------------------------------

export const CATEGORY_ORDER: PropertyCategory[] = [
  'StyleBox',
  'Per-state StyleBox',
  'Theme channels',
  'Layout & size',
  'Transform',
  'Text & font',
  'Container spacing',
  'Misc',
]
