/**
 * Per-tag human content registry for the 32 Godot host elements.
 *
 * The machine-readable data (props, signals, events, factory, godotClass) comes
 * from `hostElements.ts` (injected at build time). This file supplies the
 * *human* layer: a short blurb, a realistic `.guitkx` usage snippet, an optional
 * GDScript snippet, a nav group, and search keywords.
 *
 * Snippets use React-parity event names (onClick / onChange / onSubmit / …).
 * Where a bundled demo under examples/demos exercises the control, the snippet is
 * adapted from that real demo so the docs stay honest.
 */

export type HostGroup = 'basic' | 'advanced'

export interface HostContent {
  /** 1–3 sentence description of the control. */
  blurb: string
  /** A realistic `.guitkx` usage snippet using React-parity event names. */
  guitkx: string
  /** Optional GDScript (factory-call) equivalent. */
  gd?: string
  /** Sidebar grouping. */
  group: HostGroup
  /** Search keywords. */
  keywords: string[]
}

export const HOST_CONTENT: Record<string, HostContent> = {
  // ── Containers & structure ────────────────────────────────────────────────
  Control: {
    blurb:
      'The base Control host — a bare, unstyled node you position and size yourself. Use it as an escape hatch when you need a raw Control (for a ref target, custom drawing, or manual layout) rather than a specialised container.',
    guitkx: `<Control ref={ area_ref } clip_contents style={ {"expand_h": true, "expand_v": true, "min_height": 320} } />`,
    group: 'basic',
    keywords: ['control', 'base', 'container', 'raw', 'ref'],
  },
  VBox: {
    blurb:
      'A vertical box container (Godot VBoxContainer). Lays its children out top-to-bottom, honouring their size flags. The `separation` style controls the gap between children.',
    guitkx: `<VBox style={ {"separation": 8} }>
  <Label text="First" />
  <Label text="Second" />
</VBox>`,
    group: 'basic',
    keywords: ['vbox', 'vertical', 'container', 'layout', 'stack', 'column'],
  },
  HBox: {
    blurb:
      'A horizontal box container (Godot HBoxContainer). Lays its children out left-to-right. Give a child `{"expand_h": true}` to make it grow into the remaining space.',
    guitkx: `<HBox style={ {"separation": 8} }>
  <Button text="  −1  " onClick={ func(): s[1].call(s[0] - 1) } />
  <Button text="  +1  " onClick={ func(): s[1].call(func(c): return c + 1) } />
</HBox>`,
    group: 'basic',
    keywords: ['hbox', 'horizontal', 'container', 'layout', 'row'],
  },
  Grid: {
    blurb:
      'A grid container (Godot GridContainer). Arranges children into a fixed number of columns, wrapping to a new row automatically. Set the column count via the `columns` property.',
    guitkx: `<Grid columns={ 3 } style={ {"h_separation": 6, "v_separation": 6} }>
  <Button text="1" />
  <Button text="2" />
  <Button text="3" />
  <Button text="4" />
</Grid>`,
    group: 'basic',
    keywords: ['grid', 'columns', 'container', 'layout'],
  },
  Margin: {
    blurb:
      'A margin container (Godot MarginContainer). Insets its single child by the configured margins. The `margin` style sets all four sides at once.',
    guitkx: `<Margin style={ {"margin": 20} }>
  <VBox style={ {"separation": 12} }>
    { children }
  </VBox>
</Margin>`,
    group: 'basic',
    keywords: ['margin', 'padding', 'inset', 'container', 'spacing'],
  },
  Panel: {
    blurb:
      'A panel container (Godot PanelContainer). Draws a themed background/border behind its child and clips to it — the go-to surface for cards, sidebars, and content areas.',
    guitkx: `<Panel style={ {"bg_color": Color(0.1, 0.1, 0.12), "min_width": 210} }>
  <Margin style={ {"margin": 8} }>
    { children }
  </Margin>
</Panel>`,
    group: 'basic',
    keywords: ['panel', 'card', 'surface', 'background', 'container'],
  },
  Center: {
    blurb:
      'A center container (Godot CenterContainer). Centres its single child both horizontally and vertically within the space it is given.',
    guitkx: `<Center style={ {"expand_h": true, "expand_v": true} }>
  <Label text="Centered content" />
</Center>`,
    group: 'basic',
    keywords: ['center', 'centre', 'container', 'align', 'middle'],
  },
  Scroll: {
    blurb:
      'A scroll container (Godot ScrollContainer). Adds scrollbars when its child overflows. Control each axis with `horizontal_scroll_mode` / `vertical_scroll_mode`.',
    guitkx: `<Scroll horizontal_scroll_mode={ ScrollContainer.SCROLL_MODE_DISABLED } style={ {"expand_v": true} }>
  <VBox style={ {"separation": 4} }>
    { buttons }
  </VBox>
</Scroll>`,
    group: 'basic',
    keywords: ['scroll', 'scrollview', 'overflow', 'scrollbar', 'container'],
  },
  Tabs: {
    blurb:
      'A tab container (Godot TabContainer). Shows one child at a time behind a strip of tabs, one tab per direct child. Use it for settings panes and multi-page layouts.',
    guitkx: `<Tabs>
  <VBox name="General">
    <Label text="General settings" />
  </VBox>
  <VBox name="Audio">
    <Label text="Audio settings" />
  </VBox>
</Tabs>`,
    group: 'basic',
    keywords: ['tabs', 'tabcontainer', 'pages', 'sections', 'container'],
  },

  // ── Display ───────────────────────────────────────────────────────────────
  Label: {
    blurb:
      'A text label (Godot Label). Renders a single run of plain text. Style it with `font_size`, `font_color`, and alignment properties.',
    guitkx: `<Label text={ "Count: %d" % s[0] } style={ {"font_size": 28} } />`,
    group: 'basic',
    keywords: ['label', 'text', 'caption', 'display'],
  },
  RichText: {
    blurb:
      'A rich-text label (Godot RichTextLabel). Renders BBCode markup — bold, colour, links, images, and more — when `bbcode_enabled` is true. Use it for formatted or multi-style text.',
    guitkx: `<RichText
  bbcode_enabled
  text="[b]Bold[/b] and [color=orange]coloured[/color] text"
  style={ {"expand_h": true} }
/>`,
    group: 'basic',
    keywords: ['richtext', 'bbcode', 'formatted', 'markup', 'text'],
  },
  ColorRect: {
    blurb:
      'A solid colour rectangle (Godot ColorRect). Fills its rect with a single flat `color` — handy for backgrounds, dividers, and lightweight visual blocks.',
    guitkx: `<ColorRect color={ Color(0.2, 0.4, 0.7) } style={ {"min_width": 40, "min_height": 40} } />`,
    group: 'basic',
    keywords: ['colorrect', 'rectangle', 'fill', 'background', 'color'],
  },
  TextureRect: {
    blurb:
      'A texture rectangle (Godot TextureRect). Draws a `texture` with configurable stretch and expand behaviour — the standard way to show an image in a layout.',
    guitkx: `<TextureRect
  texture={ my_texture }
  stretch_mode={ TextureRect.STRETCH_KEEP_ASPECT_CENTERED }
  style={ {"min_width": 96, "min_height": 96} }
/>`,
    group: 'basic',
    keywords: ['texturerect', 'image', 'texture', 'sprite', 'picture'],
  },
  HSeparator: {
    blurb:
      'A horizontal separator line (Godot HSeparator). A thin themed divider used to break up vertical stacks of content.',
    guitkx: `<VBox>
  <Label text="Section title" />
  <HSeparator />
  <Label text="Body content" />
</VBox>`,
    group: 'advanced',
    keywords: ['hseparator', 'divider', 'line', 'rule', 'separator'],
  },
  VSeparator: {
    blurb:
      'A vertical separator line (Godot VSeparator). A thin themed divider used between items laid out in a row.',
    guitkx: `<HBox style={ {"separation": 8} }>
  <Label text="Left" />
  <VSeparator />
  <Label text="Right" />
</HBox>`,
    group: 'advanced',
    keywords: ['vseparator', 'divider', 'line', 'rule', 'separator'],
  },

  // ── Buttons ───────────────────────────────────────────────────────────────
  Button: {
    blurb:
      'A clickable button (Godot Button). Fires `onClick` when pressed. Combine it with `use_state` to build controlled, interactive UI. This is the workhorse of the counter demo.',
    guitkx: `<Button text="  +1  " onClick={ func(): s[1].call(func(c): return c + 1) } />`,
    gd: `V.button({
  "text": "  +1  ",
  "onClick": func(): s[1].call(func(c): return c + 1),
})`,
    group: 'basic',
    keywords: ['button', 'click', 'press', 'action', 'onClick'],
  },
  CheckBox: {
    blurb:
      'A checkbox (Godot CheckBox). A toggleable button styled as a checkmark. Read its state from `button_pressed` and react to changes via `onChange`.',
    guitkx: `<CheckBox text="CheckBox" button_pressed={ on } onChange={ func(pressed): set_on.call(pressed) } />`,
    group: 'basic',
    keywords: ['checkbox', 'check', 'toggle', 'boolean', 'onChange'],
  },
  CheckButton: {
    blurb:
      'A check button (Godot CheckButton). Functionally a toggle rendered as an on/off switch. Same toggle semantics as CheckBox with a different visual affordance.',
    guitkx: `<CheckButton text="CheckButton" button_pressed={ on } onChange={ func(pressed): set_on.call(pressed) } />`,
    group: 'basic',
    keywords: ['checkbutton', 'switch', 'toggle', 'boolean', 'onChange'],
  },
  OptionButton: {
    blurb:
      'A dropdown selector (Godot OptionButton). Presents a popup list of items and reports the chosen index through `onChange`. Populate it with `items` and track the selection in state.',
    guitkx: `<OptionButton
  items={ ["Red", "Green", "Blue"] }
  selected={ index }
  onChange={ func(i): set_index.call(i) }
/>`,
    group: 'basic',
    keywords: ['optionbutton', 'dropdown', 'select', 'combobox', 'choices', 'onChange'],
  },
  MenuButton: {
    blurb:
      'A menu button (Godot MenuButton). A button that opens a popup menu. Configure its entries through the underlying `PopupMenu` (accessible via a ref) and handle selections there.',
    guitkx: `<MenuButton text="File" ref={ menu_ref } />`,
    group: 'advanced',
    keywords: ['menubutton', 'menu', 'popup', 'dropdown'],
  },
  LinkButton: {
    blurb:
      'A hyperlink-style button (Godot LinkButton). Renders as underlined text and fires `onClick` like a link. Good for inline navigation and secondary actions.',
    guitkx: `<LinkButton text="Learn more" onClick={ func(): open_docs.call() } />`,
    group: 'advanced',
    keywords: ['linkbutton', 'link', 'hyperlink', 'text button', 'onClick'],
  },
  TextureButton: {
    blurb:
      'An image button (Godot TextureButton). A button whose faces are textures rather than themed styles — set `texture_normal`, `texture_pressed`, `texture_hover`, and handle `onClick`.',
    guitkx: `<TextureButton
  texture_normal={ icon_normal }
  texture_hover={ icon_hover }
  onClick={ func(): activate.call() }
/>`,
    group: 'advanced',
    keywords: ['texturebutton', 'icon button', 'image button', 'onClick'],
  },

  // ── Text input ────────────────────────────────────────────────────────────
  LineEdit: {
    blurb:
      'A single-line text input (Godot LineEdit). Drive it as a controlled input: bind `text` to state and push edits back through `onChange`; `onSubmit` fires when the user presses Enter.',
    guitkx: `<LineEdit
  text={ s[0] }
  placeholder_text="Type something…"
  onChange={ func(t): s[1].call(t) }
/>`,
    gd: `V.line_edit({
  "text": s[0],
  "placeholder_text": "Type something…",
  "onChange": func(t): s[1].call(t),
})`,
    group: 'basic',
    keywords: ['lineedit', 'input', 'text field', 'textbox', 'onChange', 'onSubmit'],
  },
  TextEdit: {
    blurb:
      'A multi-line text editor (Godot TextEdit). Use it for paragraphs, notes, and free-form text. Bind `text` to state and listen for edits via `onChange`.',
    guitkx: `<TextEdit
  text={ s[0] }
  onChange={ func(): s[1].call(edit_ref["current"].text) }
  style={ {"min_height": 120} }
/>`,
    group: 'basic',
    keywords: ['textedit', 'multiline', 'textarea', 'editor', 'onChange'],
  },
  CodeEdit: {
    blurb:
      'A code editor (Godot CodeEdit). A TextEdit specialised for source code — gutters, line numbers, syntax highlighting, and code completion hooks. Use it for in-app scripting or config editing.',
    guitkx: `<CodeEdit
  text={ source }
  gutters_draw_line_numbers
  onChange={ func(): set_source.call(code_ref["current"].text) }
  style={ {"min_height": 200} }
/>`,
    group: 'advanced',
    keywords: ['codeedit', 'code', 'editor', 'syntax', 'highlighting', 'onChange'],
  },
  SpinBox: {
    blurb:
      'A numeric stepper (Godot SpinBox). Combines a value field with up/down arrows. Bind `value` to state and read the new number from `onChange`; constrain it with `min_value` / `max_value` / `step`.',
    guitkx: `<SpinBox
  min_value={ 0 } max_value={ 100 } step={ 1 }
  value={ n }
  onChange={ func(v): set_n.call(v) }
/>`,
    group: 'basic',
    keywords: ['spinbox', 'number', 'numeric', 'stepper', 'increment', 'onChange'],
  },

  // ── Range controls ────────────────────────────────────────────────────────
  HSlider: {
    blurb:
      'A horizontal slider (Godot HSlider). Lets the user pick a value in a range by dragging. Bind `value` to state and read the new value from `onChange`; set the range with `min_value` / `max_value`.',
    guitkx: `<HSlider
  min_value={ 0 } max_value={ 100 }
  value={ v[0] }
  onChange={ func(x): v[1].call(x) }
  style={ {"min_width": 220} }
/>`,
    gd: `V.hslider({
  "min_value": 0, "max_value": 100,
  "value": v[0],
  "onChange": func(x): v[1].call(x),
  "style": {"min_width": 220},
})`,
    group: 'basic',
    keywords: ['hslider', 'slider', 'range', 'drag', 'value', 'onChange'],
  },
  VSlider: {
    blurb:
      'A vertical slider (Godot VSlider). The vertical counterpart to HSlider — same range/value semantics, laid out top-to-bottom. Bind `value` to state and read edits from `onChange`.',
    guitkx: `<VSlider
  min_value={ 0 } max_value={ 100 }
  value={ v[0] }
  onChange={ func(x): v[1].call(x) }
  style={ {"min_height": 220} }
/>`,
    group: 'basic',
    keywords: ['vslider', 'slider', 'range', 'vertical', 'value', 'onChange'],
  },
  ProgressBar: {
    blurb:
      'A progress bar (Godot ProgressBar). A read-only range display that fills proportionally to `value` between `min_value` and `max_value`. Use it for loading and completion indicators.',
    guitkx: `<ProgressBar min_value={ 0 } max_value={ 100 } value={ v[0] } style={ {"min_width": 260} } />`,
    group: 'basic',
    keywords: ['progressbar', 'progress', 'loading', 'bar', 'range'],
  },

  // ── Collections ───────────────────────────────────────────────────────────
  ItemList: {
    blurb:
      'A selectable list (Godot ItemList). Renders a flat, scrollable list of items; declare rows declaratively via `items` and react to selection with `onChange`.',
    guitkx: `<ItemList
  items={ ["Apple", "Banana", "Cherry", "Date"] }
  onChange={ func(index): set_selected.call(index) }
  style={ {"min_height": 90} }
/>`,
    group: 'basic',
    keywords: ['itemlist', 'list', 'selection', 'listview', 'onChange'],
  },
  Tree: {
    blurb:
      'A hierarchical tree (Godot Tree). Renders nested, expandable rows. Pass a declarative `items` model of nodes with `children`; expansion state is preserved across re-renders. React to selection with `onChange`.',
    guitkx: `<Tree hide_root items={ [
  { "id": "fruit", "text": "🍎 Fruit", "children": [
    { "id": "apple", "text": "Apple" },
    { "id": "pear", "text": "Pear" },
  ] },
  { "id": "veg", "text": "🥕 Veg", "children": [
    { "id": "carrot", "text": "Carrot" },
  ] },
] } style={ {"min_height": 150} } />`,
    group: 'basic',
    keywords: ['tree', 'treeview', 'hierarchy', 'nested', 'expand', 'onChange'],
  },
  TabBar: {
    blurb:
      'A tab strip (Godot TabBar). Renders a row of tabs without managing page content itself — you drive which pane is visible from the `onChange` (tab index) callback. For automatic page switching, prefer the Tabs container.',
    guitkx: `<TabBar
  tabs={ ["General", "Audio", "Video"] }
  current_tab={ tab }
  onChange={ func(index): set_tab.call(index) }
/>`,
    group: 'basic',
    keywords: ['tabbar', 'tabs', 'strip', 'navigation', 'onChange'],
  },
}
