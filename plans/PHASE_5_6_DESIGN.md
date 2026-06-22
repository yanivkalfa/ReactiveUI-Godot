# Phase 5 (Formatter) + Phase 6 (LSP depth) — production design

Source: a 10-agent design+critique workflow (2026-06-22). Every first-pass design came back
"needs-work"; the corrected designs below bake in the critics' fixes.

## §5 — Formatter

**Key decision (corrected): the formatter is authored in GDScript** (`guitkx_formatter.gd`) reusing
`guitkx_markup.gd` (the single parser of record) — **NOT a 2nd TS parser** (the drift the whole
codebase is built to avoid). The first design's "custom `guitkx/format` JSON-RPC over Godot's engine
LSP" is **impossible** — the built-in GDScript LSP cannot host custom methods. So:

- **`addons/reactive_ui/guitkx/guitkx_formatter.gd`** (`RUIGuitkxFormatter`): pure, `FileAccess`-only,
  headlessly unit-testable. `format(source, opts) -> { ok, text, changed }`. Reuses `guitkx_lexer.gd`
  + `guitkx_markup.gd` + the decl/setup/markup split already in `guitkx.gd`. **On ANY parse error →
  return the source verbatim** (never corrupt — Unity's guarantee).
- **Formats against the ACTUAL Godot grammar** (not Unity's): preamble = optional `@class_name` only
  (no `@using`/`@uss`); control flow = `@if`/`@elif`/`@else`, `@for (header)`, `@while (header)`,
  `@match (subj) { @case (val) { … } @default { … } }`; control-flow bodies are **raw strings
  re-parsed** via `Markup.parse` with a verbatim-reindent fallback; `@elif` (not `@else if`).
- **Embedded GDScript (v1) = a STRUCTURE-PRESERVING base-indent normalizer** (exactly what
  `_reindent_setup` does — strip common prefix, re-anchor to the host indent, keep internal relative
  indent byte-for-byte). A from-scratch GDScript re-indenter is **unsound** (no closing token).
  `gdformat` (gdscript-toolkit) is a documented **optional Tier-1 upgrade**, never required.
- **Options** (`guitkx_format_options.gd`): `printWidth`, `indentStyle` (`tab`|`space`), `indentSize`,
  `singleAttributePerLine`, `bracketSameLine`, `closingBracketSameLine`, `insertSpaceBeforeSelfClose`.
  Config via `guitkx.config.json` directory-walk (the spec defined once; both editor + LSP share a fixture).
- **Idempotency:** golden fixpoint tests — `format(x) == format(format(x))` for every fixture.
- **Integration:** the `@tool` plugin runs it on compile / via a "Format" command (primary path for
  Godot-editor users, headlessly testable). The **LSP `textDocument/formatting`** shells out to Godot
  headless to run the same GDScript formatter (on-demand, not per-keystroke; content-hash cache; timeout;
  **no-op degrade** when the Godot binary/editor is unavailable — same graceful-degradation as the proxy).
  No range formatting in v1 (the AST has no node source spans).

## §6 — LSP depth

### a) Diagnostics (live structural tier)
**Key decision:** re-implement the structural tier **in TS** as the LIVE tier over **ONE shared
`walk.ts`** (refactor `virtualDoc.ts`'s markup walk into a side-effect-free walker on the
byte-identical `scanner.ts`); the GDScript compiler is the authoritative **on-save sidecar** (NOT a
per-keystroke shell-out — the engine LSP exposes no compile API, and the LSP must work with no editor).
- **Blocker fix:** the compiler **bails on the first parse error** (returns `ok:false` before
  `_validate`), so it does NOT emit a full catalog. Make `compile()` **best-effort** (always return a
  structured diagnostics array incl. parse errors AND partial semantic checks) and write
  `Foo.guitkx.diags.json` on **every** compile attempt (decoupled from codegen success). LSP reads it,
  de-dups vs the live tier by code+offset.
- **Live checks (TS, with ranges), each mirroring the compiler exactly:** dup-key (scope resets per
  control-flow body + per element-children boundary), missing-loop-key (only when the `@for`/`@while`
  body is exactly ONE element lacking a key), multi/single-root, parse errors (`GUITKX0301/2/3/4`),
  rules-of-hooks (setup-indent heuristic, parity with `guitkx.gd`), unknown-element (Warning/Hint,
  **PascalCase only** — lowercase tags are host factories, never flagged; gated by the workspace index).
- **did-you-mean** (Levenshtein over schema tags/attrs + ClassDB props when online), small pools, first-char/length pre-filter. Route ALL skipping through `scanner.ts` (no ad-hoc quote handling → no dict-literal false positives).

### b) Navigation (workspace index + go-to-def + refs/rename + symbols)
**Key decision (corrected):** index components by **binding identity = `(@class_name override) ??
(component decl name)`** — NOT basename (the first design's basename keying was wrong: cross-file
`<Foo/>` → `V.fc(Foo.render, …)` where `Foo` is the class_name). Multi-valued `byName` + `byUri`
eviction (Unity's model). Three-tier freshness: async scan-on-init (with an `indexReady` gate),
`didChangeWatchedFiles` per-file reindex, and on-change reindex **debounced separately** from the cheap
structural diagnostics (and parse-failure-tolerant: keep the prior entry on incomplete parse).
- **`scanDeclarations(src)`** (new, shared by the index + `documentSymbol`): a module-body member loop
  mirroring `guitkx.gd`'s dispatch, returning `{kind, name, nameRange, declRange, paramsRange}` for
  every top-level/module-member decl (not just the first).
- **go-to-definition:** `<Foo/>` → the component/module decl (open-but-unsaved targets navigate too);
  an embedded-GDScript symbol → forward to Godot's LSP over the virtual doc, **mapping result ranges
  back** via the SourceMap (add a `toSourceRange` helper; drop locations in the synthetic vUri unless
  they map back). **First probe** the engine LSP's `InitializeResult.capabilities` —
  `definition/references/rename` may be absent.
- find-references + rename (scan via `scanner.ts`, skipping strings/comments/`{expr}`); documentSymbol
  (outline incl. module members). **Semantic tokens: SKIP v1** (TextMate already colors; Godot supplies none).

### c) ClassDB-driven completion
**Key decision:** a **generated ClassDB JSON dump** (`addons/reactive_ui/dev/classdb_dump.gd`, `@tool`)
as the authoritative markup-attribute source; the proxy is retained ONLY for embedded `{expr}`. Hybrid.
- **`classdb_dump.gd`** walks `Control` + `get_inheriters_from_class("Control")`; per class emits
  own-only `properties:[{name,type,enum?,hint?}]` + `signals:[{name,args}]` (base-flattened at runtime,
  gzip, ~120 classes). Bundled per Godot minor; a CI job regenerates it via headless Godot.
- **Blocker fixes:** resolve `godotClass` **only from the compiler's `HOST_TAGS` + the `v.gd`
  lowercase-factory list** (generate the LSP tag table from those GDScript sources so they never drift)
  — a PascalCase tag absent from `HOST_TAGS` is a **function component** (`V.fc`) with NO Control props /
  NO `on_<signal>`; complete enum/bool/int values **inside `={…}` as named-constant expressions**
  (`Control.MOUSE_FILTER_PASS`) — NOT inside `="…"` (a string attr emits a literal, breaking the prop);
  add `godotVersion` to `initializationOptions`; honor `enableGodotProxy=false` (short-circuit proxy paths).
- attribute-NAME completion = the element's `godotClass` properties + structural (`key`/`ref`/`style`)
  + `on_<signal>` events; attribute-VALUE = enum constants / bool / int; signature help = opportunistic
  (only when the cursor is inside `={ func(...): }` for an `on_<signal>`; don't assume the lambda shape —
  `on_pressed={_on_click}` method-ref is common).

## Resolved defaults (no user input needed — sensible recommendations)
- Formatter embedded: base-indent normalizer default; `gdformat` optional/documented. Format = explicit
  command + opt-in auto-on-save. No range formatting v1.
- Semantic tokens: skipped v1. ClassDB dump: bundle the project's target Godot minor, CI-regenerated.

## Implementation order
§5 formatter (`guitkx_formatter.gd` + options + golden/idempotency tests) → §6a diagnostics
(`walk.ts` refactor + checks + compiler best-effort + `diags.json` bridge) → §6b navigation (index +
go-to-def) → §6c ClassDB (`classdb_dump.gd` + dump-backed completion). Each ships green tests first.
