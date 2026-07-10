// Code samples for the Styling page. Godot has no USS/CSS — styling is a plain
// `style={ { … } }` Dictionary (RUIStyle) plus an optional named-bundle layer
// (RUIStyleSheet + `classes`). All markup is .guitkx; all setup code is GDScript.

export const EXAMPLE_IMPORT = `# Nothing to import. RUIStyle reads the \`style\` Dictionary on any host
# element automatically — the class_names V, Hooks, ReactiveRoot,
# RUIStyle and RUIStyleSheet are globally available once the addon is enabled.

<Label text="Hello" style={ {"font_size": 20, "font_color": Color.WHITE} } />`

export const EXAMPLE_BOTH_APIs = `# 1. Inline dict — the everyday form.
<PanelContainer style={ {"bg_color": Color(0.16, 0.17, 0.24), "corner_radius_all": 10, "content_margin_all": 16} } />

# 2. A shared style constant — the GDScript analogue of a reusable style module.
#    Declare it once in a *.style.gd file, reference it from many components.
#    (styling.style.gd)
class_name CardStyle
extends RefCounted
static var PANEL := { "bg_color": Color(0.16, 0.17, 0.24), "corner_radius_all": 10, "content_margin_all": 16 }

# then, in markup:
<PanelContainer style={ CardStyle.PANEL } />

# 3. Named bundles via RUIStyleSheet + the \`classes\` prop (see below).
<PanelContainer classes={ ["card"] } style={ {"content_margin_all": 20} } />   # inline style wins last`

export const EXAMPLE_CONDITIONAL = `# A style dict is a plain GDScript Dictionary — build it with any expression.
var is_hovered = useState(false)
var is_enabled = useState(true)

var button_style = {
    "bg_color": Color(0.3, 0.85, 0.45) if is_hovered[0] else Color(0.2, 0.2, 0.25),
    "corner_radius_all": 8,
    "content_margin_all": 12,
    "modulate": Color(1, 1, 1, 1.0 if is_enabled[0] else 0.5),
}

return (
    <Button text="Save" style={ button_style } disabled={ not is_enabled[0] } />
)`

export const EXAMPLE_INLINE = `# The style dict can be written inline in the attribute — no setup variable needed.
<Label text="Hello"
       style={ {"font_color": Color.GREEN, "font_size": 18} } />`

// ── RUIStyleSheet — named style bundles (the \`classes\` layer) ─────────────────
// These four were the "USS Stylesheets" examples on the Unity page; on Godot the
// equivalent is RUIStyleSheet: register a name -> style dict, then reference it
// through the \`classes\` prop. There is NO selector matching / cascade — just an
// ordered dictionary merge (bundles left-to-right, inline \`style\` wins last).

export const EXAMPLE_USS_BASIC = `# Register named style bundles once (e.g. in an autoload or before mount).
RUIStyleSheet.register("card", {
    "bg_color": Color(0.15, 0.15, 0.18),
    "corner_radius_all": 8,
    "content_margin_all": 12,
})

# Reference the bundle by name via the \`classes\` prop.
component Card() {
  return (
    <PanelContainer classes={ ["card"] }>
      <Label text="Styled by the 'card' bundle" style={ {"font_color": Color.WHITE} } />
    </PanelContainer>
  )
}`

export const EXAMPLE_USS_FILE = `# Bulk-register a whole { name -> style } map with RUIStyleSheet.merge().
# Later keys overwrite earlier ones. A good place: an autoload's _ready().
RUIStyleSheet.merge({
    "card":    { "bg_color": Color(0.12, 0.12, 0.14), "corner_radius_all": 8, "content_margin_all": 12 },
    "title":   { "font_size": 18, "font_color": Color.WHITE },
    "danger":  { "font_color": Color.RED },
    "muted":   { "font_color": Color(0.6, 0.6, 0.6) },
})`

export const EXAMPLE_USS_MULTIPLE = `# The \`classes\` prop takes an Array — bundles merge left-to-right, so later
# names override earlier ones for any keys they share.
component ThemedPanel() {
  return (
    <PanelContainer classes={ ["card", "danger"] }>
      <Label classes={ ["title"] } text="card + danger (danger's font_color wins)" />
    </PanelContainer>
  )
}`

export const EXAMPLE_USS_COMBINED = `# Bundles handle the shared baseline; inline \`style\` handles dynamic, per-render
# values and always wins last in the merge.
component Card(is_selected) {
  var highlight = {
      "border_color": Color(0, 0.67, 1) if is_selected else Color(0, 0, 0, 0),
      "border_width_all": 2,
  }
  return (
    <PanelContainer classes={ ["card"] } style={ highlight }>
      <Label text="Baseline from 'card', border from inline style" />
    </PanelContainer>
  )
}`
