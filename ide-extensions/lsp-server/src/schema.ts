// guitkx vocabulary for markup-side completion/hover. The tag NAME set comes from the shared
// vocabulary.json (T0.3 — a byte-identical copy of addons/reactive_ui/guitkx/vocabulary.json, the
// single source of truth guitkx.gd also loads; vocab.test.ts enforces the sync). This file keeps
// the per-tag METADATA (godotClass, events) and DERIVES alias entries (VBoxContainer,
// RichTextLabel, …) from the vocabulary, so every tag the compiler accepts gets completion/hover
// and can never be false-flagged unknown. Per-control Godot properties are NOT enumerated here —
// those come from a bundled ClassDB dump (see classdb.ts).

import vocabulary from "./vocabulary.json";

export const VOCABULARY: { directives: string[]; hooks: string[]; host_tags: Record<string, string>; v_factories: string[] } = vocabulary;

export interface TagInfo {
  tag: string;
  godotClass: string;
  factory: string;
  events?: string[];
}

export interface AttrInfo {
  name: string;
  type: string;
  detail: string;
}

const BASE_TAGS: TagInfo[] = [
  // T2.2: the named alias of `<>...</>` (Unity parity, case-insensitive at the parser). Groups
  // children without a container node; accepts only `key`.
  { tag: "Fragment", godotClass: "Fragment", factory: "V.fragment" },
  { tag: "Control", godotClass: "Control", factory: "V.control" },
  { tag: "VBox", godotClass: "VBoxContainer", factory: "V.vbox" },
  { tag: "HBox", godotClass: "HBoxContainer", factory: "V.hbox" },
  { tag: "Grid", godotClass: "GridContainer", factory: "V.grid" },
  { tag: "Margin", godotClass: "MarginContainer", factory: "V.margin" },
  { tag: "Panel", godotClass: "PanelContainer", factory: "V.panel" },
  { tag: "Center", godotClass: "CenterContainer", factory: "V.center" },
  { tag: "Scroll", godotClass: "ScrollContainer", factory: "V.scroll" },
  { tag: "Tabs", godotClass: "TabContainer", factory: "V.tabs" },
  { tag: "Label", godotClass: "Label", factory: "V.label" },
  { tag: "RichText", godotClass: "RichTextLabel", factory: "V.rich_text" },
  { tag: "ColorRect", godotClass: "ColorRect", factory: "V.color_rect" },
  { tag: "TextureRect", godotClass: "TextureRect", factory: "V.texture_rect" },
  { tag: "HSeparator", godotClass: "HSeparator", factory: "V.h_separator" },
  { tag: "VSeparator", godotClass: "VSeparator", factory: "V.v_separator" },
  { tag: "Button", godotClass: "Button", factory: "V.button", events: ["onClick", "onChange", "onPointerDown", "onPointerUp"] },
  { tag: "CheckBox", godotClass: "CheckBox", factory: "V.check_box", events: ["onChange", "onClick"] },
  { tag: "CheckButton", godotClass: "CheckButton", factory: "V.check_button", events: ["onChange"] },
  { tag: "OptionButton", godotClass: "OptionButton", factory: "V.option_button", events: ["onChange"] },
  { tag: "MenuButton", godotClass: "MenuButton", factory: "V.menu_button" },
  { tag: "LinkButton", godotClass: "LinkButton", factory: "V.link_button", events: ["onClick"] },
  { tag: "TextureButton", godotClass: "TextureButton", factory: "V.texture_button", events: ["onClick"] },
  { tag: "LineEdit", godotClass: "LineEdit", factory: "V.line_edit", events: ["onChange", "onSubmit"] },
  { tag: "TextEdit", godotClass: "TextEdit", factory: "V.text_edit", events: ["onChange"] },
  { tag: "CodeEdit", godotClass: "CodeEdit", factory: "V.code_edit" },
  { tag: "SpinBox", godotClass: "SpinBox", factory: "V.spin_box", events: ["onChange"] },
  { tag: "HSlider", godotClass: "HSlider", factory: "V.h_slider", events: ["onChange"] },
  { tag: "VSlider", godotClass: "VSlider", factory: "V.v_slider", events: ["onChange"] },
  { tag: "ProgressBar", godotClass: "ProgressBar", factory: "V.progress_bar" },
  { tag: "ItemList", godotClass: "ItemList", factory: "V.item_list", events: ["onChange"] },
  { tag: "Tree", godotClass: "Tree", factory: "V.tree", events: ["onChange"] },
  { tag: "TabBar", godotClass: "TabBar", factory: "V.tab_bar", events: ["onChange"] },
];

// Every vocabulary tag as a TagInfo: hand-maintained BASE_TAGS carry the metadata; aliases from
// vocabulary.host_tags that BASE_TAGS doesn't name (VBoxContainer -> vbox, …) clone the canonical
// entry with the alias as tag AND godotClass (the long form IS the Godot class name).
export const HOST_TAGS: TagInfo[] = (() => {
  const byFactory = new Map<string, TagInfo>();
  for (const t of BASE_TAGS) if (!byFactory.has(t.factory)) byFactory.set(t.factory, t);
  const known = new Set(BASE_TAGS.map((t) => t.tag));
  const out = [...BASE_TAGS];
  for (const [alias, factory] of Object.entries(VOCABULARY.host_tags)) {
    if (known.has(alias)) continue;
    const base = byFactory.get(`V.${factory}`);
    if (base) out.push({ ...base, tag: alias, godotClass: alias });
  }
  return out;
})();

export const STRUCTURAL_ATTRS: AttrInfo[] = [
  { name: "key", type: "Variant", detail: "Reconciler key — stabilises identity across re-renders/reorders." },
  { name: "ref", type: "Callable|Array", detail: "Forwarded ref — receives the underlying Godot Control once mounted." },
  { name: "style", type: "Dictionary", detail: "Inline style overrides (theme/StyleBox properties)." },
];

export const COMMON_ATTRS: AttrInfo[] = [
  { name: "name", type: "String", detail: "Node name." },
  { name: "visible", type: "bool", detail: "Whether the Control is visible." },
  { name: "tooltip_text", type: "String", detail: "Tooltip shown on hover." },
  { name: "mouse_filter", type: "int", detail: "Control.MouseFilter (0 STOP, 1 PASS, 2 IGNORE)." },
  { name: "size_flags_horizontal", type: "int", detail: "Container size flags (horizontal)." },
  { name: "size_flags_vertical", type: "int", detail: "Container size flags (vertical)." },
  { name: "custom_minimum_size", type: "Vector2", detail: "Minimum size hint." },
];

export interface DirectiveInfo {
  label: string;
  insert: string;
  detail: string;
}

export const PREAMBLE_DIRECTIVES: DirectiveInfo[] = [
  { label: "@class_name", insert: "@class_name ", detail: "Override the generated class name." },
  { label: "@uss", insert: '@uss "', detail: "Associate a Theme/StyleBox resource path (reserved)." },
];

export const CONTROL_FLOW: DirectiveInfo[] = [
  { label: "@if", insert: "@if (${1:cond}) {\n\t$0\n}", detail: "Conditional branch." },
  { label: "@elif", insert: "@elif (${1:cond}) {\n\t$0\n}", detail: "Else-if branch." },
  { label: "@else", insert: "@else {\n\t$0\n}", detail: "Fallback branch." },
  { label: "@for", insert: "@for (${1:x} in ${2:xs}) {\n\t$0\n}", detail: "Loop over a collection." },
  { label: "@while", insert: "@while (${1:cond}) {\n\t$0\n}", detail: "While loop." },
  { label: "@match", insert: "@match (${1:value}) {\n\t@case (${2:v}) { $0 }\n\t@default { }\n}", detail: "Pattern match." },
  { label: "@case", insert: "@case (${1:v}) {\n\t$0\n}", detail: "A match arm." },
  { label: "@default", insert: "@default {\n\t$0\n}", detail: "Default match arm." },
];

export function findTag(name: string): TagInfo | undefined {
  return HOST_TAGS.find((t) => t.tag === name);
}

// Style-dict keys understood by RUIStyle (addons/reactive_ui/core/style.gd) — offered inside a
// `style={ {…} }` (or `*_style`) dictionary, where Godot's own LSP has no vocabulary.
export const STYLE_KEYS: AttrInfo[] = [
  { name: "bg_color", type: "Color", detail: "StyleBox background fill." },
  { name: "border_color", type: "Color", detail: "StyleBox border color." },
  { name: "border_width", type: "int", detail: "StyleBox border width (all sides)." },
  { name: "corner_radius", type: "int", detail: "StyleBox corner radius (all corners)." },
  { name: "pad", type: "float", detail: "StyleBox content margin (all sides)." },
  { name: "hover", type: "Dictionary", detail: "Per-state StyleBox for the hover slot." },
  { name: "pressed", type: "Dictionary", detail: "Per-state StyleBox for the pressed slot." },
  { name: "focus", type: "Dictionary", detail: "Per-state StyleBox for the focus slot." },
  { name: "disabled", type: "Dictionary", detail: "Per-state StyleBox for the disabled slot." },
  { name: "read_only", type: "Dictionary", detail: "Per-state StyleBox for the read_only slot." },
  { name: "colors", type: "Dictionary", detail: "Theme color overrides { name: Color }." },
  { name: "constants", type: "Dictionary", detail: "Theme constant overrides { name: int }." },
  { name: "fonts", type: "Dictionary", detail: "Theme font overrides { name: Font }." },
  { name: "font_sizes", type: "Dictionary", detail: "Theme font-size overrides { name: int }." },
  { name: "icons", type: "Dictionary", detail: "Theme icon overrides { name: Texture2D }." },
  { name: "styleboxes", type: "Dictionary", detail: "Theme StyleBox overrides { name: StyleBox }." },
  { name: "min_width", type: "float", detail: "custom_minimum_size.x." },
  { name: "min_height", type: "float", detail: "custom_minimum_size.y." },
  { name: "min_size", type: "Vector2", detail: "custom_minimum_size." },
  { name: "fill", type: "bool", detail: "Anchor to fill the parent (PRESET_FULL_RECT)." },
  { name: "expand_h", type: "bool", detail: "size_flags_horizontal EXPAND_FILL." },
  { name: "expand_v", type: "bool", detail: "size_flags_vertical EXPAND_FILL." },
  { name: "grow_h", type: "int|String", detail: "size_flags_horizontal (fill/expand/center/…)." },
  { name: "grow_v", type: "int|String", detail: "size_flags_vertical (fill/expand/center/…)." },
  { name: "h_align", type: "int|String", detail: "size_flags_horizontal alignment." },
  { name: "v_align", type: "int|String", detail: "size_flags_vertical alignment." },
  { name: "modulate", type: "Color", detail: "Control.modulate." },
  { name: "self_modulate", type: "Color", detail: "Control.self_modulate." },
  { name: "rotation", type: "float", detail: "Rotation in degrees." },
  { name: "scale", type: "Vector2", detail: "Control.scale." },
  { name: "pivot", type: "Vector2", detail: "pivot_offset." },
  { name: "visible", type: "bool", detail: "Control.visible." },
  { name: "clip", type: "bool", detail: "clip_contents." },
  { name: "mouse_filter", type: "int|String", detail: "mouse_filter (stop/pass/ignore)." },
  { name: "tooltip", type: "String", detail: "tooltip_text." },
  { name: "z_index", type: "int", detail: "z_index." },
  { name: "color", type: "Color", detail: "font_color theme override." },
  { name: "font_color", type: "Color", detail: "font_color theme override." },
  { name: "font", type: "Font", detail: "font theme override." },
  { name: "font_size", type: "int", detail: "font_size theme override." },
  { name: "outline_color", type: "Color", detail: "font_outline_color theme override." },
  { name: "outline_size", type: "int", detail: "outline_size theme constant." },
  { name: "separation", type: "int", detail: "separation theme constant (containers)." },
  { name: "h_separation", type: "int", detail: "h_separation theme constant." },
  { name: "v_separation", type: "int", detail: "v_separation theme constant." },
  { name: "margin", type: "int", detail: "margin_* theme constants (MarginContainer)." },
];

// Common built-in constants for `<Type>.<member>` completion inside {expr} — a static fallback for the
// most-used ones; Godot's own LSP (when running) supplies the full set. [audit #3]
export const BUILTIN_MEMBERS: Record<string, string[]> = {
  Color: [
    "WHITE", "BLACK", "TRANSPARENT", "RED", "GREEN", "BLUE", "YELLOW", "CYAN", "MAGENTA", "GRAY",
    "DARK_GRAY", "LIGHT_GRAY", "ORANGE", "PURPLE", "PINK", "BROWN", "GOLD", "LIME_GREEN", "SKY_BLUE",
    "AQUA", "NAVY_BLUE", "TEAL", "MAROON", "SILVER", "CRIMSON",
  ],
  Vector2: ["ZERO", "ONE", "INF", "LEFT", "RIGHT", "UP", "DOWN"],
  Vector2i: ["ZERO", "ONE", "MIN", "MAX", "LEFT", "RIGHT", "UP", "DOWN"],
  Vector3: ["ZERO", "ONE", "INF", "LEFT", "RIGHT", "UP", "DOWN", "FORWARD", "BACK"],
};
