# Migrating to 0.9.0 — naming is now 1:1 loyal to Godot

0.9.0 renames the entire user-facing vocabulary to the official Godot names (decision record:
`plans/NAMING_LOYALTY_PROPOSAL.md`). **There are no compatibility shims** — old names stop
working — but the compiler/runtime emit precise "renamed: use X" messages for one release, and a
**codemod migrates your project automatically**.

## TL;DR — run the codemod

From your project root (with the 0.9.0 addon installed):

```bash
# 1. See what would change (writes nothing):
godot --headless --path . --script res://addons/reactive_ui/dev/migrate_0_9_0.gd -- --dry-run

# 2. Apply (rewrites .guitkx and hand-written .gd in place — commit/backup first!):
godot --headless --path . --script res://addons/reactive_ui/dev/migrate_0_9_0.gd

# 3. Optionally scope it to specific folders:
godot --headless --path . --script res://addons/reactive_ui/dev/migrate_0_9_0.gd -- res://ui res://scenes
```

The codemod skips `addons/`, `.git/`, `.godot/`, and every generated `.gd` that has a `.guitkx`
sibling (those regenerate on the next compile). It prints — and writes to
`migrate_0_9_0_report.txt` — a list of the few sites it refuses to guess at (see "Manual review"
below). After it runs, open the project in the editor (or run your headless guitkx build) so the
`.guitkx` sources recompile with the new vocabulary.

## What changed

### 1. Tags = official Godot class names

Shorthand tags are gone; write the class name. Any instantiable Godot `Node` class is now a valid
tag (open vocabulary — the compiler validates against ClassDB), so the entire official Control
set works from markup.

| Removed | Write instead |
|---|---|
| `<VBox>` / `<vbox>` | `<VBoxContainer>` |
| `<HBox>` / `<hbox>` | `<HBoxContainer>` |
| `<Grid>` | `<GridContainer>` |
| `<Margin>` | `<MarginContainer>` |
| `<Panel>` | `<PanelContainer>` — **meaning change:** `<Panel>` now creates Godot's actual `Panel` (a plain themed rect, no child layout). The codemod rewrites every pre-0.9 `<Panel>` to `<PanelContainer>` for you. |
| `<Center>` | `<CenterContainer>` |
| `<Scroll>` | `<ScrollContainer>` |
| `<Tabs>` | `<TabContainer>` |
| `<RichText>` | `<RichTextLabel>` |
| lowercase element tags (`<label>`, …) | the PascalCase class name (`<Label>`) |

`<Fragment>` / `<>` are unchanged (structural, not engine classes). Components are unchanged —
but engine class names are now **reserved**: a component named like a Godot class is shadowed by
the engine element (compile warning GUITKX0151); rename the component.

### 2. `V.*` factories match tags verbatim

`V.vbox(...)` → `V.VBoxContainer(...)`, `V.button(...)` → `V.Button(...)`,
`V.rich_text` → `V.RichTextLabel`, `V.audio` → `V.AudioStreamPlayer`, … 1:1, no exceptions.
Structural factories stay lowercase: `fc`, `comp`, `memo`, `h`, `text`, `fragment`, `portal`,
`suspense`, `error_boundary`, `router`, `routes`, `route`, `outlet`, `navigate`, `nav_link`,
`link`. New in 0.9.0: `V.Panel`, `V.ReferenceRect`, `V.HScrollBar`, `V.VScrollBar`,
`V.SubViewportContainer`, `V.BoxContainer`, `V.FlowContainer`, `V.SplitContainer`,
`V.VirtualJoystick` — and `V.h("AnyClassName", …)` remains the generic escape.

### 3. Events = the real signal name with an `on` marker

`on` + PascalCase(signal) → the signal, for **every** signal of **every** node
(`onPressed` → `pressed`, `onValueChanged` → `value_changed`, `onGuiInput` → `gui_input`).
The verbatim `on_<signal>` spelling still works. The React aliases are removed:

| Removed | Write instead |
|---|---|
| `onClick` | `onPressed` |
| `onChange` | the element's real signal: `onToggled` (CheckBox/CheckButton/toggle Button) · `onItemSelected` (OptionButton/ItemList/Tree) · `onValueChanged` (sliders/SpinBox) · `onTextChanged` (LineEdit/TextEdit) · `onTabChanged` (TabBar/TabContainer) · `onColorChanged` (ColorPicker) |
| `onInput` | `onTextChanged` |
| `onSubmit` | `onTextSubmitted` |
| `onFocus` / `onBlur` | `onFocusEntered` / `onFocusExited` |
| `onPointerDown` / `onPointerUp` | `onButtonDown` / `onButtonUp` |
| `onPointerEnter` / `onPointerLeave` | `onMouseEntered` / `onMouseExited` |
| `onResize` | `onResized` |

Callable props on YOUR components (`onSave={...}`, `on_start={...}`) are plain props — untouched.

### 4. Style keys = exact Godot names

Unchanged (they were already the exact Godot names): `bg_color`, `border_color`, `font_color`,
`font`, `font_size`, `outline_size`, `separation`, `h_separation`, `v_separation`, `modulate`,
`self_modulate`, `scale`, `visible`, `z_index`, `z_as_relative`, `material`, `texture_filter`,
`texture_repeat`, `mouse_filter`, the state slots (`hover`/`pressed`/`focus`/`disabled`/
`read_only`), and the six theme channels (`colors`/`constants`/`fonts`/`font_sizes`/`icons`/
`styleboxes`).

| Removed | Write instead |
|---|---|
| `min_size` | `custom_minimum_size` |
| `expand_h: true/false` | `size_flags_horizontal: Control.SIZE_EXPAND_FILL` / `Control.SIZE_FILL` |
| `expand_v: true/false` | `size_flags_vertical: …` |
| `grow_h` / `h_align` | `size_flags_horizontal` (Godot `SIZE_*` values) |
| `grow_v` / `v_align` | `size_flags_vertical` |
| `fill: true` | `anchors_preset: Control.PRESET_FULL_RECT` (any `PRESET_*` works) |
| `clip` | `clip_contents` |
| `tooltip` | `tooltip_text` |
| `pivot` | `pivot_offset` |
| `color` | `font_color` |
| `outline_color` | `font_outline_color` |
| `pad` | `content_margin_all` (or per-side `content_margin_left`/`_top`/`_right`/`_bottom`) |
| `border_width` | `border_width_all` (or per-side) |
| `corner_radius` | `corner_radius_all` (or per-corner `corner_radius_top_left`, …) |
| `margin` | the four exact theme constants `margin_left`/`margin_top`/`margin_right`/`margin_bottom` |

**Semantics:** style `rotation` is now **radians** (Godot's own `Control.rotation`); the codemod
wraps your old degree values in `deg_to_rad(...)` so nothing moves. The StyleBox builder now
accepts **any** `StyleBoxFlat` property verbatim (`shadow_size`, `skew`, `expand_margin_left`,
`draw_center`, …) plus the `*_all` umbrellas named after Godot's own `set_*_all` setters.
Enum-valued keys accept the raw int / Godot constant, or the exact constant name as a string
(`"SIZE_EXPAND_FILL"`, `"MOUSE_FILTER_IGNORE"`, `"PRESET_FULL_RECT"` — case-insensitive); the
invented short strings (`"grow"`, `"stop"`, `"begin"`, …) are gone.

Kept extensions (documented, deliberately non-Godot — no single-property equivalent exists):
`min_width` / `min_height` (the `.x`/`.y` of `custom_minimum_size`).

### 5. Props — no change

Plain props were always the exact Godot property names and still are.

## Manual review after the codemod

The codemod flags (report + console) instead of guessing:

1. **`onChange` it couldn't attribute to an element** (e.g. built through a variable or spread) —
   pick the real signal from the table above.
2. **Non-literal values** for `expand_h`/`grow_*`/`fill` (e.g. `expand_h: some_var`) — pick the
   `SIZE_*` flag or `PRESET_*` yourself.
3. **`"rotation":` outside a style dict** — element *props* named `rotation` were always radians
   and are untouched; only style-dict rotation values get `deg_to_rad(...)`-wrapped, detected by
   a same-line `style` heuristic. If you keep style dicts in standalone variables, check them.

## If you skip the codemod

Everything old fails loudly, nothing fails silently:
- Old tags → compile error GUITKX0105 with the exact new tag name.
- Old factories → GDScript "static function not found in base V" parse errors.
- Old event props → a runtime warning naming the exact replacement.
- Old style keys → a runtime warning naming the exact replacement.
- The one silent hazard would have been `<Panel>` (still a valid tag, new meaning) — hence:
  migrate with the codemod.
