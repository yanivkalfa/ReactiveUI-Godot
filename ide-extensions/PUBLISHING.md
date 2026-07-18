# Publishing the GUITKX IDE tooling

## VS Code (Marketplace + Open VSX)

The Godot crowd uses VS Code, VSCodium, and Cursor — publish to **both** the VS Code Marketplace and
**Open VSX** (VSCodium/Cursor/Theia source extensions from Open VSX).

```bash
cd ide-extensions/lsp-server && npm ci && npm run build      # build the server first
cd ../vscode && npm ci && npm run build
node scripts/bundle-server.js                                # copy server into ./server (self-contained .vsix)

# package
npx @vscode/vsce package --no-dependencies                   # -> guitkx-0.1.0.vsix

# publish to the VS Code Marketplace (needs a publisher + PAT: https://aka.ms/vscode-create-publisher)
npx @vscode/vsce publish --no-dependencies -p "$VSCE_PAT"

# publish to Open VSX (needs an open-vsx.org token)
npx ovsx publish guitkx-0.1.0.vsix -p "$OVSX_TOKEN"
```

`--no-dependencies` is used because the runtime dependency (the language server) is bundled into
`./server` by `bundle-server.js`, not resolved from `node_modules` at runtime.

## VS2022 (Marketplace VSIX)

Requires Windows + Visual Studio 2022 with the **Visual Studio extension development** workload
(`Microsoft.VSSDK.BuildTools`). `dotnet build` alone is not enough — the VSIX MSBuild targets ship
with that workload.

```powershell
# 1. build + bundle the Node server, then copy it next to the VSIX project
cd ide-extensions/lsp-server; npm ci; npm run build
Copy-Item -Recurse ide-extensions/vscode/server ide-extensions/visual-studio/GuitkxVsix/server  # or re-run bundle-server

# 2. build the VSIX (Release) — produces GuitkxVsix.vsix
msbuild ide-extensions/visual-studio/GuitkxVsix/GuitkxVsix.csproj /p:Configuration=Release

# 3. upload GuitkxVsix.vsix to the Visual Studio Marketplace (manage.visualstudio.com) or
#    publish with the VsixPublisher CLI.
```

The VSIX bundles the same Node language server under `server\` **plus a Node runtime**
(`fetch-node.ps1` — the client prefers the bundled `server\node.exe` and falls back to a PATH
`node` only if the bundle is missing), so end users need nothing installed.
Colorization comes from the TextMate grammar registered by `guitkx.pkgdef` (VS never colorizes over
LSP), so highlighting works even before the server connects.

## Versioning

Keep the three manifests in lockstep when bumping: `vscode/package.json`,
`visual-studio/GuitkxVsix/source.extension.vsixmanifest`, and `lsp-server/package.json`.
