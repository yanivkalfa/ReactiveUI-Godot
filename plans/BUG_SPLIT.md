# Bug Split — analyzer vs ReactiveUI-Godot

Quick index for the [`BUG_AUDIT.md`](BUG_AUDIT.md) catalog. Which repo owns each bug, priority, effort,
status, and dependencies. **The analyzer bugs are the ones queued for implementation; the Godot bugs are
documented but left for now.**

## gdscript-analyzer (Rust) — implement here

| ID | Priority | Effort | Status | One-liner | Deps |
|----|----------|--------|--------|-----------|------|
| **A4** | Critical | small | **DONE** (branch `fix/guitkx-diagnostic-gaps`) | one over-indented line → ~13–30 bogus diagnostics; parser now recovers the run as a nested error block, ONE diagnostic | — |
| **A2** | Critical | small | **DONE** (same branch) | bare call to a local/param `Callable` (`useState(0)`) never recorded a use → false `UNUSED_*`; locals-first in the call arm + shadow consistency | — |
| **A1** | Critical | large | **DONE** (same branch) | `usseState(0)` never flagged; `UNDEFINED_FUNCTION`/`UNDEFINED_IDENTIFIER` gated on a loader-asserted COMPLETE workspace; corpus 216→**0** FPs; engine model bumped 4.5→**4.7** | **A2** |
| **A3** | High (value-add) | large | **DONE, analyzer side** (same branch) | `Ty::Tuple` + `## @return-tuple(...)` doc-tag + constant-index projection; `sliced[1].casll()` flags via `:=`/direct/cross-file paths. guitkx e2e still needs the G-side stub change + tags in `hooks.gd` | **A2** (+ G-side) |

**Order: A4 → A2 → A1 → A3.** A2 is the foundation A1 and A3 both build on; A1 is unsound (false-flags
valid `useState`) without A2. Biggest risk is A1's false-positive surface (cross-file globals, autoloads,
dynamic dispatch) — needs the broad regression corpus before default-on.

Files: `crates/gdscript-syntax/src/parser/grammar.rs` (A4), `crates/gdscript-hir/src/infer.rs` (A1/A2/A3),
`crates/gdscript-hir/src/{warnings.rs,ty.rs}` (A1/A3).

## ReactiveUI-Godot (`.guitkx` toolchain) — leave for now

| ID | Priority | Effort | Status | One-liner | Deps |
|----|----------|--------|--------|-----------|------|
| **G1** | High | medium | to do | virtual-doc setup reindent anchors to MIN depth → one outlier line breaks the emitted `.gd` ("expected an expression" + the whole `@for` cascade) | — |
| **G4** | Medium | small | to do | Format Document reflows nested code to the wrong indent — same MIN-anchor bug in the formatter | G1 |
| **G2** | Medium | medium | to do | `@for`/`@while` body single-root rule (`GUITKX0108`) exists in the compiler but never runs **live** — double `<Label>` not flagged while typing | — |
| **G3** | Medium | medium | to do | missing `return (...)` (`GUITKX0102`) never flagged **live** — only post-save via the sidecar | — |

**G1 + G4 are one fix** replicated across three byte-identical reindenters (`virtualDoc.ts`
`emitVerbatimBlock`, `guitkx.gd` `_reindent_setup`, `formatGuitkx.ts` `reanchor`) — do them together
(cross-tested by `test-fixtures/formatter-cases.json`). **G2 + G3 share a shape:** a compiler rule that
exists but is never run in the live LSP tier — both should reuse the existing `splitReturn`/body-parse
helpers rather than re-implement.

Files: `RG/ide-extensions/lsp-server/src/{virtualDoc.ts,formatGuitkx.ts,server.ts}`,
`RG/addons/reactive_ui/guitkx/{guitkx.gd,guitkx_formatter.gd}`.

## Cross-repo note (A3 ↔ G-stub)

A3's end-to-end (`sliced[1].casll()` flagged in a real `.guitkx`) needs **both** the analyzer `Ty::Tuple`
work **and** a Godot change: `declareHookStubs` (`virtualDoc.ts:351-353`) must emit *typed* hook stubs so
the tuple return survives the `var useState = Hooks.useState` alias. The analyzer portion is verifiable now
on a hand-written `.gd`; the guitkx path is blocked on that Godot change.
