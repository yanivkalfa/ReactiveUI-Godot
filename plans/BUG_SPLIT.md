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

## ReactiveUI-Godot (`.guitkx` toolchain) — **DONE** (branch `fix/guitkx-live-diagnostics`)

| ID | Priority | Effort | Status | One-liner | Deps |
|----|----------|--------|--------|-----------|------|
| **G1** | High | medium | **DONE** | reindent now anchors to the **first non-blank non-comment line** (not MIN depth) with clamp, in all FOUR mirrors (`guitkx.gd _reindent_setup`, `guitkx_formatter.gd _reanchor`, `virtualDoc.ts emitVerbatimBlock`, `formatGuitkx.ts reanchor`); shared-corpus fixtures `setup_outlier_indent` + `setup_comment_anchor` | — |
| **G4** | Medium | small | **DONE** | same fix in the formatters (one change, four mirrors); Format Document can no longer dedent an `if` body via a stray comment/outlier | G1 |
| **G2** | Medium | medium | **DONE** | `GUITKX0108` fires live: `scanWindowDiagnostics` counts loop-body roots with `parseMarkup` (the parity-tested compiler-port), ranged at the body | — |
| **G3** | Medium | medium | **DONE** | `GUITKX0102` fires live: `missingReturnComponents()` (same recovering walk as `markupWindows`); `splitReturn` distinguishes "no return" from a half-typed unclosed `return (` | — |

Shipped as library **0.4.3** / IDE **0.5.4** together with the analyzer-0.5.3 wiring (below) and an
adversarial-review hardening pass (module members emitted under real names; workspace-completeness
soundness; `vetoGuitkxDeclared` for `.guitkx`-declared class names; comment-only hook bodies).

## Cross-repo note (A3 ↔ G-stub) — **DONE**

`@gdscript-analyzer/core` bumped to **0.5.3**; `setWorkspaceComplete(true)` is armed only after a
fresh full `.gd` scan runs with a live client file watcher (never over-claims). Hook stubs are now
class-level **wrapper funcs** with hooks.gd-byte-identical signatures (drift tripwire test) and
`## @return-tuple(...)` tags on `useState`/`useReducer`/`useTransition` in `hooks.gd` — so
`s := useState(0)` types `s[1]` as `Callable` end-to-end (verified against the real analyzer in
`core.test.ts`). Remaining, tracked follow-ups:

- **Untyped `var s = useState(0)`** stays `Variant` (GDScript semantics — only `:=` infers); needs
  the analyzer's assignment-carried flow narrowing (tracked in GA/TECH_DEBT.md).
- **`.casll()` severity**: a method miss on a typed `Callable` is `UNSAFE_METHOD_ACCESS` (opt-in via
  project warning settings / `--strict`); the closed-builtin-receiver severity study is queued in
  GA/TECH_DEBT.md before it can default on.
- **Block-structure-aware reindent** (levels derived from `:` openers, bracket continuations,
  multi-line strings) would also normalize a deep-outlier FIRST line — today that (already-invalid)
  input errors at the anomalous line, Godot-parity. Design sketched in the review notes.
- **Live `GUITKX0106`** (missing `key` in a loop) and component-level single-root live — the sidecar
  covers both today.
- **`.guitkx` vdoc library shims**: feeding never-compiled `.guitkx` declarations into the analyzer
  as virtual libraries would give full member resolution (arg-checking on `DemoHooks.use_x(...)`);
  today `vetoGuitkxDeclared` guarantees no false UNDEFINED_* but adds no member table.
