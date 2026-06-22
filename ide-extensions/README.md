# GUITKX IDE tooling

Editor support for `.guitkx` — the JSX-like markup of **ReactiveUI for Godot**. Three layers, one
shared language server:

```
grammar/        TextMate grammar (guitkx.tmLanguage.json) + schema (guitkx-schema.json)
lsp-server/     TypeScript language server (stdio). Markup intelligence + a TCP proxy to Godot's LSP
vscode/         VS Code extension (grammar + language config + LSP client)
visual-studio/  VS2022 extension (TextMate grammar via .pkgdef + ILanguageClient -> same LSP server)
```

## How it works

`.guitkx` is two languages in one file: JSX-like **markup** and embedded **GDScript** (setup,
`{expr}`, `@if`/`@for` conditions). The tooling splits them:

- **Highlighting** — a TextMate grammar (`grammar/guitkx.tmLanguage.json`), self-contained
  (hand-rolled GDScript leaf rules, no dependency on the godot-tools grammar). Used by both VS Code
  and VS2022 (VS never drives coloring over LSP, so the grammar is required there too).
- **Markup intelligence** (tag / attribute / directive completion + hover) — answered locally by the
  language server from the schema (`grammar/guitkx-schema.json`, embedded in `lsp-server/src/schema.ts`).
- **Embedded-GDScript intelligence** (completion/hover inside `{expr}`/setup/conditions) — the server
  builds a synthetic `.gd` **virtual document** with a length-preserving **source map** (Volar's
  technique, hand-rolled), then **forwards** the request to **Godot's built-in GDScript language
  server** over TCP (engine default **port 6005**), and maps the result back. Requires the Godot
  editor to be running with the project open; degrades gracefully (markup features still work) when
  it is not.

The language server is **TypeScript** (not C#): the Godot port's compiler/parser is GDScript and the
embedded language is GDScript, so there is no C# language-lib to reuse — and VS Code (the primary
Godot audience) gets a zero-runtime Node server. VS2022 drives the same server over stdio.

## Formatter configuration (`guitkx.config.json`)

`.guitkx` is **tab-indented by default** (the embedded GDScript requires tabs, and the compiler emits
tabs). To override the formatter, drop a `guitkx.config.json` at or above the file being formatted
(Prettier-style walk-up — the first one found, walking up to the filesystem root, wins):

```json
{
  "formatter": {
    "printWidth": 100,
    "indentStyle": "tab",
    "indentSize": 4,
    "singleAttributePerLine": false,
    "insertSpaceBeforeSelfClose": true
  }
}
```

| Key | Default | Meaning |
|---|---|---|
| `printWidth` | `100` | Soft column limit; a tag's attribute list wraps when the single line would exceed it. |
| `indentStyle` | `"tab"` | `"tab"` or `"space"`. **Keep `"tab"`** unless you have a reason not to: GDScript + the compiler use tabs, and a `"space"` markup indent can mix with the embedded code's tabs. |
| `indentSize` | `4` | Spaces per level when `indentStyle` is `"space"` (ignored for tabs). |
| `singleAttributePerLine` | `false` | Force every attribute onto its own line. |
| `insertSpaceBeforeSelfClose` | `true` | Emit `<Foo />` (space before `/>`) vs `<Foo/>`. |

The analogue of ReactiveUIToolKit's `uitkx.config.json`. Unknown keys are ignored; a malformed file
falls back to the defaults. (No config file is needed — the defaults above apply when none is found.)

## Build & run

```bash
# language server
cd lsp-server && npm install && npm run build && node --test out/test/*.test.js && node scripts/smoke.js

# VS Code extension (dev: F5 in VS Code, or package a .vsix)
cd ../vscode && npm install && npm run build
node scripts/bundle-server.js          # copy the built server into ./server
npx --yes @vscode/vsce package         # -> guitkx.vsix ; also publishable to Open VSX via ovsx
```

`@vscode/vsce` / `ovsx` are NOT project dependencies (they're publishing tools that pull in a large
Azure/MSAL tree) — the scripts invoke them via `npx`, so a contributor's `npm install` stays small.

**VS2022 extension** (needs VS2022 + the "Visual Studio extension development" workload):

```powershell
cd lsp-server; npm install; npm run build; cd ..\vscode; npm install; node scripts/bundle-server.js
Copy-Item -Recurse -Force vscode\server visual-studio\GuitkxVsix\server
powershell -ExecutionPolicy Bypass -File visual-studio\GuitkxVsix\fetch-node.ps1   # bundles node.exe (~80 MB)
# then build the VSIX in VS2022 (or msbuild GuitkxVsix.csproj -t:CreateVsixContainer -p:Configuration=Release)
```

The VS2022 extension is **self-contained**: `fetch-node.ps1` drops a pinned Windows Node runtime into
`server\node.exe`, and `GuitkxLanguageClient` launches `server\node.exe server.js` — so **end users do
NOT need Node on PATH** (it falls back to a PATH `node` only if the bundle is somehow missing). This is
why the VS2022 `.vsix` is ~80 MB. (VS Code needs no bundled Node — it runs the server in its own host.)

Configure Godot's port in VS Code / VS2022 settings (`guitkx.godotLanguageServerPort`, default 6005) and
make sure Godot's language server is enabled (Editor Settings → Network → Language Server).

## Publishing

Releases are automated. The changelog source of truth is **`changelog.json`**; per-extension
`CHANGELOG.md` + the VS2022 `overview.md` are generated from it by `scripts/changelog.mjs`. See
[VERSIONING.md](VERSIONING.md) for the release process and [PUBLISHING.md](PUBLISHING.md) for manual steps.

- **CI:** `.github/workflows/publish-extensions.yml` (`workflow_dispatch`) — version-gated per extension
  (skips if the `vscode-v*` / `vs2022-v*` tag exists), publishes the VS Code extension to the **VS Marketplace**
  + **Open VSX**, and the VS2022 extension via **VsixPublisher**, then tags + uploads artifacts.
- **Local:** `scripts/publish-extension.ps1` (VS Code) and `scripts/publish-vsix.ps1` (VS2022).

**Secret matrix** (GitHub repo secrets / local `publisher-secrets.json` keys):

| Secret | `publisher-secrets.json` key | Target | How to get it |
|---|---|---|---|
| `VSCE_PAT` | `vscePatToken` | VS Code Marketplace | Azure DevOps PAT, *Marketplace → Manage* scope ([docs](https://aka.ms/vscode-create-publisher)) |
| `OVSX_TOKEN` | `ovsxToken` | Open VSX | open-vsx.org access token |
| `VS_MARKETPLACE_TOKEN` | `vsMarketplaceToken` | Visual Studio Marketplace | Azure DevOps PAT for the VS Marketplace |

`publisher-secrets.json` is git-ignored — never commit it.

## Status

| Layer | State |
|-------|-------|
| Grammar + schema | Done (valid JSON, adapted from the shipping Unity grammar) |
| Language server — markup completion/hover, structural diagnostics | Done + tested (`npm test`, `smoke.js`) |
| Language server — Godot GDScript proxy | **Verified live** — round-trips against a running Godot editor (`scripts/live-godot.js`, `live-full.js`) |
| VS Code extension | Builds; server bundles + serves over stdio (proven); packages to a self-contained `.vsix` |
| VS2022 extension | ILanguageClient + `.pkgdef` pattern; needs VS2022 + VSSDK to build/verify |
| Publishing + changelogs | Done — `changelog.json` + `changelog.mjs`, `publish-extensions.yml` (VS Marketplace + Open VSX + VsixPublisher), local publish scripts, version-gating + tagging |
