# Godot Port — Parity Plan (ReactiveUIToolKit → ReactiveUI-Godot)

Source: an 18-agent gap analysis (9 areas × analyze+verify, 2026-06-21) comparing the Unity reference
(`…/ReactiveUIToolKit`) against this port. **102 gaps (12 critical, 30 high).** Per-area parity:

| Area | Parity | Headline |
|---|---|---|
| Core library | **62%** | Engine is as sophisticated as Unity; gaps are BREADTH (router, signals, suspense, hooks) |
| GDScript fidelity | **45%** | Region extraction mostly works; the real defect is the LSP virtual-doc (flat scope + un-stripped JSX) |
| Tests | **28%** | No formatter/golden corpus; substring asserts only |
| Compiler | **25%** | Walking skeleton: no JSX-as-value, no module, ~9 of ~45 diagnostics |
| HMR | **25%** | Godot-native reload works; footguns (hook-shape desync, no live re-render) — user accepts the model |
| LSP features | **15%** | Completion+hover only; no live diagnostics, go-to-def, ClassDB props |
| Publishing | **15%** | Build+artifact only; no publish workflow / changelog.json / scripts |
| Docs/samples | **8%** | 1 sample vs 163; no docs site; stale README |
| **Formatter** | **3%** | Essentially nothing vs Unity's ~3000-LOC AstFormatter |

Guiding constraints (unchanged): **full GDScript everywhere embedded** (not a subset), GDScript-in-markup,
all Control types, pure GDScript, audience = everyone. Goal = ReactiveUIToolKit's *capabilities*, not an MVP.

---

## Phase 3 — Publishing & release infrastructure  *(DOING NOW, user priority)*

Closes the publishing area (15%→100%). Mirrors Unity's `publish.yml` + `changelog.json` + `scripts/changelog.mjs`
+ `publish-extension.ps1`/`publish-vsix.ps1`, **retargeted to the TypeScript LSP server** (Unity's model
`dotnet publish`es a C# server; ours bundles a Node server) and **adds Open VSX** (Unity has none, but the
Godot/VSCodium/Cursor audience needs it).

Deliverables:
- `ide-extensions/changelog.json` — central source of truth (`{date, versions:{vscode,vs2022}, shared:[…]}`).
- `ide-extensions/scripts/changelog.mjs` — generate per-IDE `CHANGELOG.md` + marketplace `overview.md`; an
  `add` authoring command with the CP1252-mojibake guard / `--message-file` safety the verifier flagged.
- `ide-extensions/vscode/CHANGELOG.md` + `ide-extensions/visual-studio/CHANGELOG.md` (generated).
- `.github/workflows/publish-extensions.yml` — workflow-dispatch, **idempotent per-extension version gating**
  (skip if `vscode-v*`/`vs2022-v*` tag exists), builds the Node server + bundles, `vsce publish` (VS Marketplace)
  + `ovsx publish` (Open VSX) + VS2022 `VsixPublisher`, then auto-tags. `permissions: contents: write` + git
  identity for tag-push; `extract` step so the `.vsix` ships its CHANGELOG.
- `ide-extensions/scripts/publish-extension.ps1` (VS Code local publish, patch-bump) +
  `publish-vsix.ps1` (VS2022 local publish — Node-server bundle, NOT a dotnet DLL).
- `vscode/package.json` `package`/`publish`/`deploy` scripts + `@vscode/vsce`/`ovsx` devDeps.
- `visual-studio/publishManifest.json` + `overview.md` template.
- Secret matrix doc (`VSCE_PAT`, `OVSX_TOKEN`, `VS_MARKETPLACE_PAT`) in `ide-extensions/README.md`;
  `plans/VERSIONING_PROCESS.md` (extension release process); `.gitignore` for `publisher-secrets.json`/`*.vsix`/`server/`.

---

## Phase 4 — Compiler parity + embedded-GDScript fidelity  *(toolchain correctness — your #6)*

The two areas are coupled: the compiler must LOWER markup-in-expressions, and the LSP virtual-doc must present
that embedded GDScript to Godot with correct scope. Closes compiler 25%→~90% and fidelity 45%→~90%.

Critical / high:
- **JSX-as-value splicing** (C): markup inside `{expr}`, ternary `x if c else y`, `and`/`or`, and lambda returns
  must lower to `V.*` calls — today it's passed verbatim → invalid `.gd`. Runtime already has `V.fragment/fc/portal`,
  so this is a compiler-emit change, not new runtime.
- **Setup-embedded markup** (H): JSX assigned to setup locals / returned from local funcs.
- **Scope-aware virtual doc** (C, fidelity): emit `{expr}`/conditions INSIDE their real scope (loop var, `@if`
  binding, setup locals visible) instead of flat `var __eN = (...)`, so Godot's LSP stops reporting false
  "undeclared identifier". Strip JSX/markup nested in `{expr}`/lambda bodies so Godot doesn't see raw markup.
- **Module declaration kind** (H) + multi-declaration files, with source-mapped bodies.
- **Full diagnostics catalog** (H): port the ~45 `UITKX####` codes with a real severity+location model (the port
  has 9 ad-hoc strings; `0301/0302/0305/0306` aren't even implemented). Include rules-of-hooks 0014/0015/0016
  (loop/switch/handler), unknown element/attr + did-you-mean, dup/missing key, single-root in block bodies.
- **Preamble directives** (H): support `@using/@inject/@props/@key` (and don't SILENTLY DROP unknown ones — emit a
  diagnostic; today it's data-loss).
- **Hook-alias fix** (M, real bug): blind substring replace corrupts identifiers/strings containing a hook name —
  replace with scope-correct, token-boundary wrapping.
- Fidelity leaf fixes: grammar mis-colors `<`/`>` comparison as tags; `R` vs `r` raw-prefix scanner divergence;
  `$NodePath`/`%Unique`/`^"path"`/`&"name"`/`await` leaf rules; `find_matching` cross-type imbalance; source-map
  needs entry-kind/straddle handling once regions are rewritten; `__C` deep child-flattener (V._norm is 1-level).

---

## Phase 5 — Formatter  *(3% → parity)*

Port Unity's `AstFormatter` (markup indentation, attribute wrapping at print-width, self-closing normalization,
control-flow body formatting, component/hook/module headers, blank-line capping, **idempotency**) as a GDScript or
TS AST formatter over the existing markup parser.
- `FormatterOptions` + config discovery (`guitkx.config.json` directory-walk merged with editor settings).
- **Embedded-GDScript formatting** (the hard part — Godot's LSP has NO formatting): recommend shelling out to
  `gdscript-toolkit`'s `gdformat` when present, else a conservative re-indent (the existing `_reindent_setup`
  generalized); the TS-LSP→formatter bridge runs the formatter out-of-process.
- Wire `textDocument/formatting` (+ range) into the LSP; advertise the capability.
- Idempotency / round-trip harness: `format(format(x)) == format(x)`.

## Phase 6 — LSP feature depth  *(15% → parity)*

- **Live compiler diagnostics** (C): run the compiler on change, surface its diagnostics (today only brace-balance).
- **Structural diagnostics tier**: unknown element/attribute (+did-you-mean), duplicate/missing key, rules-of-hooks,
  multiple render roots — as LSP diagnostics, not just compile-time.
- **ClassDB-driven completion** (H): per-control properties/signals from Godot (via the proxy or a generated dump),
  + attribute-VALUE completion (enums, style keys).
- **Workspace component index** (H): scan `.guitkx`/`.gd` for user components + their props for tag/attr completion.
- Go-to-definition, find-references, rename, signatureHelp, semantic tokens.
- Perf: cache/debounce `buildVirtualDoc` (today rebuilt + full-resynced per keystroke); fix SourceMap boundary
  ambiguity + O(n) scan.

## Phase 7 — Core library breadth  *(62% → parity)*

- **Router rewrite** (C, XL): nested/layout routes + `<Outlet>`, basename, query strings, `<NavLink>` active styling,
  `<Navigate>`, blockers, `useMatches/useSearchParams/useResolvedPath/useGo`, nested-router guard. Port `RouterPath`,
  `RouteMatch`, `RouteRanker`.
- **Signal registry/factory** (H): process-wide string-keyed shared signals + `use_signal_key`.
- **Suspense** (M): `V.suspense` + a poll/await-driven boundary (GDScript has no throw-to-suspend).
- Hook-order validation + dev diagnostics (StrictMode-ish), missing-deps warnings, state-update-during-render guard.
- `Text` vnode (string children); `Memo`/structural-equality bailout; remaining hooks (`use_deferred_value` real
  scheduler, media/animation hooks); host-config item-model adapters + `resolve_child_host`; style USS-class/
  pseudo-state (hover/pressed) layer.

## Phase 8 — HMR hardening  *(user accepts Godot-native; close the footguns)*

- Live-root re-render on hot-reload via a `ReactiveRootNode` registry (re-render mounted trees on sibling `.gd` reload).
- **Hook-shape-change guard** (H): a hook count/order signature → auto-remount when a refresh changes hook shape
  (today positional slots desync silently).
- Re-run `useEffect` cleanups on reload. (Family-based identity + HMR UX are optional/low.)

## Phase 9 — Documentation & samples  *(8% → parity)*

- Docs site (or a structured `docs/` set): getting-started, `.guitkx` language guide, concepts (hooks rules,
  context, signals, router, error boundary, differences-from-React/Unity), per-component reference, style vocabulary.
- Port a meaningful subset of the 163 Unity samples to `.guitkx` (incl. a couple of the game samples); an
  `examples/README.md` index; document the `examples/app.gd`/`main.tscn` launch path.
- Refresh the stale README (it claims "10 host elements" / understates 18 hooks + 51 `V.*` factories).

## Phase 10 — Test parity  *(28% → parity)*

- Formatter idempotency + snapshot tests (Unity's biggest suite).
- Golden codegen corpus (replace substring asserts; mirror EmitterTests' ~81 cases).
- Full diagnostics coverage incl. rules-of-hooks loop/switch/handler matrix.
- JSX-in-expression-position tests; grammar TextMate snapshot tests; virtual-doc/source-map round-trip breadth;
  samples-as-golden; a consolidated test runner + CI aggregation.

---

### Sequencing
Phase 3 first (now). Then 4 (toolchain correctness) → 5 (formatter) → 6 (LSP depth) are the IDE track;
7 (core breadth) → 8 (HMR) are the runtime track (independent, can interleave); 9 (docs) + 10 (tests) run
throughout and consolidate at the end. Each phase ships green tests before the next.
