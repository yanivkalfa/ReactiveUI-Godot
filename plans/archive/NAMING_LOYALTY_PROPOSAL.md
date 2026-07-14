# Naming loyalty — 1:1 to Godot (0.9.0, breaking) — APPROVED & EXECUTED

**Status: APPROVED by the owner 2026-07-11 and EXECUTED the same day** (branch
`feat/naming-loyalty-0.9.0`, one PR). The Godot analogue of ReactiveUI-Unreal's D-33 decision
("naming is 1:1 loyal to the engine"). Companion coverage artifact:
plans/WIDGET_INVENTORY.md (every official Control accounted for).

**Final owner decisions on the open questions:** (1) factories PascalCase verbatim (`V.Button`);
(2) `<Panel>` repointed to Godot's Panel, codemod rewrites old usages to `<PanelContainer>`;
(3) extensions kept: `min_width`/`min_height` + the `*_all` box keys (Godot's own `set_*_all`
spellings); the non-native `fill` was renamed to the loyal `anchors_preset`; (4) renames + all 9
Batch-1 controls in ONE batch, one branch, one PR, released as 0.9.0; (5) editor addon → 0.7.0
(not synced to 0.9.0). **No back-compat shims** — the codemod
(`addons/reactive_ui/dev/migrate_0_9_0.gd`) + MIGRATION-0.9.md are the migration path; compiler/
runtime emit exact "renamed: use X" messages for one release.

**The rule:** a Godot user should never have to learn a second vocabulary. Element/tag names are
the official Godot class names; props are the exact Godot property names; style keys are the
exact Godot property / theme-item / StyleBoxFlat names; enum values are Godot's; events are the
native signal name with an `on` marker (`pressed` → `onPressed`) — the marker exists because a
bare signal name is ambiguous with a bool prop in markup. Engine names are never squatted by
framework shorthands. Framework-structural names (`key`, `ref`, `style`, `classes`, `items`,
`draw_fn`, `redraw_key`, `Fragment`, hooks, router) are OUR API and stay as-is.

**Where we already are** (found by the audit, 2026-07-11):
- Plain props are ALREADY 100% loyal — `RUIHost` applies them verbatim via `node.set`.
- `onPascalCase` → `signal_name` ALREADY works generically (`onValueChanged` → `value_changed`),
  and `on_<signal>` binds verbatim. The deviations are the 11 React aliases layered on top.
- The generic `V.h("AnyClass")` path and the six generic theme channels are already loyal.
- The deviations are concentrated in: 9 shorthand tags, 46 snake_case factory names, the React
  event aliases, ~10 non-loyal flat style keys, string enum values, and the curated IDE metadata.

---

## 1. Tags — official Godot class names, verbatim

- Every host tag is the exact ClassDB class name: `<VBoxContainer>`, `<PanelContainer>`,
  `<RichTextLabel>`, `<TabContainer>`, `<HSplitContainer>` …
- **Shorthand aliases are removed** (breaking): `VBox`, `HBox`, `Grid`, `Margin`, `Panel`,
  `Center`, `Scroll`, `Tabs`, `RichText`. Lowercase host tags (`<vbox>` = factory name) are
  removed too — one spelling, the official one.
- **`<Panel>` is the one semantic repoint**: today it maps to PanelContainer; from 0.9.0 it means
  Godot's actual `Panel` class. Because this is silent-behavior-change territory, the compiler
  ships a one-release migration diagnostic (new GUITKX code, warning) on every `<Panel>` usage:
  *"`<Panel>` now maps to Godot's Panel; the pre-0.9 alias meant `<PanelContainer>`"*.
- **Open vocabulary (coverage win):** any PascalCase tag that names a ClassDB `Control` class
  compiles (codegen emits `V.h("ClassName", …)`), validated at compile time by the compiler via
  ClassDB and by the LSP via its bundled ClassDB dump. The curated vocabulary list remains only
  as IDE metadata (completion/hover/events/docs), not as a gate. This closes the tag gap for the
  12 shipped classes that currently have factories but no tags (HFlowContainer, HSplitContainer,
  AspectRatioContainer, FoldableContainer, NinePatchRect, TextureProgressBar, ColorPicker,
  MenuBar, …) and for all Batch-1 classes at once.
- Component tags are unchanged (PascalCase non-ClassDB names). New rule: ClassDB Control names
  are **reserved** — a user component whose class_name collides with an engine Control gets a
  compile diagnostic instead of silently shadowing it.
- `Fragment` / `<>` stays (structural, not an engine class — same as Unreal keeping the `Rui`
  mark off engine names).

**Complete tag rename table** (mechanical; the codemod applies it):

| Removed | Write instead |
|---|---|
| `VBox` | `VBoxContainer` |
| `HBox` | `HBoxContainer` |
| `Grid` | `GridContainer` |
| `Margin` | `MarginContainer` |
| `Panel` | `PanelContainer` (old meaning) / `Panel` (Godot's Panel — new meaning) |
| `Center` | `CenterContainer` |
| `Scroll` | `ScrollContainer` |
| `Tabs` | `TabContainer` |
| `RichText` | `RichTextLabel` |
| lowercase `<vbox>` etc. | the PascalCase class name |

## 2. Factories — match tags verbatim (`V.VBoxContainer`)

Spike-verified on 4.7-stable (2026-07-11): GDScript accepts static funcs named after native
classes (`static func Button(...)` inside `V` parses, calls, and warns nothing), so factories can
match tags verbatim — the same family-congruence rule as Unreal D-33.

- The 46 snake_case element factories are **renamed to the exact class names**:
  `V.vbox`→`V.VBoxContainer`, `V.panel`→`V.PanelContainer`, `V.rich_text`→`V.RichTextLabel`,
  `V.flow_h`→`V.HFlowContainer`, `V.split_h`→`V.HSplitContainer`, `V.aspect`→
  `V.AspectRatioContainer`, `V.foldable`→`V.FoldableContainer`, `V.nine_patch`→`V.NinePatchRect`,
  `V.texture_progress`→`V.TextureProgressBar`, `V.tabs`→`V.TabContainer`,
  `V.audio`→`V.AudioStreamPlayer`, `V.video`→`V.VideoStreamPlayer`, … (1:1, no exceptions).
- Structural factories stay lowercase (not engine classes): `fc`, `comp`, `memo`, `h`, `text`,
  `fragment`, `portal`, `suspense`, `error_boundary`, `router`, `routes`, `route`, `outlet`,
  `navigate`, `nav_link`, `link`.
- `V.h("ClassName", …)` remains the generic path and the compilation target for open-vocabulary
  tags; named factories become pure DX for hand-written GDScript.
- Old snake_case factories are **removed** (breaking), not aliased — the vocabulary tripwire test
  (`v_factories` reflection) keeps the list honest.

## 3. Props — exact Godot property names (no change needed)

Already loyal via passthrough. Framework-reserved props (`key`, `ref`, `style`, `classes`,
`items`, `draw_fn`, `redraw_key`, `reuse_by_slot`) are documented as framework API. The
LineEdit/TextEdit `text` caret preservation keeps its name and behavior (name-loyal, semantics
deliberate). The "removed plain prop is not reset" constraint is unchanged (faithful to
reference).

## 4. Events — `on` + PascalCase(signal), aliases removed

Canonical form: `on` + PascalCase of the exact signal name — `pressed`→`onPressed`,
`toggled`→`onToggled`, `value_changed`→`onValueChanged`, `text_submitted`→`onTextSubmitted`,
`item_selected`→`onItemSelected`, `gui_input`→`onGuiInput`. This is the *existing* generic
mechanism promoted to canonical; the snake `on_<signal>` verbatim escape also stays (it is the
most literal spelling). What's removed (breaking): the React alias table —

| Removed alias | Write instead (the real signal) |
|---|---|
| `onClick` | `onPressed` |
| `onChange` *(polymorphic)* | the control's actual signal: `onToggled` (CheckBox/CheckButton/toggle Button) · `onItemSelected` (OptionButton/ItemList/Tree) · `onValueChanged` (HSlider/VSlider/SpinBox — Range) · `onTextChanged` (LineEdit/TextEdit) · `onTabChanged` (TabBar/TabContainer) |
| `onInput` | `onTextChanged` |
| `onSubmit` | `onTextSubmitted` |
| `onFocus` | `onFocusEntered` |
| `onBlur` | `onFocusExited` |
| `onPointerDown` / `onPointerUp` | `onButtonDown` / `onButtonUp` |
| `onPointerEnter` / `onPointerLeave` | `onMouseEntered` / `onMouseExited` |
| `onResize` | `onResized` |

`RUIHost` keeps a removed-alias table for one release purely to emit a precise
"renamed in 0.9.0 — use onPressed" warning instead of a generic unknown-signal warning.
Component-prop callables (`on_start`, `onRemove` on user components) are untouched — they're
plain props, not host signal bindings.

**IDE win:** event completion stops being 17 hand-curated tag entries and derives `onPascalCase`
completions for every signal of every class from the bundled ClassDB dump (which already carries
signals) — full-surface IntelliSense for free.

## 5. Style keys — exact Godot names

The three-layer model stays; the flat vocabulary becomes loyal:

**Already exact — unchanged:** `bg_color`, `border_color` (StyleBoxFlat property names),
`font_color`, `font_size`, `font`, `outline_size`, `separation`, `h_separation`, `v_separation`
(theme item names), `modulate`, `self_modulate`, `scale`, `visible`, `z_index`, `z_as_relative`,
`material`, `texture_filter`, `texture_repeat`, `mouse_filter` (Control/CanvasItem property
names), state slots `hover`/`pressed`/`focus`/`disabled`/`read_only` (exact theme stylebox item
names), and the six generic channels.

**Renamed (breaking):**

| Removed | Write instead | Godot name it maps to |
|---|---|---|
| `tooltip` | `tooltip_text` | Control.tooltip_text |
| `clip` | `clip_contents` | Control.clip_contents |
| `pivot` | `pivot_offset` | Control.pivot_offset |
| `outline_color` | `font_outline_color` | theme color font_outline_color |
| `color` (alias) | `font_color` | theme color font_color |
| `grow_h` / `expand_h` / `h_align` | `size_flags_horizontal` | Control.size_flags_horizontal |
| `grow_v` / `expand_v` / `v_align` | `size_flags_vertical` | Control.size_flags_vertical |
| `min_size` | `custom_minimum_size` | Control.custom_minimum_size |
| `pad` | `content_margin_all` (or per-side `content_margin_left/…`) | StyleBoxFlat set_content_margin_all / content_margin_* |
| `border_width` | `border_width_all` (or per-side) | StyleBoxFlat set_border_width_all / border_width_* |
| `corner_radius` | `corner_radius_all` (or per-corner) | StyleBoxFlat set_corner_radius_all / corner_radius_* |
| `margin` | `margin_left/top/right/bottom` | MarginContainer theme constants |

**Semantic fixes (breaking):** `rotation` becomes radians (the exact Control.rotation semantics;
today the style layer converts from degrees). The box builder additionally accepts **any**
StyleBoxFlat property verbatim (`sb.set(key, …)`) — full StyleBoxFlat coverage, zero vocabulary.

**Documented framework extensions (kept, explicitly marked non-Godot — Godot has no
single-property equivalent):** `fill` (anchors PRESET_FULL_RECT), `min_width`/`min_height`
(single-axis custom_minimum_size — a dict can't set `.x`), the `*_all` umbrella keys above
(named after Godot's own `set_*_all` methods).

## 6. Enum values — Godot's constant names

Attr/style values in markup are GDScript expressions, so `Control.SIZE_EXPAND_FILL` and
`Control.MOUSE_FILTER_IGNORE` already work and are the canonical spelling. Where the style layer
accepts strings, the accepted strings become the exact Godot constant names
(`"SIZE_EXPAND_FILL"`, `"MOUSE_FILTER_IGNORE"`, case-insensitive); the invented short strings
(`"grow"`, `"stop"`, `"begin"`, `"expand_fill"`, …) are removed.

---

## Back-compat & migration plan

0.x semver: hard break at **0.9.0**, no runtime alias shims (one vocabulary, no dual paths).
Softened by tooling:

1. **Rename diagnostics, not mysteries.** The compiler/LSP keep a removed-name → new-name table
   for one release: old tags, old factories (via the existing did-you-mean edit-distance hook,
   upgraded to exact "renamed in 0.9.0: use X" messages), removed event aliases (host-side
   warning with the exact replacement), removed style keys (the existing unknown-style-key
   warning names the new key). `<Panel>` gets its dedicated repoint warning.
2. **Codemod.** A migration script in `addons/reactive_ui/dev/` (headless GDScript, same harness
   as the other dev tools) rewrites `.guitkx` and `.gd` sources: tag table, factory table, event
   aliases where unambiguous (`onClick`→`onPressed`, `onSubmit`→`onTextSubmitted`, …), style
   keys. The polymorphic `onChange` is rewritten per element type when the tag is known (markup),
   and flagged for manual review in plain `.gd` (`V.h`/dynamic cases).
3. **Docs.** README, docs site, `new-component` skill, and templates updated in the same PR; the
   changelog entry carries the full rename tables (they're small — that's the point of loyalty).
4. **Repo migration proof:** all 49 `.guitkx` examples and ~945 `V.*` callsites in
   tests/examples are migrated by the codemod itself — the codemod's own acceptance test.

## Version plan (all four deliverables)

| Deliverable | Current | Release | Why |
|---|---|---|---|
| `addons/reactive_ui` (runtime + compiler) | 0.8.7 | **0.9.0** | breaking vocabulary |
| VS Code + VS2022 `.guitkx` extensions (+ lsp-server) | 0.8.8 | **0.9.0** | breaking vocabulary sync + schema/grammar |
| `addons/reactive_ui_editor` | 0.6.3 | **0.7.0** | consumes the new vocabulary (its own lane, minor-bump breaking) |
| Docs site | unversioned | content update | rename tables + migration guide |

Release rides the standard release-process runbook (two-lane changelog: hand-written library
lane + generated tooling lane; Discord notes; verification gates).

## Effort estimate

| Workstream | Scope | Est. |
|---|---|---|
| Runtime: `v.gd` factory renames + codegen open-vocabulary path (`V.h` emission, ClassDB tag validation) + `TEXT_FACTORIES` + vocabulary.json + `gen_vocabulary` regen | ~6 files | 0.5–1 day |
| Runtime: `host_config.gd` alias removal + rename-warning table | 1 file | 0.5 day |
| Runtime: `style.gd`/LSP STYLE_KEYS loyal keys + generic StyleBoxFlat builder + resets + `style_test.gd` | 2 files + tests | 1 day |
| IDE: `schema.ts` + synced vocabulary + ClassDB-derived event completion + tests (`vocab.test.ts`, smoke) + grammar check + VS2022 pass | lsp-server + vscode + vs2022 | 1 day |
| Editor addon: highlighter/LSP verification against new vocabulary (mostly inherited via `guitkx.gd`) | verify + bump | 0.5 day |
| Codemod + migrate repo (49 `.guitkx`, ~945 callsites, 12 test suites green, demos render) | dev tool + sweep | 1 day |
| Docs: README, docs site (~37 files), `new-component` skill, changelogs, release staging | docs + release | 1 day |
| **Total (rename only)** | | **~5–6 focused days** |
| Batch-1 coverage line (9 classes: named metadata + demos + tests; tags come free with open vocabulary) | see WIDGET_INVENTORY | +1–2 days |

## Open questions for the owner

1. **Factory casing** — PascalCase verbatim (`V.Button`, spike-verified) per Unreal D-33
   congruence: confirm? (Alternative: keep factories snake_case and only make markup loyal —
   breaks family congruence; not recommended.)
2. **`<Panel>` repoint** — repoint to Godot's Panel with a one-release warning (proposed), or
   permanently reject `<Panel>` for one release before re-introducing it?
3. **Extensions** — keep `fill`, `min_width`/`min_height`, `*_all` box keys as documented
   framework extensions (proposed), or drop for absolute purity?
4. **Batch-1 coverage** — inside 0.9.0, or immediately after in 0.9.1?
5. **Editor addon** 0.6.3 → 0.7.0 (proposed) vs jumping it to 0.9.0 to sync the family numbering?
