# Asset Store / Asset Library publishing — plan

**Status: RESEARCHED 2026-07-04 — awaiting user inputs (license, icon, accounts), repo prep staged.**

## 1. The venue landscape (verified 2026-07)

- **The new [Godot Asset Store](https://store.godotengine.org/) is live** and is the go-forward
  venue, fully integrated in **Godot 4.7** (exactly our tested floor). It uses Godot's shared
  account system, supports multiple download versions per asset, changelog pages, tags,
  reviews. Free assets only for now. **No publishing API/CLI yet** — versions are added through
  the publisher dashboard. ([announcement](https://godotengine.org/article/introducing-the-godot-asset-store/))
- **The classic [Asset Library](https://godotengine.org/asset-library/asset) is deprecated but
  running** (will eventually go read-only). It is still what Godot ≤4.6 editors browse in-app,
  its process is [fully documented](https://docs.godotengine.org/en/stable/community/asset_library/submitting_to_assetlib.html),
  and it has a maintained CI action ([godot-asset-lib](https://github.com/marketplace/actions/godot-asset-lib))
  that can push version/commit updates on release (moderated edits).
- **No automatic migration** between the two — separate accounts, separate listings.

**Decision: dual-publish.** New store = primary listing; classic AL = legacy reach + the only
automatable channel today. Both point at the same repo + release tag. When the new store ships
an API, add it to the pipeline and let the AL entry age out.

## 2. How each venue works

### Classic Asset Library (documented, automatable)
- Listing = metadata + a repo URL + a **download commit**; the download is the provider's
  archive of that commit — **`.gitattributes export-ignore` trims it** (staged, see §3), so
  installs contain only `addons/reactive_ui/` + LICENSE + README.
- Hard requirements: **LICENSE file in the repo** matching the declared license (OSI; MIT/BSD/
  GPL/Boost options), square **icon ≥128×128** served via `raw.githubusercontent.com`, plain-
  English description, working asset on the declared Godot version, `.gitignore` present.
- First submission: manual web form, human moderation (up to a few days). Updates: "edits"
  (new version string + new download commit), also moderated but fast — and postable from CI
  via the marketplace action (username/password secrets + asset id).

### New Asset Store (manual for now)
- Publisher account = your godotengine.org shared account. Create the asset once via the
  dashboard; each release adds a **version** (upload/point at the release) + changelog entry —
  ~2 minutes/release by hand until an API exists (tracked as a follow-up).

## 3. Repo prep (staged by me — no input needed)
- **`.gitattributes`** with `export-ignore` for everything that isn't the addon, LICENSE, or
  README — examples/, tests/, ide-extensions/, docs site, plans/, workflows. This shapes BOTH
  the AL download and any `git archive`-based zip.
- **`.asset-template.json.hb`** — the classic-AL edit payload (version + commit from the
  release event).
- **publish.yml `assetlib-update` job** — chained on `release-addon`, runs only when a NEW
  addon version was actually released. A job rather than an `on: release` workflow because
  the release is created with `GITHUB_TOKEN`, whose events never trigger other workflows.
  **Inert until** the repo variable `ASSETLIB_ASSET_ID` and secrets
  `ASSETLIB_USERNAME`/`ASSETLIB_PASSWORD` exist; materializes `.asset-template.json.hb` with
  the tag + commit, posts the AL edit, prints the new-store manual version-add reminder.
- README top section doubles as listing copy (both venues render repo README-ish content).

## 4. What I need from the user
1. **License** — the repo has NO LICENSE file and both venues require one. Recommendation:
   MIT, copyright "Yaniv Kalfa". Say the word (or pick another) and I commit it.
2. **Icon** — a square PNG ≥128×128 committed to the repo. Provide one, or approve me deriving
   a clean icon from the docs site's logo.
3. **Accounts** — (a) godotengine.org shared account → log into store.godotengine.org once so
   the publisher profile exists; (b) classic Asset Library account (separate system!) at
   godotengine.org/asset-library.
4. **First submissions** (account-bound, one-time): I hand you a filled field sheet (name,
   description, category `Addons/Tools`, Godot version `4.7`, version, download commit, icon
   URL, repo/issues URLs) — you paste into both forms. After AL approval, send me the **asset
   id** and add the two **GitHub secrets** + the `ASSETLIB_ASSET_ID` repo variable; from then
   on the pipeline posts AL updates automatically on every Publish.
5. **Decisions** — listing name (proposal: **“Reactive UI (React for Godot)”**); publish
   `reactive_ui_editor` as a second asset now or in Wave 3 (recommendation: Wave 3).

## 5. Plans housekeeping (user-added scope)
Audit every document in `plans/`: refresh stale statements (pre-0.7 grammar, global-name
generated code), mark shipped plans DONE, and move completed ones to `plans/archive/`.
(Executed alongside this plan — see the audit commit.)

## 6. Follow-ups
- Automate new-store version publishing the moment an API/CLI ships (watch the store
  changelog: https://store.godotengine.org/changelog/).
- Wave 3 adds the `reactive_ui_editor` listing + docs/screenshots pass for both storefronts.
