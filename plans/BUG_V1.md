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

**React-parity follow-up (library 0.3.0 / IDE 0.4.0):** the "Fixable" parity gaps below are now resolved
(additive, non-breaking):
- **#1 Event names** — DONE. Full React camelCase surface (`onClick`, polymorphic `onChange`, `onSubmit`,
  `onFocus`/`onBlur`, `onPointerDown/Up/Enter/Leave`, `onResize`, generic `onXxxYyy`→`xxx_yyy`), resolved
  node-aware in `host_config.gd` (`_EVENT_ALIASES`/`_resolve_signal`); native `on_<signal>` kept as an
  escape hatch. Mirrored across the LSP (`events.ts` → completion/hover/signature/validation/tokens), all
  3 TextMate grammars, and the schema. 51→54 lsp tests green; GDScript `core_test::_test_react_events`.
- **#2 Prop spread `{...obj}`** — DONE. Parser (`guitkx_markup.gd`) + codegen (`guitkx.gd` → `V._spread_all`)
  + runtime (`v.gd`) + formatter, mirrored in the LSP parser/formatter/diagnostics/semantic-tokens.
  Left-to-right merge (later wins), host + components. `core.test.ts` (3) + GDScript `guitkx_test::_test_spread`.
- **#3 Context handle** — DONE. `Hooks.create_context(default)` → `RUIContext` (`core/context.gd`);
  `provide_context`/`use_context` accept a handle (object-identity key, collision-free) or a String
  (back-compat); handle returns its default when unprovided. GDScript `core_test::_test_context_handles`.
- **#2b `ref["current"]` (not `ref.current`) and #4 `children` param (not `props.children`)** — remain, and
  are **GDScript constraints, not gaps**: Dictionaries have no dot-access, so `ref.current` is impossible
  without making `ref` an Object (which breaks `ref["current"]`), and `props.children` likewise can't be a
  dot-accessed member. Documented as by-design; the `children` render param and `ref["current"]` box stay.

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

---
---

# BUG_V2 — round 2 (2026-07): validation gaps + the camelCase-hooks overhaul

Research pass (workflow, 2026-07-01): traced each reported repro through the Godot compiler, compared
against the **Unity ReactiveUIToolKit** (which has a full `.uitkx` markup compiler — the direct ancestor
of `.guitkx`, with a UITKX#### diagnostic catalog + structure/hooks validators), and verified the prior
round.

### Prior round — VERIFIED fixed-present in current code
All **BUG-1…BUG-8** and React-parity **#1 event names / #2 prop spread / #3 context handle** were
confirmed present in the current tree (not just claimed), with code evidence for each. Branch
`fix/guitkx-lsp-bugs-v1` is **merged** (PR #20, commit `a3671b0`); parity shipped in library 0.3.0 /
IDE 0.4.0 (PR #22). Nothing was missing, partial, or regressed. So: **the previous bugs are actually fixed.**

### Honest correction to the new reports
Two of the five reported "no error" cases **do** emit an error today — the gap is the *quality*/*position*
of the error, not its absence:
- **R1** (`componeent`) → already errors, but with the generic `GUITKX0102 "no declaration found"`, not a
  targeted "did you mean `component`?".
- **R4** (`return <s><  a>`, `return <><  a>`) → already errors (`GUITKX0300` unexpected-token / `GUITKX0301`
  unclosed-tag). The genuine sub-gap is that `<  a>` (space after `<`) is silently reinterpreted as `<>` +
  a boolean attribute instead of being flagged as an invalid/empty tag name.

### Unity parity verdict (the "nuanced differences" you asked for)
| Case | Unity `.uitkx` | Godot `.guitkx` today | Verdict |
|---|---|---|---|
| Misspelled keyword (V1) | `UITKX0305 UnknownDirective` (did-you-mean) | generic `GUITKX0102` | **regression (weak)** |
| Invalid `@class_name` (V2) | `UITKX0109` unknown-attr (schema-dependent) | none — raw passthrough → GDScript parse error | **shared gap** |
| Multi-root loop body / keys (V3) | `UITKX0108` (Error, even in loops) + `UITKX0104`/`0106` | `0108` only at top level; loop body auto-fragmented, dup expr-keys undetected | **regression (high)** |
| Malformed markup (V4) | `UITKX0300-0304` | `0300`/`0301` fire, but `<  a>` mis-parsed | **mostly parity, 1 gap** |
| Double return / unreachable (V5/V6) | `UITKX0108` + **`UITKX0107 UnreachableAfterReturn` (Hint, dimmed)** | second return silently dropped; no dimming | **regression** |

---

## BUG-0 — [TOP PRIORITY / OVERHAUL] Hooks snake_case → camelCase (full React parity)

**Decision (user): Option B — camelCase is canonical, NO aliases, clean breaking change.** Reverses the old
"parity gap #9 (hooks are snake_case, byDesign)".

### Scope — 23 public hooks, 8 layers, ~100 files
Canonical source `addons/reactive_ui/core/hooks.gd` (23 hooks): `useState useReducer useRef useMemo
useCallback useImperativeHandle useEffect useLayoutEffect createContext useContext provideContext
useDeferredValue useTransition useStableCallback useStableFunc useStableAction useSafeArea useSignal
useSignalKey useTween useTweenValue useAnimate useSfx`.

- **Core**: `hooks.gd` (rename 23 decls + internal cross-calls) — 57 refs.
- **Internal callers**: `core/router/router.gd` (~53 real calls — the heaviest), `core/suspense.gd` (2); comment-only in context/signal_registry/signal_store/reconciler.
- **Compiler**: `guitkx.gd` — **two hardcoded lists** must go camelCase: `HOOK_NAMES` (~:916, auto-prefixes bare `use_*(…)`→`Hooks.use_*`) and `_line_calls_hook` (~:161, the GUITKX0013 rules-of-hooks heuristic). **Both currently list only 11 of the 23 hooks** — a latent bug (12 hooks don't auto-prefix today); complete them during the overhaul.
- **LSP**: `lsp-server/src/virtualDoc.ts` `HOOK_STUBS` (the editor mirror of `HOOK_NAMES`) + `core.test.ts` fixtures; rebuild `vscode/server/*.js` artifacts. `server.ts` regex is name-agnostic.
- **Grammars / schema**: **no change** (no hardcoded hook names — verified).
- **Docs**: `ReactiveUIGodotDocs~` — 35 files, ~320 refs (`HooksAPIPage.tsx` is the canonical list).
- **Examples**: 29 `.guitkx`/`.gd` files, ~84 refs.

### Migration (bottom-up so each layer compiles against the one below)
1. `hooks.gd` decls + internal cross-calls (atomic). 2. internal callers (`router.gd`, `suspense.gd`) same commit. 3. compiler `HOOK_NAMES` + `_line_calls_hook` → camelCase **and complete to all 23**. 4. LSP `HOOK_STUBS` + tests, rebuild server.js. 5. codemod 29 examples. 6. codemod 35 docs files. Codemod keyed on the 23-name snake→camel map; guard false positives (`_record` kind-strings `'state'/'effect'/'ref'`, helper names). **Hard break for all existing user code** → bump MAJOR + ship a migration note with the 23-name map.

---

## BUG-V1 — Misspelled declaration keyword gives only a generic error *(low; parity regression)*
`_find_decl` (`guitkx.gd:61-76`) matches the exact words `component`/`hook`/`module`; a near-miss falls
through to `GUITKX0102 "no declaration found"` (`:56-58`) — no pointer at the offending token. **Fix**: add
near-miss detection on a leading identifier at a line start → `unknown declaration 'X' — did you mean
'component'?`. (Unity: `UITKX0305`.)

## BUG-V2 — `@class_name` value is never validated *(medium; shared gap)*
`guitkx.gd:40-43` does a raw `substr + strip_edges` of everything after `@class_name` to EOL with no
validation; an empty/illegal value flows into the emitted `class_name X` (`:85/266/368/420`) and only fails
later as a GDScript parse error in the generated `.gd`. **Fix**: validate a single PascalCase identifier at
the directive and emit a diagnostic otherwise. (Unity's nearest analogue is schema-dependent `UITKX0109`.)

## BUG-V3 — `@for`/`@while` body: no single-root rule + dup expr-keys undetected *(HIGH; parity regression)*
`GUITKX0108` (multiple roots) is enforced only on the top-level render root (`guitkx.gd:129-132`), never
inside a directive body; `_validate_body` (`:188-198`) key-warning is gated on `nodes.size()==1` so a
two-sibling loop body skips `GUITKX0106`, and `_check_dup_keys` (`:200-210`) only runs over one node's
children — never across loop-body siblings. Worse, `_literal_key` (`:218-222`) only returns `kind=="str"`
keys, so `key={ str(i) }` (an **expr** key) collisions are invisible — the exact repro (two siblings, same
`key={str(i)}`) collides every iteration and breaks reconciliation with **no error**. Codegen silently wraps
them in `V.fragment([…])` (`:585-598`). **Fix**: in `_validate_body`, enforce single-root (`GUITKX0108`)
for loop bodies and/or run dup-key across siblings; extend `_check_dup_keys`/`_literal_key` to compare expr
key sources. (Unity: `UITKX0108` even in loops + `UITKX0104`.)

## BUG-V4 — Space after `<` mis-parsed as fragment + attribute *(medium; 1 sub-gap of otherwise-parity)*
`return <s><  a>` and `return <><  a>` **do** error today (`GUITKX0300`/`0301`). But `_parse_element`
(`guitkx_markup.gd:72-78`) treats a zero-length tag run after `<`+whitespace as a fragment `<>` and reads
`a` as a boolean attribute, so `<  a>` is silently accepted rather than flagged. **Fix**: distinguish a true
fragment `<>`/`</>` from `< name` (leading whitespace) → emit an "invalid tag name" diagnostic. (Unity:
`UITKX0300-0304`.)

## BUG-V5 — Second `return` in a component is silently dropped *(medium; parity regression)*
`_split_return` (`guitkx.gd:384-411`) takes the **first** top-level `return` and bounds only that; everything
after (incl. a second `return (...)`) is neither in `setup` nor markup — it's silently discarded, no error.
**Fix**: after locating the markup return, detect trailing top-level code (esp. a second `return`) → emit an
"unreachable code / multiple return" diagnostic. (Unity: `UITKX0108` or `UITKX0107`.) Pairs with BUG-V6.

## BUG-V6 — [feature] Dim the unreachable code after `return (...)` *(parity: Unity `UITKX0107`)*
Code after the markup `return (...)` is provably unreachable (the compiler drops it — `guitkx.gd:133`).
Unity already fades it (`UITKX0107 UnreachableAfterReturn`, Hint, `DiagnosticTag.Unnecessary`). Feasible in
both hosts reusing the existing return-boundary logic:
- **VS Code** *(low effort, idiomatic)*: publish an LSP `Diagnostic { severity: Hint, tags:[Unnecessary] }`
  over the range — VS Code renders it faded natively (like TS dead code). Reuse `markupWindows()`
  (`formatGuitkx.ts:444`) → `markupEnd`→body-`}`, merge into the array at `server.ts:422`. Must advertise
  `publishDiagnostics.tagSupport` in `initialize`.
- **Godot addon**: repaint each unreachable line with a muted colour in `guitkx_code_highlighter.gd`
  (`_get_line_syntax_highlighting` honours only `"color"` — no fade flag; use theme text lerped toward
  background, recomputed in `update_colors()`). Reuse `RUIGuitkxLexer.keyword_at`+`find_matching` (the
  `_split_return` boundary), compute once per buffer + cache, gate behind a `RUIEditorSettings` toggle.
- Caveats (both): module files have many components (dim each per-component gap), skip `hook`/`module`
  decls and pre-markup `return null` guards, and fail safe (dim nothing) on an unclosed return.

---

## Live-LSP addendum (VS Code testing, 2026-07)

Hands-on VS Code testing revealed the validation gaps are primarily a **live-LSP** problem, distinct from
the compiler:
- **`markupDiagnostics` (`server.ts:1209-1213`) only scans INSIDE the markup `return (...)` window**
  (`markupWindows`) and via `scanWindowDiagnostics` (`:1216`) does only **lightweight** checks —
  `GUITKX0104` dup-key, `GUITKX0105` unknown-element, `GUITKX0107` unknown-attr. It runs **no** parser-error
  catalog (0300–0306) and **never scans the setup region**.
- The **full** compiler diagnostics (`0102`, `0108`, `0300`/`0301`, …) exist only in `guitkx.gd` and reach
  VS Code through the **hash-gated sidecar** (`diagsSidecar.ts`, read at `server.ts:460`) — **suppressed as
  soon as you edit** (buffer hash ≠ last-compiled hash). So while typing, none of them show.

Consequence for the round-2 bugs: **BUG-V1 (typo'd keyword), BUG-V4 (malformed markup), BUG-V5 (double
return)** are invisible *live* because (a) a typo'd keyword yields no `markupWindows` entry → nothing scanned;
(b) `return <s><  a>` is in the **setup region**, outside every markup window; (c) `scanWindowDiagnostics` is
not a full parser. **Fix direction:** raise the live LSP to compiler parity — port the structural/parser
validations into the live path (extend `scanWindowDiagnostics` / wire `markup.ts`'s `parseMarkup` errors),
and add a setup-region + no-declaration check — rather than relying on the stale sidecar. (Godot's editor
addon compiles live via `RUIGuitkx.compile`, so it already surfaces the compiler diagnostics the sidecar
can't — the two hosts should converge on the same catalog.)

## BUG-V7 — Host-element hover shows the internal "compiles to `V.label`" *(low; polish)*
`markupHover` (`server.ts:380`) renders `**<Label>** — host element, compiles to \`V.label\` (Godot \`Label\`).`
The `compiles to V.label` is an internal codegen detail users don't need. **Fix**: drop it, keep the Godot
class reference (the valued part) — e.g. `**<Label>** — host element · Godot \`Label\`` (optionally link the
class to the Godot docs). Confirmed working: setup-block hover (BUG-5), markup hover incl. ClassDB attrs
(BUG-6), and component hover + F12/ctrl+click all function.

## BUG-V8 — Hook hover shows only "Callable" *(medium; hover quality)*
Hovering `use_state` in a setup block returns just `Callable` — because the hover routes through the embedded
analyzer, which sees the virtual-doc stub `var use_state = Hooks.use_state` and reports its *type* (Callable),
not the hook's signature. **Fix**: intercept hover on a known hook identifier (the same name list the
compiler/LSP already maintain) and return a curated signature/doc — e.g. `useState(initial) → [value, setter]`
— OR give the `HOOK_STUBS` real typed signatures so the analyzer hovers them meaningfully. Ties into BUG-0
(the hook-name list) and should ship with the camelCase rename.

## BUG-V9 — Shipped features have NO demo/example: prop spread + context handle *(low; coverage gap)*
Two "DONE" React-parity features have **zero** example coverage, so they're undiscoverable and can't be
tested by hand:
- **Prop spread `{...obj}`** (parity #2) — no `.guitkx` in the repo uses it (`grep '{...'` over `**/*.guitkx`
  = 0 matches). Implemented + unit-tested only (`guitkx.gd` codegen, `v.gd._spread_all`,
  `guitkx_test::_test_spread`, `core.test.ts`).
- **Context handle `create_context` → `RUIContext`** (parity #3) — no example uses it (`grep create_context`
  over `examples/` = 0); the `context` demo shows only the older **string-keyed** form
  (`provide_context("accent", …)`). Implemented + unit-tested only (`context.gd`,
  `core_test::_test_context_handles`).

**Fix — add 2 demos** (part of this fix): (1) a **prop-spread** demo (`var cfg = {…}` →
`<Button {...cfg} … />`, showing later-wins merge); (2) a **context-handle** demo (`create_context(default)`
→ provider `provide_context(handle, value)` + consumer `use_context(handle)`, no string key). Both must
**compile** and be wired into the gallery so they run. Author them **after / as part of BUG-0** so the hook
calls use the final **camelCase** names and don't need re-migration. Optionally cross-link from the docs
Context/Styling pages.

## Suggested fix order (round 2)
1. **BUG-0 camelCase overhaul** — user's #1; do it as one bottom-up sequence (core → callers → compiler →
   LSP → examples → docs) + complete the auto-prefix lists to all 23 hooks (closes a latent gap).
2. **BUG-V3** (loop-body single-root + dup expr-keys) — highest-severity correctness gap; compiler-side.
3. **BUG-V5 + BUG-V6** (post-return unreachable — error + dim) — shared root; do together (compiler diagnostic + the two-host dimming).
4. **BUG-V2** (`@class_name` validation), **BUG-V4** (invalid-tag-name), **BUG-V1** (keyword did-you-mean) — smaller compiler/parser validations.

All of BUG-V1…V5 are **compiler**-side (`guitkx.gd` / `guitkx_markup.gd`), mirrored into the LSP for live
diagnostics; BUG-V6 is editor-only (LSP + Godot highlighter); BUG-0 spans the whole stack.
