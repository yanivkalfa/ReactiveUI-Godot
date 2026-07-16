export const UITKX_SIGNALS_COMPONENT_EXAMPLE = `component SignalCounterDemo() {
  // Read the PROCESS-WIDE signal registered under "demo.counter".
  // useSignalKey lazily creates one shared RUISignal per key, so every
  // component that reads the same key sees the same store.
  var count = useSignalKey("demo.counter", 0)

  return (
    <VBoxContainer style={ {"separation": 8} }>
      <Label text="Signal Counter" />
      <Label text={ "Count: %d" % count } />
      <HBoxContainer style={ {"separation": 8} }>
        // update() takes a func(old) -> new. set_value(x) sets directly.
        <Button text="Increment"
                onPressed={ func(): RUISignals.get_or_create("demo.counter").update(func(v): return v + 1) } />
        <Button text="Reset"
                onPressed={ func(): RUISignals.get_or_create("demo.counter").set_value(0) } />
      </HBoxContainer>
    </VBoxContainer>
  )
}`

export const UITKX_SIGNALS_INSTANCE_EXAMPLE = `@class_name PlayerHud

# A signal is just a value store that lives OUTSIDE the component tree.
# Create one anywhere and share the instance (e.g. an autoload or a static).
module {
  static var player := RUISignal.new({ "hp": 100, "name": "Rin" })
}

component PlayerHud() {
  // Subscribe with a SELECTOR: re-render only when the selected slice changes.
  // Editing name won't re-render this component; changing hp will.
  var hp = useSignal(PlayerHud.player, func(s): return s["hp"])

  return (
    <Label text={ "HP: %d" % hp } />
  )
}`

export const UITKX_SIGNALS_RUNTIME_EXAMPLE = `# Outside of components, work with the signal directly.
var counter := RUISignals.get_or_create("demo.counter", 0)
counter.update(func(previous): return previous + 1)

# Subscribe imperatively; the returned Callable unsubscribes.
var unsub := counter.subscribe(func(v): print("counter is now ", v))
# ... later ...
unsub.call()

# On a full session reset (e.g. returning to the main menu), drop keyed state:
RUISignals.clear()`
