export const EVENTS_CLICK_EXAMPLE = `@class_name ClickDemo

component ClickDemo() {
  var msg = use_state("Click the button")

  return (
    <VBox style={ {"separation": 8} }>
      <Label text={ msg[0] } />
      <Button text="Click me"
              onClick={ func(): msg[1].call("Clicked!") } />
    </VBox>
  )
}`

export const EVENTS_POINTER_EXAMPLE = `@class_name PointerTracker

component PointerTracker() {
  var inside = use_state(false)

  return (
    // onPointerEnter -> mouse_entered, onPointerLeave -> mouse_exited.
    // (Godot fires these with no arguments, so the handler takes none.)
    <Panel style={ {"min_size": Vector2(240, 120), "pad": 12} }
           onPointerEnter={ func(): inside[1].call(true) }
           onPointerLeave={ func(): inside[1].call(false) }>
      <Label text={ "Pointer inside: %s" % inside[0] } />
    </Panel>
  )
}`

export const EVENTS_KEYBOARD_EXAMPLE = `@class_name KeyboardDemo

component KeyboardDemo() {
  var last = use_state("None")

  // Godot has no per-Control key signals; use the native gui_input escape
  // hatch (on_gui_input -> "gui_input") and inspect the InputEvent yourself.
  var on_key = func(event: InputEvent):
    if event is InputEventKey and event.pressed:
      last[1].call(OS.get_keycode_string(event.keycode))

  return (
    <VBox style={ {"separation": 8} }>
      <LineEdit placeholder_text="Type here" on_gui_input={ on_key } />
      <Label text={ "Last key: %s" % last[0] } />
    </VBox>
  )
}`

export const EVENTS_FOCUS_EXAMPLE = `@class_name FocusDemo

component FocusDemo() {
  var focused = use_state(false)

  // onFocus -> focus_entered, onBlur -> focus_exited.
  return (
    <LineEdit placeholder_text="Name"
              onFocus={ func(): focused[1].call(true) }
              onBlur={ func(): focused[1].call(false) }
              style={ {"border_color": Color.CYAN if focused[0] else Color.GRAY} } />
  )
}`

export const EVENTS_GEOMETRY_EXAMPLE = `@class_name ResizeWatcher

component ResizeWatcher() {
  var size = use_state(Vector2.ZERO)
  var box = use_ref(null)

  // onResize -> resized. The signal carries no argument, so read the size
  // off the node via a ref.
  var on_resized = func():
    if box["current"] != null:
      size[1].call(box["current"].size)

  return (
    <Panel ref={ box } style={ {"expand_h": true, "min_size": Vector2(0, 120)} }
           onResize={ on_resized }>
      <Label text={ "Size: %d x %d" % [size[0].x, size[0].y] } />
    </Panel>
  )
}`

export const EVENTS_CHANGE_EXAMPLE = `// onChange is POLYMORPHIC — it binds to whichever value/selection signal the
// control actually has (value_changed / text_changed / item_selected /
// tab_changed / toggled). The first matching signal wins, so one React name
// works across control types. Each Godot signal passes its own argument.

// CheckButton — onChange binds to "toggled", which passes the new bool.
<CheckButton text="Enable" button_pressed={ enabled }
             onChange={ func(on): set_enabled.call(on) } />

// HSlider — onChange binds to "value_changed", which passes the new float.
<HSlider min_value={ 0 } max_value={ 100 } value={ volume }
         onChange={ func(v): set_volume.call(v) } />

// OptionButton — onChange binds to "item_selected", which passes the index.
<OptionButton items={ ["Low", "Medium", "High"] } selected={ quality }
              onChange={ func(idx): set_quality.call(idx) } />

// LineEdit — onChange binds to "text_changed", which passes the new String.
// (onInput is an explicit alias for "text_changed" when you want to be clear.)
<LineEdit text={ name } onInput={ func(s): set_name.call(s) } />`

export const EVENTS_SUBMIT_EXAMPLE = `@class_name SearchBox

component SearchBox() {
  var query = use_state("")
  var submitted = use_state("")

  return (
    <VBox style={ {"separation": 8} }>
      // onSubmit -> text_submitted, fired on Enter. It passes the final text.
      <LineEdit text={ query[0] }
                onInput={ func(s): query[1].call(s) }
                onSubmit={ func(s): submitted[1].call(s) } />
      <Label text={ "Searched for: %s" % submitted[0] } />
    </VBox>
  )
}`

export const EVENTS_NATIVE_EXAMPLE = `@class_name NativeEscapeHatch

component NativeEscapeHatch() {
  // The on_<signal> escape hatch binds VERBATIM to any Godot signal on the
  // node — no alias table, no polymorphism. Use it to reach signals the React
  // aliases don't cover.
  var menu_items = [
    { "text": "New",  "id": 1 },
    { "text": "Open", "id": 2 },
    { "text": "Quit", "id": 3 },
  ]

  return (
    <VBox style={ {"separation": 8} }>
      // PopupMenu emits "id_pressed"; there is no React alias, so bind natively.
      <PopupMenu items={ menu_items }
                 on_id_pressed={ func(id): print("menu id ", id) } />

      // A Tree emits "item_activated" (double-click / Enter) — native only.
      <Tree on_item_activated={ func(): print("row activated") } />

      // Any signal at all: reach the raw InputEvent stream with on_gui_input.
      <ColorRect color={ Color.DARK_SLATE_BLUE }
                 on_gui_input={ func(e): print("gui input: ", e) } />
    </VBox>
  )
}`
