---
name: new-component
description: Create a new .guitkx component for ReactiveUI-Godot — file placement, component/props/hooks/events syntax, children, styling, and what the compiler generates.
---

# Writing a ReactiveUI-Godot component

## Where files go

- One component per `.guitkx` file, named in snake_case after the component:
  `res://ui/<feature>/<component_name>.guitkx` (any folder works; group by feature).
  Examples of the house style: `examples/demos/counter/counter.guitkx`.
- Saving the file makes the `reactive_ui` watcher compile a **sibling `.gd`** next to it
  (`<name>.guitkx` → generated GDScript). You never write or edit that file; renames/moves in the
  FileSystem dock retarget it automatically. The repo gitignores generated siblings — they
  regenerate on open; exported games pick them up from disk.
- `@class_name SomeName` at the top registers the component globally so any other `.guitkx` can
  use `<SomeName />` without imports.

## Anatomy (real syntax — from examples/demos)

```
@class_name ScoreCard

## Doc comment: shows in editor hover for <ScoreCard>.
component ScoreCard(title: String = "", max_score: int = 100) {
  var s = useState(0)                      # setup: plain GDScript lines before `return (`
  return (
    <DemoBox title={ title }>
      <Label text={ "Score: %d / %d" % [s[0], max_score] } style={ {"font_size": 24} } />
      <HBoxContainer style={ {"separation": 8} }>
        <Button text="+10" onPressed={ func(): s[1].call(s[0] + 10) } />
        <Button text="Reset" onPressed={ func(): s[1].call(0) } />
      </HBoxContainer>
      { children }
    </DemoBox>
  )
}
```

Rules that matter:
- **Props** are the component's parameter list — typed, with defaults: `component X(title: String = "")`.
  Pass them as attributes: `<X title="hi" />` or `<X title={ expr } />`. Spread is supported: `{...obj}`.
- **Hooks** are camelCase and return an indexable pair where stateful: `var s = useState(0)` →
  `s[0]` is the value, `s[1]` the setter Callable — call it `s[1].call(new_value)` (an updater
  Callable like `func(c): return c + 1` also works). Full set: useState, useReducer, useEffect,
  useMemo, useRef, useContext, useSignal, useTween. Rules of hooks apply (top level of the
  component, no hooks inside `@if`/loops — the editor diagnoses violations).
- **Events** (0.9.0 — 1:1 loyal to Godot): the native signal name with an `on` marker —
  `on` + PascalCase(signal) reaches ANY signal of ANY node (`onPressed` → `pressed`,
  `onValueChanged` → `value_changed`, `onTextSubmitted` → `text_submitted`, `onGuiInput` →
  `gui_input`); the verbatim `on_<signal>` spelling also works. Handlers are GDScript lambdas:
  `onPressed={ func(): do_thing() }`. There are NO React aliases (no onClick/onChange).
- **Embedded expressions** `{ expr }` are plain GDScript (typed intelligence in the editors);
  `{ children }` renders the children passed between your tags.
- **Control flow directives**: `@if cond { … } @elif { … } @else { … }`, `@for x in xs { … }`,
  `@while`, `@match` with `@case`/`@default`.
- **Styling**: `style={ {"font_size": 28, "separation": 8} }` dicts — every key is the EXACT
  Godot property / theme-item / StyleBoxFlat name (`custom_minimum_size`, `size_flags_horizontal`,
  `bg_color`, `corner_radius_all`, `margin_left`, …). Host element tags ARE the official Godot
  class names (`<VBoxContainer>`, `<HBoxContainer>`, `<Label>`, `<Button>`, `<MarginContainer>`,
  `<PanelContainer>`, …) — any instantiable Godot Node class is a valid tag (open vocabulary).
- Keyed lists: give siblings from loops a `key` attribute for stable reconciliation.
- Tabs, not spaces (GDScript requirement; the formatter enforces it).

## Checklist before calling it done

1. File saved → sibling `.gd` generated with no `GUITKX####` diagnostics (Problems panel clean).
2. Renders where it's used (`<ScoreCard … />` from another component or a root scene mount).
3. If it's reusable API surface: doc comment (`##`) on the component, sensible prop defaults.
4. Formatting passes (format-on-save or the Format button — `guitkx.config.json` governs).
