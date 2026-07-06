# VS Code → VS2022 Extension Parity Plan

> **Goal:** every user-visible capability of the guitkx VS Code extension (0.8.6) exists in the
> VS2022 extension. **Status: hardened, execution starting** — inventories complete (2026-07-05),
> reviewed + web-verified against Microsoft docs the same day (see below), execution beginning on
> `feat/vs2022-parity`.
>
> **2026-07-05 review pass** (web-verified, not just re-read): fixed a real build bug found while
> verifying this plan — `GuitkxVsix.csproj` pinned `Microsoft.VisualStudio.LanguageServer.Client
> 17.7.41` / `Microsoft.VSSDK.BuildTools 17.7.2189`, neither of which exists on NuGet, so restore was
> silently floating to `17.8.36` with NU1603/NU1605 warnings (including a detected
> `Microsoft.VisualStudio.Telemetry` downgrade) instead of failing loudly — repinned to the real,
> exact 17.7 GA versions (`17.7.20` / `17.7.2196`), verified with a clean `dotnet restore` and a full
> `msbuild ... CreateVsixContainer` (real VS2022 install on this machine). Also corrected: Phase 3's
> `ICommentSelectionService` (not a public API — see §5), Phase 1's options cold-start race (see
> §3), Phase 4's restart claim (no documented restart API exists — see §6), a broken
> `changelog.mjs` invocation in two places (§2, §11), and `publish-vsix.ps1 -LocalOnly` never
> calling `fetch-node.ps1` (fixed in the script itself). A `changelog-sync` CI job
> (`ide-extensions.yml`) now guards `changelog.json` against the exact drift that let it fall 14
> versions behind (0.6.0→0.8.4) undetected.
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

## 0.5 Current state of the code (read before touching anything)

The entire VS2022 extension is these files under `ide-extensions/visual-studio/GuitkxVsix/`:

| File | Role |
|---|---|
| `GuitkxContentDefinition.cs` (23 lines) | MEF: `guitkx` content type (base `CodeRemoteContentDefinition` — REQUIRED for `ILanguageClient` attach) + `.guitkx` file-extension mapping. Nothing else. |
| `GuitkxLanguageClient.cs` (82 lines) | The `ILanguageClient`: `Name`, `ConfigurationSections = {"guitkx"}` (inert — no options UI exists), `InitializationOptions => new { enableEmbeddedAnalysis = true }` (hardcoded), `FilesToWatch => null`, `ShowNotificationOnInitializeFailed = true`. `ActivateAsync` launches `<extensionDir>\server\node.exe "<extensionDir>\server\server.js" --stdio` (PATH-`node` fallback), returns a `Connection` over the process's stdio streams. `OnServerInitializedAsync` is a no-op. |
| `guitkx.pkgdef` | `[$RootKey$\TextMate\Repositories] "ReactiveUIGuitkx"="$PackageFolder$\Syntaxes"` — TextMate grammar registration. **Audited/load-bearing; do not clobber.** |
| `Syntaxes/guitkx.tmLanguage.json` | Byte-identical copy of `grammar/guitkx.tmLanguage.json`. |
| `GuitkxVsix.csproj` | Legacy VSIX project, net472, `GeneratePkgDefFile=false` (static pkgdef ships instead), bundles `server\**\*` into the VSIX. Packages (fixed 2026-07-05 — see note below): `Microsoft.VisualStudio.LanguageServer.Client` 17.7.20, `Microsoft.VisualStudio.SDK` 17.7.37357, `Microsoft.VSSDK.BuildTools` 17.7.2196. |
| `source.extension.vsixmanifest` | Identity `GuitkxVsix.ReactiveUITK` v0.5.5, Publisher `Yaniv Kalfa` (mismatch — see P0), target `Microsoft.VisualStudio.Community [17.0,18.0)` amd64. |
| `publishManifest.json`, `overview-template.md` → `overview.md`, `CHANGELOG.md` | Marketplace metadata. `overview.md`/`CHANGELOG.md` are **generated** from `ide-extensions/changelog.json` by `ide-extensions/scripts/changelog.mjs` — never hand-edit. |
| `fetch-node.ps1` | Downloads the pinned Windows x64 Node (20.18.0) → `server\node.exe`. Idempotent. |

**The server's initializationOptions contract** (`lsp-server/src/server.ts:70-84`) — this is everything
the client can configure at init; anything else requires a server change:

```ts
let embeddedReflow  = true;   // opts.embeddedReflow  ?? opts.useGdformat        (legacy alias)
let embeddedEnabled = true;   // opts.enableEmbeddedAnalysis ?? opts.enableGodotProxy (legacy alias)
canWatchFiles = !!params.capabilities.workspace?.didChangeWatchedFiles?.dynamicRegistration;
```

There is **no `onDidChangeConfiguration` handler** anywhere in the server — every option change
requires a server restart to apply, in both editors. The server also reads `project.godot` from the
workspace root at init (autoload resolution) and scans the workspace for `.guitkx`/`.gd`; when the
client cannot register file watchers (VS2022 can't), it starts its own recursive `fs.watch` fallback
— win32/darwin only, which is fine because VS2022 is Windows-only.

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
2. Add changelog entries for the inherited 0.6.0–0.8.6 server features with:
   `node ide-extensions/scripts/changelog.mjs add --scope shared --message "..." --vs2022 X.Y.Z`
   (repeat per version, or fold into one entry — see the tool's own `--help` output; the previous
   revision of this plan had the command's flags wrong: it is `--scope`/`--message`, not `--ide`/`-m`).
   The changelog is the single source of truth; `overview.md`/`CHANGELOG.md` regenerate via `extract`.
   CI (`changelog-sync` in `ide-extensions.yml`, added 2026-07-05) now fails the build if a committed
   `CHANGELOG.md` drifts from `changelog.json` — this is the guard that would have caught
   `changelog.json` silently falling 14 versions behind a hand-edited `vscode/CHANGELOG.md`
   (0.6.0→0.8.4), which is what actually happened; run `node ide-extensions/scripts/changelog.mjs
   verify` locally before pushing.
3. Fix the **publisher mismatch**: manifest `Publisher="Yaniv Kalfa"` vs `publishManifest.json`
   `"publisher": "ReactiveUITK"`. The manifest Publisher is a display string; align it to the
   marketplace publisher (`ReactiveUITK`) so the listing and the installed-extension dialog agree.
4. Release via the existing `publish.yml` → `publish-vs2022` job (already verifies the VSIX
   contains `server/server.js` + `server/node.exe`, publishes with VsixPublisher, tags
   `vs2022-v<version>`).
5. **Verification checklist V1** (manual, in a VS2022 instance with a Godot project open):
   - [ ] All of rows 1–8, 12 behave identically to VS Code on the same files.
   - [ ] **Code actions**: verify the lightbulb surfaces analyzer quick-fixes — this one has solid,
         long-standing support (LSP code actions have been wired into the VS lightbulb since 15.8,
         2018), so treat a failure here as a real bug, not an environment gap.
   - [ ] **Semantic tokens / inlay hints — budget these as a stretch, not a core P0 deliverable.**
         Web research (2026-07-05) found no Microsoft documentation confirming the third-party
         `ILanguageClient` MEF extensibility surface renders `textDocument/semanticTokens/full` or
         `textDocument/inlayHint` at all — the official LSP feature-support table
         (learn.microsoft.com/.../adding-an-lsp-extension) doesn't list either as a row, supported or
         not, and the only concrete inlay-hint milestone found (VS 17.12, first-party languages only)
         postdates this project's pinned client by five feature releases. If neither renders after
         verifying, that's the expected outcome given the evidence, not a bug to chase — log it in §8
         Risks and fall back to TextMate-only colouring; do NOT hand-roll a classifier in this phase.
   - [ ] Diagnostics dimming (`DiagnosticTag.Unnecessary`) renders (unreachable-after-return).
6. Also close the **VS Code-side packaging question** found during inventory: the npm `package`
   script runs `vsce package` *without* `--no-dependencies`, while `publish-extension.ps1` uses
   `--no-dependencies`. Since the client depends on `vscode-languageclient` at runtime and there is
   no bundler, confirm the published VSIX contains `node_modules/vscode-languageclient`; align the
   two paths (either bundle with esbuild or drop the flag).

**Files touched:** `source.extension.vsixmanifest`, `changelog.json` (via script), possibly
`vscode/package.json`/`publish-extension.ps1` (item 6). No C#.

## 3. Phase 1 — Options page + initialization options (bucket B2/B3) — **DONE 2026-07-05**

**Outcome:** rows 13, 14, 23. The three VS Code settings get a real VS surface, and what the
server is told is user-controlled. All four items below are implemented and build clean
(`msbuild ... CreateVsixContainer`, VSIX contents inspected); manual V-checklist verification in a
real VS2022 Experimental Instance (options page renders/persists, server actually receives the
options) is still outstanding — nothing here has been driven interactively yet.

1. **DONE (2026-07-05), empirically verified.** Introduced an `AsyncPackage` (`GuitkxPackage.cs`)
   with `[PackageRegistration]`/`[ProvideOptionPage]`/`[ProvideAutoLoad]` (both `NoSolution` and
   `SolutionExists` UI contexts, background load). Flipped `GeneratePkgDefFile` from `false` to
   `true` — the `false` setting (with its load-bearing-sounding comment) predates any real package
   existing; with a real `[PackageRegistration]` type now in the project, `false` silently produced
   **no pkgdef at all** for it (compiled, never registered — confirmed by inspecting the built VSIX
   before flipping the flag). After flipping it: `CreateVsixContainer` auto-generates
   `GuitkxVsix.pkgdef` (verified content: correct `Packages`/`AutoLoadPackages` ×2/`ToolsOptionsPages`
   registry keys, deterministic GUID for the options page) and bundles it into the VSIX
   **automatically, alongside the static `guitkx.pkgdef`, with no `source.extension.vsixmanifest`
   edit needed** — the anticipated "merge, don't clobber" manifest surgery wasn't necessary in
   practice; both pkgdefs coexist (disjoint registry paths). Verified via `unzip -l`/`unzip -p` on
   the built `.vsix`, not just a successful build. (Build/restore gotcha hit along the way: run
   `msbuild -t:Restore` as its own invocation before `-t:Build` on a clean `obj/` — combining
   `-t:Restore,Build,CreateVsixContainer` in one call evaluates the project before restore produces
   the NuGet-imported targets that define `CreateVsixContainer`, failing with MSB4057.)
2. **DONE (2026-07-05), builds clean.** `DialogPage`-based options: **Tools → Options → GUITKX**:
   - `Enable embedded GDScript analysis` (default true) → init option `enableEmbeddedAnalysis`.
   - `Use gdformat for embedded reflow` (default true) → init option `useGdformat`.
   - `Analyze plain .gd files` (default true) → gates Phase 2's document coverage.

   Sketch (the standard VSSDK shape — options persist in the registry automatically):
   ```csharp
   public sealed class GuitkxOptionsPage : DialogPage
   {
       [Category("Language server"), DisplayName("Embedded GDScript analysis"),
        Description("Type-aware completion/hover/definition inside {expr} and setup code.")]
       public bool EnableEmbeddedAnalysis { get; set; } = true;

       [Category("Language server"), DisplayName("Use gdformat for embedded reflow")]
       public bool UseGdformat { get; set; } = true;

       [Category("Language server"), DisplayName("Analyze plain .gd files")]
       public bool EnableGdscriptAnalysis { get; set; } = true;
   }
   // On GuitkxPackage: [ProvideOptionPage(typeof(GuitkxOptionsPage), "GUITKX", "Language Server", 0, 0, true)]
   ```
   **Reading options from the MEF client is a real cold-start race, not a detail to hand-wave.**
   `ILanguageClient.ActivateAsync` can fire before `GuitkxPackage` is sited — packages load lazily
   and are not coordinated with MEF content-type activation at all (confirmed: Microsoft Q&A states
   there is no documented/supported way to force package-before-client ordering). Reading options via
   `AsyncPackage.GetGlobalService`/`ServiceProvider.GlobalProvider` therefore silently falls back to
   hardcoded defaults on a fresh VS start whenever a `.guitkx`-associated file is among the first
   things opened — the exact failure mode a user would never be able to explain.

   **DONE (2026-07-05), builds clean — implemented as `GuitkxSettings.cs`.** Don't route the read
   through the package instance at all. `SVsSettingsManager`
   (`Microsoft.VisualStudio.Settings.WritableSettingsStore`) is a core shell service Visual Studio
   itself proffers — in practice, reached via `new ShellSettingsManager(serviceProvider)
   .GetWritableSettingsStore(SettingsScope.UserSettings)` (both `GuitkxOptionsPage` and
   `GuitkxLanguageClient` pass `ServiceProvider.GlobalProvider`), regardless of whether `GuitkxPackage`
   has loaded. `GuitkxOptionsPage`'s persistence is overridden to
   write through a `WritableSettingsStore` under an explicit named collection (e.g. `"GUITKX\Options"`)
   instead of relying on `DialogPage`'s reflection-derived default registry path, and have
   `ActivateAsync` read that *same* collection directly — this decouples the read path from package
   sitedness by construction, not by luck. (The "read via automation" alternative,
   `dte.get_Properties(category, page)`, is a red herring: Microsoft's own docs say automation
   property access forces the owning package to load to resolve the value, reintroducing the exact
   synchronous load this is meant to avoid.) `ActivateAsync`'s thread affinity is undocumented either
   way (Microsoft's own sample opens it with `await Task.Yield();` as a defensive idiom, not proof of
   a guaranteed background thread) — settings-store reads are free-threaded and safe without
   switching, but never assume the UI thread is or isn't already current for anything else in there.
3. **DONE (2026-07-05), builds clean.** `GuitkxLanguageClient.InitializationOptions` now builds
   `{ enableEmbeddedAnalysis, useGdformat }` dynamically from `GuitkxSettings.Read(...)`, replacing
   the hardcoded anonymous object. (`EnableGdscriptAnalysis` is persisted but not yet sent as an init
   option — VS Code doesn't send it either; it's a client-side document-selector gate, wired up in
   Phase 2 once the `.gd` content type exists to gate.)
4. **DONE (2026-07-05), builds clean.** **Config-change semantics:** the shared server has **no**
   `onDidChangeConfiguration` handler (VS Code has the same restart requirement). `ConfigurationSections`
   is now `null` (was the inert `new[] { "guitkx" }` — advertising a section VS would dutifully notify
   on, into a handler that doesn't exist, is worse than admitting there's no live sync). On option
   change, `GuitkxOptionsPage.OnApply` shows a modal message box: "Reload the solution (or restart
   Visual Studio)... A restart command is planned" — to be replaced by a lighter `IVsInfoBar` +
   real restart once Phase 4 lands.
   - `plans/FINAL_AUDIT_GODOT.md` G-12 independently found the same gap and proposes the real fix —
     implement `workspace/didChangeConfiguration` in `lsp-server/src/server.ts` — which would give
     BOTH editors live config reload. **Deliberately not done here**: it changes shared `server.ts`
     runtime behavior that VS Code depends on today, and this campaign is scoped to leave the VS
     Code extension's behavior untouched. Track G-12 as a separate follow-up campaign, not folded
     into this one.

**Files:** new `GuitkxPackage.cs`, new `GuitkxOptionsPage.cs`, new `GuitkxSettings.cs`, edit
`GuitkxLanguageClient.cs`, `.csproj` (`GeneratePkgDefFile` flipped to `true` + 3 new `<Compile>`
items). `source.extension.vsixmanifest` needed **no** change — the generated `GuitkxVsix.pkgdef`
bundles in automatically alongside the static `guitkx.pkgdef`, verified.

**Acceptance:** toggling each option + restart changes observable behavior (embedded completion
disappears when off; gdformat reflow stops when off).

## 4. Phase 2 — Plain `.gd` language service (bucket B2; biggest single gap) — **mostly DONE 2026-07-05**

**Outcome:** row 15 (and verify row 16). The server's entire `.gd` surface — diagnostics,
completion, hover, navigation, project-wide rename, formatting, semantic highlighting, inlay
hints, code actions, symbols — reaches VS users, as it reached VS Code users in 0.3.0.

1. **DONE, builds clean.** New content type in `GuitkxContentDefinition.cs` — `gdscript` /
   `.gd`, exactly as sketched.
2. **DONE, builds clean.** The same `[Export(typeof(ILanguageClient))] GuitkxLanguageClient` now
   carries both `[ContentType("guitkx")]` and `[ContentType("gdscript")]` — one client, one server
   process, no second connection spawned.
3. **NOT done — deliberately deferred, unlike the sketch above.** The gate is **not wired up**:
   `.gd` analysis is unconditional today regardless of the "Analyze plain .gd files" setting. The
   server-side `enableGdscriptAnalysis` init-option check this needs touches
   `lsp-server/src/server.ts`, which VS Code's client also depends on — out of scope for this
   campaign per the same reasoning as the Phase 1 G-12 deferral (this campaign leaves VS Code's
   behavior untouched, even for additive/backward-compatible changes). The option is persisted
   (`GuitkxOptionsPage`/`GuitkxSettings` already carry it, ready for Phase 2's real gate) but its
   description now says plainly that it isn't enforced yet, and the "coexistence escape hatch"
   framing from item 5 below doesn't apply until it is.
4. **Decided: (b), semantic tokens only** — no `gdscript.tmLanguage.json` was added in this
   campaign (kept scope to the content-type/client wiring the "biggest single gap" line item is
   actually about); plain `.gd` colouring relies on the analyzer's semantic tokens until someone
   picks up (a) separately.
5. **Docs note only, not a real gate today** (see item 3): the options page's tooltip states that
   turning "Analyze plain .gd files" off does not currently disable anything, so it is NOT yet a
   working coexistence escape hatch — correcting what the original sketch implied.
6. **Verification checklist V2 — outstanding, needs a real VS2022 instance:**
   - [ ] `.gd` file: diagnostics, completion, hover, goto, rename across files, format document.
   - [ ] Absence-based `UNDEFINED_*` diagnostics arm after startup (server `fs.watch` fallback is
         win32 — VS is win32-only, so this should work; verify `setWorkspaceComplete` fires by
         typo-ing a function name and seeing the diagnostic).
   - [ ] guitkx ↔ gd cross-file: renaming a component updates `.guitkx` usages AND generated
         sibling awareness still holds.
   - [ ] Confirm `.gd` files opened in the same session as `.guitkx` files really do share one
         server process (no duplicate Node child spawned) — the design intent of item 2, unverified
         interactively.

**Files:** `GuitkxContentDefinition.cs`, `GuitkxLanguageClient.cs`. Not touched (deliberately):
`Syntaxes/gdscript.tmLanguage.json` (decided against for this campaign), `lsp-server/src/server.ts`
(the `enableGdscriptAnalysis` gate — deferred, same reasoning as G-12).

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
4. **Comment toggle (row 20)** — `ICommentSelectionService` **is not a real option**: it's a
   Roslyn `EditorFeatures`-internal language-service abstraction (consumed by Roslyn's own
   comment/uncomment command handler for languages plugged into Roslyn's workspace model), not a
   public VS SDK extensibility contract a MEF content type outside Roslyn can implement. Two real
   options, either is fine here since this language is `#`-line-comment-only:
   - **(a, likely lower effort)** A declarative **Language Configuration** file
     (`learn.microsoft.com/.../language-configuration`, VS2022-current — the VS Code-compatible
     `*language-configuration.json`), registered against the `guitkx` content type via
     `guitkx.pkgdef`'s `TextMate\LanguageConfiguration\ContentTypeMapping`: `{ "comments": {
     "lineComment": "#" } }` and Ctrl+K,Ctrl+C / uncomment/toggle work with zero handler code.
     Working sample: `github.com/microsoft/VSExtensibility` → "Language Configuration Setup Example".
   - **(b)** Export `ICommandHandler<ToggleLineCommentCommandArgs>` (or
     `CommentSelectionCommandArgs`/`UncommentSelectionCommandArgs`) from
     `Microsoft.VisualStudio.Text.Editor.Commanding.Commands`, `[ContentType("guitkx")]` — the
     documented MEF pattern from "Walkthrough: Using a shortcut key with an editor extension". Gives
     more control (e.g. custom logic around mixed indentation) if (a) turns out insufficient.
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
2. Restart mechanics — **there is no Microsoft-documented, supported restart API for a legacy MEF
   `ILanguageClient`** (verified 2026-07-05: the official "Adding an LSP extension" walkthrough and
   the Microsoft sample only cover one-shot `ActivateAsync`/`StartAsync`; `ILanguageClientBroker`'s
   entire public surface is `LoadAsync(metadata, client)` — no `Stop`/`Restart`/`Reload`). Investigate
   in order, budgeting for genuine API risk at every step (this is the correct framing, not "pick a,
   done"):
   a. Call `ILanguageClientBroker.LoadAsync()` again — the workaround described in a Microsoft Q&A
      thread, **with known reliability caveats**: reported to work only once per client instance
      unless the old one is disposed first, and a related Roslyn issue documents a race
      (`InvalidOperationException: The language server has not yet shutdown`) on repeated attempts.
      Treat as first-choice-with-caveats, not a guaranteed contract — wrap in a retry-with-backoff
      loop, and expect to dispose/recreate the client instance between attempts.
   b. else: own-the-connection restart — keep the `Connection`/process handle from
      `ActivateAsync`, dispose + signal `StopAsync`/re-activate;
   c. worst case: kill the `node.exe` child and rely on VS's automatic single-restart of crashed
      servers, with the command as UX sugar; or simply tell the user to reload the solution/restart
      VS, which may be the more honest answer given how thin (a) and (b) are in practice.
   Record which path shipped in the code comment — this is the piece with real API risk. (A newer,
   parallel extensibility model — `Microsoft.VisualStudio.Extensibility`'s `LanguageServerProvider`,
   VS 17.9+ — does expose a real `Enabled` flag that stops/restarts a server, but adopting it means
   migrating off `Microsoft.VisualStudio.LanguageServer.Client` entirely; out of scope for this plan,
   noted here as the more official direction if the workarounds above prove too unreliable in field
   use.)
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
| R1 | VS LSP client likely does NOT render semantic tokens / inlay hints via the third-party `ILanguageClient` surface at all (2026-07-05 research found no Microsoft documentation confirming either, at any client version) | Phase 0 verification, budgeted as a likely-fails stretch, not a blocker; accept TextMate-only colouring (document in README) — do NOT hand-roll classifiers. `codeAction` (the lightbulb) is solid since VS 15.8 and should NOT be lumped in with this risk. |
| R2 | **Confirmed, not just suspected:** there is no public/documented restart API for a legacy MEF `ILanguageClient` (`ILanguageClientBroker`'s only member is `LoadAsync`) | Phase 4 options a→c, with (a) treated as a fragile workaround (works once; needs dispose+retry; a Roslyn issue documents a shutdown race) rather than a guaranteed contract; worst case the command degrades to guidance + auto-restart |
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

## 10. Dev environment & inner loop (for the implementing dev)

**Prerequisites:** VS2022 (Community is fine) with the **"Visual Studio extension development"**
workload; Node.js 20.x + npm; a Godot 4.4+ project to test against — the RG repo itself is the
best workspace (it has `project.godot` + `examples/demos/**.guitkx` + the addon `.gd` libraries the
server loads for cross-file resolution).

**Build the server + VSIX from scratch** (PowerShell, repo root = `ide-extensions/`):
```powershell
cd lsp-server;  npm ci; npm run build            # tsc -> out/
cd ..\vscode;   npm ci; node scripts\bundle-server.js   # server + THIS machine's analyzer .node -> vscode\server
Copy-Item -Recurse -Force ..\vscode\server ..\visual-studio\GuitkxVsix\server
powershell -ExecutionPolicy Bypass -File ..\visual-studio\GuitkxVsix\fetch-node.ps1
# open GuitkxVsix.csproj in VS2022 and Build, or:
msbuild ..\visual-studio\GuitkxVsix\GuitkxVsix.csproj -t:Restore,Build,CreateVsixContainer -p:Configuration=Release
```
`ide-extensions/scripts/publish-vsix.ps1 -LocalOnly` does all of the above + `overview.md`
generation in one shot (finds MSBuild via vswhere) — **fixed 2026-07-05**: the script previously
never called `fetch-node.ps1`, so a local-only build silently produced a VSIX missing the bundled
`server/node.exe` (unlike the CI `publish-vs2022` job, which does call it and explicitly verifies
the bundled `node.exe` is present). It now calls `fetch-node.ps1` in the same place CI does.

**Debug loop:** F5 on the VSIX project launches the **VS Experimental Instance**
(`/rootSuffix Exp`); open the RG repo folder/solution there and open a `.guitkx` from
`examples/demos/`. The LSP client's log appears in the experimental instance under
**Output → "GUITKX Language Server"**; `[lsp-client]` messages and server stderr land there. To see
raw LSP traffic, set the VS option *Text Editor → Advanced → LSP trace* (or attach to the
`node.exe` child with `--inspect` by editing `ActivateAsync` locally — remove before commit).
Server-side `console.error` writes are visible in that same pane.

**Iterating on the server only:** rebuild `lsp-server` (`npm run build`), re-run
`bundle-server.js`, re-copy to `GuitkxVsix\server`, restart the experimental instance (or the
Phase-4 restart command once it exists). The server under `GuitkxVsix\server` is a **copy** — editing
`lsp-server/src` does nothing until re-bundled; forgetting this is the classic wasted hour.

**Manual test corpus:** `examples/demos/counter/counter.guitkx` (hooks + events),
`examples/demos/controls/controls.guitkx` (attribute breadth), plus a scratch file for the V2 `.gd`
checks. A ready-made embedded-intelligence probe:
```
component Probe {
  var b := Button.new()
  var s = useState(0)
  return (
    <VBox>
      <Label text={ b. } />        // typed completion on `b.` — Button members expected
      <Button text="x" onClick={ func(): s[1].call(s[0] + 1) } />
    </VBox>
  )
}
```

## 11. Repo working agreements (non-negotiable)

- **Branch flow:** base on `origin/dev`, PR into `dev` (title becomes the squash title), then dev
  is fast-forwarded to master by the maintainer (`git push origin origin/dev:master`). Never push
  master directly; never rebase shared branches.
- **Never weaken a check to get green** — CI gates (VSIX content verification, tag gating,
  lsp-server tests `npm test` + `node scripts/smoke.js`) are load-bearing. If one fails, the code
  is wrong, not the gate.
- **Releases are the Publish button** (`publish.yml`, `workflow_dispatch`): the `publish-vs2022`
  job is version-gated on the `vs2022-v<manifest version>` tag — bump the manifest or the job
  skips. It bundles/builds/verifies/publishes/tags on its own; there is no manual VsixPublisher
  step in the happy path.
- **Changelog:** `node ide-extensions/scripts/changelog.mjs add --scope shared --message "..."
  --vs2022 X.Y.Z` — the JSON is the single source; generated `CHANGELOG.md`/`overview.md` must never
  be edited by hand. Run `node ide-extensions/scripts/changelog.mjs verify` before pushing — CI
  (`changelog-sync`) runs it too and fails the build on drift.
- **Server changes serve three clients** (VS Code, VS2022, and the in-Godot editor mirrors its
  contracts): anything touching `lsp-server/src` needs its tests updated
  (`lsp-server/npm test`) and a sanity pass in VS Code, not just VS.
- **Git authorship is the maintainer's** — no `Co-Authored-By` trailers; commit/push only what the
  task requires.
