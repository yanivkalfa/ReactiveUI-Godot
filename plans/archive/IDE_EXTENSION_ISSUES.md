# GUITKX IDE extension — issue tracker

> ⚠️ **OBSOLETE caveat (2026-06-30).** The "#3/#4 forward to Godot's LSP, so they need the Godot editor
> running (port 6005)" framing below is **no longer true.** Since IDE 0.2.5/0.2.6 the embedded-GDScript
> completion / hover / diagnostics / go-to-definition are answered **in-process by `@gdscript-analyzer/core`**
> — *no Godot editor, no TCP*. The open residuals worth re-checking against IDE 0.2.6 are: find-references +
> rename on embedded GDScript symbols (still markup-level — that's the G1 work in `PARITY_PLAN.md`), and the
> optional gdformat embedded-reflow dependency (#6).

Tracking reported problems in the `.guitkx` editor tooling (VS Code + VS 2022, which share one Node
LSP server under `ide-extensions/lsp-server/`). Logged 2026-06-22 against **VS Code / VS 2022 0.2.3**.

**Resolution: #1–#7 fixed in IDE 0.2.4; #8 is by design.** Most live in the shared language server, so
the fixes land in both editors. #3/#4 forward to Godot's LSP, so they need the Godot editor running.

Legend — **Status:** ✅ fixed (0.2.4) · 🟢 by-design (won't fix). **Where:** `server` = shared LSP
(`lsp-server/`), `client` = VS Code config, `formatter` = `formatGuitkx.ts` + `guitkx_formatter.gd`.

| # | Issue | Where | Sev | Status |
|---|---|---|---|---|
| 1 | Formatter deletes blank lines (setup boundaries) | formatter | med | ✅ 0.2.4 |
| 2 | Diagnostic severities too soft (unknown attr = warning, unknown element = hint/"…") | server | low | ✅ 0.2.4 |
| 3 | No autocomplete for `Color.WHITE` (embedded-GDScript symbols) | server | med | ✅ 0.2.4 (static fallback + Godot proxy) |
| 4 | No go-to-definition / find-all-references | server | med | ✅ 0.2.4 (components + GDScript via Godot) |
| 5 | No autocomplete for style keys (`bg_color`, `pad`, …) inside `style={…}` | server | high | ✅ 0.2.4 |
| 6 | Formatter doesn't normalize embedded GDScript whitespace (`==␣␣␣null`) | formatter | med | ✅ 0.2.4 |
| 7 | Enter after a self-closing tag indents one level too deep | client | low | ✅ 0.2.4 |
| 8 | Hook names are `use_ref`, not `useRef` | — | — | 🟢 by design |

> **Note on #3/#4:** the static `Color.*`/`Vector2.*` constants and the style/built-in completions work
> offline; full embedded-GDScript completion and go-to-definition on library symbols (`use_ref` →
> `core/hooks.gd`) forward to Godot's LSP and require the **Godot editor open** (port 6005). Find-all-
> references on GDScript symbols (vs component tags) is still server-side only — a possible follow-up.

---

## 1. 🔴 Formatter deletes blank lines around the setup block

**Reported:** in `examples/demos/keyed/keyed_tile.guitkx`, adding a blank line between
`component DemoKeyedTile(id) {` and `var col = use_ref(null)` is removed on format; same for a blank
line between the last setup line and `return (`.

```guitkx
component DemoKeyedTile(id) {

	var col = use_ref(null)          # <- the blank line above is stripped
	...
	col["current"] = Color(...)

	return (                          # <- the blank line above is stripped
```

**Root cause:** `reanchor()` in `lsp-server/src/formatGuitkx.ts` trims leading/trailing blank lines of
the setup block (`while (lines[0].trim()==="") lines.shift()` / `pop()`), and `fmtComponent` doesn't
re-insert a blank line at the `{`→setup or setup→`return (` boundaries. Interior blank lines *between*
setup statements are preserved; only the boundary blanks are lost. The formatter also has no
blank-line policy between markup siblings.

**Fix:** port ReactiveUIToolKit's `preserveBlankLines` / `maxConsecutiveBlankLines` behaviour — keep
(at most one) blank line at setup boundaries and between sibling nodes. Keep TS + GD formatters
byte-identical (shared golden corpus).

## 2. 🔴 Diagnostic severities are too soft

**Reported:** (a) `<Label text={…}/>` with `text` changed to an invalid attribute shows a **warning**;
it should be an **error**. (b) Changing `Label` → `Labeler` gives `GUITKX0105: unknown element
'Labeler'. Did you mean 'Label'?` but rendered as a faint **"…" / 3-dot hint**, not a squiggle.

**Root cause:** in `lsp-server/src/server.ts` the live markup-diagnostic tier assigns
`DiagnosticSeverity.Warning` to `GUITKX0107` (unknown attribute) and `DiagnosticSeverity.Hint` to
`GUITKX0105` (unknown element). Hints render as the faint dotted underline.

**Fix:** raise unknown-attribute (`GUITKX0107`) and unknown-element (`GUITKX0105`) to
`DiagnosticSeverity.Error` (or at least `Warning` with a real squiggle for 0105). Note: 0107 is gated
on the ClassDB dump, so promoting it to Error is safe (it only fires when we have authoritative data).

## 3. 🟡 No autocomplete for `Color.WHITE` (embedded-GDScript symbols)

**Reported:** typing `Color.` inside a `{ … }` expression gives no completion for `WHITE` etc.

**Root cause / dependency:** completion inside `{expr}`/setup is **embedded GDScript** — the server
builds a synthetic `.gd` virtual document and **forwards** the request to **Godot's GDScript language
server** (TCP, port 6005). That requires the **Godot editor running with the project open**. If Godot
is running and member/constant completion still doesn't come back, the virtual-doc member-access
mapping (`virtualDoc.ts` / `sourceMap.ts`) or the proxy request shape needs investigation.

**Next step:** confirm with Godot open (`enableGodotProxy` on, port 6005). If still missing, debug the
proxy round-trip for `Color.<member>`.

## 4. 🔴 No go-to-definition / find-all-references

**Reported:** go-to-def and find-all-refs don't work.

**Root cause:** the server *does* implement `onDefinition` / `onReferences`, but **only for component
tags** — `<DemoKeyedTile/>` jumps to its `component` declaration via the workspace index. **GDScript
symbols** (`use_ref`, `Color`, a local `var`) are **not** wired for definition/references (only
*completion* and *hover* are proxied to Godot). So def/refs on anything that isn't a `<Component>` tag
does nothing.

**Fix:** (a) verify component-tag def/refs actually work in 0.2.3 (they should now that the extension
activates); (b) optionally proxy `textDocument/definition` + `references` to Godot's LSP for
GDScript symbols, like completion/hover already are.

## 5. 🔴 No autocomplete for style keys inside `style={ … }`

**Reported:** inside `style={ { "…": … } }` there's no completion for the style keys.

**Root cause:** `style={ {…} }` is a GDScript `Dictionary` literal, so the server classifies it as
**embedded** and forwards to Godot — which has **no knowledge of the RUIStyle keys** (`bg_color`,
`corner_radius`, `pad`, `separation`, `expand_h`/`expand_v`, `min_size`/`min_width`/`min_height`,
`font_size`, `font_color`, `border_width`, `border_color`, the per-state slots, `classes`, …). There
is no style-key vocabulary anywhere in the tooling.

**Fix (new feature):** add a style-key schema (enumerate the keys `RUIStyle`/`host_config.gd`
understands, with types) + context detection ("cursor is inside a `style={ {…} }` dict key") in
`context.ts`, and serve those as completions. This is the highest-value missing feature.

## 6. 🟡 Formatter doesn't normalize embedded GDScript whitespace

**Reported:** `if col["current"] ==␣␣␣␣␣null:` is **not** reformatted to `== null:`.

**Root cause:** the formatter only **re-anchors the base indentation** of the embedded setup
(`reanchor()`); it deliberately does **not** reformat the GDScript *content* (operator spacing, etc.).
Collapsing `==␣␣␣null` → `== null` needs a real GDScript formatter — the optional `useGdformat`
(`reflowEmbedded.ts`) path, which only runs when **gdformat (gdscript-toolkit)** is installed on PATH.

**Fix:** either document that embedded-GDScript reflow needs `gdformat`, or add a light built-in
GDScript whitespace pass (collapse runs of spaces around operators) as a fallback.

## 7. 🔴 Enter after a self-closing tag indents one level too deep

**Reported:** pressing Enter after `<Label text={ "asas d" } />` lands the cursor one tab too far in.

**Root cause:** `vscode/language-configuration.json` →
`indentationRules.increaseIndentPattern` includes the alternative `(>\\s*$)`, which matches **any line
ending in `>`** — including a self-closing `… />`. So VS Code increases the indent after a self-closed
tag, which should be indent-neutral.

**Fix:** exclude `/>` from the increase pattern, e.g. `([^/]>\\s*$)` (or a `(?<!/)` negative
lookbehind), so only real opening tags (`<VBox>`) increase indent.

## 8. 🟢 Hook names are `use_ref`, not `useRef` (by design)

**Reported:** why `use_ref` and not `useRef`?

**Answer:** GDScript's convention is `snake_case` (Godot's own API: `add_child`, `queue_free`), and
`use_ref` is the **actual core-library API** (`Hooks.use_ref` in `addons/reactive_ui/core/hooks.gd`) —
the markup just calls the real hook. ReactiveUIToolKit uses `UseRef` because C# is PascalCase. Same
API, each spelled in its language's idiom (also why it's `V.fc`, not `V.Func` — `func` is reserved).
Renaming to camelCase would mean renaming the whole core library to a style Godot devs find alien.
**Won't change** unless the project deliberately re-idioms the core API.

---

### Suggested fix order
Quick wins first: **#7** (one regex), **#2** (severity constants), **#1** (blank-line preservation).
Then the high-value **#5** (style-key completion). **#3/#4** depend on the Godot-LSP proxy and need a
running-editor repro. **#6** is gated on `gdformat`. **#8** is by-design.
