// Code samples for the Assets page. Godot loads assets from res:// resource
// paths with preload() (compile-time) or load() (runtime) — there is no asset
// registry or USS url(). Resources are Texture2D / Font / Theme / StyleBox /
// AudioStream / PackedScene, used directly in .guitkx markup and style dicts.

export const EXAMPLE_BASIC = `@class_name Avatar

component Avatar(image_path) {
  # load() resolves a res:// path at runtime — good for a dynamic path prop.
  var tex = load(image_path)   # -> Texture2D
  return (
    <TextureRect texture={ tex } expand_mode={ TextureRect.EXPAND_IGNORE_SIZE }
                 style={ {"min_size": Vector2(64, 64)} } />
  )
}`

export const EXAMPLE_RELATIVE = `@class_name Card

component Card() {
  # preload() takes a constant res:// path and resolves at compile time — the
  # resource is baked into the export and there is no runtime disk hit.
  var bg   = preload("res://ui/images/card_bg.png")    # Texture2D
  var icon = preload("res://ui/images/icon.svg")       # Texture2D
  return (
    <Panel>
      <TextureRect texture={ bg } />
      <TextureRect texture={ icon } style={ {"min_size": Vector2(24, 24)} } />
    </Panel>
  )
}`

export const EXAMPLE_SHORTHAND = `@class_name Badge

component Badge() {
  # A texture works anywhere a Texture2D is expected: TextureRect.texture,
  # Button.icon, or the "icons" theme channel in a style dict.
  var star = preload("res://ui/star.svg")
  return (
    <Button text="Starred" icon={ star } onClick={ func(): print("clicked") } />
  )
}`

export const EXAMPLE_INLINE = `@class_name Logo

component Logo() {
  # preload() can be called inline in an attribute expression — no setup var.
  return (
    <TextureRect texture={ preload("res://ui/logo.png") } />
  )
}`

export const EXAMPLE_USS = `@class_name ThemedCard

# A Godot Theme resource is just another asset: preload it and hand it to a
# subtree via the "theme" prop. Every descendant inherits it.
component ThemedCard() {
  var theme = preload("res://ui/dark_theme.tres")
  return (
    <Panel theme={ theme }>
      <Label text="Styled by dark_theme.tres" />
      <Button text="OK" />
    </Panel>
  )
}`

export const EXAMPLE_FONT = `@class_name Heading

component Heading(title) {
  # Fonts are FontFile / FontVariation resources. Apply via the "font" and
  # "font_size" style shorthands (or the "fonts" theme channel for a named item).
  var display = preload("res://ui/Inter-Bold.ttf")
  return (
    <Label text={ title }
           style={ {"font": display, "font_size": 28, "font_color": Color.WHITE} } />
  )
}`

export const EXAMPLE_STYLEBOX = `@class_name Framed

component Framed() {
  # A hand-authored StyleBox resource can be dropped into the "styleboxes"
  # theme channel — or let RUIStyle build one from bg_color/border/pad for you.
  var frame = preload("res://ui/frame.stylebox.tres")
  return (
    <Panel style={ {"styleboxes": {"panel": frame}} }>
      <Label text="Framed by a .tres StyleBox" />
    </Panel>
  )
}`

export const EXAMPLE_AUDIO = `@class_name Chime

component Chime() {
  # AudioStream resources drive the AudioStreamPlayer element (V.audio factory).
  var stream = preload("res://sfx/chime.ogg")
  return (
    { V.audio({ "stream": stream, "autoplay": true }) }
  )
}`
