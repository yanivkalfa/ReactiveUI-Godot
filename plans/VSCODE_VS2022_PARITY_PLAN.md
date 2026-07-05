# VS Code → VS2022 Extension Parity Plan

> **Goal:** every user-visible capability of the guitkx VS Code extension (0.8.6) exists in the
> VS2022 extension. **Status: PLANNED** — inventories complete (2026-07-05), no work started.
>
> Companion docs: `ide-extensions/README.md` (architecture), `ide-extensions/VERSIONING.md`
> (release process), `ide-extensions/visual-studio/README.md` (build/publish pointers).

## 0. The one fact that shapes everything

Both extensions are thin clients around the **same shared language server**
(`ide-extensions/lsp-server`, TypeScript, ~2,000 lines — capabilities registered in one block at
`src/server.ts:101-121`). The VS Code client is 68 lines (`vscode/src/extension.ts`); the VS2022
client is two C# files (~100 LOC): a content-type definition (`GuitkxContentDefinition.cs`) and a
MEF `ILanguageClient` (`GuitkxLanguageClient.cs`) that launches the bundled `server\node.exe
server.js --stdio`. The TextMate grammar is **byte-identical** across `grammar/`, `vscode/syntaxes/`,
and `visual-studio/GuitkxVsix/Syntaxes/` (verified by diff).

Consequently parity splits into four buckets:

| Bucket | Examples | Cost |
|---|---|---|
| **B1. Ship a fresh server** — features that arrive by repackaging alone, because VS routes whatever the server advertises | every server-side fix/feature of VS Code 0.6.0→0.8.6 (sidecar merge, live diagnostics tiers, semantic tokens, inlay hints, code actions, rename, signature help, gdformat reflow…) | trivial (rebuild + version bump) |
| **B2. Client wiring** — server supports it; the VSIX never feeds it | plain-`.gd` analysis (no `gdscript` content type), `useGdformat` init option, settings | small, mechanical |
| **B3. VS-native re-implementation** — VS Code contribution-manifest concepts with no VSIX equivalent | format-on-save, editor defaults (tabs/4), bracket auto-close, comment toggle, smart indent, restart command, options page | the real work |
| **B4. Process/packaging hygiene** | version drift (VSIX 0.5.5 bundling would-be-0.8.6 server), publisher mismatch, release checklist | small |

The current shipped VSIX is **0.5.5** and has not been re-released since; `README.md` already
documents that it is missing "every fix/feature shipped in VS Code 0.6.0–0.8.6". That is bucket B1.

## 1. Parity matrix (source of truth)

Legend: ✅ works today · 🟡 works but degraded/uncontrollable · ❌ absent · `P#` = phase that closes it.

| # | Feature | VS Code 0.8.6 | VS2022 0.5.5 today | Phase |
|---|---|---|---|---|
| 1 | Markup completion (tags/attrs/directives/style keys/events) | ✅ | ✅ (old server) | P0 refresh |
| 2 | Hover (schema + ClassDB + hooks) | ✅ | ✅ (old server) | P0 |
| 3 | Signature help (markup `on_<signal>` + embedded calls) | ✅ | ✅ (old server) | P0 |
| 4 | Go-to-definition (component/workspace + embedded → library `.gd`) | ✅ | ✅ (old server) | P0 |
| 5 | Find references (cross-file) | ✅ | ✅ (old server) | P0 |
| 6 | Rename + prepare-rename (project-wide, correct-or-refuse) | ✅ | ✅ (old server) | P0 |
| 7 | Document symbols / outline | ✅ | ✅ (old server) | P0 |
| 8 | Diagnostics: structural GUITKX + embedded GD + **compiler-sidecar merge** | ✅ | 🟡 old server = pre-0.8.x sidecar behavior | P0 |
| 9 | Semantic tokens (markup overlay + analyzer merge) | ✅ | 🟡 server-side yes; **verify VS 17.x LSP client renders them** | P0 (verify V1) |
| 10 | Inlay hints | ✅ | 🟡 same — **verify VS ≥17.6 LSP inlay-hint support** | P0 (verify V1) |
| 11 | Code actions (quick fixes) | ✅ | 🟡 same verification | P0 (verify V1) |
| 12 | Formatting: full + range, `guitkx.config.json` walk-up | ✅ | ✅ (old server; config walk-up is server-side) | P0 |
| 13 | Embedded-GDScript analysis toggle (`enableEmbeddedAnalysis`) | ✅ setting | 🟡 hardcoded `true` (`GuitkxLanguageClient.cs:27`) | P1 |
| 14 | gdformat embedded reflow toggle (`useGdformat`) | ✅ setting | ❌ never sent → server default on, uncontrollable | P1 |
| 15 | **Plain `.gd` language service** (diagnostics/completion/hover/nav/rename/format/semantic/inlay/actions/symbols) | ✅ (`enableGdscriptAnalysis`) | ❌ **no `gdscript` content type — unreachable** | P2 |
| 16 | Absence-based `UNDEFINED_*` diagnostics (watcher-gated) | ✅ dynamic LSP watcher | 🟡 server's `fs.watch` fallback (win32 ✓ — VS is Windows-only) — verify arming | P2 (verify V2) |
| 17 | Format-on-save | ✅ (`configurationDefaults`) | ❌ | P3 |
| 18 | Editor defaults for the language (tabs, size 4, no detect) | ✅ | ❌ (VS global settings apply) | P3 |
| 19 | Bracket auto-close/surround (`{} [] () <> " '`) | ✅ language-configuration | ❌ | P3 |
| 20 | Comment toggle (`#`, Ctrl+K,C / Ctrl+/) | ✅ | ❌ | P3 |
| 21 | Smart indent / on-enter rules (JSX-aware) | ✅ | ❌ (TextMate defaults only) | P3 |
| 22 | Restart Language Server command | ✅ command palette | ❌ (no commands at all) | P4 |
| 23 | Settings surface for the three `guitkx.*` options | ✅ | ❌ (`ConfigurationSections` declared but inert — nothing can set values) | P1 |
| 24 | Server-start failure UX | n/a (VS Code shows output) | ✅ custom notification (`ShowNotificationOnInitializeFailed`) | — |
| 25 | Syntax highlighting (TextMate) + embedded GDScript colouring | ✅ | ✅ (`guitkx.pkgdef` → VS TextMate engine; grammar identical) | — |
| 26 | Self-contained runtime | n/a (VS Code hosts Node) | ✅ bundled `node.exe` via `fetch-node.ps1` | — |
| 27 | Marketplace metadata correctness | ✅ | 🟡 manifest Publisher `Yaniv Kalfa` ≠ marketplace `ReactiveUITK` (`publishManifest.json`) | P0 |
| 28 | Snippets | ❌ (none) | ❌ (none) | non-goal |
| 29 | Untitled/unsaved buffers analyzed | ❌ (`scheme:"file"` only) | ❌ | non-goal |

Server capabilities **not** advertised by the shared server (so out of scope for both editors):
workspace symbols, folding, document highlight/links, color, declaration/typeDef/implementation,
call/type hierarchy, code lens, on-type formatting, selection range, linked editing, pull
diagnostics, completion-resolve.

## 2. Phase 0 — Repackage, verify, re-release (bucket B1 + B4)

**Outcome:** VS2022 ships the 0.8.6 server + current analyzer; rows 1–12 go green with zero C#.

1. Bump `source.extension.vsixmanifest` `Identity/@Version` — see §7 for the number (recommend
   jumping to **0.8.6** to version-lock with the bundled server).
2. `scripts/changelog.mjs add --ide vs2022 …` entries summarizing the inherited 0.6.0–0.8.6 server
   features (the changelog is the single source of truth; `overview.md`/`CHANGELOG.md` regenerate).
3. Fix the **publisher mismatch**: manifest `Publisher="Yaniv Kalfa"` vs `publishManifest.json`
   `"publisher": "ReactiveUITK"`. The manifest Publisher is a display string; align it to the
   marketplace publisher (`ReactiveUITK`) so the listing and the installed-extension dialog agree.
4. Release via the existing `publish.yml` → `publish-vs2022` job (already verifies the VSIX
   contains `server/server.js` + `server/node.exe`, publishes with VsixPublisher, tags
   `vs2022-v<version>`).
5. **Verification checklist V1** (manual, in a VS2022 instance with a Godot project open):
   - [ ] All of rows 1–8, 12 behave identically to VS Code on the same files.
   - [ ] **Semantic tokens**: confirm VS's LSP client (`Microsoft.VisualStudio.LanguageServer.Client`
         17.7) renders `textDocument/semanticTokens/full`. If it does not, log it in §8 Risks —
         TextMate colouring remains the baseline; do NOT hand-roll a classifier in this phase.
   - [ ] **Inlay hints**: supported by VS LSP clients from ~17.6; verify hints appear inside
         `{expr}`. If not rendered, record and move on (cosmetic).
   - [ ] **Code actions**: verify the lightbulb surfaces analyzer quick-fixes.
   - [ ] Diagnostics dimming (`DiagnosticTag.Unnecessary`) renders (unreachable-after-return).
6. Also close the **VS Code-side packaging question** found during inventory: the npm `package`
   script runs `vsce package` *without* `--no-dependencies`, while `publish-extension.ps1` uses
   `--no-dependencies`. Since the client depends on `vscode-languageclient` at runtime and there is
   no bundler, confirm the published VSIX contains `node_modules/vscode-languageclient`; align the
   two paths (either bundle with esbuild or drop the flag).

**Files touched:** `source.extension.vsixmanifest`, `changelog.json` (via script), possibly
`vscode/package.json`/`publish-extension.ps1` (item 6). No C#.

## 3. Phase 1 — Options page + initialization options (bucket B2/B3)

**Outcome:** rows 13, 14, 23. The three VS Code settings get a real VS surface, and what the
server is told is user-controlled.

1. Introduce an `AsyncPackage` (`GuitkxPackage.cs`) — required host for options/commands. Keep
   `GeneratePkgDefFile` semantics intact: the package now generates its pkgdef; **merge, don't
   clobber**, the static TextMate `guitkx.pkgdef` registration (either keep the static file as a
   second VsPackage asset — as today — or fold the TextMate key into the generated pkgdef; keep
   the static file, it is load-bearing and audited).
2. `DialogPage`-based options: **Tools → Options → GUITKX**:
   - `Enable embedded GDScript analysis` (default true) → init option `enableEmbeddedAnalysis`.
   - `Use gdformat for embedded reflow` (default true) → init option `useGdformat`.
   - `Analyze plain .gd files` (default true) → gates Phase 2's document coverage.
3. `GuitkxLanguageClient` reads the options at `ActivateAsync` and builds `InitializationOptions`
   dynamically (replacing the hardcoded anonymous object).
4. **Config-change semantics:** the shared server has **no** `onDidChangeConfiguration` handler
   (VS Code has the same restart requirement). So: on option change, show an info bar/dialog
   "Restart the GUITKX language server to apply" — wired to the Phase 4 restart command once it
   exists; until then, instruct to reload VS. Do NOT pretend live sync works; remove or implement
   `ConfigurationSections` accordingly (currently inert).

**Files:** new `GuitkxPackage.cs`, new `GuitkxOptionsPage.cs`, edit `GuitkxLanguageClient.cs`,
`.csproj` (VSSDK package generation), `source.extension.vsixmanifest` (VsPackage asset if the
generated pkgdef is added).

**Acceptance:** toggling each option + restart changes observable behavior (embedded completion
disappears when off; gdformat reflow stops when off).

## 4. Phase 2 — Plain `.gd` language service (bucket B2; biggest single gap)

**Outcome:** row 15 (and verify row 16). The server's entire `.gd` surface — diagnostics,
completion, hover, navigation, project-wide rename, formatting, semantic highlighting, inlay
hints, code actions, symbols — reaches VS users, as it reached VS Code users in 0.3.0.

1. New content type in `GuitkxContentDefinition.cs`:
   ```csharp
   [Export] [Name("gdscript")] [BaseDefinition(CodeRemoteContentDefinition.CodeRemoteContentTypeName)]
   internal static ContentTypeDefinition GdscriptContentType;
   [Export] [FileExtension(".gd")] [ContentType("gdscript")]
   internal static FileExtensionToContentTypeDefinition GdExtension;
   ```
2. Attach the SAME `ILanguageClient` to both content types (add a second
   `[ContentType("gdscript")]` attribute on the existing export) — one server instance serves
   both, mirroring VS Code's two-entry document selector. Do **not** spawn a second client.
3. Gate on the Phase 1 option (`Analyze plain .gd files`): when off, skip registering… MEF
   attributes are static, so instead gate inside `ActivateAsync`/document-open path: simplest
   correct approach is to always register the content type but have the client send the option to
   the server and let the server no-op `.gd` documents when disabled (add the tiny server-side
   check under an init option `enableGdscriptAnalysis`, mirroring what VS Code does client-side
   with its selector — a small shared-server change, ~10 lines, benefiting both editors).
4. **Highlighting for `.gd` in VS**: LSP semantic tokens provide type-aware colour, but the
   TextMate baseline for plain GDScript is NOT shipped (the guitkx grammar only colours embedded
   blocks). Decide: (a) ship a minimal `gdscript.tmLanguage.json` next to the guitkx grammar in
   the pkgdef repository (the grammar dir is already the repo root — one more file), or (b) rely
   on semantic tokens only. Recommend (a) for offline/cold-start parity with VS Code (where the
   user typically has godot-tools' grammar installed).
5. **Coexistence note** (docs + options tooltip): if another VS extension claims `.gd`, the
   content-type/file-extension mapping may conflict; document the toggle as the escape hatch —
   same policy as the VS Code README's godot-tools paragraph.
6. **Verification checklist V2:**
   - [ ] `.gd` file: diagnostics, completion, hover, goto, rename across files, format document.
   - [ ] Absence-based `UNDEFINED_*` diagnostics arm after startup (server `fs.watch` fallback is
         win32 — VS is win32-only, so this should work; verify `setWorkspaceComplete` fires by
         typo-ing a function name and seeing the diagnostic).
   - [ ] guitkx ↔ gd cross-file: renaming a component updates `.guitkx` usages AND generated
         sibling awareness still holds.

**Files:** `GuitkxContentDefinition.cs`, `GuitkxLanguageClient.cs`, optionally
`Syntaxes/gdscript.tmLanguage.json` + `guitkx.pkgdef` (already points at the folder), ~10 lines in
`lsp-server/src/server.ts` (init-option gate), `.csproj` (include new grammar file in VSIX).

## 5. Phase 3 — Editor ergonomics (bucket B3)

**Outcome:** rows 17–21. This is where VS Code's `language-configuration.json` +
`configurationDefaults` get VS-native equivalents. All are per-content-type MEF exports — no
global behavior changes.

1. **Editor defaults (row 18)** — `IWpfTextViewCreationListener` for `ContentType("guitkx")`:
   set `ConvertTabsToSpaces=false`, `TabSize=4`, `IndentSize=4` on the view's `IEditorOptions`.
   (VS has no `detectIndentation`; nothing to disable.)
2. **Format-on-save (row 17)** — `IVsRunningDocTableEvents3.OnBeforeSave` (advise via the RDT in
   the package) for guitkx documents: send `textDocument/formatting` through the LSP client and
   apply the `TextEdit[]` before the save proceeds. Add an options-page toggle (default ON to
   match VS Code's `configurationDefaults`). Guard re-entrancy (applying edits must not re-trigger
   OnBeforeSave) and no-op when the server is down.
   - Implementation note: the cleanest LSP-request path from the client side is
     `ILanguageClientBroker`/`RequestAsync` on the JSON-RPC connection; we own `ActivateAsync`'s
     `Connection`, so keep a reference to the `JsonRpc` wrapper if the broker route is awkward.
3. **Brace completion (row 19)** — `IBraceCompletionDefaultProvider` export with
   `[BracePair('{','}')] [BracePair('(',')')] [BracePair('[',']')] [BracePair('<','>')]
   [BracePair('"','"')] [BracePair('\'','\'')]` for `ContentType("guitkx")`.
4. **Comment toggle (row 20)** — export `ICommentSelectionService` (`#` line comment, no block
   comment) for the content type; VS's Ctrl+K,C / Ctrl+K,U then work natively.
5. **Smart indent (row 21)** — `ISmartIndentProvider` for guitkx: minimal port of the two
   `language-configuration.json` rules — indent after a line ending in `>` of an opening tag or
   `{`/`(`; keep child indent between `<Tag>` and `</Tag>`. The "Enter between `></`" splits into
   an indented middle line" nicety from the in-Godot editor/VS Code onEnterRules can be a
   command-filter (`IOleCommandTarget` on RETURN) — mark OPTIONAL; ship the basic smart indent
   first.
6. **Verification checklist V3:** each of the five behaviors demonstrated in a `.guitkx` buffer;
   format-on-save round-trips a dirty misformatted file byte-identically to VS Code's output.

**Files:** new `Editor/` C# files (view-creation listener, RDT save listener, brace provider,
comment service, smart indent), `.csproj` compile items. No manifest changes.

## 6. Phase 4 — Commands (bucket B3)

**Outcome:** row 22 (+ the Phase 1 restart hook).

1. `.vsct` with one command: **GUITKX: Restart Language Server** (Tools menu + context menu of
   guitkx editors). Wire through the `AsyncPackage` from Phase 1.
2. Restart mechanics — investigate in order:
   a. `Microsoft.VisualStudio.LanguageServer.Client` 17.7's supported reload path (RPC to
      `ILanguageClientBroker` to re-`LoadAsync` the client) — the documented pattern;
   b. else: own-the-connection restart — keep the `Connection`/process handle from
      `ActivateAsync`, dispose + signal `StopAsync`/re-activate;
   c. worst case: kill the `node.exe` child and rely on VS's automatic single-restart of crashed
      servers, with the command as UX sugar.
   Record which path shipped in the code comment — this is the piece with real API risk.
3. Also from Phase 1: option changes surface an info bar with a "Restart now" action bound here.

**Verification V4:** command visible in Command Window/Tools menu; after restart, edits in
`guitkx.config.json` (formatter width) take effect without reloading VS.

## 7. Versioning & release policy for parity

- Today: VSIX version is hand-bumped in the manifest, tagged `vs2022-v<version>`, fully decoupled
  from the server version. That is how 0.5.5 could silently fall 15 releases behind.
- **Recommendation:** at Phase 0, jump the VSIX to **0.8.6** and adopt the rule "the VSIX version
  tracks the bundled `lsp-server` version; a 4th segment (`0.8.6.1`) covers VS-only fixes". Encode
  the rule in `ide-extensions/VERSIONING.md`, and add a CI guard in `publish-vs2022`: warn when
  `vsixmanifest` version < `lsp-server/package.json` version (drift alarm — the exact failure mode
  that produced this plan).
- Changelog: keep `changelog.json` as the single source; every phase lands entries via
  `scripts/changelog.mjs add`.

## 8. Risks / open questions

| # | Risk | Mitigation |
|---|---|---|
| R1 | VS LSP client may not render semantic tokens / inlay hints at the pinned client-lib 17.7 | Phase 0 verification; if unsupported, bump `Microsoft.VisualStudio.LanguageServer.Client` / VS floor, or accept TextMate-only colouring (document in README) — do NOT hand-roll classifiers |
| R2 | No public restart API for `ILanguageClient` | Phase 4 options a→c; worst case the command degrades to guidance + auto-restart |
| R3 | `.gd` content-type conflicts with other installed Godot extensions | Option toggle (Phase 1) + docs; content type only claims `.gd` when no other definition wins MEF ordering — test alongside the popular godot VS extensions |
| R4 | Format-on-save via RDT re-entrancy / async deadlocks (JTF) | Follow VSSDK JoinableTaskFactory rules; format with a timeout; never block the UI thread on the LSP call |
| R5 | Server-side `enableGdscriptAnalysis` init-option change regresses VS Code | The VS Code client keeps its selector gating; the server option defaults ON, so absent = current behavior; add an lsp-server test |
| R6 | The Phase 1 pkgdef merge breaks TextMate registration | Keep the audited static `guitkx.pkgdef` asset untouched; the package's generated pkgdef is additive |
| R7 | VSIX size (~80 MB, bundled Node) — unchanged by this plan | Non-goal; note `single-file` Node alternatives only if the Marketplace ever complains |

## 9. Execution order & effort ballpark

| Phase | Contents | Effort | Ships value |
|---|---|---|---|
| P0 | repackage + verify + publisher fix + vsce-flag check | ~half a day incl. manual V1 | ~70% of the gap (all server-side features) |
| P1 | package + options page + init options | ~1 day | control surface |
| P2 | `.gd` content type + server gate + optional grammar | ~1 day | headline feature |
| P3 | ergonomics (5 MEF exports) | ~1–2 days | daily-driver feel |
| P4 | restart command | ~half a day + API investigation | quality of life |

Each phase is independently releasable (P0 alone justifies a release); tag + changelog per phase
per §7. Suggested branch naming: `feat/vs2022-parity-p<N>`, PRs into `dev` as usual.
