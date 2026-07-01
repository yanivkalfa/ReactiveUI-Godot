export const HOOKS_USESTATE_EXAMPLE = `@class_name CounterDemo

component CounterDemo() {
  # use_state returns [value, setter]. Destructure by index.
  var count = use_state(0)

  # Direct value:            count[1].call(5)
  # Functional updater:      count[1].call(func(c): return c + 1)   # reads latest state

  return (
    <VBox>
      <Label text={ "Count: %d" % count[0] } />
      <Button text="Increment" onClick={ func(): count[1].call(count[0] + 1) } />
      <Button text="Double" onClick={ func(): count[1].call(func(c): return c * 2) } />
    </VBox>
  )
}`

export const HOOKS_USEREDUCER_EXAMPLE = `@class_name ReducerDemo

component ReducerDemo() {
  # reducer(state, action) -> new_state. Actions are just values (here: String).
  var reducer = func(state, action):
    match action:
      "inc": return state + 1
      "dec": return state - 1
      "reset": return 0
    return state

  # use_reducer returns [state, dispatch].
  var r = use_reducer(reducer, 0)

  return (
    <VBox>
      <Label text={ "Count: %d" % r[0] } />
      <Button text="+" onClick={ func(): r[1].call("inc") } />
      <Button text="-" onClick={ func(): r[1].call("dec") } />
      <Button text="Reset" onClick={ func(): r[1].call("reset") } />
    </VBox>
  )
}`

export const HOOKS_USEEFFECT_EXAMPLE = `@class_name EffectDemo

component EffectDemo() {
  var seconds = use_state(0)

  # [] => run once on mount. The effect returns a cleanup Callable (run on unmount).
  var tick = func():
    var timer := Engine.get_main_loop().create_timer(1.0)
    var running := [true]
    var loop := func():
      while running[0]:
        await Engine.get_main_loop().create_timer(1.0).timeout
        if running[0]:
          seconds[1].call(func(s): return s + 1)
    loop.call()
    return func(): running[0] = false   # cleanup

  use_effect(tick, [])

  return (<Label text={ "Elapsed: %ds" % seconds[0] } />)
}`

export const HOOKS_USELAYOUTEFFECT_EXAMPLE = `@class_name LayoutMeasure

component LayoutMeasure() {
  var el_ref = use_ref(null)     # Control ref box
  var width = use_state(0.0)

  # Runs synchronously during commit, before the frame paints.
  var measure = func():
    if el_ref["current"] != null:
      width[1].call(el_ref["current"].size.x)
    return Callable()
  use_layout_effect(measure, [])

  return (
    <VBox ref={ el_ref }>
      <Label text={ "Width: %dpx" % width[0] } />
    </VBox>
  )
}`

export const HOOKS_USEMEMO_EXAMPLE = `@class_name ExpensiveList

component ExpensiveList() {
  var filter = use_state("")
  var items = use_state(get_all_items())   # an Array

  # Recomputes only when filter or items change (shallow dep compare).
  var filtered = use_memo(func():
    return items[0].filter(func(i): return filter[0] in i),
    [filter[0], items[0]])

  return (
    <VBox>
      <LineEdit text={ filter[0] } onChange={ func(t): filter[1].call(t) } />
      @for (item in filtered) {
        <Label text={ item } key={ item } />
      }
    </VBox>
  )
}`

export const HOOKS_USECALLBACK_EXAMPLE = `@class_name StableCallback

component StableCallback() {
  var count = use_state(0)

  # Returns a Callable whose identity is stable while deps are unchanged.
  var get_count = use_callback(func(): return count[0], [count[0]])

  return (
    <VBox>
      <Label text={ "Count: %d" % get_count.call() } />
      <Button text="Increment" onClick={ func(): count[1].call(count[0] + 1) } />
    </VBox>
  )
}`

export const HOOKS_USEREF_EXAMPLE = `@class_name RefDemo

component RefDemo() {
  # Mutable value ref — persists across renders, no re-render on change.
  var render_count = use_ref(0)
  render_count["current"] += 1

  # Control ref — gives access to the underlying Godot node after commit.
  var label_ref = use_ref(null)

  var log_name = func():
    if label_ref["current"] != null:
      print("Label node: ", label_ref["current"].name)
    return Callable()
  use_effect(log_name, [])

  return (
    <VBox>
      <Label ref={ label_ref }
             text={ "This component rendered %d time(s)" % render_count["current"] } />
    </VBox>
  )
}`

export const HOOKS_CONTEXT_EXAMPLE = `# Provider component
@class_name ThemeProvider

component ThemeProvider() {
  Hooks.provide_context("theme", "dark")

  return (
    <VBox>
      <ThemedCard />
    </VBox>
  )
}

# Consumer component — any depth in the subtree
@class_name ThemedCard

component ThemedCard() {
  var theme = use_context("theme")   # "dark"

  return (
    <Panel style={ {
      "bg_color": Color.BLACK if theme == "dark" else Color.WHITE,
      "pad": 12,
    } }>
      <Label text={ "Theme: %s" % theme } />
    </Panel>
  )
}`

export const HOOKS_STABLE_EXAMPLE = `@class_name EventOptimization

component EventOptimization() {
  var name = use_state("")

  # use_stable_action wraps a 1-arg callback with a stable identity that always
  # calls through to the latest closure body.
  var on_name_changed = use_stable_action(func(v): name[1].call(v))

  # use_stable_callback for 0-arg callbacks.
  var on_reset = use_stable_callback(func(): name[1].call(""))

  return (
    <VBox>
      <LineEdit text={ name[0] } onChange={ on_name_changed } />
      <Button text="Reset" onClick={ on_reset } />
    </VBox>
  )
}`

export const HOOKS_DEFERRED_EXAMPLE = `@class_name SearchResults

component SearchResults() {
  var query = use_state("")

  # Deferred value lags one frame behind: the LineEdit updates immediately while
  # the expensive ResultsList catches up at low priority next frame.
  var deferred_query = use_deferred_value(query[0])

  return (
    <VBox>
      <LineEdit text={ query[0] } onChange={ func(t): query[1].call(t) } />
      <ResultsList filter={ deferred_query } />
    </VBox>
  )
}`

export const HOOKS_IMPERATIVE_EXAMPLE = `@class_name FancyInput

component FancyInput(handle_ref) {
  var input_ref = use_ref(null)
  var val = use_state("")

  # Build a handle Dictionary of imperative methods, memoized until deps change.
  var handle = use_imperative_handle(func(): return {
    "focus": func():
      if input_ref["current"] != null: input_ref["current"].grab_focus(),
    "clear": func(): val[1].call(""),
  }, [])

  # Publish the handle to the parent's ref box.
  var publish = func():
    if handle_ref != null:
      handle_ref["current"] = handle
    return Callable()
  use_layout_effect(publish, [handle])

  return (<LineEdit ref={ input_ref } text={ val[0] }
                    onChange={ func(t): val[1].call(t) } />)
}`

export const HOOKS_DEPENDENCY_RULES = `# deps == null  ->  runs cleanup + effect EVERY commit
use_effect(func(): ... return cleanup)

# empty array [] -> runs once on mount, cleanup on unmount
use_effect(func(): ... return cleanup, [])

# with deps    ->  runs when any dep changes (shallow, == value comparison)
use_effect(func(): ... return cleanup, [dep1, dep2])

# The effect body may return a Callable cleanup (or Callable() for none).
# Dependency comparison is shallow value-equality (==) per element.`
