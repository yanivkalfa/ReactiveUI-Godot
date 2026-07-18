# Extension versioning & release process

Mirrors ReactiveUIToolKit's release model, retargeted to the TypeScript language server + Open VSX.

## Sources of version truth

| Extension | Version lives in | Release tag |
|---|---|---|
| VS Code | `ide-extensions/vscode/package.json` → `version` | `vscode-v<version>` |
| VS2022 | `ide-extensions/visual-studio/GuitkxVsix/source.extension.vsixmanifest` → `Identity/@Version` | `vs2022-v<version>` |

The changelog source of truth is **`ide-extensions/changelog.json`**; per-extension `CHANGELOG.md` and the
VS2022 `overview.md` are **generated** from it (never hand-edited) by `scripts/changelog.mjs`.

## Cutting a release

1. **Add a changelog entry** (prefer `--message-file` for any non-ASCII content):
   ```bash
   node ide-extensions/scripts/changelog.mjs add --scope shared \
     --message "Feature: …" --vscode 0.2.0 --vs2022 0.2.0
   ```
   Use `--scope vscode` / `--scope vs2022` for IDE-specific notes.
2. **Bump the version** in the extension manifest(s) to match the changelog entry.
3. **Publish** — either:
   - **CI (preferred):** run the *Publish Extensions* workflow (`workflow_dispatch`). Each job reads its
     extension's version, **skips if the `vscode-v*`/`vs2022-v*` tag already exists**, publishes, then tags.
   - **Local:** `pwsh ide-extensions/scripts/publish-extension.ps1 -BumpVersion -ChangelogEntry "…"` (VS Code,
     to VS Marketplace + Open VSX) and `pwsh ide-extensions/scripts/publish-vsix.ps1` (VS2022).

## Idempotency

Re-running the workflow on an unchanged version is a no-op (the version-already-tagged check short-circuits
each job). To re-publish, bump the version first.

## Secrets

See the *Publishing* section of [README.md](README.md) for the required secret matrix
(`VSCE_PAT`, `OVSX_TOKEN`, `VS_MARKETPLACE_TOKEN`).
