export const CONTEXT_HANDLE_API = `# Create a context handle (React parity for createContext). Declare it once, at
# module scope, and share the SAME handle between provider and consumers.
Hooks.createContext(default_value = null, name = "") -> RUIContext

# Provide a value for all descendants (call inside a component's setup body).
Hooks.provideContext(handle_or_key, value) -> void

# Consume the nearest provided value above; returns the handle's default when
# no ancestor provides it. (String keys return null when unprovided.)
Hooks.useContext(handle_or_key)   # auto-prefixed to Hooks.useContext in .guitkx`

export const CONTEXT_HANDLE_EXAMPLE = `# app_contexts.gd — declare the handle ONCE, at module scope, so every file
# references the same object. Its identity is the map key, so it can never
# collide with an unrelated feature that happens to also use "theme".
class_name AppContexts
extends RefCounted

# The argument is the DEFAULT returned by useContext(Theme) when unprovided.
static var Theme: RUIContext = Hooks.createContext({ "accent": Color.CYAN }, "Theme")

# ── Provider ────────────────────────────────────────────────
@class_name AppRoot

component AppRoot(my_theme: Dictionary) {
  # Pass the HANDLE (not a string) plus the value.
  Hooks.provideContext(AppContexts.Theme, my_theme)

  return (
    <VBox>
      <Toolbar />
    </VBox>
  )
}

# ── Consumer ────────────────────────────────────────────────
@class_name Toolbar

component Toolbar() {
  # Pass the same handle. Returns my_theme, or the handle's default if no
  # AppRoot provided one above this component.
  var theme = Hooks.useContext(AppContexts.Theme)

  return (
    <Panel style={ {"bg_color": theme["accent"]} }>
      <Label text="Toolbar" />
    </Panel>
  )
}`

export const CONTEXT_HANDLE_MODULE_EXAMPLE = `# Idiomatic single-file form: the handle lives in a module alongside the
# component that owns it, created with an inline default value.
module ThemePanel {
  const Theme = Hooks.createContext({ "accent": Color.CYAN }, "Theme")
}

@class_name ThemePanel

component ThemePanel(accent: Color = Color.MAGENTA) {
  # Provide overrides the default for this subtree.
  Hooks.provideContext(ThemePanel.Theme, { "accent": accent })

  return (
    <VBox>
      <AccentDot />
    </VBox>
  )
}

@class_name AccentDot

component AccentDot() {
  # If no ThemePanel provided a value above, this returns { "accent": Color.CYAN }
  # — the handle's default — rather than null.
  var theme = Hooks.useContext(ThemePanel.Theme)

  return (
    <Panel style={ {"bg_color": theme["accent"], "min_size": Vector2(16, 16)} } />
  )
}`

export const CONTEXT_BASIC_EXAMPLE = `# Provider — makes a value available to all descendants
@class_name AppRoot

component AppRoot() {
  Hooks.provideContext("user_name", "Alice")
  Hooks.provideContext("theme", "dark")

  return (
    <VBox>
      <Sidebar />
      <MainContent />
    </VBox>
  )
}

# Consumer — reads the value anywhere in the subtree
@class_name Sidebar

component Sidebar() {
  var user_name = useContext("user_name")
  var theme = useContext("theme")

  return (
    <Panel style={ {"bg_color": Color("#1e1e1e") if theme == "dark" else Color.WHITE} }>
      <Label text={ "Logged in as %s" % user_name } />
    </Panel>
  )
}`

export const CONTEXT_SHADOWING_EXAMPLE = `@class_name OuterProvider

component OuterProvider() {
  Hooks.provideContext("theme", "light")

  return (
    <VBox>
      <Label text={ useContext("theme") } />   # "light"
      <InnerProvider />
    </VBox>
  )
}

@class_name InnerProvider

component InnerProvider() {
  Hooks.provideContext("theme", "dark")   # shadows outer

  return (
    <VBox>
      <Label text={ useContext("theme") } />   # "dark"
    </VBox>
  )
}`

export const CONTEXT_DYNAMIC_EXAMPLE = `@class_name ThemeToggle

component ThemeToggle() {
  var dark = useState(true)
  Hooks.provideContext("theme", "dark" if dark[0] else "light")

  return (
    <VBox>
      <CheckButton text="Dark mode" button_pressed={ dark[0] }
                   onChange={ func(pressed): dark[1].call(pressed) } />
      <ThemedPanel />
    </VBox>
  )
}

@class_name ThemedPanel

component ThemedPanel() {
  var theme = useContext("theme")
  # Automatically re-renders when the provided value changes

  return (
    <Panel style={ {
      "bg_color": Color("#1e1e1e") if theme == "dark" else Color.WHITE,
      "pad": 16,
    } }>
      <Label text={ "Current theme: %s" % theme } />
    </Panel>
  )
}`

export const CONTEXT_VS_SIGNALS = `# Use context when:
# - Data is scoped to a subtree (e.g., theme for a panel)
# - Different parts of the tree need different values
# - Provider/consumer relationship is 1-to-many within a branch

# Use signals (RUISignal / useSignalKey) when:
# - Data is truly global (e.g., user session, app-wide settings)
# - Multiple independent trees need the same value
# - You want process-wide reactivity without a component hierarchy`

export const CONTEXT_TYPED_EXAMPLE = `# Predefined context keys as constants, kept in a small companion .gd module.
# (The component/module grammar has no class-level 'const', so shared keys live
# in a plain script and .guitkx components reference it by class_name.)
class_name AppContextKeys
extends RefCounted

const THEME := "app.theme"
const LOCALE := "app.locale"
const AUTH := "app.auth"

# Provider
@class_name AppShell

component AppShell(current_theme, auth_state) {
  Hooks.provideContext(AppContextKeys.THEME, current_theme)
  Hooks.provideContext(AppContextKeys.LOCALE, "en-US")
  Hooks.provideContext(AppContextKeys.AUTH, auth_state)
  # ...
}

# Consumer
@class_name LocalizedLabel

component LocalizedLabel() {
  var locale = useContext(AppContextKeys.LOCALE)
  # ...
}`
