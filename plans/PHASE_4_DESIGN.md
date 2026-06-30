# Phase 4 — Compiler Parity + Embedded-GDScript Fidelity (production design)

> ⚠️ **Backend correction (2026-06-30).** §2's "scope-aware virtual doc" is now consumed by
> **`@gdscript-analyzer/core`** (in-process, headless), **not** Godot's built-in GDScript LSP. Anywhere this
> design says "forward to Godot's LSP" / "the proxy", read `@gdscript-analyzer/core` via `analyzerAdapter.ts`.
> The design itself stands; only the consumer changed. Live status: `PARITY_PLAN.md`.

> **STATUS: COMPLETE (2026-06-22).** §1 (jsx-as-value), §4 (module), §5 (fidelity + grammar +
> byte-identity CI), §2 (scope-aware virtual doc — LIVE-verified against the editor), §3 (structured
> diagnostics + live LSP dup-key tier) all shipped + tested. **§0 (the GDScript-parser absolute-offset
> refactor) was consciously DESCOPED:** its only consumer would be compiler-side diagnostic ranges, but
> compiler diagnostics surface through the `@tool` plugin's `push_error`/`push_warning` (which take no
> ranges), while the user-visible diagnostic ranges (LSP squiggles) are computed TS-side from the
> document natively (see §3's `markupDiagnostics`). The heavy refactor had no surface, so it was not
> done. If a future need arises (e.g. a `#line`-style source map for the generated `.gd`), revisit §0.


Source: a 10-agent design+critique workflow (2026-06-22) reading Unity's actual implementation and the
current Godot code. **Every first-pass design came back "needs-work"** — the corrected designs below bake
in the critics' fixes. One load-bearing assumption was smoke-tested (✓ noted).

## 0. Foundational refactor — ABSOLUTE source offsets (do FIRST; unblocks 4 of 5 sub-areas)

The critics found the same blocker in diagnostics, the virtual doc, and jsx-as-value: **the parser
destroys absolute source positions.** `_split_return` parses the component `body` *substring* (offset 0 =
body start, not file start); `_read_brace_body`/`_read_paren` hand control-flow bodies to `Markup.parse`
as *detached strings*; and `guitkx_markup.gd` `strip_edges()`es captured text (expr code, attr value,
cond/header, case value). So no diagnostic can carry a real source range and no virtual-doc segment can map.

**Fix (prerequisite for everything else):**
- Thread an **absolute base offset** through the pipeline. `Markup.parse` already takes `(src, start, end)`
  — pass the **full source** + the absolute `[start, end)` window instead of the extracted substring.
- `_split_return` returns the absolute body-start offset it already computes (`j + 1`).
- `_read_brace_body`/`_read_paren` return `body_off`/`body_end` (absolute); control-flow bodies are
  re-parsed over the **same full source** at those absolute offsets, never as detached strings.
- Every AST node records **raw `start`/`end` offsets BEFORE any `strip_edges()`** (keep both the raw span
  and the trimmed text). `_parse_nodes`/`_parse_element` store each node's `_end`.
- Add `to_line_col(src, off)` (1-based line / 0-based UTF-16 char) computed lazily only at the LSP boundary.
  Account for CRLF (the offset includes `\r`).

This is mechanical but load-bearing. It also fixes the bare-`return <Tag/>` window mis-bounding (fidelity #7)
because nodes then carry real end offsets.

## 1. JSX-as-value lowering  (verdict: needs-work → corrected)

**Goal:** markup nested inside an embedded expression (`text={ c if x else <A/> }`, `{ items.map(func(it): return <Row item={it}/>) }`, `cond and <A/>`) lowers to `V.*` calls. Today it's passed verbatim → invalid `.gd`.

**Unity mechanism (proven):** NOT general `<`-disambiguation — a **position-gated whitelist**. A `<` starts
markup only when it follows (ws-skipped) a boundary token that can only be followed by an expression, AND the
char after `<` is a letter/`_`/`>` (tag or fragment). `FindBareJsxRanges`/`FindJsxBlockRanges` + element
extent via `FindJsxElementEnd` (depth-tracked, skipping strings + `{…}` holes). `&&` is desugared to a ternary.

**Corrected design:**
- New `addons/reactive_ui/guitkx/guitkx_jsx_scan.gd` (`RUIGuitkxJsxScan`). It **reuses `L.skip_noncode` /
  `L.find_matching`** for all string/comment/brace skipping — **zero edits to the byte-identical lexer/scanner.**
- `find_markup_ranges(src, start, end)` walks via `skip_noncode`, and at each position tests the
  **GDScript-specific boundary whitelist** (NOT Unity's C# `=>`/`?:` arms — those don't exist in GDScript):
  - `return` / `else` (keyword_at), `(`, `[`, `,`, `and`/`&&`/`or`/`||` (short-circuit, all desugared),
    `=` **only as a simple assign** (i+1≠`=`, i-1 not a compound-assign lead `+-*/%&|^<>!`, not `:=`),
    and `:` **only as a dict value** (innermost open delimiter is `{`, not `::`/`:=`/type-hint/lambda-header).
  - Maintain a delimiter stack so the dict-`:` rule is context-correct.
  - Guard `<<`/`<=` (advance past the 2-char op, never test as a tag).
  - Require char-after-`<` ∈ {letter, `_`, `>`}; handle bare fragment `<>…</>` in `_find_element_end`.
- `_splice_expr_markup(expr, line, ctx)` re-parses each range with `Markup.parse` and emits via the existing
  `_emit_expr` (so nested control-flow/attrs/children work), splicing `V.*` back in. The **single sink** is
  `_emit_expr`'s "expr" case → every re-parsed sub-expr inherits splicing.
- **`and`/`&&` desugar:** `cond and <A/>` → `(V.a(...) if (cond) else null)`, with a precedence-aware LHS
  finder (GDScript boundaries: `or`,`,`,`;`,`if`,`else`, paren depth — NOT C# `?`/`:`/`??`).
- **Control-flow in a value position** (a `@for`/`@while` inside `{expr}`): **forbid with a diagnostic**
  (mirror Unity UITKX0025) — it can't be hoisted out of a lambda/attr. `@if`-as-value uses native ternary.
- **`_attr_value_code` must take `ctx`** (today it's ctx-free) so attribute exprs route through the splice.
- **Deep flatten (blocker):** `V._norm` flattens only ONE level (v.gd:144-147), but `.map(...).map(...)` yields
  array-of-arrays. **Fix `_norm` to recurse** (deep flatten + null-drop) so any-depth expression children work.

## 2. Scope-aware LSP virtual document + robust source map  (verdict: needs-work → corrected; HIGHEST RISK)

**Goal:** `{expr}` referencing `@for`/`@if` vars + setup locals stop getting false "undeclared identifier";
nested markup in `{expr}` no longer reaches Godot as raw markup.

**Corrected framing (critic blocker):** the virtual doc is its **OWN artifact**, NOT a mirror of the compiler's
`__cfN` accumulator output. Model the BODY on **Unity's `VirtualDocumentGenerator`**: emit real `for`/`while`/
`if`/`match` headers (so loop/branch vars are in scope) with each `{expr}` as a `var _eN = (expr)` sibling
**inside its block, recursively nested** for nested control flow. Reuse the compiler only for header/subject/
pattern/expr TEXT extraction.

**Decisions baked in:**
- **Do NOT apply `_apply_hook_aliases`** in the virtual doc (it's non-length-preserving). Instead pre-declare
  the hook names as in-scope stubs in the scaffold so `use_state(...)` resolves.
- **Do NOT port `RUIGuitkxMarkup` to TS** (the critics strongly warn against a 2nd parser that drifts). Reuse
  the existing TS scanner primitives to do the **shallow structural walk** the LSP needs (find control-flow
  headers + `{expr}` spans), not a full re-parse.
- **Source map = sorted SEGMENT list with kinds** (Mapped vs Scaffold), binary-search lookup, bidirectional,
  boundary tie-break defined. **Rewritten regions are SCAFFOLD-only, never mapped** → length-preservation of
  mapped segments holds (this is exactly why Unity survives future rewrites like the formatter).
- Empty/branchless control flow → `pass` body (mirror the compiler); skip empty `match`.
- `match` → real `match subject:` + real pattern arms; tag pattern-segment kind so **match-pattern diagnostics
  are filtered out** in the diagnostic mapper.
- Boolean-shorthand attrs / `key=` exprs handled; CRLF handled in offset↔position.
- **Still to verify at implementation (needs running editor):** that Godot's LSP resolves a `@for` loop var
  referenced in a `var _eN=(x)` inside the emitted `for x in xs:` block. (We already verified local-var +
  project-global resolution live; this extends that.)

## 3. Diagnostics model + full UITKX catalog  (verdict: needs-work → corrected)

- **`RUIGuitkxDiag`** record (`addons/reactive_ui/guitkx/guitkx_diag.gd`): `{ code, severity (ERROR|WARNING|
  INFO|HINT), message, start, end (absolute offsets), category }`. Offsets are the source of truth; line/col
  computed lazily at the boundary. **Depends on §0** (absolute offsets) — that's the blocker the critics flagged.
- **Catalog** as a single JSON (`ide-extensions/grammar/guitkx-diagnostics.json`): the full code list ported
  from Unity's `DiagnosticsAnalyzer`/`HooksValidator`/parser, each `{number, name, severity, category, message
  template}`. Map every Unity code → `{port | adapt | drop}`: drop Unity/Roslyn/HMR-only (0120/0121/0200/0210/
  0211/0150/0112), adapt ref-routing, port syntax/structure/rules-of-hooks. **Renumber the 0103 collision**
  (it's used for BOTH module-unsupported and filename-mismatch) — give module-unsupported a fresh code.
- **Build step** emits the catalog as a TS module for the packaged LSP (no runtime file read); the GDScript
  compiler reads the JSON via `res://`.
- **LSP diagnostics = layered** (the critics: TS can't call the GDScript compiler): (a) the LSP does its own
  fast TS **structural tier** (unclosed tags, unknown element/attr + did-you-mean, dup/missing key,
  rules-of-hooks, multi-root) for live feedback with no editor; (b) embedded-GDScript diagnostics come from the
  Godot LSP proxy on the virtual doc; (c) full compiler diagnostics surface on save from the `@tool` plugin.
  did-you-mean on attributes is gated behind the live ClassDB property set (suppressed when Godot is offline).

## 4. module (multi-declaration) support  (verdict: needs-work → corrected; emit VERIFIED ✓)

- A `module` file → ONE `.gd` class with **one `static func` per declaration** (`static func Foo(props,
  children) -> RUIVNode` per component; `static func use_x(...)` per hook), each with a `# from <file>.guitkx`
  banner for manual line-mapping.
- **Intra-module `<Foo/>` → `V.fc(Foo, props, …)` using the BARE static-func name** as the Callable — **smoke-
  tested ✓** (`V.fc(bar, …)` inside the class renders; `self.X`/`ClassName.X` self-reference avoided).
- Refactor: extract `_emit_component_func(func_name, …)` / `_emit_hook_func` so the single-file path
  (`render`/`<hookname>`) and the module path share emit; **assert golden-equality of existing single-file output.**
- `_apply_hook_aliases` rewritten as a **single skip_noncode-aware pass** (fixes the substring-corruption bug,
  §5 item 5) and excludes module-local hook names.
- **No FS probe in the compiler** (it's engine-free) → drop the sibling-file "unknown component" check; emit the
  reference anyway (the GDScript compiler surfaces a real error if missing).
- Diagnostics: duplicate decl name → error + skip the duplicate func (don't emit two same-named funcs);
  host-tag-shadow + lowercase-component-name rejected.

## 5. Fidelity leaf fixes  (verdict: needs-work → corrected; ship 2/3/5/6/7, reframe 1/4)

- **Item 1 (grammar `<`/`>` mis-color):** REFRAME — Unity's grammar *also* has tag rules in paren-expression;
  removing them would break `return (<markup>)`. The `(a < b)` mis-color is intrinsic JSX/markup ambiguity Unity
  lives with. **Don't "fix" by removing tag rules.** (Optional: minor tightening only.)
- **Item 2 (raw-string prefix R):** DO IT, both scanners — the GD lexer and TS scanner have **already drifted**
  (`R` clause). Remove `|| c === "R"` so the set is `{r,&,^}`; fix grammar `[rR&^]?`→`[r&^]?`. Add a
  token-boundary guard (prefix only when `src[i-1]` is not ident/`)`/`]`/quote).
- **Item 3 (`$`/`%`/`^`/`&` + node paths):** DO IT, both scanners + grammar — extend the prefix set with the
  token-boundary guard; add grammar leaf rules for `$"..."`/`$Node`, `%"..."`/`%Name`, `^"..."`, `&"..."`
  (anchored on the following quote, before `gd-operator`); add `await`/`signal`. Also fix `_parse_text`
  (markup text scanner) so a bare `$Player/Sprite` or `%Health` in markup text doesn't mis-split.
- **Item 4 (find_matching mixed stack):** REFRAME — it's **not** a correctness bug for VALID GDScript (balanced
  code never has cross-type imbalance). Deprioritize as optional Unity-parity alignment.
- **Item 5 (hook-alias substring bug):** DO IT — replace the blind `.replace()` (corrupts `my_use_state(` and
  `"use_state()"` strings) with a **single skip_noncode-aware, token-boundary pass**. (Open: wrapper-method vs
  rewrite — needs confirming GDScript static-func lambda resolution; default to the safe rewrite.)
- **Item 6 (deep child-flattener):** DO IT — `_norm` recurse (see §1); make `_emit_body` return precise
  `(expr, is_array)` where `is_array` is true IFF the body is exactly one `@for`/`@while` node.
- **Item 7 (bare-return mis-bounding):** fixed by §0 (nodes carry real end offsets).
- **Byte-identity enforcement:** add a CI cross-test running the SAME string corpus through both the GDScript
  lexer and the TS scanner and asserting identical skip/balance results (nothing enforces it today — that's how
  the `R` drift happened).

## Verification status
- ✓ Module bare static-func Callable (`V.fc(bar, …)`) — smoke-tested, renders.
- ⏳ Godot LSP resolves a `@for` loop var inside an emitted `for x in xs:` block — verify against the running
  editor when building the virtual doc (extends the already-verified local-var/project-global resolution).
- ⏳ GDScript static-func resolution from a lambda (hook-alias wrapper option) — verify if we choose wrappers.

## Implementation order (dependency-driven)
1. **§0 absolute offsets** (parser refactor) — unblocks 3, 1, 2.
2. **§5 fidelity leaf** (items 2/3/5/6/7 + the `_norm` deep flatten + byte-identity CI) — mostly independent, low risk.
3. **§1 jsx-as-value** (`guitkx_jsx_scan.gd` + splice).
4. **§4 module** (emit verified).
5. **§3 diagnostics** (model + catalog + ranges — needs §0).
6. **§2 scope-aware virtual doc** (LSP, highest risk — needs §0 raw spans).
Each ships green tests before the next; golden tests guard the existing single-file output.

## Resolved language-design decisions (2026-06-22)
1. `@if`-as-value → GDScript-native ternary `cond if c else <A/>` (no JSX `?:`).
2. Multi-root `{ <A/> <B/> }` → **hard error** (matches Unity UITKX0025); author writes an explicit `<>…</>`.
3. Short-circuit-to-markup → **`and` and `&&` only** (the `cond && <El/>` idiom ReactiveUIToolKit desugars);
   `or`/`||` NOT supported.
4. `module` file → **`module Name { … }`** (named block; `Name` sets the `.gd` class; matches Unity + the
   existing grammar rule). Intra-module `<Foo/>` → `V.fc(Foo, …)` (bare static-func Callable, verified).
