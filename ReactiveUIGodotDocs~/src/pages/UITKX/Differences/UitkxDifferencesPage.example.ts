export const UITKX_STATE_COUNTER_EXAMPLE = `@class_name StateCounterExample

component StateCounterExample() {
  var s = use_state(0)
  var count = s[0]
  var set_count = s[1]
  return (
    <VBox>
      <Label text={ "Count: %d" % count } />
      <Button text="Increment" onClick={ func(): set_count.call(func(prev): return prev + 1) } />
      <Button text="Reset" onClick={ func(): set_count.call(0) } />
    </VBox>
  )
}`
