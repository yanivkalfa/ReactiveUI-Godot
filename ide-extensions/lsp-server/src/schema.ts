// guitkx vocabulary for markup-side completion/hover. Embedded (not loaded from disk) so the
// server is self-contained; mirrors ide-extensions/grammar/guitkx-schema.json. Per-control Godot
// properties are NOT enumerated here — those come live from Godot's ClassDB via the proxy.

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

export const HOST_TAGS: TagInfo[] = [
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
  { tag: "Button", godotClass: "Button", factory: "V.button", events: ["on_pressed", "on_button_down", "on_button_up", "on_toggled"] },
  { tag: "CheckBox", godotClass: "CheckBox", factory: "V.check_box", events: ["on_pressed", "on_toggled"] },
  { tag: "CheckButton", godotClass: "CheckButton", factory: "V.check_button", events: ["on_toggled"] },
  { tag: "OptionButton", godotClass: "OptionButton", factory: "V.option_button", events: ["on_item_selected"] },
  { tag: "MenuButton", godotClass: "MenuButton", factory: "V.menu_button" },
  { tag: "LinkButton", godotClass: "LinkButton", factory: "V.link_button", events: ["on_pressed"] },
  { tag: "TextureButton", godotClass: "TextureButton", factory: "V.texture_button", events: ["on_pressed"] },
  { tag: "LineEdit", godotClass: "LineEdit", factory: "V.line_edit", events: ["on_text_changed", "on_text_submitted"] },
  { tag: "TextEdit", godotClass: "TextEdit", factory: "V.text_edit", events: ["on_text_changed"] },
  { tag: "CodeEdit", godotClass: "CodeEdit", factory: "V.code_edit" },
  { tag: "SpinBox", godotClass: "SpinBox", factory: "V.spin_box", events: ["on_value_changed"] },
  { tag: "HSlider", godotClass: "HSlider", factory: "V.h_slider", events: ["on_value_changed"] },
  { tag: "VSlider", godotClass: "VSlider", factory: "V.v_slider", events: ["on_value_changed"] },
  { tag: "ProgressBar", godotClass: "ProgressBar", factory: "V.progress_bar" },
  { tag: "ItemList", godotClass: "ItemList", factory: "V.item_list", events: ["on_item_selected"] },
  { tag: "Tree", godotClass: "Tree", factory: "V.tree", events: ["on_item_selected"] },
  { tag: "TabBar", godotClass: "TabBar", factory: "V.tab_bar", events: ["on_tab_changed"] },
];

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
