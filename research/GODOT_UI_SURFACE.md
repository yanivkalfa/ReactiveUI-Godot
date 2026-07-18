# Godot UI surface (auto-dumped from ClassDB + ThemeDB)

Control-derived classes: 76 total, 60 instantiable.

## Instantiable controls (the host elements to support)

- `AspectRatioContainer` (extends `Container`)
- `BaseButton` (extends `Control`)
- `BoxContainer` (extends `Container`)
- `Button` (extends `BaseButton`)
- `CenterContainer` (extends `Container`)
- `CheckBox` (extends `Button`)
- `CheckButton` (extends `Button`)
- `CodeEdit` (extends `TextEdit`)
- `ColorPicker` (extends `VBoxContainer`)
- `ColorPickerButton` (extends `Button`)
- `ColorRect` (extends `Control`)
- `Container` (extends `Control`)
- `Control` (extends `CanvasItem`)
- `FlowContainer` (extends `Container`)
- `FoldableContainer` (extends `Container`)
- `GraphEdit` (extends `Control`)
- `GraphElement` (extends `Container`)
- `GraphFrame` (extends `GraphElement`)
- `GraphNode` (extends `GraphElement`)
- `GridContainer` (extends `Container`)
- `HBoxContainer` (extends `BoxContainer`)
- `HFlowContainer` (extends `FlowContainer`)
- `HScrollBar` (extends `ScrollBar`)
- `HSeparator` (extends `Separator`)
- `HSlider` (extends `Slider`)
- `HSplitContainer` (extends `SplitContainer`)
- `ItemList` (extends `Control`)
- `Label` (extends `Control`)
- `LineEdit` (extends `Control`)
- `LinkButton` (extends `BaseButton`)
- `MarginContainer` (extends `Container`)
- `MenuBar` (extends `Control`)
- `MenuButton` (extends `Button`)
- `NinePatchRect` (extends `Control`)
- `OptionButton` (extends `Button`)
- `Panel` (extends `Control`)
- `PanelContainer` (extends `Container`)
- `ProgressBar` (extends `Range`)
- `Range` (extends `Control`)
- `ReferenceRect` (extends `Control`)
- `RichTextLabel` (extends `Control`)
- `ScrollContainer` (extends `Container`)
- `SpinBox` (extends `Range`)
- `SplitContainer` (extends `Container`)
- `SubViewportContainer` (extends `Container`)
- `TabBar` (extends `Control`)
- `TabContainer` (extends `Container`)
- `TextEdit` (extends `Control`)
- `TextureButton` (extends `BaseButton`)
- `TextureProgressBar` (extends `Range`)
- `TextureRect` (extends `Control`)
- `Tree` (extends `Control`)
- `VBoxContainer` (extends `BoxContainer`)
- `VFlowContainer` (extends `FlowContainer`)
- `VScrollBar` (extends `ScrollBar`)
- `VSeparator` (extends `Separator`)
- `VSlider` (extends `Slider`)
- `VSplitContainer` (extends `SplitContainer`)
- `VideoStreamPlayer` (extends `Control`)
- `VirtualJoystick` (extends `Control`)

## Abstract / base classes (not instantiable)

- `EditorDock` (extends `MarginContainer`)
- `EditorInspector` (extends `ScrollContainer`)
- `EditorProperty` (extends `Container`)
- `EditorResourcePicker` (extends `HBoxContainer`)
- `EditorScriptPicker` (extends `EditorResourcePicker`)
- `EditorSpinSlider` (extends `Range`)
- `EditorToaster` (extends `HBoxContainer`)
- `FileSystemDock` (extends `EditorDock`)
- `OpenXRBindingModifierEditor` (extends `PanelContainer`)
- `OpenXRInteractionProfileEditor` (extends `OpenXRInteractionProfileEditorBase`)
- `OpenXRInteractionProfileEditorBase` (extends `HBoxContainer`)
- `ScriptEditor` (extends `PanelContainer`)
- `ScriptEditorBase` (extends `VBoxContainer`)
- `ScrollBar` (extends `Range`)
- `Separator` (extends `Control`)
- `Slider` (extends `Range`)

## Control base properties (layout + common vocabulary)

- `custom_minimum_size`: Vector2 [suffix:px]
- `custom_maximum_size`: Vector2 [suffix:px]
- `propagate_maximum_size`: bool
- `clip_contents`: bool
- `layout_mode`: int [Position,Anchors,Container,Uncontrolled]
- `anchors_preset`: int [Custom:-1,Full Rect:15,Top Left:0,Top Right:1,Bottom Right:3,Bottom Left:2,Center Left:4,Center Top:5,Center Right:6,Center Bottom:7,Center:8,Left Wide:9,Top Wide:10,Right Wide:11,Bottom Wide:12,VCenter Wide:13,HCenter Wide:14]
- `anchor_left`: float [0,1,0.001,or_less,or_greater]
- `anchor_top`: float [0,1,0.001,or_less,or_greater]
- `anchor_right`: float [0,1,0.001,or_less,or_greater]
- `anchor_bottom`: float [0,1,0.001,or_less,or_greater]
- `offset_left`: float [-4096,4096,1,or_less,or_greater,suffix:px]
- `offset_top`: float [-4096,4096,1,or_less,or_greater,suffix:px]
- `offset_right`: float [-4096,4096,1,or_less,or_greater,suffix:px]
- `offset_bottom`: float [-4096,4096,1,or_less,or_greater,suffix:px]
- `grow_horizontal`: int [Left,Right,Both]
- `grow_vertical`: int [Top,Bottom,Both]
- `size`: Vector2 [suffix:px]
- `position`: Vector2 [suffix:px]
- `rotation`: float [-360,360,0.1,or_less,or_greater,radians_as_degrees]
- `scale`: Vector2
- `pivot_offset`: Vector2 [suffix:px]
- `pivot_offset_ratio`: Vector2
- `size_flags_horizontal`: int [Fill:1,Expand:2,Shrink Center:4,Shrink End:8]
- `size_flags_vertical`: int [Fill:1,Expand:2,Shrink Center:4,Shrink End:8]
- `size_flags_stretch_ratio`: float [0,20,0.01,or_greater]
- `offset_transform_enabled`: bool
- `offset_transform_position`: Vector2 [suffix:px]
- `offset_transform_position_ratio`: Vector2
- `offset_transform_scale`: Vector2
- `offset_transform_rotation`: float [-360,360,0.1,or_less,or_greater,radians_as_degrees]
- `offset_transform_pivot`: Vector2 [suffix:px]
- `offset_transform_pivot_ratio`: Vector2
- `offset_transform_visual_only`: bool
- `localize_numeral_system`: bool
- `layout_direction`: int [Inherited,Based on Application Locale,Left-to-Right,Right-to-Left,Based on System Locale]
- `translation_context`: StringName
- `tooltip_text`: String
- `tooltip_auto_translate_mode`: int [Inherit,Always,Disabled]
- `focus_neighbor_left`: NodePath [Control]
- `focus_neighbor_top`: NodePath [Control]
- `focus_neighbor_right`: NodePath [Control]
- `focus_neighbor_bottom`: NodePath [Control]
- `focus_next`: NodePath [Control]
- `focus_previous`: NodePath [Control]
- `focus_mode`: int [None,Click,All,Accessibility]
- `focus_behavior_recursive`: int [Inherited,Disabled,Enabled]
- `mouse_filter`: int [Stop,Pass (Propagate Up),Ignore]
- `mouse_behavior_recursive`: int [Inherited,Disabled,Enabled]
- `mouse_force_pass_scroll_events`: bool
- `mouse_default_cursor_shape`: int [Arrow,I-Beam,Pointing Hand,Cross,Wait,Busy,Drag,Can Drop,Forbidden,Vertical Resize,Horizontal Resize,Secondary Diagonal Resize,Main Diagonal Resize,Move,Vertical Split,Horizontal Split,Help]
- `shortcut_context`: Object [Node]
- `accessibility_name`: String
- `accessibility_description`: String
- `accessibility_live`: int [Off,Polite,Assertive]
- `accessibility_controls_nodes`: Array [NodePath]
- `accessibility_described_by_nodes`: Array [NodePath]
- `accessibility_labeled_by_nodes`: Array [NodePath]
- `accessibility_flow_to_nodes`: Array [NodePath]
- `theme`: Object [Theme]
- `theme_type_variation`: String

## Theme items per control type (the full 'styles' surface)

### BoxContainer
- constants: separation

### Button
- colors: font_color, font_disabled_color, font_focus_color, font_hover_color, font_hover_pressed_color, font_outline_color, font_pressed_color, icon_disabled_color, icon_focus_color, icon_hover_color, icon_hover_pressed_color, icon_normal_color, icon_pressed_color
- constants: align_to_largest_stylebox, h_separation, icon_max_width, outline_size
- fonts: font
- font_sizes: font_size
- styleboxes: disabled, focus, hover, normal, pressed

### CheckBox
- colors: checkbox_checked_color, checkbox_unchecked_color, font_color, font_disabled_color, font_focus_color, font_hover_color, font_hover_pressed_color, font_outline_color, font_pressed_color
- constants: check_v_offset, h_separation, outline_size
- fonts: font
- font_sizes: font_size
- icons: checked, checked_disabled, radio_checked, radio_checked_disabled, radio_unchecked, radio_unchecked_disabled, unchecked, unchecked_disabled
- styleboxes: disabled, focus, hover, hover_pressed, normal, pressed

### CheckButton
- colors: button_checked_color, button_unchecked_color, font_color, font_disabled_color, font_focus_color, font_hover_color, font_hover_pressed_color, font_outline_color, font_pressed_color
- constants: check_v_offset, h_separation, outline_size
- fonts: font
- font_sizes: font_size
- icons: checked, checked_disabled, checked_disabled_mirrored, checked_mirrored, unchecked, unchecked_disabled, unchecked_disabled_mirrored, unchecked_mirrored
- styleboxes: disabled, focus, hover, hover_pressed, normal, pressed

### CodeEdit
- colors: background_color, bookmark_color, brace_mismatch_color, breakpoint_color, caret_background_color, caret_color, code_folding_color, completion_background_color, completion_existing_color, completion_scroll_color, completion_scroll_hovered_color, completion_selected_color, current_line_color, executing_line_color, folded_code_region_color, font_color, font_outline_color, font_placeholder_color, font_readonly_color, font_selected_color, line_length_guideline_color, line_number_color, search_result_border_color, search_result_color, selection_color, word_highlighted_color
- constants: completion_lines, completion_max_width, completion_scroll_width, line_spacing, outline_size
- fonts: font
- font_sizes: font_size
- icons: bookmark, breakpoint, can_fold, can_fold_code_region, completion_color_bg, executing_line, folded, folded_code_region, folded_eol_icon, space, tab
- styleboxes: completion, focus, normal, read_only

### ColorPicker
- colors: focused_not_editing_cursor_color
- constants: center_slider_grabbers, h_width, label_width, margin, sv_height, sv_width
- icons: add_preset, bar_arrow, color_copy, color_hue, color_script, expanded_arrow, folded_arrow, menu_option, overbright_indicator, picker_cursor, picker_cursor_bg, sample_bg, sample_revert, screen_picker, shape_circle, shape_rect, shape_rect_wheel
- styleboxes: picker_focus_circle, picker_focus_rectangle, sample_focus

### ColorPickerButton
- colors: font_color, font_disabled_color, font_focus_color, font_hover_color, font_outline_color, font_pressed_color
- constants: h_separation, outline_size
- fonts: font
- font_sizes: font_size
- icons: bg
- styleboxes: disabled, focus, hover, normal, pressed

### FlowContainer
- constants: h_separation, v_separation

### FoldableContainer
- colors: collapsed_font_color, font_color, font_outline_color, hover_font_color
- constants: h_separation, outline_size
- fonts: font
- font_sizes: font_size
- icons: expanded_arrow, expanded_arrow_mirrored, folded_arrow, folded_arrow_mirrored
- styleboxes: focus, panel, title_collapsed_hover_panel, title_collapsed_panel, title_hover_panel, title_panel

### GraphEdit
- colors: activity, connection_hover_tint_color, connection_rim_color, connection_valid_target_tint_color, grid_major, grid_minor, selection_fill, selection_stroke
- constants: connection_hover_thickness, port_hotzone_inner_extent, port_hotzone_outer_extent
- icons: grid_toggle, layout, minimap_toggle, snapping_toggle, zoom_in, zoom_out, zoom_reset
- styleboxes: menu_panel, panel, panel_focus

### GraphFrame
- colors: resizer_color
- icons: resizer
- styleboxes: panel, panel_selected, titlebar, titlebar_selected

### GraphNode
- colors: resizer_color
- constants: port_h_offset, separation
- icons: port, resizer
- styleboxes: panel, panel_focus, panel_selected, slot, slot_selected, titlebar, titlebar_selected

### GridContainer
- constants: h_separation, v_separation

### HBoxContainer
- constants: separation

### HFlowContainer
- constants: h_separation, v_separation

### HScrollBar
- icons: decrement, decrement_highlight, decrement_pressed, increment, increment_highlight, increment_pressed
- styleboxes: grabber, grabber_highlight, grabber_pressed, scroll, scroll_focus

### HSeparator
- constants: separation
- styleboxes: separator

### HSlider
- constants: center_grabber, grabber_offset, tick_offset
- icons: grabber, grabber_disabled, grabber_highlight, tick
- styleboxes: grabber_area, grabber_area_highlight, slider

### HSplitContainer
- constants: autohide, minimum_grab_thickness, separation
- icons: grabber, touch_dragger
- styleboxes: split_bar_background

### ItemList
- colors: font_color, font_hovered_color, font_hovered_selected_color, font_outline_color, font_selected_color, guide_color, scroll_hint_color
- constants: h_separation, icon_margin, line_separation, outline_size, v_separation
- fonts: font
- font_sizes: font_size
- icons: scroll_hint
- styleboxes: cursor, cursor_unfocused, focus, hovered, hovered_selected, hovered_selected_focus, panel, selected, selected_focus

### Label
- colors: font_color, font_outline_color, font_shadow_color
- constants: line_spacing, outline_size, shadow_offset_x, shadow_offset_y, shadow_outline_size
- fonts: font
- font_sizes: font_size
- styleboxes: focus, normal

### LineEdit
- colors: caret_color, clear_button_color, clear_button_color_pressed, font_color, font_outline_color, font_placeholder_color, font_selected_color, font_uneditable_color, selection_color
- constants: caret_width, minimum_character_width, outline_size
- fonts: font
- font_sizes: font_size
- icons: clear
- styleboxes: focus, normal, read_only

### LinkButton
- colors: font_color, font_focus_color, font_hover_color, font_outline_color, font_pressed_color
- constants: outline_size, underline_spacing
- fonts: font
- font_sizes: font_size
- styleboxes: focus

### MarginContainer
- constants: margin_bottom, margin_left, margin_right, margin_top

### MenuBar
- colors: font_color, font_disabled_color, font_focus_color, font_hover_color, font_hover_pressed_color, font_outline_color, font_pressed_color
- constants: h_separation, outline_size
- fonts: font
- font_sizes: font_size
- styleboxes: disabled, hover, normal, pressed

### MenuButton
- colors: font_color, font_disabled_color, font_focus_color, font_hover_color, font_outline_color, font_pressed_color
- constants: h_separation, outline_size
- fonts: font
- font_sizes: font_size
- styleboxes: disabled, focus, hover, normal, pressed

### OptionButton
- colors: font_color, font_disabled_color, font_focus_color, font_hover_color, font_hover_pressed_color, font_outline_color, font_pressed_color
- constants: arrow_margin, h_separation, modulate_arrow, outline_size
- fonts: font
- font_sizes: font_size
- icons: arrow
- styleboxes: disabled, disabled_mirrored, focus, hover, hover_mirrored, normal, normal_mirrored, pressed, pressed_mirrored

### Panel
- styleboxes: panel

### PanelContainer
- styleboxes: panel

### ProgressBar
- colors: font_color, font_outline_color
- constants: outline_size
- fonts: font
- font_sizes: font_size
- styleboxes: background, fill

### RichTextLabel
- colors: default_color, font_outline_color, font_selected_color, font_shadow_color, selection_color, table_border, table_even_row_bg, table_odd_row_bg
- constants: line_separation, outline_size, paragraph_separation, shadow_offset_x, shadow_offset_y, shadow_outline_size, strikethrough_alpha, table_h_separation, table_v_separation, text_highlight_h_padding, text_highlight_v_padding, underline_alpha
- fonts: bold_font, bold_italics_font, italics_font, mono_font, normal_font
- font_sizes: bold_font_size, bold_italics_font_size, italics_font_size, mono_font_size, normal_font_size
- icons: horizontal_rule
- styleboxes: focus, normal

### ScrollContainer
- colors: scroll_hint_horizontal_color, scroll_hint_vertical_color
- icons: scroll_hint_horizontal, scroll_hint_vertical
- styleboxes: focus, panel

### SpinBox
- colors: down_disabled_icon_modulate, down_hover_icon_modulate, down_icon_modulate, down_pressed_icon_modulate, up_disabled_icon_modulate, up_hover_icon_modulate, up_icon_modulate, up_pressed_icon_modulate
- constants: buttons_vertical_separation, buttons_width, field_and_buttons_separation, set_min_buttons_width_from_icons
- icons: down, down_disabled, down_hover, down_pressed, up, up_disabled, up_hover, up_pressed, updown
- styleboxes: down_background, down_background_disabled, down_background_hovered, down_background_pressed, field_and_buttons_separator, up_background, up_background_disabled, up_background_hovered, up_background_pressed, up_down_buttons_separator

### SplitContainer
- colors: touch_dragger_color, touch_dragger_hover_color, touch_dragger_pressed_color
- constants: autohide, minimum_grab_thickness, separation
- icons: h_grabber, h_touch_dragger, v_grabber, v_touch_dragger
- styleboxes: split_bar_background

### TabBar
- colors: drop_mark_color, font_disabled_color, font_hovered_color, font_outline_color, font_selected_color, font_unselected_color, icon_disabled_color, icon_hovered_color, icon_selected_color, icon_unselected_color
- constants: h_separation, hover_switch_wait_msec, icon_max_width, outline_size
- fonts: font
- font_sizes: font_size
- icons: close, decrement, decrement_highlight, drop_mark, increment, increment_highlight
- styleboxes: button_highlight, button_pressed, tab_disabled, tab_focus, tab_hovered, tab_selected, tab_unselected

### TabContainer
- colors: drop_mark_color, font_disabled_color, font_hovered_color, font_outline_color, font_selected_color, font_unselected_color, icon_disabled_color, icon_hovered_color, icon_selected_color, icon_unselected_color
- constants: icon_max_width, icon_separation, outline_size, side_margin
- fonts: font
- font_sizes: font_size
- icons: decrement, decrement_highlight, drop_mark, increment, increment_highlight, menu, menu_highlight
- styleboxes: panel, tab_disabled, tab_focus, tab_hovered, tab_selected, tab_unselected, tabbar_background

### TextEdit
- colors: background_color, caret_background_color, caret_color, current_line_color, font_color, font_outline_color, font_placeholder_color, font_readonly_color, font_selected_color, search_result_border_color, search_result_color, selection_color, word_highlighted_color
- constants: caret_width, line_spacing, outline_size, wrap_offset
- fonts: font
- font_sizes: font_size
- icons: space, tab
- styleboxes: focus, normal, read_only

### Tree
- colors: children_hl_line_color, custom_button_font_highlight, drop_on_item_color, drop_position_color, font_color, font_disabled_color, font_hovered_color, font_hovered_dimmed_color, font_hovered_selected_color, font_outline_color, font_selected_color, guide_color, parent_hl_line_color, relationship_line_color, scroll_hint_color, title_button_color
- constants: button_margin, check_h_separation, children_hl_line_width, dragging_unfold_wait_msec, draw_guides, draw_relationship_lines, h_separation, icon_h_separation, icon_max_width, inner_item_margin_bottom, inner_item_margin_left, inner_item_margin_right, inner_item_margin_top, item_margin, outline_size, parent_hl_line_margin, parent_hl_line_width, relationship_line_width, scroll_border, scroll_speed, scrollbar_h_separation, scrollbar_margin_bottom, scrollbar_margin_left, scrollbar_margin_right, scrollbar_margin_top, scrollbar_v_separation, v_separation
- fonts: font, title_button_font
- font_sizes: font_size, title_button_font_size
- icons: arrow, arrow_collapsed, arrow_collapsed_mirrored, checked, checked_disabled, indeterminate, indeterminate_disabled, scroll_hint, select_arrow, unchecked, unchecked_disabled, updown
- styleboxes: button_hover, button_pressed, cursor, cursor_unfocused, custom_button, custom_button_hover, custom_button_pressed, focus, hovered, hovered_dimmed, hovered_selected, hovered_selected_focus, panel, selected, selected_focus, title_button_hover, title_button_normal, title_button_pressed

### VBoxContainer
- constants: separation

### VFlowContainer
- constants: h_separation, v_separation

### VScrollBar
- icons: decrement, decrement_highlight, decrement_pressed, increment, increment_highlight, increment_pressed
- styleboxes: grabber, grabber_highlight, grabber_pressed, scroll, scroll_focus

### VSeparator
- constants: separation
- styleboxes: separator

### VSlider
- constants: center_grabber, grabber_offset, tick_offset
- icons: grabber, grabber_disabled, grabber_highlight, tick
- styleboxes: grabber_area, grabber_area_highlight, slider

### VSplitContainer
- constants: autohide, minimum_grab_thickness, separation
- icons: grabber, touch_dragger
- styleboxes: split_bar_background

### VirtualJoystick
- styleboxes: normal_joystick, normal_tip, pressed_joystick, pressed_tip

