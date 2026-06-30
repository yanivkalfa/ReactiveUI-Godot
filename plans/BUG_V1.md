# BUG_V1 — known defects + parity gaps to fix before the next phase

Two parts:
- **Bugs** (BUG-1 … BUG-8): real defects, fix before native-Godot-editor work.
- **React parity gaps**: ways the library/markup diverges from React — some are real bugs we
  can close, most are deliberate Godot/GDScript constraints. Listed so we stop confusing the
  two.

BUG-3 … BUG-7 were found in ~15 min of hands-on testing of the published **0.3.0** extension
and then **empirically reproduced** by driving the compiled LSP modules against the real repro
files (`examples/demos/effect_order/effect_order.guitkx` + `effect_order_row.guitkx`). All
file:line citations are into `ide-extensions/`.

Status: **FIXED** on branch `fix/guitkx-lsp-bugs-v1` (BUG-1…BUG-8). Two follow-ups from adversarial
review folded in: BUG-3's tag-boundary probe is gated through `isTagBoundary` (a comparison `a < Bcd`
is never mistaken for a tag), and BUG-4's rename rewrites the `component` decl name only when it equals
the binding (so `@class_name X` over `component Y` keeps Y) and `@class_name` reads only to end-of-line.
Verified: tsc clean + 45/45 lsp-server tests green (incl. 7 new regression tests).

---

## BUG-1 — Embedded GDScript in `.guitkx` is not formatted by our analyzer

### Symptom
The same GDScript formats differently depending on where it lives:
- A `.gd` file → fully normalized by our `gdscript-fmt`.
- Inside a `.guitkx` setup block / hook body / `{expr}` → only **re-anchored** (dedent + re-indent
  + collapse 2+ spaces). It is **not** reflowed.

### Root cause
`server.ts` `onDocumentFormatting`/`onDocumentRangeFormatting` route `.guitkx` to `formatGuitkx()`
+ an **optional** `reflowEmbedded()`. `reanchor()` (`formatGuitkx.ts`) is the only thing that
touches embedded code by default. `reflowEmbedded.ts` is the only reflow path and it is (a) opt-in
behind a `useGdformat` flag (default off) and (b) shells out (`spawnSync`) to the **external
`gdformat` binary** (gdtoolkit, a different project) — **not** our analyzer, which already exposes
`format`/`formatRange` (used only for `.gd` via `analyzerAdapter.formatAt`/`formatRangeAt`).

### Fix
Reuse the region machinery in `reflowEmbedded.ts` (`embeddedRegions()`, dummy-`func` wrap,
token-equivalence safety check, boundary-whitespace restore) but call **`analyzer.format`** instead
of the `gdformat` binary, and make it the default. Then `.gd` and embedded GDScript format
identically and the external Python dependency is deleted. Keep the token-equivalence guard (never
corrupt a file). Note the Godot-side `guitkx_formatter.gd` stays re-anchor-only (it has no analyzer).

### Effort
Medium.

---

## BUG-2 — Embedded GDScript in `.guitkx` is not semantically highlighted by our analyzer

### Symptom
Inside `.guitkx`, embedded GDScript is colored by the TextMate grammar only, not the analyzer's
type-aware semantic tokens. Same snippet colors differently in a `.gd` file vs in `.guitkx`.

### Root cause
`server.ts` `semanticTokens.on()` routes `.gd` → `analyzer.semanticTokensAt()` but `.guitkx` →
`buildSemanticTokens()` (`semanticTokens.ts`), a markup-only classifier that emits **no tokens for
the embedded GDScript**. The unified legend already reserves the analyzer's token types, so the
legend is not the blocker — the wiring is.

### Fix
For `.guitkx`, also build the virtual doc, call `analyzer.semanticTokensAt(vUri, vText)`, map ranges
back via `map.toSource()` (drop glue → null), and **merge** with the markup tokens; share the
delta-encoder with the `.gd` path. Plumbing (virtual doc + source map + adapter) already exists.

### Effort
Small–Medium. **Note:** depends on BUG-5's source-map fix — until setup/embedded spans round-trip,
mapped-back tokens would be dropped too.

---

## BUG-3 — Ctrl+click / Find-References / Rename dead when the cursor is on the tag opener `<`

### Symptom
On a `<DemoEffectOrderRow .../>` usage: **find-all-references** warns *"no definition was found"* and
**ctrl+click** (go-to-definition) does nothing, while **F12** works. The component is declared and
indexed correctly.

### Root cause
All three features route through `componentTagAt(src, offset)` (`workspaceIndex.ts:241-253`), which
identifies the symbol by expanding an identifier **outward** from the cursor (`while isIdent(src[s-1])
s--; while isIdent(src[e]) e++`) and bails `if (s===e) return null` (`:246`). When the position lands
on the `<` itself (or the tab just before it), `src[offset]` is not an identifier char → `s===e` →
null. It never looks **right**, past the `<`, to the tag name. Then both handlers fall through to the
embedded path: `onDefinition` → `forwardDefinition` (the analyzer sees `<` as less-than, returns null
→ VS Code's *"no definition was found"*); `onReferences` → `embeddedReferences` → `[]`.

**The F12-vs-ctrl+click split is a cursor-position artifact of the same handler**, not two code
paths: F12 uses the caret (which the user placed inside the word, where `componentTagAt` succeeds);
ctrl+click uses the **mouse** position, which on a tab-indented tag easily lands on the `<` boundary
where it fails. (`definitionProvider`/`referencesProvider` are both advertised — not a capabilities
issue.)

### Fix
In `componentTagAt`, when `s===e`, probe right: skip an optional `<`, an optional `/`, and inline
whitespace, then take the following identifier as the tag name; keep the existing PascalCase +
back-scan-to-`<` validation so it stays safe. Fixes ctrl+click, find-references, **and** prepareRename
uniformly (all three consume `componentTagAt`). Add a regression test asserting
`componentTagAt(src, indexOf('<Tag')) === 'Tag'` (cursor on the `<`) — the current test only probes
inside the name.

### Confidence / citations
High, verdict **confirmed**. `workspaceIndex.ts:241-253`, `:244-246`; `server.ts:446-465`, `:467-503`,
`:572-579`, `:698-724`, `:783-812`, `:92-93`; `refs.ts:15-41`.

---

## BUG-4 — Renaming a component that has `@class_name` does a half-rename (dangling `GUITKX0105`)

### Symptom
F2-rename `DemoEffectOrderRow` → `DemoEffectOrderRows`: the `component` decl and the `<…>` usage in
the consumer get renamed, but the **`@class_name DemoEffectOrderRow` directive is left untouched**, so
the renamed `<DemoEffectOrderRows>` now triggers **GUITKX0105 "unknown element … Did you mean
'DemoEffectOrderRow'?"**. (The "error" the user saw is that red GUITKX0105 squiggle — there is **no JS
exception**; the rename simply applied a partial edit.)

### Root cause
The intended "refuse rename when a `@class_name` override is present" rule is mis-implemented as a
**name-vs-binding inequality** test, so it silently fails to fire when the override is spelled the same
as the decl. `isRenameable` (`server.ts:583-586`) ends with
`index.lookup(name).every(e => e.name === e.binding)`. For `@class_name X` over `component X`,
`binding === name` (`workspaceIndex.ts:60`), so `every(...)` is true → rename **allowed**. But the
edit set only contains (a) `scanTagRefs` `<Tag>`/`</Tag>` matches (`refs.ts:15-41`, never `@class_name`)
and (b) index decl entries edited at the **`component <name>` token** (`workspaceIndex.ts:64`). The
`@class_name` token is in neither set → never rewritten. Worse, **GUITKX0105 resolves a tag by its
`binding` (= the `@class_name`)** (`server.ts:1159`, `index.has` keyed on binding at
`workspaceIndex.ts:163,186`): after the half-rename the binding is unchanged but the usage now says
`<DemoEffectOrderRows>`, for which no binding exists → unknown; `closestTag` (`:1282-1295`) then
suggests the old name.

### Fix — atomic rename (do **not** keep the refuse rule)
Refusing whenever `@class_name` is present would make **every** `@class_name`'d component unrenameable
— and `@class_name X` over `component X` is the idiomatic, majority case. Instead rename the
`@class_name` token, the `component` token, and all `<Tag>` usages **together**:
1. Record the `@class_name` identifier's start/end on the first-component `DeclInfo` (`readClassName`,
   `workspaceIndex.ts:74-91`, already locates it); surface on `IndexEntry`.
2. In `onRenameRequest` (`server.ts:850-863`), also emit an edit at that `@class_name` range for the
   owning decl. Usage edits + the collision guard already key off `binding` (= override), so they stay
   correct.
3. Drop the override-blocking `every(...)` clause in `isRenameable` (`:585`); keep only "not a host
   tag, and indexed."
4. Test: `@class_name X` over `component X`, rename → assert edits cover the `@class_name` token, the
   `component` token, and the `<X>` usage in a second file, and **no GUITKX0105 remains**.

### Confidence / citations
High, verdict **confirmed**. `workspaceIndex.ts:60,64,74-91,163,186`; `server.ts:581-586,816-835,
837-865,850-863,1159,1282-1295`; `refs.ts:15-41`.

---

## BUG-5 — No hover / completion / go-to-definition for embedded GDScript in **setup blocks**

This is the big one (it's why "hover/completion return *nothing*"). It is **one shared root cause**
that kills hover **and** completion **and** definition inside a component's setup region.

### Symptom
In a component setup block (the lines before `return (...)`), e.g. typing `var g = use_s`: no
completion (not even `use_state`), no hover on any variable, no go-to-definition. The `{expr}` holes
(e.g. `n[0]`) **do** work — so it looks maddeningly inconsistent.

### Root cause
`buildVirtualDoc` emits the setup region via `emitVerbatimBlock`, which records its source-map span
only under an **all-or-nothing length guard**: `if (block.length === text.length) ctx.map.addSpan(...)`
(`virtualDoc.ts:289-290`). `reindent()` collapses any whitespace-only line to `""`
(`virtualDoc.ts:310`), and the setup region always ends with a whitespace-only line (the `\t` before
`return`), so `block.length !== text.length` → the span is **dropped for the entire setup block**.
Every setup offset then maps to `toGenerated() === null`, so `forwardCompletion` bails `[]`
(`server.ts:317-319`) and `onHover`/`forwardDefinition` return null (`:350-351`, `:467-473`) before
ever reaching the analyzer. **CRLF makes it strictly worse** (the repro file is 100% CRLF: the leading
`\r`-only line is also collapsed, dropping 2 chars). `{expr}` holes work because `emitExpr`
(`virtualDoc.ts:263-274`) calls `addSpan` **unconditionally**. Confirmed end-to-end: fed a correctly
mapped virtual doc, `AnalyzerAdapter.completionsAt` returns `use_state` for `use_s` — the analyzer is
healthy; the mapping is the bug. (Activation + provider registration are fine.)

### Fix
Replace the whole-block guard in `emitVerbatimBlock` (`virtualDoc.ts:284-292`) with **per-line
mapping** (which the function's own comment already claims it does): for each source line, if its
reindented length equals the source length, `addSpan` for that line; skip whitespace-only lines. This
maps all real setup code regardless of CRLF/LF and survives interior blank lines. Must be
**line-ending agnostic**.

### Confidence / citations
High, verdict **confirmed** (reproduced end-to-end). `virtualDoc.ts:60-62,263-274,284-292,289-290,
299-312,310`; `server.ts:315-325,348-357,467-473`; `sourceMap.ts:27-34`.

---

## BUG-6 — Markup hover returns nothing except at the exact end of a host-tag name

A **separate** defect from BUG-5 (this one is the markup/schema side of "no hover").

### Symptom
Hovering `<Label>`, an attribute like `text`/`on_pressed`/`separation`, or a component tag like
`<DemoEffectOrderRow>` shows nothing — *unless* the caret sits exactly at the end of a **host**-tag
name.

### Root cause
`onHover` (`server.ts:341-346`) resolves using **`ctx.word`** — the word **before** the cursor
(`wordBefore`, `context.ts:46-50`) — so mid-identifier it's truncated (`Label` → `La`,
`findTag('La')` undefined). It also only consults `findTag` (**host tags only** — component tags never
resolve) plus a small `STRUCTURAL_ATTRS`/`COMMON_ATTRS` set; it **never consults the ClassDB
property/signal dump**, so real attrs (`title`, `text`, `on_pressed`, `separation`, …) return null.
(Markup *completion* survives because `onCompletion` builds full lists from schema + ClassDB and
doesn't need a resolved word.)

### Fix
In `onHover`: use a full **`wordAt(offset)`** (not `ctx.word`); resolve tags via `findTag` **+ the
workspace index** (component tags) and attributes via the **ClassDB dump** (mirroring `onCompletion`);
wrap the handler in try/catch.

### Confidence / citations
High, verdict **confirmed**. `server.ts:341-346`; `context.ts:46-50`.

---

## BUG-7 — No completion at markup / `@for`-body positions; component tags never offered

A **separate** defect from BUG-5 (the markup side of "no completion").

### Symptom
At a blank markup position (cursor in indentation, no `<` typed yet) — at top level or inside a
`@for (…) { … }` body — completion offers nothing. And even where it works, indexed component tags
(`<DemoEffectOrderRow>`) are never suggested.

### Root cause
Two faults: (1) a blank position inside a component/`@for` **body brace** is misclassified `"embedded"`
because `classifyContext` hits `insideUnmatchedBrace` (`context.ts:37-41,99-117`) — brace depth > 0 —
so it routes to the (BUG-5-dead) `forwardCompletion` analyzer path instead of the schema markup
branch. (2) The schema branches (`server.ts:191-197` tagName, `:233-243` markup) emit only
`HOST_TAGS` + `CONTROL_FLOW` and **never `index.names()`**, so component tags are never offered (the
server already has `index.names()`, used for did-you-mean at `:1285`).

### Fix
1. Classify a blank position whose innermost enclosing brace is a **body brace** (`isBodyBrace`, already
   imported in `context.ts`) as `"markup"`, not `"embedded"` — mirroring `emitMarkup`/`enclosingTag`.
2. Add `index.names()` (as `CompletionItemKind.Class`) alongside `HOST_TAGS` in both completion
   branches.

### Confidence / citations
High, verdict **confirmed** (reproduced). `context.ts:37-41,99-117`; `server.ts:191-197,233-243,
244-254,317-319,1285`.

---

## BUG-8 — Enter after a multi-line opening tag doesn't indent the attributes

### Symptom
Given
```
<Label
	text="…"
	style={ {…} } />
```
pressing Enter right after `<Label` keeps the cursor at the `<L` column instead of indenting one level
(to align with `text`/`style`).

### Root cause
`increaseIndentPattern` (`ide-extensions/vscode/language-configuration.json:28`) only increases indent
for a line ending in `{`, `(`, `:`, or a **closed** `>` (`[^/]>\s*$`). An **unclosed** opening-tag line
`<Label` (no `>`, because attributes are on following lines) matches none of them → no increase → the
continuation stays at the tag's column.

### Fix
Add an alternative matching an unclosed opening tag, e.g. `(<[A-Za-z][^>]*$)` (a `<Tag…` with no `>` on
the line — this won't match `/>` or `>`-closed lines, nor `</…` close tags). Also ensure the line
**after** the tag's closing `/>`/`>` de-indents back (the current `decreaseIndentPattern`
`^\s*(\}|\)|</)` doesn't catch a trailing `/>`). For robust multi-line-tag behavior prefer
`onEnterRules` over the `indentationRules` regex (the regex can't express "indent attributes, then
outdent once the tag closes"). `language-configuration.json:27-37`.

### Confidence
Root cause certain (read directly). *(This was the one investigator leg that failed structured output;
diagnosed by hand.)*

---

# React parity gaps (the `on_pressed`-vs-`onClick` question)

The goal was "make the library React-like." It largely is (hooks, JSX-ish markup, `key`, fragments,
`{expr}` with `&&`/ternary/`.map` lowering). These are where it diverges. **`byDesign`** = a real
Godot/GDScript constraint; **fixable** = could be made more React-like. Severity is the day-to-day
papercut size.

### Fixable — worth doing for ergonomics
1. **Event names `on_<godot_signal>` vs `onClick`/`onChange`** *(moderate, fixable)*. `on_pressed`,
   `on_text_changed`, `on_toggled` — derived by stripping `on_` and `node.connect(signal, cb)`
   (`host_config.gd:138-155`). No alias layer, no camelCase; a typo'd `on_click` is a **runtime**
   `push_warning`, not a compile error. You must know Godot's ClassDB signal names. → Add an alias map
   (`on_click`→`pressed`, …) and/or compile-time validation against ClassDB.
2. **No prop spread `{...obj}`; `ref` is `ref["current"]` not `ref.current`** *(moderate, fixable)*.
   The attribute parser accepts only `name` / `name="s"` / `name={expr}` (`guitkx_markup.gd:125-156`)
   — no `{...spread}`. `ref` is a `{"current": x}` Dict. → Add a spread form to the parser.
3. **String-keyed context, no `<Provider>`** *(moderate, fixable)*. `provide_context("accent", v)` +
   `use_context("accent")` (`hooks.gd:219-249`) — same string keys collide across unrelated features,
   and there's no `<Ctx.Provider value=…>` element. Functionally subtree-scoped + reactive, but the
   model differs. → A context-handle object would remove the string-collision footgun.
4. **`children` is a separate param, not `props.children`** *(moderate, fixable-ish)*. The `children`
   param is implicit/auto-injected; React devs expect `props.children` (`guitkx_codegen.gd:429-435`).

### By design — GDScript/Godot constraints (document, don't "fix")
5. **State `s[0]` read / `s[1].call(v)` set** *(fundamental, byDesign)* — the biggest daily papercut.
   GDScript has **no tuple destructuring** (`const [v,setV]=…` impossible) and **no call-sugar** on a
   Callable in a variable (must write `s[1].call(x)`, not `set(x)`). You can alias
   `var set_x = s[1]` but `.call()` remains. Functional + value updates both work; equal-value sets
   bail (Object.is). `hooks.gd:89-112`.
6. **`style={ {…} }` double brace, Godot keys (not CSS)** *(moderate, byDesign)* — outer `{}` is the
   expr hole, inner `{}` the Dictionary literal. Keys are `separation`/`bg_color`/`pad`/… (unknown key
   → runtime warning); the `classes` layer is a plain dict merge, **no CSS cascade/specificity**.
   `style.gd:171-208`, `host_config.gd:75-111`.
7. **`component Name {…}` → sibling `.gd`, exactly one root** *(moderate, byDesign)* — bespoke
   `component`/`hook`/`module` keywords; compiles to a sibling `Foo.gd` you must not edit; multiple
   roots must be wrapped in `<>…</>` (GUITKX0108). `guitkx_codegen.gd`, `guitkx.gd`.
8. **Removing a plain prop keeps the old value** *(moderate, byDesign)* — `apply_props` only sets
   changed props + disconnects removed events/refs/styles; a dropped plain prop is left as-is (no
   generic Godot default to restore), so conditionally omitting `text=` leaves stale text.
   `host_config.gd:40-65`.
9. **Hooks are snake_case, return Arrays/Dicts** *(papercut, byDesign)* — `use_state`→`[v,setter]`,
   `use_ref`→`{"current":…}`. Faithful 1:1 ports otherwise. `hooks.gd`.
10. **Suspense = signal/poll, error boundary = imperative** *(papercut, byDesign)* — GDScript has no
    throw, so Suspense polls `is_ready()` and boundaries show fallback + reset on `reset_key` rather
    than catching a render throw. `v.gd:114-124`.
11. **Control-flow directives `@if/@for/@while/@match`** *(moderate, byDesign)* — needed because
    GDScript is statement-oriented; but note React idioms `{cond and <X/>}`, ternary, and
    `items.map(func(it): return <Row/>)` **do** work inside `{expr}`. Gap: in a **lambda** body only
    `@if`/`@for` lower inline; `@while`/`@match` can't be expressions → **GUITKX0113**.
    `guitkx_codegen.gd:644-685`.

---

# Suggested fix order
1. **BUG-5** (setup source-map span) — unblocks embedded hover/completion/definition **and** is a
   prerequisite for BUG-2. Highest leverage, smallest change.
2. **BUG-3 / BUG-4** (component nav + rename) — correctness; both touch `componentTagAt`/the index.
3. **BUG-6 / BUG-7** (markup hover + completion) — round out the editing experience.
4. **BUG-8** (multi-line tag indent), **BUG-1 / BUG-2** (embedded format + semantic tokens).
5. React parity: the four **fixable** gaps (event aliases, prop spread, context handle,
   `props.children`) as a follow-up pass; document the by-design ones in the README/limitations.

All BUG-1…BUG-7 fixes live entirely in `ide-extensions/lsp-server` (+ `language-configuration.json`
for BUG-8) and need no analyzer changes; the React-parity fixes touch the compiler + runtime.
