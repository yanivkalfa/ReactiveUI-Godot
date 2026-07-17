# plans/archive — executed / superseded plans

Moved here by the 2026-07-04 plans audit. Everything in this folder is **done or dead** — kept
as the design/root-cause record, not as work to do. The live plans stay in `plans/`.

| Plan | Why archived |
|---|---|
| `PORTING_PLAN.md` | The original port pitch. Superseded by execution: `PARITY_PLAN.md` is the living status doc. (Its "HMR deletes state" principle was later *reversed* — Fast Refresh preserves hook state.) |
| `PHASE_2_GUITKX_PLAN.md` | `.guitkx` compiler + sibling-`.gd` codegen — shipped. Its "Godot LSP proxy / port 6005" IDE model is DEAD (own analyzer instead). |
| `PHASE_4_DESIGN.md` | VS Code extension + LSP server v1 — shipped (now 0.8.x). Proxy-era IDE architecture superseded. |
| `PHASE_5_6_DESIGN.md` | Diagnostics/completion depth + VS2022 — shipped (VS2022 currently parked at 0.5.5, refresh = Wave 1). Proxy-era notes superseded. |
| `PHASE_7_PLAN.md` | Runtime parity push (router, hooks, signals, Suspense, styles) — COMPLETE; suite green on 4.7. |
| `IDE_EXTENSION_ISSUES.md` | Issue ledger for the proxy-era extension — all fixed or moot after the analyzer swap. |
| `BUG_AUDIT.md` | Root-cause catalog (A-series analyzer + G-series Godot) — **every entry resolved**. |
| `BUG_SPLIT.md` | Quick index for `BUG_AUDIT.md` — all rows resolved. |
| `BUG_V1.md` | First field-testing bug wave — all fixed in 0.5.x–0.6.x. |
| `UITKX_GUITKX_SYNTAX_PARITY.md` | The Unity↔Godot divergence matrix (evidence base, snapshot of `e843fa0`) — parity since executed; matrix is historical. |
| `SYNTAX_PARITY_EXECUTION_PLAN.md` | The parity execution — 31/32 tasks shipped (0.7.0). Sole leftover **T6.1 (docs authoring)** moved to the docs wave (Wave 3). |
| `FIELD_TRIAGE_FIX_PLAN.md` | 0.6.0 field-triage wave (0105 storm, markup leak, 2101 masking, stale sidecar…) — all shipped across 0.6.x–0.8.x. |
| `HMR_FAST_REFRESH_PLAN.md` | Fast Refresh / HMR — shipped as addon 0.8.0 (+0.8.1 hot-link/`V.comp` hardening). |
| `GODOT_ANALYZER_INTEGRATION_PLAN.md` | Native gdext analyzer binding — **ALL PHASES DONE** (2026-07-05), shipped editor 0.3.0–0.6.0. Archived 2026-07-08 after full test suite green. |
| `NATIVE_EDITOR_PARITY_PLAN.md` | Native-editor parity M1–M3 — **ALL MILESTONES DONE** (2026-07-05), editor 0.4.0–0.6.0 (E17 + P3 incremental remap consciously skipped). Archived 2026-07-08. |
| `GODOT_EDITOR_EXTENSION_PLAN.md` | Full `.guitkx` tooling in the Godot editor — P1–P2 + **P3 shipped as editor 0.6.0** (now 0.6.2): embedded-GDScript intelligence via the native gdext analyzer bridge. Last of its trio; archived 2026-07-08. Kept as mechanism/constraint reference. |
| `DOOM_GAME_GUITKX_PORT_PLAN.md` | Software-rendered Doom FPS `.guitkx` sample — **all 6 phases done** (2026-07-08), `tests/doom_game_test.gd` green (179 checks). Audio/tween/gallery-entry consciously deferred as out-of-scope optionals. |
| `NAMING_LOYALTY_PROPOSAL.md` | 0.9.0 naming loyalty — **APPROVED & EXECUTED 2026-07-11**, shipped as 0.9.0 (PR #70). Decision record; coverage ledger lives on in `plans/WIDGET_INVENTORY.md`. |
| `IMPORT_EXPORT_PLAN.md` | The 0.10.0 imports leg (leg 2 of the family campaign) — **ALL MILESTONES M0–M8 EXECUTED** (2026-07-12), incl. the codemod migration of the whole tree, strict resolution, and the frozen `GUITKX2300–2309` family block. Archived 2026-07-14. |
| `IMPORTS_LEG_BUGHUNT.md` | Adversarial bug hunt over the imports leg (71-agent workflow + independent verification) — 18 verified bugs, **ALL FIXED** (2026-07-14, 7 commits, each with a regression test). Kept as the repro/method record. |
| `FINAL_AUDIT_GODOT_FINDINGS.md` | Correctness audit G-01…G-23 — v6 verification pass: **everything fixed except G-09** (hooks deps deep-compare: documented in README; optional `same_ref` escape hatch carried to `MASTER_PLAN.md`). Record, not work-list. |
| `FINAL_AUDIT_GODOT_OPTIMIZATIONS.md` | Perf audit + measurements — reconciler batch (GO-05/06/08) shipped 0.8.6, scanners G-10/G-08/G-15 shipped 0.8.7, doom GO-03/04 done. Open leftovers (GO-01, G-11, reconciler ~11µs/node lever, ColumnInfo tail) carried to `MASTER_PLAN.md`. |
| `VSCODE_VS2022_PARITY_PLAN.md` | VS Code → VS2022 parity — all 5 phases shipped (`vs2022-v0.8.6`/`0.8.7` tagged; 0.10.0 vsix builds clean). Sole leftover — the **interactive VS2022 verification checklist** — carried to `MASTER_PLAN.md`. |
| `PARITY_PLAN.md` | The living Unity→Godot parity status doc, 2026-06 era — core/compiler/formatter/LSP/publishing all at parity; superseded as a status surface by `MASTER_PLAN.md` (which carries its two leftovers: the niche-adapter decision and native-editor analyzer depth). |
| `ASSET_STORE_PLAN.md` | Asset Store / AssetLib research + repo prep — prep staged, CI auto-post jobs armed. The actionable remainder (owner accounts/listing, first submission) is tracked in `MASTER_PLAN.md`. |
| `imports-m1-parked.patch` | Safety copy of the imports-leg M1 WIP taken when the leg was parked for the Unreal contract freeze (2026-07-13). The same work is in git history (`ecf2915`); kept only as the park-protocol artifact. |
| `EXTENSION_LISTING_PLAN.md` | Marketplace listing overhaul (family campaign) — **EXECUTED**, shipped extensions 0.10.1 (2026-07-16): distinguishable display names (`GUITKX (Godot - VS Code)` / `GUITKX (Godot - VS2022)`) and a structured page body (Title/Description/Features/Requirements/Changelog) generated from the centralized changelog on both marketplaces. Reference implementation was the sibling Unreal repo (`c74680b`), executed here second. |
| `CLASSNAME_CLEANUP_PLAN.md` | `@class_name` redundancy cleanup (Option A) — **EXECUTED**, shipped reactive_ui 0.10.2 (2026-07-16): retired `GUITKX0103` emission, dropped all 45 demos' redundant `@class_name` directives (byte-identity verified), swept the README + docs site teaching examples to the same style. The directive itself is UNCHANGED — grammar removal (Option B) is a deferred family decision, tracked in `MASTER_PLAN.md` §2.3. |
| `ES_MODULES_EXECUTION_PLAN.md` | ES-modules Layer 2 (family contract: `../ES_MODULES_GENERAL_PLAN.md`) — **EXECUTED**, shipped reactive_ui 0.11.0 / editor 0.9.0 / extensions 0.11.0 (2026-07-18): wrapper keywords deprecated (GUITKX2320 window), plain signature-classified declarations + value exports + full ES import surface, whole tree modernized via `dev/migrate_0_11_0.gd`. Family corpus re-pin deferred until the Unreal leg lands its cases (recorded in MASTER_PLAN §2). |

Still live in `plans/`: **`MASTER_PLAN.md` — the single consolidated plan (all remaining work + status)**, plus the
living ledgers it references: `TECH_DEBT.md` (TD-01/TD-02 open-accepted), `WIDGET_INVENTORY.md` (Control coverage,
re-diffed per engine version — see `AUTOMATION.md`), `DISCORD_CHANGELOG.md` (community release log), and
`family-corpus.hash` (CI drift-gate data).
