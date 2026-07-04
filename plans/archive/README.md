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

Still live in `plans/`: `ASSET_STORE_PLAN.md` (in flight), `GODOT_ANALYZER_INTEGRATION_PLAN.md`
(P3 gdext binding — design of record), `GODOT_EDITOR_EXTENSION_PLAN.md` (P3 remainder),
`PARITY_PLAN.md` (living status; G2 docs phases open), `DISCORD_CHANGELOG.md` (needs 0.6→0.8 backfill).
