# Bug Audit — ReactiveUI-Godot `.guitkx` toolchain + gdscript-analyzer

Researched root-cause + fix for every bug surfaced in the `.guitkx` tooling work. Each entry cites
the **exact source location** and a **production-grade fix** (no bandaids). Two repos are involved:

- **ReactiveUI-Godot** — `addons/reactive_ui/**` (compiler/formatter/plugin) + `ide-extensions/**`
  (the language server / VS Code + VS2022 extensions). Path root below: `RG/`.
- **gdscript-analyzer** — the Rust analyzer (`gdscript`/`gdscript-cli`) the LSP embeds for
  embedded-GDScript intelligence. Path root below: `GA/`.

A companion quick-index split (analyzer vs Godot) is in [`BUG_SPLIT.md`](BUG_SPLIT.md).

> Verification note: root causes were confirmed against the **real analyzer + the guitkx virtual
> doc** (dumping `buildVirtualDoc` output and running the built `gdscript check` CLI), not inferred.

---

## 0. Already fixed & shipped — library 0.4.2 / IDE 0.5.3 (commit `5724aef`, branch `feat/docs-pages-deploy`)

Recorded for completeness; **done**.

| # | Bug | Fix |
|---|-----|-----|
| F1 | `.guitkx` not recompiled until a full Godot restart (external edits didn't retrigger) | `plugin.gd` recompiles on editor **focus-in**; de-duplicated the append-only Errors dock; "resolved" line |
| F2 | Format Document left a **tab + 4 spaces** in nested embedded code | Depth-based `reanchor` (TS `formatGuitkx.ts` + GD `guitkx_formatter.gd`), byte-identical, new fixture |
| F3 | One misspelled header keyword **blacked out the whole file** (only 1 diagnostic) | Error-recovery `declScan.ts`: a near-miss `component`/`hook`/`module` header is analyzed; markup windows are structural (a malformed tag no longer collapses the component) |
| F4 | A misspelled `@class_name` directive (`@clasaas_name`) produced **no** diagnostic | Flagged live as `GUITKX0300` with a did-you-mean |

---

## 1. Analyzer bugs (gdscript-analyzer) — **CRITICAL**

These live in the Rust analyzer. They are why "you can write whatever you want and get no errors,"
plus the ~30-diagnostic cascade on one bad line. All are analyzer-verifiable (unit tests + `gdscript`
CLI) **except A3's guitkx end-to-end**, which additionally needs one Godot-side virtual-doc change.

### A4 — one over-indented body line cascades to ~13–30 bogus diagnostics  ·  effort: **small**  ·  status: **implemented (UNCOMMITTED, pending your decision)**
**Root cause.** Parser is resilient recursive-descent (`GA/crates/gdscript-syntax/src/parser/grammar.rs`);
INDENT/DEDENT come from `prepass.rs`. `block()` (grammar.rs:456) loops `while !self.at(Dedent)` and
closes on the **first** Dedent (grammar.rs:468). An over-indented line is wrapped by the pre-pass in a
balanced `Indent…Dedent`; the stray `Indent` isn't Dedent/Newline so it falls to `primary()`'s
`_ =>` arm (grammar.rs ~886) → `advance_with_error("expected an expression")`, swallowing only the
`Indent`. The now-unmatched inner `Dedent` terminates the block one level too early → the rest of the
function **spills to class level**, so every following `for i in N:` / `var _eN` becomes
`expected a declaration` / `UNUSED_PRIVATE_CLASS_VARIABLE` / bogus `SHADOWED_VARIABLE`. Measured: a
6-line input → **13 syntax errors** (1 real + 12 bogus) + downstream unused/shadow noise.

**Fix.** In `block()` add, before the `stmt()` fallthrough, `if self.at(Indent) { self.over_indented_region(); continue; }`,
and a helper `over_indented_region()` that emits **exactly one** `"unexpected indentation"`, opens one
`Block`, and consumes the stray `Indent` + its matching `Dedent` (depth-tracked) parsing the run as
real nested statements — so control never leaves the function body. Every branch advances/breaks
(fuel-safe). Follow-up (not in this slice): the same `while !self.at(Dedent)` premature-close exists in
`property_body` (grammar.rs:401), `match_stmt` (~613), and inner-class `members(&[Dedent])`.

**Verified.** CLI now reports 1 `GDSCRIPT_SYNTAX: unexpected indentation` + only legitimate warnings,
zero `expected a declaration`; regression test `over_indented_body_line_does_not_cascade_to_class_level`
(`parser.rs`); full workspace `cargo test` green. **This fix currently exists uncommitted in the
working tree** (`grammar.rs` +48, `parser.rs` +36). Keep or revert — your call.

### A2 — a bare call to a **local/param Callable** never records a use → false UNUSED_*  ·  effort: **small**  ·  status: **to do (foundation for A1/A3)**
**Root cause.** `GA/crates/gdscript-hir/src/infer.rs`. (1) `resolve_call_name` (2300-2327) resolves
`foo(...)` through own-func → self-base method → utility → gdscript-builtin → constructor → `Ty::Unknown`
and **never consults `self.locals`**. (2) The `Expr::Name` arm of `infer_call` (2193-2197) is
`let ret = self.resolve_call_name(&name); … ; ret` — unlike the value-read path `resolve_name`
(2886-2888, which does `used_locals.insert(...)`), it **never records a read** of the local/param. The
UNUSED_* pass (219-244) then flags the called local. Confirmed on the built CLI: `UNUSED_VARIABLE` fires
on `useState` though `useState(0)` is called next line; same for `cb: Callable` called as `cb(0)` and
a lambda `var lam = func(x): …` called as `lam(5)`. (`Ty::Callable` carries no return type, so the call
result is correctly the `Unknown` seam — the defect is *only* the missing use-recording.)

**Fix.** In the `Expr::Name` arm of `infer_call` (2193-2197), check `self.locals` first (locals-first,
matching `resolve_name`'s ordering at 2913-2917): if present, `used_locals.insert(...)` and resolve the
call as the seam `Ty::Unknown`; else fall to `resolve_call_name`. Do **not** invent a `Variant` return
(would risk false `INFERENCE_ON_VARIANT`). Arg-checking is unaffected (`check_call_args` already ignores
locals). **Depends on: nothing. Blocks: A1 (below).**

### A1 — undefined identifier/call detection: `usseState(0)` produces zero diagnostics  ·  effort: **large**  ·  status: **to do** · *(already logged in `GA/TECH_DEBT.md` CRITICAL)*
**Root cause.** `resolve_call_name` (infer.rs:2300-2327) returns a single undifferentiated `Ty::Unknown`
seam (comment 2324-2326) for *any* unresolved name — conflating (a) "unresolved because it's cross-file
and we haven't loaded it" (must stay silent: `MyClass()`, `Music.play()`) with (b) "unresolved with the
full project graph loaded → a genuine typo" (should be `UNDEFINED_FUNCTION`). Godot's own compiler flags
`Function "usseState()" not found in base self`; the analyzer is the only silent surface. `infer_field`
has the mirror gap for methods on uninformative receivers.

**Fix.** Split the seam by **project-graph-loaded**: add `WarningCode::UndefinedFunction` /
`UndefinedIdentifier` (later `UndefinedMethod`) to `warnings.rs`; have `resolve_call_name` return a
resolved-vs-unresolved signal so the `&mut self` caller (`infer_call` `Expr::Name` arm, 2193-2197 — the
same arm A2 touches) can emit. Emit **only** when: every tier missed (own-member, base method, utility,
gdscript-builtin, constructor, **local per A2**, project-global via `global_registry(db).resolve(name)`),
the **graph is loaded** (never single-file mode), and it is not dynamic dispatch (`obj[name]()`,
`_call`/`_get`, `super`). Gate on "graph loaded," **not** "guitkx vs .gd" (the guitkx LSP always feeds
the whole project + `project.godot`). **Depends on: A2** (else valid `useState(...)` local calls
false-flag). **Biggest false-positive surface in the whole plan — needs the broad regression corpus
before default-on.**

### A3 — hook-return tuple typing so `sliced[1].casll()` is catchable  ·  effort: **large**  ·  status: **to do (analyzer portion verifiable now; guitkx e2e needs a Godot change)**
**Root cause.** Hooks return a fixed-shape pair (`useState → [value, setter: Callable]`), but the call
result is the `Unknown` seam, `Ty` (`GA/crates/gdscript-hir/src/ty.rs`) has **no tuple variant**, and
index expressions can't select an element type by constant index — so `sliced[1]` is `Unknown` and a
method on it can't be checked. (Godot itself doesn't catch this either → this is a **value-add beyond
Godot parity**, same category as the documented `is`-narrowing deviation.)

**Fix (two coordinated parts).** *Analyzer (verifiable now):* add `Ty::Tuple(Vec<Ty>)` to `ty.rs`
(never-cascade discipline); in `infer_index`, a `Ty::Tuple` receiver + **constant** integer literal in
bounds returns the element `Ty` (non-constant / OOB → element-union or seam); provide a tuple-returning
signature source for the known `Hooks.*` (API table or a guitkx-specific typing hook). *Godot (needed
for guitkx e2e):* `RG/ide-extensions/lsp-server/src/virtualDoc.ts` `declareHookStubs` (351-353) emits an
untyped `var useState = Hooks.useState` (types `Variant`), which can't carry the tuple — it must emit
**typed** stubs (or the analyzer special-cases the known `Hooks.*` names). **Depends on: A2** (call-result
seam), composes with **A1** (once `sliced[1]` is a typed receiver, `UNDEFINED_METHOD` on `.casll()`
becomes sound). See the full design in `GA/TECH_DEBT.md`.

---

## 2. ReactiveUI-Godot bugs — **leave for now (documented, not fixed)**

### G1 — virtual-doc setup reindent anchors to MIN depth → "expected an expression" + the whole @for cascade  ·  effort: **medium**
**Root cause.** `RG/ide-extensions/lsp-server/src/virtualDoc.ts` `emitVerbatimBlock` anchors the setup
block to `base = min(depths)` (306) and emits each line at `level = Math.max(1, indent + depths[k] - base)`
(316). A **single outlier-indented line** shifts every other line: with one line shallower, the *normal*
lines emit at 2 tabs beneath the 1-tab `render()` body — a statement over-indented with no preceding `:`
= Godot's `GDSCRIPT_SYNTAX: expected an expression`. That trips the parser (see **A4**) and everything
after spills to class level → the `@for` `expected a declaration` ×5 + bogus `UNUSED_PRIVATE_CLASS_VARIABLE`
/ `SHADOWED_VARIABLE`. **There is no independent @for bug** — it is entirely this cascade. (A4 makes the
parser *tolerant*, but the emitted `.gd` must still be *correct*, so this must be fixed too.)

**Fix.** Stop anchoring to MIN. Anchor to the **first non-blank line's depth** and **clamp**:
`level = Math.max(1, indent + Math.max(0, depths[k] - anchor))` (a stray shallow line never raises the
rest; nothing goes shallower than the body indent). Best: block-structure-aware (only increase after a
line ending in `:`). **Must be applied to all THREE mirrored reindenters together** — `virtualDoc.ts`
`emitVerbatimBlock` (301-316), `guitkx.gd` `_reindent_setup` (902-919), `formatGuitkx.ts` `reanchor`
(311-329) — cross-tested byte-identical via `test-fixtures/formatter-cases.json`; add an outlier-indent
fixture.

### G4 — formatter reflows nested code to the wrong indent (same MIN-anchor bug)  ·  effort: **small**  ·  depends on **G1**
**Root cause.** `formatGuitkx.ts` `reanchor` (305-332) uses the same `base = min(depths)` (311-321) →
Format Document pushes the majority a level off. Mirrors `guitkx.gd _reindent_setup`, so format + codegen
agree on the *same wrong* output. **Fix:** the same change as G1 (it is literally one fix across the three
reindenters).

### G2 — `@for`/`@while` body single-root rule (`GUITKX0108`) never runs live  ·  effort: **medium**
**Root cause.** The rule EXISTS in the compiler — `guitkx.gd` `_validate_body` (270-285) emits
`GUITKX0108` — but the LSP **live** tier (`server.ts:454-461`) never computes it; `scanWindowDiagnostics`
(server.ts:1276-1383) only checks 0104/0105/0107/0300. So double `<Label>` in one loop body is only
flagged post-save via the sidecar (line-1, deduped), never live. **Fix:** add a live single-root count in
`scanWindowDiagnostics`, or port `_validate_body`, emitting `GUITKX0108` ranged at the body (reuse the
`splitReturn`/body-parse helpers; match the compiler's root-counting so it doesn't diverge on save).

### G3 — missing `return (...)` (`GUITKX0102`) never flagged live  ·  effort: **medium**
**Root cause.** Compiler catches it (`guitkx.gd` `_split_return` 478-505 / `_parse_component_at` 196-199),
but live: `markupWindows` (formatGuitkx.ts:539-567) just produces **no window** when there's no return,
and `buildVirtualDoc` emits `\tpass` — both silent. Only the sidecar surfaces it (line-1). **Fix:** wire a
live diagnostic off `splitReturn` returning null (formatGuitkx.ts:621-648), ranged at the component
name/body; must not fire on non-component helper funcs.

---

## 3. Recommended order (analyzer work), shared foundations, biggest risk

**Order:** **A4 → A2 → A1 → A3.**
1. **A4** — standalone, zero deps, kills the cascade so real diagnostics are readable on any over-indented
   input. (Already implemented/verified, uncommitted.)
2. **A2** — small, zero deps. Makes bare-name local-Callable calls record a use and establishes
   locals-first resolution. **Must land before A1.**
3. **A1** — large, depends on A2 + the project-graph gate. Highest user value (catches `usseState` live)
   and highest FP risk → after the foundations, with a regression corpus.
4. **A3** — large, depends on A2; land the analyzer portion (Ty::Tuple + constant-index) first, coordinate
   the Godot typed-hook-stub change for the guitkx e2e; composes with A1.

**Shared foundation:** `infer.rs:2193-2197` (the `Expr::Name` call arm) is the single choke point.
A2 makes it consult locals; A1 extends the *same* path to emit `UNDEFINED_FUNCTION` when a name resolves
nowhere; A3 replaces A2's seam with `Ty::Tuple` for known hook signatures. **A1's soundness literally
depends on A2 executing first.** A4 is independent (syntax layer) but a practical prerequisite — until the
cascade is fixed, HIR diagnostics are drowned in ~30 bogus errors.

**Biggest risk:** **A1's false-positive surface** — cross-file `class_name` globals + autoloads, local
Callables (mitigated only if A2 lands first), dynamic dispatch, and any missing builtin/utility in the API
table. Shipping A1 before A2 or without a strict "project graph loaded" gate would false-flag the very
`useState` aliases the guitkx workflow depends on — worse than the current silent gap. Prove it against
the broad regression corpus (the one used to drive TYPE_MISMATCH false-positives 55→1) before default-on.
