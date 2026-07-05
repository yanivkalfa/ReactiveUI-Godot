# GUITKX for Visual Studio 2022

VS2022 extension for `.guitkx` (ReactiveUI for Godot): TextMate colouring via `.pkgdef` +
`ILanguageClient` driving the same shared language server as the VS Code extension
(`ide-extensions/lsp-server`), bundled self-contained with a pinned Node runtime
(`GuitkxVsix/fetch-node.ps1`) so end users need nothing on PATH.

- **Marketplace page**: `GuitkxVsix/overview.md` — **generated** from
  `ide-extensions/changelog.json` by `scripts/changelog.mjs`; don't hand-edit it.
- **Build**: see the *VS2022 extension* section of [../README.md](../README.md)
  (build the lsp-server, bundle it via the vscode `bundle-server.js`, copy into
  `GuitkxVsix/server`, fetch Node, then `msbuild -t:CreateVsixContainer`).
- **Publishing**: automated by `.github/workflows/publish.yml` (`publish-vs2022` job),
  version-gated on the `vs2022-v<version>` tag.

**Status**: published at 0.5.5; behind the VS Code extension (0.8.x). The feature-parity
gap and the plan to close it live in
[`plans/VSCODE_VS2022_PARITY_PLAN.md`](../../plans/VSCODE_VS2022_PARITY_PLAN.md).
