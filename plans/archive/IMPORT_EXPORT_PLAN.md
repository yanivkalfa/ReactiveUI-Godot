# Import/Export — Godot leg (feat/guitkx-imports) — EXECUTION PLAN

> **Status:** APPROVED design (owner sign-off 2026-07-11, rounds 1–3 + amendments A1–A8).
> This file is leg 2 of the three-repo campaign (canonical master:
> `ReactiveUI-Unreal/plans/IMPORT_EXPORT_MASTER_PLAN.md`). Self-contained: do NOT re-research.
> **Branch:** `feat/guitkx-imports`, one PR. **Order:** Unreal → **Godot** → Unity.
> **Hard gates before starting:** (1) Unreal leg (`feat/uetkx-imports`) merged — family diagnostic
> block + canonical corpus home exist; (2) `feat/doom-guitkx-port` merged — the codemod migrates
> doom in this leg's normal sweep (round-3 owner decision); doom is this leg's codemod acceptance
> corpus.
> **Gate status (2026-07-11): see §0 CONTRACT FREEZE — contract frozen: YES; doom/naming merged:
> YES.** Gate (1)'s substance (frozen block + corpus home) is satisfied by §0 even ahead of the
> Unreal PR's merge; leg 1 is verified green on its branch.

---

## 0. CONTRACT FREEZE (leg 1 shipped) — 2026-07-11

> Unreal leg 1 **SHIPPED** on `feat/uetkx-imports` (21 commits, verified green: battery 55/55,
> `RUICompile -check` 0 drift, corpus + mirror gates, VS2022 vsix rebuilt). This section is the
> AS-SHIPPED contract extracted from that branch (`UetkxResolve.cpp`, `UetkxFileScan.cpp`,
> `UetkxDriver.cpp`, `plans/TECH_DEBT.md` TD-023..025) and SUPERSEDES this plan's original
> guesses wherever they disagree. **Restart gates now: contract frozen: YES (this section) +
> doom/naming merged: YES** (PR #69 `feat/doom-guitkx-port` and PR #70
> `feat/naming-loyalty-0.9.0` are both on `master`).
>
> **Parked state:** branch `feat/guitkx-imports` holds one WIP commit (`cc194ad`, "M1
> grammar+scan parked green — do not build on"). It predates this freeze and still carries the
> provisional 26xx numbering — the FIRST restart task is renumbering 26xx→23xx (vocabulary rows,
> emit sites, tests, TS mirror) before building anything on top of it.

### 0.1 Frozen family diagnostic table — GUITKX2300–2309 (+ 2310–2315 reserved)

Family block = **2300–2315**, frozen by leg 1's shipped M0.2 audit (23xx free in all three
registries — the 26xx fallback is DEAD). Codes + messages are identical family-wide modulo
prefix (`UETKX`→`GUITKX`) and extension (`.uetkx`→`.guitkx`). Only 2304 is a warning. Shipped
emit split: 2303/2309 fire at SCAN (file-local), 2300/2301/2302/2304/2305/2307/2308 at RESOLVE,
2306 at the DRIVER (sweep) level.

| Code | Sev | Frozen message (Godot substitutions applied) |
|---|---|---|
| GUITKX2300 | err | ``unknown import specifier `%s` — no file at %s(.guitkx)`` (both args = the specifier) |
| GUITKX2301 | err | `` `%s` is not exported by %s — add `export` to its declaration `` |
| GUITKX2302 | err | `` `%s` is not declared in %s `` |
| GUITKX2303 | err | ``duplicate import of `%s` (already imported from %s)`` |
| GUITKX2304 | warn | ``unused import `%s` `` |
| GUITKX2305 | err | `` `%s` is defined in %s but not imported — add: import { %s } from "%s" `` |
| GUITKX2306 | err | ``value-import cycle: %s (hooks/modules load eagerly — break the chain or move to component refs)`` — ONE placeholder = the whole chain of filenames, `a.guitkx -> b.guitkx -> a.guitkx` |
| GUITKX2307 | err | `` `%s` is used like a guitkx component/hook but no file exports it `` |
| GUITKX2308 | err | ``import crosses a module/root boundary (%s -> %s) — imports are module-scoped in v1`` |
| GUITKX2309 | err | ``import must appear in the preamble, before the first declaration`` |
| GUITKX2310–2315 | — | reserved (family) — never mint leg-local codes here without registering them in the canonical Unreal table |

- **Renumbering vs this plan's original §4 draft** (the §4 list below is already fixed): the old
  draft's 2302 ("no .guitkx file exports X") is frozen **2307**; the old draft's 2307 ("exists
  but not exported") folds into frozen **2301**; **2308** (boundary) and **2309** (preamble-only)
  were missing from the draft entirely.
- **2306 semantics (shipped):** VALUE-import cycles only — cycle-graph edges are imported HOOKS
  and MODULES (here: the const-preload lowerings); component import edges are EXEMPT. Driver
  (sweep)-level DFS over FRESH preamble scans; the error prints the full chain. The shipped
  message has ONE `%s` (the joined chain) — not the master plan's `%s -> %s -> %s` sketch.
- **Component cycles are LEGAL — UETKX2107 RETIRED in leg 1.** Unreal earned this with the
  two-phase DECL/BODY aggregator plus a committed `CycleProof/` fixture pair that compiles AND
  renders. **Godot gets the same semantic for free via `V.comp` laziness (§6.4) — no two-phase
  emit needed here**; mirror the CycleProof pair as fixtures to PROVE it. (This repo's existing
  `GUITKX2107` is the unrelated dangling-refs check — it keeps its number; the family never
  mints a 2107.)
- **2308 applicability here:** Godot has no UE-module analog; the v1 trigger = a config
  `"root"` resolving outside the project, or a specifier escaping `res://`. Message stays
  identical (family rule).
- **2105 (family retarget shipped):** UETKX2105 went scan-ERROR → sev-1 WARN "one component per
  file — convention" in leg 1 (genuinely unparseable junk stays a 2101-class error). GUITKX2105
  staying ERROR until this leg lands is the recorded transient divergence — at restart either
  mirror the retarget or record §4's docs-only choice as a permanent divergence in the registry
  note.

### 0.2 Shipped semantics this leg must match (as-built, not as-planned)

- **Two-phase emit** (Unreal mechanism; the family SEMANTIC = component cycles compile): DECL
  phase = complete props structs + defaulted wrapper fwd-decls + hook fwd-decls + module bodies;
  BODY phase = impls + default-free wrapper defs + registrations; the aggregator includes every
  generated file twice. Godot needs none of the mechanism — `V.comp` laziness already satisfies
  the semantic.
- **Source-truth aggregator ordering (A2, shipped):** compile order + graph come from RESOLVED
  preamble import edges (Kahn topo, alphabetical ties, cycle remainder alphabetical); sidecars
  demoted to per-machine cache/verifier ONLY (Unreal deleted its sidecar-ordering reader).
  §6.2/M3/M4 here already match — hold that line.
- **Single-sweep staleness fixpoint (shipped):** ONE compile-all call converges. Pass 1 compiles
  stale files; if any `export_hash` moved, an internal pass 2 re-sweeps importers. Verdict
  un-poisoning included: an error verdict is invalid the moment any recorded dep export-hash
  differs from the dep's current one, and **unresolved specifiers record the resolved-candidate
  path with hash 0** so the file's later appearance flips staleness. M4 must meet this same
  single-call bar (its "recompile in the SAME sweep" wording already agrees).
- **Codemod (shipped default):** export-EVERYTHING; idempotent + re-runnable; the reference scan
  is a FRESH scan (tags + hook calls + module quals) — never sidecar/edge-derived. M6 matches.
- **`#line` project-relative:** shipped in leg 1 (VS2022 breakpoint bind on the `.uetkx` source
  confirmed by owner); GDScript has no `#line` mechanism — N/A for this leg, no analog required.
- **Privacy (shipped):** compile-time scoping only — Unreal wraps non-exported decls in a
  per-file detail namespace; the Godot analog is §6.2/M2 (no `class_name`, no global
  registration). Duplicate-binding ledgers key EXPORTED names only (2106 arbitration — §6.2
  matches). Runtime registries stay name-flat family-wide (accepted v1 divergence, Unreal
  TD-026); M5's injector/HMR caveats are the local analog.

### 0.3 Corpus mirror sources + drift gate (build item)

Mirror FROM the Unreal repo (`../ReactiveUI-Unreal`, branch `feat/uetkx-imports`); paths
repo-relative:

- `ide-extensions/lsp-server/test-fixtures/uetkx-scanner-cases.json` — the shared scanner
  corpus. `_tiers.familyCore = ["skipNoncodeMarkup", "findMatchingMarkup", "fileScan"]` is
  byte-identical family-wide after `UETKX|GUITKX|UITKX → TKX` code-prefix normalization;
  `_tiers.perLeg` (`skipNoncode`, `findMatching`, `fileScanLeg`) is engine lexis — NOT
  mirrored/hashed.
- `ide-extensions/lsp-server/test-fixtures/uetkx-formatter-cases.json` — the shared formatter
  corpus (import canonicalization, `export`, mixed-decl idempotency); mirror in shape, not
  hashed.
- `scripts/corpus-hash.mjs` + `plans/family-corpus.hash` — **the drift gate (build item for this
  leg):** adopt the same script + hash file into THIS repo, point it at the mirrored corpus,
  wire into `.github/workflows/test.yml` (engine-free node job). Release-time hash-match across
  all three repos = TD-009's resolution. Pinned family hash as of the freeze:
  `657e5f4ef77cb44df693e7cfebc1112163cdc1ee2bd541b4b5e1069abb08013b`.
- `Source/RuiHostTests/ContractFixtures/` — contract fixtures to mirror in shape: `Showcase` /
  `StatusChip` / `ChipSupport` / `Counter` / `Preamble` / `Palette` (`.uetkx` +
  `.inl.expected`), `BadAttr` (+ `.diags.expected`), and `ImportError.uetkx` +
  `ImportError.uetkx.diags.expected` (pins 2300/2301/2305 message text).
- `Source/RuiHostTests/CycleProof/` — `CycleA.uetkx` ↔ `CycleB.uetkx` (+ `.uetkx.diags.json`,
  `.uetkx.inl`): the component-cycle-LEGAL proof pair (compiles + renders).
- `Source/RuiHostTests/Private/ReactiveUIUetkxResolveTest.cpp` — the resolve suite exercising
  every 2300–2309 code; mirror its case list into `tests/guitkx_test.gd`'s import block.

---

## 1. Family locked decisions (duplicate — do not re-litigate)

1. **Strict from day one.** Implicit cross-file resolution is an ERROR the moment the feature
   lands; the migration codemod runs inside the same PR so every file gains imports before
   strictness turns on. Codemod correctness = this leg's first milestone.
2. **Named exports only.** No `default`, no `import *`. Re-export = fast-follow, not v1.
3. **Specifiers:** relative (`./`, `../`) AND root alias `~/` — both v1. Engine-native forms
   (`res://`, `uid://`) FORBIDDEN in import specifiers. `~/` = project UI source root from the
   `guitkx.config.json` walk-up (new top-level `"root"` key; Godot default `res://`).
   Specifiers are extensionless (`.guitkx` implied). Static, string-literal, preamble-only.
4. **Full ESM cycle parity.** Cross-file COMPONENT cycles legal (Godot: free via lazy `V.comp` —
   verified HOLDS; leg 1 shipped the same semantic by retiring UETKX2107, §0.1). VALUE cycles
   (preload chains) = compile ERROR printing the chain (frozen 2306 message, §0.1).
   NOTE (A6e, probe-confirmed): Godot 4.7 TOLERATES mutual preload cycles — the value-cycle error
   is family TDZ-parity POLICY, not engine necessity, and it does NOT mitigate the fresh-clone
   ordering hazard (§7 M4 fixes that separately; keep both).
5. **Round 3: FULL MIXED-DECL v1** — multiple components + hooks + modules per file. The Godot
   data-model rewrite this implies is in scope (§6). File-kind conventions (one component per
   file, hooks in `.hooks` files) become LINT tier, not errors.
6. **Round 3: `~/` extends into ASSET references v1** — `@uss`/`@theme` accept `~/` (§7 M3.6).
7. **Strict mode scopes to markup-owned names only (A4).** Hand-written `class_name` `.gd`
   (DoomTypes, DoomTextures, DoomGameScreenLogic…) are AMBIENT: imports address `.guitkx` targets
   only; strict diagnostics fire only for names present in the guitkx export tables. Ambient set =
   `ProjectSettings.get_global_class_list()` + ClassDB, minus guitkx-generated bindings.
8. **Codemod exports everything existing (A3/A5-discovered).** Zero-inbound-edge roots are real
   (hand `.gd` mounts `V.fc(DoomGameScreen.render, …)`, `ReactiveRoot.create` call sites, tests).
   Privacy is opt-in going forward; the codemod never makes anything private.
9. **Graph truth = declared imports in SOURCE (A2).** Sidecars (`*.guitkx.diags.json`) are
   git-ignored per-machine cache/verifier only — never the transport.
10. **Hook idiom is per-repo (round-2 amendment):** grammar is SHAPE-identical, not
    byte-identical. Godot hooks are `snake_case use_*` (the fingerprint scanner keys the `use_`
    prefix — `guitkx.gd` `_hook_signature`, ~1523–1528). Family corpus splits family-core
    (byte-identical markup-mode) vs per-leg declaration/casing cases (§3).
11. **Godot's import/export identity = the BINDING** (`@class_name` override else decl name) —
    all tables key on it (A6b). See §6.2.

## 2. Grammar (Godot-idiom examples)

```guitkx
import { StatusChip } from "./status_chip"
import { DoomGameScreenHooks, DoomHudStyles } from "~/demos/doom/doom_game_screen.hooks"

@class_name DoomGameScreen          # optional binding override — BEFORE or AFTER imports (both legal)
@uss "~/theme/dark.tres"            # ~/ now legal here too (res:// / uid:// stay legal in asset positions)

export component DoomGameScreen(level: int = 1) {
	var doom = DoomGameScreenHooks.use_doom_game(view_ref, level, difficulty)
	return (<PanelContainer>…</PanelContainer>)
}

component LocalRow(label: String) {    # no export = file-private, unreachable cross-file
	return (<Label text={label}/>)
}

export hook use_blink(interval: float) -> Dictionary { … }

export module HudStyles { … }
```

- Preamble = imports + `@class_name` + `@uss`/`@theme`, any order, before the first decl.
- A file is a SEQUENCE of decls; content between decls that isn't a decl stays GUITKX2105 ERROR.
- Import names bind EXPORTED TOP-LEVEL DECL NAMES of the target file (component / module /
  top-level hook). Hooks nested in a `module` are reached via the module name (unchanged idiom).
- Asset asymmetry (documented, family wording): asset positions (`@uss`/`@theme`) accept
  `res://`, `uid://`, AND `~/`; import specifiers accept ONLY `./ ../ ~/`.

## 3. Corpus mirroring prerequisite (A8b — TD-009/TD-018)

- The mirror mechanism SHIPPED in leg 1 (TD-009: "mechanism shipped leg 1; sibling PRs
  pending"). The import corpus is the FIRST mirrored set; the canonical home + hash-drift gate
  now exist — exact source paths, tier partition, and the pinned family hash are in **§0.3**.
  This leg CONSUMES:
  - Mirror the family-core (markup-mode, byte-identical after `UETKX→GUITKX` substitution)
    corpus cases from `uetkx-scanner-cases.json` `_tiers.familyCore` into
    `tests/contract/fixtures/` (flat `imp_*.guitkx` names) + regenerate `tests/contract/golden/`.
  - Add the per-leg (snake_case hook, binding-identity) cases as Godot-local fixtures.
  - CI drift gate (build item): adopt leg 1's `scripts/corpus-hash.mjs` +
    `plans/family-corpus.hash` into this repo; wire into `.github/workflows/test.yml` (§0.3).

## 4. Family diagnostics contract

- **Code block FROZEN by leg 1 (supersedes the A8a audit):** family block = **2300–2315**
  (2300–2309 emitted, 2310–2315 reserved). The 26xx fallback is DEAD — leg 1's shipped M0.2
  audit verified 23xx free in all three registries (this repo's occupied set:
  00xx/01xx/03xx/21xx/2504–2508 — no 23xx). Canonical table + semantics notes: **§0.1**.
- **Codes (severity, FROZEN message — Godot substitutions applied)** — add to `vocabulary.json`
  (+ regenerate `guitkx_vocabulary.gen.gd`, + mirror
  `ide-extensions/lsp-server/src/vocabulary.json`):
  - `GUITKX2300` ERROR ``unknown import specifier `%s` — no file at %s(.guitkx)``
  - `GUITKX2301` ERROR `` `%s` is not exported by %s — add `export` to its declaration ``
  - `GUITKX2302` ERROR `` `%s` is not declared in %s ``
  - `GUITKX2303` ERROR ``duplicate import of `%s` (already imported from %s)``
  - `GUITKX2304` WARNING ``unused import `%s` ``
  - `GUITKX2305` ERROR `` `%s` is defined in %s but not imported — add: import { %s } from "%s" ``
  - `GUITKX2306` ERROR ``value-import cycle: %s (hooks/modules load eagerly — break the chain or move to component refs)``
  - `GUITKX2307` ERROR `` `%s` is used like a guitkx component/hook but no file exports it ``
  - `GUITKX2308` ERROR ``import crosses a module/root boundary (%s -> %s) — imports are module-scoped in v1``
  - `GUITKX2309` ERROR ``import must appear in the preamble, before the first declaration``
- **Severity-divergence policy:** codes + messages identical family-wide; severities may diverge
  only where engine semantics force it, recorded in a per-repo divergence note in each registry.
  Godot divergence: single-decl-per-file is NOT enforced at any tier by the compiler (mixed-decl
  v1); one-component-per-file becomes a docs-level convention only (no new lint code in v1).
  NOTE: leg 1 shipped the family shape for this — UETKX2105 is now a sev-1 WARN "one component
  per file — convention" (see §0.1); at restart either mirror that retarget for GUITKX2105 or
  record the docs-only choice as a permanent divergence in the registry note.
- Ambient names (rule 7) NEVER fire 2302/2305/2307.

## 5. Sequencing / gates

- Gate 0: Unreal leg merged (family block + corpus home + `~/` asset wording locked) —
  **substance SATISFIED by §0 (contract frozen off the verified-green branch).**
- Gate 1: `feat/doom-guitkx-port` merged to master; this branch forks after — **DONE (PR #69;
  naming 0.9.0 also merged, PR #70).** NOTE: the parked `feat/guitkx-imports` WIP forked
  earlier — rebase onto `master` at restart (after the 26xx→23xx renumber, §0).
- Gate 2 (in-PR): codemod sweep produces a ZERO-23xx tree AND `guitkx_build` exits 0 with the
  new counted parse gate (§7 M4) before review.
- Codemod is idempotent + re-runnable (`--script res://tests/guitkx_migrate.gd`) so future
  in-flight branches self-migrate on rebase (critic requirement).
- Unity leg starts only after this PR merges.

---

## 6. MIXED-DECL v1 — the Godot data-model rewrite (A1; this is the heart of the leg)

Current state (verified anchors): single-decl by construction — one `_find_decl` dispatch
(`guitkx.gd:210-238`, `match decl["kind"]` at 225-238, GUITKX2101 else); `_binding_name` takes the
FIRST decl and its preamble scan BREAKS on any non-`@class_name` token (`guitkx_codegen.gd:280-311`,
loop 284-297); `V.comp(path)` hard-codes `Callable(load(path), "render")` (`v.gd:35-40`);
`__RUI_KIND`/`__RUI_HOOK_SIG` are per-FILE consts (`guitkx.gd:1489-1495`); HMR component-vs-module
dichotomy is per-script (`hmr.gd:160-164`). Module emission ALREADY lowers multiple nested
components as sibling static funcs (`guitkx.gd:903-998`, `_emit_func` per member at 984) — that is
the lowering seed; adopt it.

### 6.1 Parse model

- `Compiler.compile()` (`guitkx.gd:130`): replace the single `_find_decl` + `match` with a LOOP:
  repeatedly `_find_decl(source, i)`; before each decl, `_first_real` junk check keeps GUITKX2105
  (message reworded: "invalid content between declarations"). Each decl optionally prefixed by
  `export` (extend `_find_decl` to recognize `export` + ws + decl keyword; record `export: bool`).
- Result: `decls: Array[{kind, name, export, parse}]`. Empty → GUITKX2101 unchanged.
- `_parse_component_at` / `_parse_hook_at` / `_compile_module`'s member parser: unchanged.
- Lint tier: none in v1 (see §4 divergence note).

### 6.2 Binding identity + export tables

- **File binding** = `@class_name` override, else **first EXPORTED decl's name**, else "" (fully
  private file). Emitted script gets `class_name <binding>` IFF binding != "" — this is what keeps
  hand-written `.gd` consumers (`DoomGameScreen.render`, `DoomTypes` style access) working.
- `_binding_name` → **`_binding_names(src) -> Dictionary`**:
  `{ binding: String, exports: Array[{name, kind, func}], all: Array[...] }`.
  **Fix the order-sensitive scan (A6b):** the preamble loop must SKIP `import` lines, `@uss`,
  `@theme`, and blank/comment lines instead of breaking at the first non-`@class_name` token —
  mirror `compile()`'s order-agnostic loop (`guitkx.gd:161-209`). This fix lands in M1 BEFORE the
  codemod exists (its insertion point depends on it).
- `project_bindings(paths)` (`guitkx_codegen.gd:321-356`):
  - keys the winners map on EXPORTED binding names only (privacy: two private `Helper`s never
    collide — GUITKX2106 arbitration at 330-355 / 481-499 keys exported names only, A6d).
  - returns additionally `exports: {path -> [{name,kind,func}]}` and `imports: {path ->
    [{names:[…], spec, resolved_path}]}` (preamble import scan; source of graph truth).
  - stays the VERIFIER for the emitter; declared imports become the resolver's truth (rule 9).

### 6.3 Emission shape (exact before/after)

**Single exported component file (back-compat — output byte-identical except `export` keyword):**
```gdscript
# BEFORE (today) and AFTER, unchanged:
class_name DoomFace
extends RefCounted
## AUTO-GENERATED from doom_face.guitkx -- do not edit.
const __RUI_HOOK_SIG := "useState|useEffect"
const __RUI_KIND := "component"
static func render(props: Dictionary, children: Array) -> RUIVNode: …
```

**Mixed file `hud.guitkx` (`export component Hud`, `component LocalRow` private, `export hook
use_blink`, `export module HudStyles`) — NEW shape:**
```gdscript
class_name Hud                                  # binding = first exported decl
extends RefCounted
## AUTO-GENERATED from hud.guitkx -- do not edit.
const StatusChip = preload("res://ui/status_chip.gd")      # value-import lowerings (hooks/modules)
const __RUI_DECLS := {                          # per-decl kind + hook fingerprint (replaces
	"Hud":      { "kind": "component", "sig": "useState|use_blink", "export": true },
	"LocalRow": { "kind": "component", "sig": "", "export": false },
	"use_blink":{ "kind": "hook", "export": true },
	"HudStyles":{ "kind": "module", "export": true },
}
const __RUI_KIND := "mixed"                     # legacy consts kept for old HMR readers
const __RUI_HOOK_SIG := "useState|use_blink"    # = binding component's sig
static func render(props: Dictionary, children: Array) -> RUIVNode: …   # the BINDING component
static func LocalRow(props: Dictionary, children: Array) -> RUIVNode: … # non-binding components
static func use_blink(interval): …                                      # top-level hooks
class HudStyles:                                                         # non-binding modules
	static func …
```
- Rule: the binding component keeps func name `render`; every other component emits a static func
  named after the decl. Non-binding `module` decls emit as inner `class Name:`; the binding module
  (module-only file, today's shape) keeps the flat static-func layout — byte-compat.
- Lone-hook-file normalization (latent bug): `_compile_hook` (`guitkx.gd:850-859`) emits
  `class_name <basename>` while `_binding_name` returns the hook name — unify: cls = binding
  (@class_name else hook name). **FLAG: changes committed contract fixtures for `t*hook*` cases.**

### 6.4 Cross-file addressing (V.comp per-decl — render-per-file dies)

- `v.gd` `comp()` gains a decl arg, cache keyed on `path + "::" + fn`:
```gdscript
static func comp(path: String, fn: String = "render") -> Callable:
	var k := path + "::" + fn
	var c = _comp_cache.get(k)
	if c == null:
		c = Callable(load(path), fn)
		_comp_cache[k] = c
	return c
```
- Emitter tag lowering (`guitkx.gd:1842-1868`): imported component tag →
  `V.fc(V.comp("res://…/hud.gd", "LocalRow"), …)`; func name comes from the target's export table
  entry (binding component → `"render"`, arg omitted). **V.comp laziness preserved (verified
  HOLDS)** — component imports never become preloads; cycles + fresh-clone ordering stay immune.
- Value imports (hook/module/hook-container names): lower to
  `const <Name> = preload("res://…/<target>.gd")` right after the `extends` line; a non-binding
  module import lowers to `const <Name> = preload("res://…/<target>.gd").<Name>`.
- Individual top-level hook import (`import { use_blink } from "./hud"`): lower
  `const __RUI_IMP_HUD = preload("res://…/hud.gd")` + call-site rewrite `use_blink(` →
  `__RUI_IMP_HUD.use_blink(` in verbatim regions via the existing `_apply_hook_aliases` pipeline
  (`guitkx.gd`, used at 853/989). `_hook_signature` runs on the PRE-rewrite text so fingerprints
  keep the bare snake_case name (family key stability).

### 6.5 Per-file-scoped known map (A6/adversarial: known is global today)

- Today `known` = one global map (`guitkx.gd:146-154`). New per-file resolution universe =
  ambient global classes (`true`) + this file's OWN decls (module-local form) + this file's
  IMPORTS (path form). Names in OTHER files' export tables but not imported → GUITKX2305.
  Names nowhere → GUITKX2307 (frozen semantics — 2302 is a name missing from a RESOLVED import
  target; existing 2102-unknown-tag path stays for markup-vocab misses).
- `compile_file` signature (`guitkx_codegen.gd:361`): pass the resolver product
  `{ambient, exports_by_name, imports_resolved}` instead of flat `known_components` /
  `component_paths` (keep old params defaulted for one release; tests use the new form).

---

## 7. Milestones (each ends green on the verify commands in §10)

### M0 — prerequisites
- Confirm gates (§5). Family block + canonical corpus list are FROZEN in §0 (2300–2315; the
  26xx fallback is dead). FIRST restart task: renumber the parked WIP commit's 26xx → 23xx
  everywhere (vocabulary rows, emit sites, tests, TS mirror), then rebase onto `master`.

### M1 — grammar + scan (both implementations)
- `guitkx.gd`: preamble import parser (static string-literal only; anything else = GUITKX0300
  malformed-directive style error); `export` prefix in `_find_decl`; decl LOOP (§6.1). Scan-side
  diags per the frozen split (§0.1): GUITKX2303 duplicate-import + GUITKX2309
  import-after-first-decl fire AT SCAN, file-locally.
- `guitkx_codegen.gd`: `_binding_names` (§6.2, order-agnostic scan fix FIRST).
- TS mirror: `ide-extensions/lsp-server/src/declScan.ts` (`DECL_KEYWORDS` + export prefix,
  `findDecl` loop), `scanner.ts`, `workspaceIndex.ts` (`scanDeclarations` + import scan; regex in
  `guitkx_workspace.gd:21` gains `(?:export[ \t]+)?`), `guitkx_workspace.gd` `_decl_re`/`_cn_re`.
- Tokenizer/highlighter: `addons/reactive_ui_editor/editor/guitkx_tokenizer.gd` +
  `guitkx_code_highlighter.gd` (import/export keywords); TextMate
  `ide-extensions/vscode/syntaxes/guitkx.tmLanguage.json`; `semanticTokens.ts`.
- Formatter BOTH sides (`guitkx_formatter.gd:39-64` preamble canonicalization currently models
  ONLY `@class_name` — it must model the import block or preserve it verbatim; canonical order:
  imports, then `@class_name`, then `@uss`; normalize spacing, never reorder import lines;
  idempotency corpus case). Mirror `formatGuitkx.ts`/`guitkxFormat.ts`.
- Diagnostics: add the frozen 23xx rows (§0.1) to both `vocabulary.json` copies; **FLAG:
  regenerate committed `guitkx_vocabulary.gen.gd`.**

### M2 — data model + emission (mixed-decl, privacy)
- Implement §6.3/§6.4/§6.5. `v.gd` `comp(path, fn)`.
- Privacy emission: no `class_name` when nothing exported; non-binding decls never register
  globally; GUITKX2106 keys exported bindings only (`project_bindings`).
- Sidecar schema v3 (`write_diags_sidecar`, `guitkx_codegen.gd:36-45`):
  `{ v:3, src_hash, diagnostics, refs, imports:[{names,spec,path}], exports:[{name,kind,func}],
  export_hash:int, dep_export_hashes:{path->int} }`. `refs` stays for GUITKX2107 dangling checks.
- Workspace index + completion export-aware (A6d): `guitkx_workspace.gd` records `export` per
  entry; `guitkx_completion.gd` offers only (a) ambient classes, (b) this file's decls,
  (c) imported names, (d) exported names elsewhere WITH auto-import edit (LSP nicety, optional).
- **FLAG (committed generated output): `tests/contract/fixtures/*.gd`, `*.diags.json`,
  `tests/contract/golden/*.json` re-pin via `godot --headless --path . --script
  res://tests/contract_dump.gd` after every emitter change in this milestone.**

### M3 — resolution + strict diagnostics
- New `addons/reactive_ui/guitkx/guitkx_resolve.gd` (static): specifier→path (relative + `~/`),
  export tables, per-file import resolution, resolve-side 2300/2301/2302/2304/2305/2307/2308
  emission (frozen split §0.1), value-cycle DFS (preload edges only — imported hooks/modules;
  component edges excluded) printing the full chain (2306, sweep-level).
- `~/` root: `GuitkxConfig` (`addons/reactive_ui_editor/lsp/guitkx_config.gd`) — but the RUNTIME
  compiler cannot depend on the editor addon: move/duplicate the walk-up into
  `addons/reactive_ui/guitkx/guitkx_config.gd` (compiler-side), editor + TS (`schema.ts`,
  `formatGuitkx.ts` loader) delegate. New top-level key `"root"` (default `res://`); nearest
  config wins, NO merge — a formatter-only config in a subdir shadows an ancestor root
  (documented, family wording from A5g).
- Strict scoping: build ambient set once per sweep (rule 7); 2305 fires only for names in the
  cross-file export tables; setup-text references to ambient hand classes never diagnose.
- `compile_all` + `guitkx_build` + editor sweep all resolve from SOURCE imports each pass;
  sidecars only accelerate the unchanged-file path (verify `dep_export_hashes` before trusting).
- M3.6 `~/` in assets: `@uss`/`@theme` value handling (`guitkx.gd:191-207`) — `~/`-prefixed →
  rewrite to `res://<root-rel>` at compile time before the existing FileAccess/ResourceLoader
  validation; `uid://` passthrough untouched (G-07 comment stays). Same in the editor LSP asset
  validation and `virtualDoc` theme const.

### M4 — two-pass parse check + CI gate + reverse-edge staleness (A6a, probe-confirmed)
- Problem: `compile_file` parse-checks IMMEDIATELY after write (`guitkx_codegen.gd:413-426`);
  `GDScript.new().reload()` with a missing preload target = ERR_PARSE_ERROR 43; `guitkx_build.gd`
  compiles lexicographically (`:12`), so const-preload value imports fail A-before-B on fresh
  clones; and `gd_parse_ok=false` exits 0 today (`guitkx_build.gd:20-25,37`).
- Fix: **two-pass write-all-then-check-all** in BOTH `compile_all` (`guitkx_codegen.gd:439-560`)
  and `tests/guitkx_build.gd`: pass 1 compiles + writes every `.gd` (parse check deferred);
  pass 2 runs the throwaway `GDScript.new().reload()` per output; a pass-2 failure whose file has
  unwritten deps re-checks once after the sweep (probe P5: re-reload heals once deps exist).
- **Promote `gd_parse_ok` to a COUNTED CI error:** `guitkx_build.gd` sums pass-2 failures into
  `errors` and exits 1. (Strip-`class_name` trick at 420-421 stays.)
- **HMR-push gating:** `plugin.gd:135-147` currently pushes gd_ok=false deliberately (the
  transient registry case). Post-M2, guitkx-to-guitkx refs are path-based (`V.comp` / const
  preload) so that transient reason is gone: after pass 2, push ONLY `gd_ok == true` entries; the
  in-game injection retry (`hmr.gd:88`) remains for pre-migration scripts. Update the 136-142
  comment block.
- **Reverse-edge staleness (A6-EXTRA):** `compile_all` computes `export_hash` per file (hash of
  sorted `exports` incl. func addressing); when it differs from the previous sidecar value, mark
  every importer stale (reverse edges from this sweep's source-import scan) and recompile them in
  the SAME sweep — this also fixes the error-verdict poison (sidecar error skip at 540-546 must
  additionally compare stored `dep_export_hashes` against current).

### M5 — HMR (scoped re-render + injector dedupe)
- Per-decl semantics: `hmr.gd` `_is_module` (160-164) → `_changed_kinds(scr)` reading
  `__RUI_DECLS`; component entries re-render targeted (per-decl `sig` compare drives per-component
  state RESET, not per-file); hook/module entries no longer force `global_rerender` — instead:
- Editor computes the refresh set: `plugin.gd` push gains a third element —
  `session.send_message("rui_hmr:reload", [gd_paths, bindings, refresh_roots])`
  (`editor/hmr_debugger.gd:26`), where `refresh_roots` = generated `.gd` paths of the nearest
  COMPONENT importers reachable from each changed hook/module file over reverse import edges
  (React Fast Refresh parity: propagate up to nearest component importers; escapes the graph →
  fall back to global re-render, exactly today's behavior). `RUIHmr.apply` + 
  `RUIReconciler.hmr_refresh_all` accept the targeted root set; pre-import pushes (2-element
  messages) keep the global path — wire-compat.
- **Injector dedupe (A6c, probe-confirmed duplicate-const = reload ERR_PARSE_ERROR):**
  `_inject_unregistered_bindings` (`hmr.gd:118-145`) gains a fourth skip: name already
  const-declared in source — regex `(?m)^const[ \t]+<name>\b` (NOT `src.contains`, which the
  existing mention-check already does and passes). Keep the injector alive for pre-migration
  cached scripts; note retirement path once no bare-name guitkx refs remain.

### M6 — codemod (`res://tests/guitkx_migrate.gd` runner + `addons/reactive_ui/guitkx/guitkx_migrate.gd`)
- **Inputs:** `Codegen.find_all("res://")` (fixtures excluded via `.gdignore`), `project_bindings`
  sources, ambient set (rule 7).
- **Reference-scan rules (A3 — sidecar refs are NOT enough: they record only markup tags,
  `guitkx.gd:1858-1860`; hook files return `refs:{}`, `:858-859`; setup-text calls like
  `DoomGameScreenHooks.use_doom_game` — `doom_game_screen.guitkx:14` — are recorded nowhere):**
  1. Markup tags: existing component-tag walk per file → component refs.
  2. NEW verbatim-region identifier scan: setup text, `{expr}`s, hook/module bodies — lexer-aware
     (`L.skip_noncode`), collect identifiers followed by `.` or `(`; match against OTHER files'
     binding/export names; drop ambient names, own-file decls, params/locals shadowing.
- **Output per file:** (a) prefix `export ` onto EVERY top-level decl (export-everything default);
  (b) write one import line per referenced target file, names sorted, targets sorted.
- **Specifier choice:** same directory → `./name`; else `~/`-rooted (root = `res://` default).
- **Insertion point (A6b):** immediately AFTER the existing directive block (`@class_name`/`@uss`
  lines) and before the first decl — safe in either order because M1 fixed `_binding_names`'s
  scan; blank line after the import block.
- **Idempotent:** skip names already imported; never duplicate `export `; re-runnable on rebases.
- **Acceptance:** run over the whole tree incl. doom (`doom_game_screen.guitkx` gains
  `import { DoomGameScreenHooks } from "./doom_game_screen.hooks"`; its DoomTypes/DoomTextures/
  DoomGameScreenLogic references remain import-free — ambient); then Gate 2 (§5) must pass.

### M7 — LSP / editor tooling mirrors (beyond M1 scan work)
- `guitkx_refs.gd` + `server.ts`: go-to-def/find-refs across files via import resolution
  (specifier click-through → target file/decl).
- `guitkx_scan_diags.gd` + LSP diagnostics: surface the frozen 23xx live (editor sweep already writes
  sidecars; ensure the resolver runs in the single-file on-type path with the cached tables).
- Virtual docs (`guitkx_virtual_doc.gd`, `virtualDoc.ts`): synthesize the const-preload lines in
  the header region so imported names resolve during embedded-GDScript analysis
  (length-preserving map: header inserts only, offsets unaffected — same trick as today's consts).
- `guitkx_outline.gd` / outline: multi-decl files list every decl with export badges.
- Editor recompile-on-focus flow unchanged; `GuitkxWorkspace.reindex` handles multi-entry files
  (it already erases-by-path — verified `guitkx_workspace.gd:45-54`).

### M8 — docs site + changelogs + versions
- `ReactiveUIGodotDocs~/src/pages/UITKX/`: NEW Imports page (grammar, strictness, codemod/
  migration guide, `~/`); rewrite `CompanionFiles/` (file-kind rules → conventions);
  `Config/` (+`"root"` key, no-merge shadowing note); `Diagnostics/` (+frozen 23xx table, §0.1);
  `Reference/` + `GettingStarted/` touch-ups.
- Changelogs (release-process two-lane rule): `CHANGELOG.md` (runtime lane, hand-written) +
  `addons/reactive_ui/CHANGELOG.md` mirror; `addons/reactive_ui_editor/CHANGELOG.md`;
  `ide-extensions/changelog.json` (source of truth for extension notes);
  `plans/DISCORD_CHANGELOG.md` entry.
- Version bumps (minor, all four deliverables): `addons/reactive_ui/plugin.cfg` 0.9.0→0.10.0;
  `addons/reactive_ui_editor/plugin.cfg` 0.7.0→0.8.0; `ide-extensions/vscode/package.json`
  0.9.0→0.10.0 (+ lsp-server, + VS2022 `.vsixmanifest`); docs `package.json`.
- **Skew rule (critic):** publish the VS Code/VS2022 extensions in the SAME release window as the
  addon (old TS mirror red-squiggles `import`/`export` otherwise); the new mirror treats imports
  as OPTIONAL syntax (no strict diagnostics without compiler sidecars) so old projects stay green.
- Do NOT commit anything without an explicit owner ask (house rule).

---

## 8. Test matrix (add/update; run per milestone)

| Suite | Adds |
|---|---|
| `tests/guitkx_test.gd` | import parse forms (`./`,`../`,`~/`, multi-name, dup=2303); export prefix on all 3 kinds; mixed-decl emission shapes (§6.3 snippets pinned); privacy (no class_name; two private same-name files BOTH compile); 2300–2309 each with a fixture (mirror `ReactiveUIUetkxResolveTest.cpp`'s case list, §0.3); value-cycle chain text; binding-identity (@class_name divergent file imports by binding name); `_binding_names` order cases (import-before-@class_name, @uss-before-@class_name — the latent bug); lone-hook-file binding normalization; V.comp per-decl addressing; component-cycle-legal pair (CycleProof mirror); asset `~/` rewrite |
| `tests/guitkx_build.gd` | two-pass; parse failure exits 1 (fixture pair compiled in adversarial order) |
| `tests/hmr_test.gd` | injector skips existing `const X`; per-decl sig reset; targeted refresh_roots path; 2-element wire back-compat |
| `tests/demos_test.gd` | unchanged assertions over the MIGRATED tree (real post-codemod render check) |
| `tests/doom_game_test.gd` | passes post-migration (codemod acceptance) |
| `tests/guitkx_editor_test.gd` / `tests/guitkx_lsp_test.gd` | export-aware index/completion; config `root`; go-to-def across imports; virtual-doc import consts |
| `tests/contract` | new `imp_*` fixtures (family-core mirrored + Godot-local) — **FLAG: committed goldens re-pin via `contract_dump.gd`** |
| `ide-extensions/lsp-server` | `node --test` corpus: declScan export/import cases, formatter round-trip (imports survive), workspaceIndex export-awareness, contract.test.ts against re-pinned goldens |

## 9. Steps that change COMMITTED generated output (flag list)

1. `tests/contract/fixtures/*.gd` + `*.guitkx.diags.json` + `tests/contract/golden/*.json` —
   M2 (emission), M3 (diags), M6 (fixture migration where applicable). Regenerate, review diff.
2. `addons/reactive_ui/guitkx/guitkx_vocabulary.gen.gd` — M1 (frozen 23xx rows, §0.1).
3. `examples/**/*.gd` are git-ignored (NOT committed) — no golden churn there; the hand-written
   exceptions (`doom_types.gd` etc.) are untouched by this leg.
4. No analyzer DLLs in this repo (Unity-only concern).

## 10. Verify commands (CI order; run after every milestone)

```bash
godot --headless --path . --script res://tests/guitkx_build.gd          # now two-pass + counted parse gate
godot --headless --path . --editor --quit || true                       # class-cache scan: STILL REQUIRED
godot --headless --path . --script res://tests/guitkx_test.gd
godot --headless --path . --script res://tests/hmr_test.gd
godot --headless --path . --script res://tests/demos_test.gd
godot --headless --path . --script res://tests/doom_game_test.gd
godot --headless --path . --script res://tests/guitkx_editor_test.gd
godot --headless --path . --script res://tests/guitkx_lsp_test.gd
godot --headless --path . --script res://tests/core_test.gd             # V.comp signature regression
godot --headless --path . --script res://tests/contract_dump.gd -- --check
cd ide-extensions/lsp-server && npm ci && npm run build && node --test out/test/*.test.js && node scripts/smoke.js
cd ide-extensions/vscode && npm ci && npm run build
cd ReactiveUIGodotDocs~ && npm ci && npm run build && npm run lint
```
- Class-cache scan note (research Q): it remains required — setup code still references AMBIENT
  hand-written `class_name` scripts (DoomTypes et al.) that only resolve headlessly after the
  scan; guitkx-to-guitkx reliance shrinks to zero (all path-based) but the step stays.
- Codemod run (Gate 2): `godot --headless --path . --script res://tests/guitkx_migrate.gd`
  then the full list above.

## 11. Risks / watch-list (leg-local)

- Const-preload value imports reintroduce load-order sensitivity — mitigated by M4 two-pass (the
  REAL fix; the 2306 policy error does not mitigate it) + V.comp laziness for components.
- `_binding_names` regression risk: every identity table (V.comp paths, 2106 arbitration, HMR
  link table, workspace index) keys on it — land its fix + tests FIRST (M1), before any emission
  change.
- HMR wire change (3-element message) must stay back-compat with 2-element (older running game).
- Codemod is load-bearing: zero-23xx tree is the PR's first green gate; doom is the acceptance
  corpus (module-hook consumption, ambient hand classes, multi-file companions).
- Family block RESOLVED — 2300–2315 frozen by leg 1 (§0.1); the 26xx fallback is dead. The
  parked WIP commit (`cc194ad`) still carries 26xx: renumber FIRST on restart, never ship
  divergent numbers.
