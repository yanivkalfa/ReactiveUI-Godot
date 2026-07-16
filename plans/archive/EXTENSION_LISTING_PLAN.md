# Extension marketplace-listing overhaul — GODOT leg (family campaign, owner directive 2026-07-16)

> **The problem (owner-reported):** all six family extensions appear on the VS Marketplace
> publisher page as bare acronyms — `GUITKX`, `UETKX`, `UITKX`, each twice (VS Code + VS2022) —
> indistinguishable from one another.
>
> **The fix (all three repos, same canonical scheme):** distinguishable display names, and every
> extension page structured **Title → Description → Features → Requirements → Changelog**.
> Sibling plans: `ReactiveUI-Unreal/plans/EXTENSION_LISTING_PLAN.md` (the reference
> implementation — its §1 defines the family scheme) and
> `UnityComponents/Assets/ReactiveUIToolKit/Plans~/EXTENSION_LISTING_PLAN.md`.
>
> **Execution notes:** one branch off the working baseline, follow THIS repo's
> `release-process` skill for all release mechanics (it gained a "Marketplace listing surfaces"
> section in this campaign). The owner merges + presses Publish.

## §0 Where every marketplace-visible string lives (researched 2026-07-16)

| Surface | VS Code | VS2022 |
|---|---|---|
| List/page title | `ide-extensions/vscode/package.json` → `displayName` (currently `"GUITKX"`, v0.10.0) | `ide-extensions/visual-studio/GuitkxVsix/source.extension.vsixmanifest` → `<DisplayName>` (line 5, currently `GUITKX`) |
| Short description | package.json `description` (already rich — names Godot; keep) | vsixmanifest `<Description>` (keep) |
| Page body | `ide-extensions/vscode/README.md` (exists, rich content, but H1 is `# GUITKX — ReactiveUI for Godot tooling` and there is NO Changelog section) | `GuitkxVsix/overview.md`, generated at publish time by `changelog.mjs extract-overview` from `GuitkxVsix/overview-template.md` (see publish.yml line ~513) |
| Changelog tab/section | `vscode/CHANGELOG.md` (generated from `ide-extensions/changelog.json`) is the marketplace tab; the body gains a `## Changelog` section via this plan | appended by extract-overview |

**Godot-specific caution:** `publish-vscode` in `.github/workflows/publish.yml` is a
**6-platform matrix** (the bundled gdscript-analyzer is a native napi addon — one
platform-specific .vsix per target). Any new README-generation step goes ONCE per matrix leg,
BEFORE its `vsce package --target` step. Open VSX publishing rides the same legs.

## §1 Canonical strings (family-wide — defined in the Unreal plan §1, do not improvise)

| Field | New value |
|---|---|
| package.json `displayName` | `GUITKX (Godot - VS Code)` |
| vsixmanifest `<DisplayName>` | `GUITKX (Godot - VS2022)` |
| VS Code body H1 | `# Reactive UI - Godot - VS Code (GUITKX)` |
| VS2022 body H1 (overview-template) | `# Reactive UI - Godot - VS2022 (GUITKX)` |

Body structure (both templates, this exact order): H1 → description paragraph(s) →
`## Features` → `## Requirements` → (Changelog appended by the script — the template file
ENDS after Requirements).

**Content rule: PRESERVE this repo's existing prose.** The current README's `.guitkx` markup
section AND the headless-GDScript language-service section both survive — they become
bold-lead bullet groups under `## Features`. Do not drop the gdscript-analyzer / offline
story; it is the extension's differentiator.

## §2 File changes

1. `ide-extensions/vscode/package.json` — `displayName` per §1.
2. `ide-extensions/visual-studio/GuitkxVsix/source.extension.vsixmanifest` — `<DisplayName>`
   per §1.
3. **NEW `ide-extensions/vscode/readme-template.md`** — the current README.md content,
   restructured per §1 (H1, Description, Features, Requirements; STOPS after Requirements).
4. `GuitkxVsix/overview-template.md` — H1 per §1; restructure to the same section order if it
   deviates; content preserved.
5. **README.md becomes GENERATED + COMMITTED** (template + changelog):
   ```bash
   node ide-extensions/scripts/changelog.mjs extract-overview --ide vscode \
     --template ide-extensions/vscode/readme-template.md \
     --out ide-extensions/vscode/README.md
   ```
6. `.vscodeignore` — exclude `readme-template.md` from the .vsix (README.md stays included).

## §3 Script + CI wiring

1. `ide-extensions/scripts/changelog.mjs`:
   - usage text for extract-overview → `--ide <vscode|vs2022>` (the command already works for
     any ide — it filters changelog.json entries by `versions[ide]`).
   - **extend `verify`**: when `ide-extensions/vscode/readme-template.md` exists, compose
     template + changelog exactly like `cmdExtractOverview` and byte-compare against the
     committed README.md; mismatch fails with the regeneration command. (Generated-and-committed
     files get drift gates — the family scar.)
2. `.github/workflows/publish.yml`, `publish-vscode` matrix job — add one step before
   `vsce package`:
   ```yaml
   - name: Generate README.md from centralized changelog
     run: node ide-extensions/scripts/changelog.mjs extract-overview --ide vscode --template ide-extensions/vscode/readme-template.md --out ide-extensions/vscode/README.md
   ```
   (Guard it with the same skip/idempotency condition the leg's other steps use.)

## §4 Release mechanics (per THIS repo's release-process skill)

1. Bumps (version table is in the skill §0): `vscode/package.json` 0.10.0 → **0.10.1**;
   `GuitkxVsix` vsixmanifest `Identity Version` → **0.10.1**. Respect the skill's lockstep
   note (vsixmanifest tracks the lsp-server version — if that rule requires it, bump
   `lsp-server/package.json` to 0.10.1 too; verify against the skill text, don't guess).
2. Lane B (tooling changelog) via `ide-extensions/scripts/changelog.mjs` — one `add` per
   change, `--message-file`, then `extract` for EVERY named target, then `verify`:
   - bullet 1 (shared): "Marketplace listing overhaul: distinguishable display names —
     `GUITKX (Godot - VS Code)` / `GUITKX (Godot - VS2022)` — and a structured page body
     (Title / Description / Features / Requirements / Changelog) on both marketplaces + Open VSX."
   - bullet 2 (vscode scope): "README.md is now generated from the centralized changelog —
     the page body carries the changelog inline."
3. Run this repo's verification gates (release-process skill §; includes the byte-identical
   changelog mirror tripwire in `tests/guitkx_editor_test.gd` — untouched here, but run it).
4. PR → owner merges → fast-forward → owner presses **Publish** (only extension legs fire;
   the runtime/editor addons are untouched, their tags exist).

## §5 What does NOT change

- Runtime addon (`reactive_ui`) + editor addon versions — untouched.
- publisher (`ReactiveUITK`), extension ids (`guitkx`, `GuitkxVsix.ReactiveUITK`) — renaming
  ids orphans installs. Display strings only.
- The napi platform matrix, icons, categories, keywords.

## §6 Post-publish verification

- Publisher page rows read `GUITKX (Godot - VS Code)` / `GUITKX (Godot - VS2022)`.
- `items?itemName=ReactiveUITK.guitkx` body: §1 structure incl. Changelog; GDScript-service
  prose intact.
- Open VSX (`open-vsx.org/extension/ReactiveUITK/guitkx`) shows the same README.

## §7 Skill upkeep (part of this campaign)

Add a "Marketplace listing surfaces" section to `.claude/skills/release-process/SKILL.md`
mirroring the Unreal skill's new section (the §0 table above + the naming scheme + the
"listing-only changes still bump" rule + "edit the template, regenerate, commit both").
