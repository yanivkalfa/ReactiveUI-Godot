# Imports leg (0.10.0) — adversarial bug hunt

> **Scope:** every line I wrote on `feat/guitkx-imports` (16 commits, ~1660 GDScript + ~200 TS lines):
> the mixed-decl compiler, the resolver (`guitkx_resolve.gd`), config (`guitkx_config.gd`), the
> codemod (`guitkx_migrate.gd`), the two-pass codegen/sidecar/staleness changes, HMR, and the TS LSP
> mirror. **NOT a re-review of pre-existing code** except where this leg changed its behavior.
>
> **Method.** (1) An 11-finder multi-agent adversarial workflow (71 subagents, 3.5M tokens), each
> finding refuted by 3 distinct-lens skeptics; 20 findings survived (≥2/3 REAL). (2) An **independent**
> pass by me. (3) **Every** finding below was then verified by me directly — an empirical repro run
> against the real compiler in Godot 4.7 headless, or a line-level code trace. The per-finding
> "Evidence" line records which. The adversarial verifier skewed lenient (0 refutations overall), so
> the independent re-verification is what these rest on, not the vote.
>
> **Status: ALL FIXED (2026-07-14).** Every bug below is resolved, each with a regression test built
> from its exact repro, using the house loop (research → develop → test → bughunt → fix → commit). The
> full matrix is green (build 0 err, migrate idempotent, contract 66, all GDScript suites, corpus,
> changelog, TS 182 + smoke, vscode, docs build+lint). Fix commits:
>
> | Commit | Bugs |
> |---|---|
> | `44d05ed` | BH-01, BH-08 (parse: markup-lexis enumeration, multi-line imports) |
> | `0d99add` | BH-02, BH-17 (shared render-component rule, last-`@class_name` parity) |
> | `ed19778` | BH-03, BH-13, BH-14 (codemod offset, canonical path-boundary specifier) |
> | `d97aea3` | BH-06, BH-09 (bare hook-import lowering, mixed `@uss` 2210) |
> | `e79771e` | BH-10, BH-11, BH-12, BH-16 (wire the four dead diagnostics 2306/2307/2308/2309) |
> | `de43019` | BH-04, BH-05 (TS: v3 sidecar code, index all mixed decls) |
> | `7289c79` | BH-07, BH-15, BH-18 (transitive HMR roots, mixed hook-sig reset, 2305 offset) |
>
> Guiding principle throughout: **no bandaids.** The three duplicated specifier functions were merged
> into one canonical `RUIGuitkx.import_specifier`; the render-target-component rule became one shared
> `RUIGuitkx.render_component` used by the emitter AND both export tables; the bare-hook lowering
> implemented the deferred §6.4 design (aliased const + lexer-aware call rewrite) rather than
> suppressing the case.
>
> **Original triage (below) preserved for the record.** The shipped example tree was unaffected by all
> of these — every bug needed a NEW input shape (a mixed-decl file, a hand-written `export`, a
> `@class_name`≠decl-name, a bare top-level hook import, a `~/` custom root, a value cycle, or the VS
> Code diagnostic surface), which is why the leg's matrix stayed green before the fixes.

## Summary

| ID | Sev | Area | One-liner | Evidence |
|---|---|---|---|---|
| BH-01 | HIGH | compiler/parse | `_decl_body_end` uses GDScript brace-matching, not markup — a markup comment (`//` `/* */` `<!-- -->`) with a `}` in a component body desyncs decl enumeration → spurious `GUITKX2105` or a dropped declaration | repro |
| BH-02 | HIGH | resolver/emit | `exports_of`/`decl_table` record a component's cross-file func as its decl name, but the emitter always names the sole/binding component `render`; when `@class_name` ≠ decl name, a cross-file import lowers to `V.comp(path,"Decl")` which doesn't exist | repro |
| BH-03 | HIGH | codemod | import block inserted at the decl **keyword** (`at`) not its **start**; a file whose first decl is already `export`-prefixed becomes `export import { … } … component X` — invalid + non-idempotent | repro |
| BH-04 | HIGH | TS LSP | `server.ts mergeCompilerSidecar` gates the code prefix on `sc.v === 2`; my v2→v3 bump makes it false, so **every** compiler diagnostic in VS Code now shows with no `GUITKX####` code at all | code trace |
| BH-05 | HIGH | TS LSP | `workspaceIndex.reindex` still keeps only the first top-level decl (stale T1.3 filter); mixed-decl files compile every decl, so cross-file go-to-def / completion for the 2nd+ decl is broken | code trace |
| BH-06 | HIGH | resolver/emit | a bare **top-level** hook import (`import { use_x }` + `use_x()`) lowers to `const use_x = preload(...)` but never rewrites the call, so the emitted `.gd` calls a resource as a function → **does not parse** | repro |
| BH-07 | HIGH | HMR | `refresh_roots` only finds **direct** importers of a changed hook/module; a component consuming it through an intermediate module isn't re-rendered — and because the roots set is non-empty (the intermediate module), the global fallback doesn't fire either → stale UI | code trace |
| BH-08 | MED | compiler/parse | `_parse_import_at` bounds the specifier terminator by the **import keyword's line**, so a legal multi-line `import { … }` (names or `from` on a later line) gets a false `GUITKX0300` | repro |
| BH-09 | MED | mixed emit | mixed-decl `@uss` with a non-single-element binding root silently **drops the theme** and skips the `GUITKX2210` the single-decl path emits | repro |
| BH-10 | MED | resolver | `GUITKX2306` (value-import cycle) is implemented + unit-tested (`value_cycle`) but **has no production caller** — a real value cycle emits nothing | grep + repro |
| BH-11 | MED | resolver | `GUITKX2308` (module/root boundary) is **unreachable**: `resolve_specifier` always returns a `res://`-prefixed path (escapes become `res://../…`), so `not begins_with("res://")` is never true; `../`-escapes are mis-reported as `GUITKX2300` | repro + code |
| BH-12 | MED | compiler/parse | `GUITKX2309` (import after first decl) is **never emitted**; the case surfaces as a generic `GUITKX2105` | grep + repro |
| BH-13 | MED | specifier | `_specifier` (codemod) / `_import_specifier` use `begins_with(root)` with no path-separator boundary; a file in `res://ui2/` under root `res://ui` yields `~/2/card`, which resolves to the **wrong file** | repro |
| BH-14 | MED | codemod | the out-of-root `_specifier` fallback writes `~/` as **res://-relative**, but the resolver roots `~/` at the **config root**; with a non-`res://` root the two disagree → unresolvable import | code trace |
| BH-15 | MED | HMR | a mixed file with any hook/module is classified `_is_module==true`, so a hook-**signature** change in its binding component skips the deliberate state RESET → stale/corrupt component state after edit | code trace |
| BH-16 | LOW | resolver | `GUITKX2307` (used-but-no-file-exports-it) is registered but **never emitted** | grep |
| BH-17 | LOW | resolver | `_class_name_override` (resolver) returns the **first** `@class_name`, `_binding_name` (codegen) the **last**; a file with two `@class_name` lines binds inconsistently between resolver and emitter | repro |
| BH-18 | LOW | strict | `GUITKX2305` uses naive `source.find(name)` for the offset, matching the first textual occurrence (a comment / a substring) rather than the real reference the scan found | repro |

**Dead-diagnostics cluster:** BH-10/11/12/16 mean **four of the ten frozen family codes (2306, 2307, 2308, 2309) never fire** in this leg — a real family-parity gap versus the §0.1 contract.

## Validated CORRECT (adversarial claims that did NOT hold up / features I re-verified working)

- **Two-pass counted parse gate** — reproduced: a text-OK-but-GDScript-invalid emit (`NopeUndefinedClass.foo()` in setup) → `GDSCRIPT PARSE FAIL` → `guitkx_build` exits 1. Not a no-op.
- **Reverse-edge staleness** — reproduced: renaming A's export re-checks importer B in the same sweep → `GUITKX2302`. Works.
- **TS `importAt`** — `IMPORT_RE.lastIndex` resets each call; substring names (`Foo` vs `FooBar`) handled; `res://`/`uid://` rejected. No bug.
- **`_binding_name` ↔ `_binding_of` parity** — agree on every normal shape (first-exported wins, `@class_name` override, `@class_name` after import). They diverge **only** on the two-`@class_name` edge (BH-17).

---

## Details

### BH-01 (HIGH) — `_decl_body_end` uses GDScript lexis, not markup lexis
`addons/reactive_ui/guitkx/guitkx.gd` · `_decl_body_end` (body-brace match via `L.find_matching`).

`_parse_component_at` closes a component body with `L.find_matching_markup` (the G-01 fix: a component
body is markup, so `//`, `/* */`, `<!-- -->` are comments and their braces are not code). My
`_enumerate_decls` instead computes each decl's extent with `_decl_body_end`, which uses plain
`L.find_matching` (GDScript lexis, only `#` is a comment). So a `}` inside a markup comment pops the
component's `{` early → wrong `next`. In `_compile_mixed` the between-decls junk gate then flags the
real trailing markup as `GUITKX2105`; a mismatch that runs `find_matching` to `-1` instead drops the
trailing declaration.

**Repro (verified):** the two-component file below compiles clean *without* the `// close } here`
comment (`ok=true`) but is **rejected with `GUITKX2105`** *with* it.
```guitkx
component A() {
	return (
		<Label /> // close } here
	)
}

component B() { return ( <Label /> ) }
```
**Fix:** in `_decl_body_end`, match the body brace with `L.find_matching_markup` for `kind=="component"`
(and for the markup/return regions generally), mirroring `_parse_component_at`.

### BH-02 (HIGH) — cross-file func mis-addressed when `@class_name` ≠ decl name
`guitkx_resolve.gd` · `decl_table` / `_binding_of`; `guitkx_codegen.gd` · `exports_of`.

Both compute `func = "render" if kind=="component" and name==binding else name`. But the single-decl
emitter names the **sole** component `render` regardless of `@class_name`. With `@class_name Custom` +
`component Widget`, `binding=="Custom"` ≠ `name=="Widget"`, so the tables record `func="Widget"`, while
the file emits `static func render`. A cross-file `import { Widget }` then lowers to
`V.comp(path,"Widget")` → `Callable(load(path),"Widget")` → no such method at render time.

**Repro (verified):** `exports_of("@class_name Custom\nexport component Widget() {…}")` →
`[{name:Widget, kind:component, func:Widget}]`, but the emitted `.gd` contains `static func render(` and
**not** `static func Widget(`.
**Fix:** treat a component as `render` when it is the file's binding component — for a single-component
file that's always the sole component; for mixed, when `name==binding` OR `@class_name` designates it.
Compute the func from the emitter's actual naming rule, not a name-equality shortcut.

### BH-03 (HIGH) — codemod inserts the import block mid-token
`guitkx_migrate.gd` · `migrate_source` (import insertion at `int(decls[0]["at"])`).

Step 3 prefixes `export ` at each *unexported* decl's `at`; step 4 inserts the import block at
`decls[0]["at"]` (the keyword). For an unexported first decl this is correct (the freshly-inserted
`export ` sits at `at`, so imports land before it). For an **already-exported** first decl, step 3 is a
no-op and `at` still points *past* the existing `export `, so the import block splits the token.

**Repro (verified):** `migrate_source` on `export component Widget() { return ( <Card /> ) }` (Card not
yet imported) produces:
```guitkx
export import { Card } from "./card"

component Widget() { return ( <Card /> ) }
```
— invalid, `Widget` lost its `export`, and the codemod is no longer idempotent. Bites any hand-written
`export` file, or a re-run over a partially-migrated file.
**Fix:** insert the import block at `decls[0]["start"]` (the decl's true start, incl. any `export`
prefix), not `at`. `start` is correct for both cases.

### BH-04 (HIGH) — VS Code loses the diagnostic code for v3 sidecars
`ide-extensions/lsp-server/src/server.ts` · `mergeCompilerSidecar` line ~936.

`message: sc.v === 2 ? \`${d.code}: ${d.message}\` : d.message`. The pushed `Diagnostic` has **no**
`code` field, so the `GUITKX####` identity is carried only by the message prefix. v1 messages embed it;
v2 gets it composed here; **v3 falls through to the bare message**. Since I bumped every sidecar to v3,
all compiler diagnostics (import errors and every pre-existing code) now show in the editor with no
code — worse than before this leg.
**Fix:** `sc.v === 2` → `sc.v >= 2` (v2 and v3 both need the composed prefix). Optionally also set
`code: d.code` on the pushed Diagnostic.

### BH-05 (HIGH) — workspace index drops all but the first declaration
`ide-extensions/lsp-server/src/workspaceIndex.ts` · `WorkspaceIndex.reindex`.

`const first = decls.find(d => d.kind !== "member"); decls = decls.filter(d => d===first || member-of-first)`.
This T1.3 rule ("index only what the compiler compiles — the first top-level decl") is now false: the
0.10.0 compiler compiles **every** top-level decl. So in a mixed-decl file only the first decl is
indexed; cross-file go-to-def, find-refs, and tag completion for the 2nd+ decl silently fail.
**Fix:** index every top-level decl (and module members) now that mixed-decl is legal; drop/relax the
`first`-only filter.

### BH-06 (HIGH) — bare top-level hook import emits an uncallable const
`guitkx_resolve.gd` · `resolve_file_imports` (value branch); `guitkx.gd` · `_insert_value_imports`.

A value import lowers to `const Name = preload(path)[.Member]`. For a **module** import the body uses
`Mod.member(...)` — fine. For an imported **top-level hook** called bare (`use_x()`), the const is the
*script resource*, so `use_x()` calls a resource → invalid GDScript.

**Repro (verified):** importer with `import { use_thing } from "./h"` + `var v = use_thing()` →
`ok=true`, emits `const use_thing = preload(...)`, body still `use_thing()`, and
`gd_source_parses(...) == false`. (The plan §6.4 deferred the bare-hook call rewrite; the gap emits
*broken* code, not just a missing feature. The migrated tree avoids it — doom uses module-qualified
hooks — so the build stayed green, but a user hits it.)
**Fix:** implement the deferred rewrite — `const __RUI_IMP_<FILE> = preload(path)` + rewrite `use_x(` →
`__RUI_IMP_<FILE>.use_x(` in verbatim regions (fingerprint on pre-rewrite text) — or reject the form
with a clear diagnostic until then.

### BH-07 (HIGH) — HMR misses transitive component consumers
`guitkx_codegen.gd` · `_compute_refresh_roots`; `addons/reactive_ui/core/hmr.gd` · `apply`.

`_compute_refresh_roots` adds files that **directly** import a changed value-decl. If component C
imports module M1 which imports the changed module M2, the roots set is `{M1.gd}` (a module, no fiber
matches it) and C is absent. In `apply`, because the roots set is **non-empty**, the global fallback is
skipped, `targeted` marks fibers whose script is M1 (none), and nothing re-renders → C shows stale UI.
**Fix:** compute refresh roots over the **transitive** reverse-import closure up to the nearest
*component* importers (React Fast Refresh parity), and fall back to global when the target set contains
no component roots.

### BH-08 (MED) — false 0300 on multi-line imports
`guitkx.gd` · `_parse_import_at`. `line_end` is the first `\n` after the `import` keyword, but the `{ … }`
list is brace-matched (multi-line capable) and the specifier check requires `qe <= line_end`. So a
legal `import {\n\tFoo,\n\tBar\n} from "./x"` gets `GUITKX0300 "unterminated import specifier string"`.
**Repro (verified):** that input → `ok=false, codes=[GUITKX0300, …]`.
**Fix:** bound the specifier scan by the end of the *import statement* (past `}` → `from` → the closing
quote), not the keyword's line — or drop the `qe > line_end` guard and rely on brace/quote matching.

### BH-09 (MED) — mixed `@uss` silently drops the theme
`guitkx.gd` · `_compile_mixed`. The theme is applied only when the binding component's root is a single
`el`; otherwise nothing happens — no theme, and no `GUITKX2210` (which the single-decl path emits for a
non-element root). **Repro (verified):** mixed file, `@uss` + a `<>…</>` fragment root → theme dropped,
no 2210. **Fix:** mirror `_compile_component`'s 2210 emission in the mixed path.

### BH-10 / BH-11 / BH-12 / BH-16 (MED/LOW) — four dead frozen diagnostics
- **2306** (`value_cycle`) — defined + unit-tested in `guitkx_resolve.gd`, **no pipeline caller** (grep:
  only referenced in `tests/`). Wire a driver-level DFS over value-import edges into `compile_all`.
- **2308** — `resolve_specifier` always returns a `res://`-prefixed path (escapes become `res://../…`),
  so the boundary check `not begins_with("res://")` never fires; `../`-escapes mis-report as 2300.
  Detect boundary crossing before/instead of the file-exists check (e.g. a normalized-path
  `res://../` / out-of-root test).
- **2309** — import-after-first-decl never emitted; it surfaces as a generic `GUITKX2105`. The preamble
  loop stops at the first decl, so a later `import` is treated as junk. Detect a stray `import` keyword
  after the first decl and emit 2309.
- **2307** — registered, no emit site anywhere. Decide its relationship to the existing unknown-tag path
  and wire it (or record a permanent divergence note in the registry).

### BH-13 (MED) — specifier prefix-boundary bug
`guitkx_migrate.gd` · `_specifier`; `guitkx.gd` · `_import_specifier`. `base.begins_with(root)` matches a
string prefix, not a path prefix. **Repro (verified):** `_specifier(target=res://ui2/card, root=res://ui)`
→ `~/2/card`, which `resolve_specifier` maps to `res://ui/2/card.guitkx` (wrong; expected
`res://ui2/card.guitkx`). **Fix:** require `base == root or base.begins_with(root + "/")` before
treating a target as under the root.

### BH-14 (MED) — codemod out-of-root `~/` mis-root
`guitkx_migrate.gd` · `_specifier` fallback `return "~/" + base.trim_prefix("res://")` for out-of-root
targets. This encodes a `res://`-relative path, but `resolve_specifier` roots `~/` at the **config
root**; with a non-`res://` root they disagree and the emitted import won't resolve. **Fix:** for a truly
out-of-root target, emit a relative (`../`) specifier, or refuse (there is no `~/` that names it).

### BH-15 (MED) — HMR skips state reset for value-mixed files
`hmr.gd` · `apply` / `_is_module`. A mixed file with a hook/module is `_is_module==true`, so `apply`
takes the module/refresh-roots branch and never reaches `elif _hook_sig(scr) != old_sig: resets.append`.
So if the binding component's hook signature changed, its state is **not** reset (React would reset it),
risking corrupt positional-hook state after an edit. **Fix:** for a mixed file, drive per-component
reset from `__RUI_DECLS` per-decl `sig` compare (the plan's `_changed_kinds`), independent of the
module-global path.

### BH-17 (LOW) — resolver vs codegen disagree on multiple `@class_name`
`guitkx_resolve.gd` · `_class_name_override` returns the **first** `@class_name`; `guitkx_codegen.gd` ·
`_binding_name` keeps overwriting → the **last**. **Repro (verified):** two `@class_name` lines →
`codegen=Second`, `resolver=First`. Malformed input, but they should agree (and ideally one should be a
diagnostic). **Fix:** make both take the same one (and consider erroring on a second `@class_name`).

### BH-18 (LOW) — strict 2305 offset is imprecise
`guitkx.gd` · strict-2305 block, `ref_at = maxi(0, source.find(name))`. Matches the first textual hit —
a comment, a string, or a substring — not the reference `referenced_names` actually found. **Repro
(verified):** `# Widget is cool` before `<Widget/>` → 2305 offset lands on the comment. **Fix:** have
`referenced_names` return the reference offset (it already scans lexer-aware) and use that.

---

## Recommended fix order

1. **BH-04, BH-03, BH-06, BH-01** — the ones that produce wrong output a user hits immediately (no
   editor code; corrupt codemod output; a `.gd` that won't parse; a valid file rejected). Small, local.
2. **BH-02, BH-05, BH-07, BH-15** — cross-file correctness (wrong `V.comp` target, broken nav, stale/
   corrupt HMR).
3. **BH-10/11/12/16 (dead diagnostics), BH-13/14 (specifier boundary), BH-08/09** — contract-parity and
   specifier robustness.
4. **BH-17, BH-18** — low-severity polish.

Each fix should land with a regression test that fails today (the repros above are ready-made), and the
full matrix (§10 of `IMPORT_EXPORT_PLAN.md`) re-run.
