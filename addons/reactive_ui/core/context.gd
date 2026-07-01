class_name RUIContext
extends RefCounted
## A context handle created by `Hooks.create_context(default)` — React parity for `createContext`.
##
## Passing a handle to `provide_context` / `use_context` instead of a bare String key removes the
## string-collision footgun (two unrelated features both keying on "theme") because the handle's
## OBJECT IDENTITY is the map key — distinct create_context() calls never collide. The handle also
## carries a `default` value that `use_context(handle)` returns when no ancestor provides it.
##
## String keys still work everywhere (back-compat); handles are the recommended, collision-free form.
##
##   const Theme = Hooks.create_context({ "accent": Color.CYAN })   # module-level handle
##   # provider:  Hooks.provide_context(Theme, my_theme)
##   # consumer:  var theme = Hooks.use_context(Theme)              # -> my_theme, or the default

## Value returned by use_context(this) when no provider is found walking up the fiber tree.
var default
## Optional label for diagnostics/debugging (never affects identity — identity is the object itself).
var name: String = ""

func _init(default_value = null, ctx_name: String = "") -> void:
	default = default_value
	name = ctx_name
