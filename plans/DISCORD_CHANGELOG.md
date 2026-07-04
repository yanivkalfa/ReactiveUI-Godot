## Now on the Godot Asset Store roadmap — MIT-licensed, publishing pipeline staged

The repo is now dual-license-ready for distribution: an **MIT `LICENSE`** landed, plus a store icon, and a `.gitattributes` `export-ignore` pass so an AssetLib/Asset Store download or `git archive` contains only the addon + README + LICENSE (a bundled `project.godot` or root `icon.png` would otherwise clobber a user's own project on install — now excluded). A `publish.yml` CI job is staged to auto-update the classic Godot Asset Library listing on every tagged release; the new Godot Asset Store still needs a manual first submission. Not live yet — accounts + first submissions are next.

---

## [IDE 0.8.6] - 2026-07-04

**Deleting a component's whole folder now actually gets caught — on both the fast path and the slow one.** Two holes, closed together: the extension's folder-delete handling (shipped in 0.8.5) turned out to be correct but *unreachable* — VS Code only delivers folder-delete events to a watcher whose glob matches the folder path itself, and the registration listed per-extension file globs. It's a single `**` watcher now. Separately, the Godot addon's watch poll only went hot on stale mtimes — but a deleted folder takes its outputs down with it, so nothing looked stale and `GUITKX2107` waited for an unrelated save or editor focus-in. The poll now re-reads each tracked file's sidecar references every tick and goes hot on any state mismatch (flagged-but-restored, or missing-but-unflagged), settling once everything matches again.

Pins: a folder-style deletion (no orphaned files to notice) now goes poll-hot → flags → settles → and heals cleanly on restore, end to end.

Reinstall **GUITKX 0.8.6** (VS Code + VS 2022) and update to **Reactive UI 0.8.2**.

---

## [0.8.2] - 2026-07-04

**The dangling-reference guard from 0.8.1 now catches a deleted *folder*, not just a deleted file.** Removing a component's whole folder takes its generated output down with it — so nothing was stale, and nothing dependent looked stale either, which meant `GUITKX2107` sat quiet until some unrelated save nudged the watch poll. The poll now compares each tracked file's sidecar references against reality every tick and goes hot the moment they disagree in either direction, settling the instant they match again — no spinning, no waiting on a coincidental save.

Pairs with **GUITKX IDE 0.8.6**, which fixes the matching VS Code-side gap (folder-delete events were being filtered out before they ever reached the extension).

Update to **Reactive UI 0.8.2** (copy `addons/reactive_ui/` into your project).

---

## [IDE 0.8.5] - 2026-07-04

**Deleting a component's folder now actually clears it out of the project.** VS Code coalesces a bulk delete into a single folder-level event — and the handler for that event only closed each file's analyzer library, leaving the `.guitkx` index entries and their harvested generated classes behind. The component never left the project's universe, so no squiggle ever told you a reference was now dangling. The folder-deleted path now evicts every indexed `.guitkx` under it, un-harvests every generated class under it, and re-validates open documents — including the reverse case, where a restored folder clears stale squiggles.

Bonus: single-file deletions un-harvest the sibling class immediately now, instead of waiting ~2 seconds for the Godot addon's own orphan sweep to produce a second event.

(One caveat found in the field the same day: this handler turned out to never actually fire — fixed next release, 0.8.6.)

Reinstall **GUITKX 0.8.5** (VS Code + VS 2022).

---

## [IDE 0.8.4] - 2026-07-04

**Deleting a component whose tab is still open now squiggles its consumers right away.** The dangling-reference index refused to touch files with an open buffer — the right call for *edits* (the buffer is the source of truth), the wrong one for *deletions*: VS Code keeps a deleted file's tab alive, so the component stayed in the index and every reference to it looked perfectly healthy until some unrelated save finally touched it. Deletions now evict the index regardless of open buffers; re-saving the (now-orphaned) open tab recreates the file and re-indexes it right back, so nothing gets stuck either way.

Reinstall **GUITKX 0.8.4** (VS Code + VS 2022).

---

## [IDE 0.8.3] - 2026-07-04

**Deleting or renaming a component now squiggles every place that referenced it — live, no save required.** Two gaps, closed together: the server only recomputed diagnostics for the file you just edited, so deleting a component elsewhere never updated the tabs still pointing at it; and generated `.gd` classes were only ever *added* to the known-class set, never removed, which permanently suppressed the unknown-component check for anything that had ever existed once. The server now re-validates every open document whenever the component universe changes, and un-harvests a generated class the moment its source file disappears.

Pairs with the addon's **`GUITKX2107`** compile-tier error (0.8.1) — same problem, caught at two different moments now: the instant you delete the file here, and at the next compile there.

Reinstall **GUITKX 0.8.3** (VS Code + VS 2022, language server 0.8.3).

---

## [IDE 0.8.2] - 2026-07-04

**Compiler-only errors finally reach VS Code after you save.** The Godot addon compiles a saved `.guitkx` roughly 2 seconds *after* the save and writes its verdict into a `.diags.json` sidecar file — but the server never watched those sidecars. So a compiler-only error (say, an unknown element buried inside setup-value markup, which the fast live-typing tier doesn't scan) could genuinely never become a squiggle: by the time the sidecar updated, your next keystroke had already diverged the buffer from what was compiled, and diverged buffers suppress compiler-tier diagnostics by design. The server now watches every `**/*.guitkx.diags.json` and re-validates the matching open document the instant Godot writes or clears a verdict.

Reinstall **GUITKX 0.8.2** (VS Code + VS 2022, language server 0.8.2).

---

## [0.8.1] - 2026-07-04

**Renaming or deleting a `.guitkx` no longer leaks its generated output — and components stop depending on the global class registry at all.** Two related hardening passes:

**Orphan cleanup + `GUITKX2106`.** Renaming a component used to leave its old generated `.gd` behind — still declaring the same `class_name`, now a duplicate that broke resolution project-wide. The sweep now detects and removes orphaned generated output by its `AUTO-GENERATED` header (hand-written scripts are never touched). Copy-pasting a `.guitkx` is caught too: the incumbent keeps compiling, the copy errors with `GUITKX2106` and writes nothing, so a duplicate class can never reach disk.

**Generated code now references other components by *path*, not by global class name.** `<Card />` compiles to `V.fc(V.comp("res://ui/card.gd"), …)` — a lazy, cached, path-based resolver — instead of `Card.render`. This removes an entire failure class: a component created mid-session, an editor rescan lag, or a self-recursive component graph can no longer break resolution. Brand-new components even **hot-link into a running game** the moment you reference them, no restart needed. Hand-written `class_name` components keep the classic form.

**`GUITKX2107`** flags a dangling reference — deleting or renaming a component now errors at every tag that still points to it, and heals automatically once you restore it or edit the reference away.

Update to **Reactive UI 0.8.1**.

---

## [Editor 0.3.0] - 2026-07-04

**The native in-Godot `.guitkx` editor gets completion and hover — no VS Code required.** Five new pure-logic modules (schema, context, completion, hover, workspace index), all headlessly tested, wired straight into the built-in editor tab:

- **Completion** on `<` (host tags + your own project's components), inside attribute lists (structural attributes, React-style event names resolved to their real Godot signal via live `ClassDB`, plain properties), and after `@` (directives).
- **Hover** for tags, attributes, directives, and your own components — a native tooltip, Godot 4.4+.

Both read the vocabulary against the **running engine's own `ClassDB`**, so they never drift from a bundled snapshot. Independently toggleable under Project Settings, default on. Embedded-GDScript intelligence inside `{expr}`/setup code is still VS Code/VS 2022-only — that gap is tracked next.

Update to **Reactive UI Editor 0.3.0** (copy `addons/reactive_ui_editor/`; it needs `reactive_ui`).

---

## [0.8.0] - 2026-07-04

**Runtime Fast Refresh — edit a `.guitkx` while your game runs under F5, and the UI updates in place, hook state preserved.** The editor's watcher pushes freshly-compiled scripts into the running session over the debugger protocol; the game reloads them in place (`reload(keep_state=true)`, so `Callable` identity survives and the fiber reconciler keeps matching every component's hooks); exactly the affected components re-render, synchronously, so there's never a frame where old handlers meet new code.

A changed **component** re-renders just its own fibers; a changed **hook/module** triggers a global re-render, since any component might call it. If the hook-call *shape* changed (added/removed/reordered), that component's state is **deliberately reset** instead of risking corruption — a compiler-embedded hook-order fingerprint decides which. Dev-only by construction: gated on an attached debugger session, so exported builds carry zero HMR code. 30 new checks, wired into CI.

Update to **Reactive UI 0.8.0**.

---

## [0.7.2] - 2026-07-04

**Found it: the real reason some editors never recompiled a single `.guitkx`, ever.** A `static var` initializer doesn't reliably run during the editor's early script indexing — so a path constant silently read as `""` instead of its real value, which diverted the compiler into a test-only file-read branch, tried to read a file at path `""`, and **held every compile of every session, forever** — while headless runs (tests, CI) stayed green the whole time, because statics *do* initialize normally there. Proven with an instrumented run and fixed: an empty path now just means "use the embedded default," so nothing holds unless a real override is explicitly set.

Also fixed: a hook-aliasing/diagnostic-offset bug that pinned some setup-code errors to the wrong line (both in the Godot dock and via the VS Code sidecar) — the splice now runs before aliasing, not after, so offsets land where the error actually is.

Update to **Reactive UI 0.7.2**.

---

## [0.7.1] - 2026-07-04

**The watcher now provably notices your saves.** A `.guitkx` saved from an external editor was never guaranteed to recompile — editor focus-in and Godot's own `filesystem_changed` were the only triggers, and neither reliably fires for an external save. Worse, a sweep that found nothing stale printed nothing, so "plugin dead" and "nothing to do" looked identical in the Output panel.

Fixed with a **standing 2-second watch poll** that sweeps the moment any `.guitkx` changes on disk — no focus dance, no restart required. Same-second saves (mtimes are whole seconds) are now broken by content hash instead of silently skipped, and the very first sweep of a session always prints a proof-of-life line, so a silent Output after startup now genuinely means the plugin isn't running.

Update to **Reactive UI 0.7.1**.

---

## [IDE 0.8.1] - 2026-07-04

**Fixed a false-positive multi-root error on perfectly valid directive bodies.** A leftover pre-0.8 live scanner pass was still parsing directive bodies as bare markup — counting the `return (` / `)` lines themselves as extra root elements, so every correctly-migrated `@if`/`@for` body squiggled `GUITKX0108` for no reason. The scanner now walks only each `return`'s actual markup span, matching the same body model the compiler and formatter already use. Correct bodies are diagnostic-free again; a smoke test pins it.

Pairs with addon **0.7.1**'s watcher-liveness rework.

Reinstall **GUITKX 0.8.1** (VS Code + VS 2022, language server 0.8.1).

---

## [0.7.0] - 2026-07-04

**Directive bodies are code blocks now — full Unity convergence (BREAKING).** A directive body (`@if`/`@elif`/`@else`, `@for`, `@while`, `@match`/`@case`/`@default`) is no longer bare markup — it's GDScript prep code plus `return ( <markup> )`, exactly like ReactiveUIToolKit for Unity, nesting recursively:

```
@for (it in items) {
	if it == null:
		return null
	return ( <Label key={ str(it) } text={ "row %s" % it } /> )
}
```

Pre-0.7 bare-markup bodies now error with **`GUITKX2103`**, live in the editor and at compile. Migrate a whole project in one shot: `godot --headless --path . --script res://addons/reactive_ui/dev/migrate_directive_bodies.gd -- res://<your-ui-dir>`. A hook call inside a directive body is now `GUITKX2104` (hooks must stay unconditional in setup). Canonical formatting also changes to **spaces at width 2** (Unity-exact) — run `dev/reformat_all.gd` to reformat a project.

Update to **Reactive UI 0.7.0** and migrate.

---

## [IDE 0.8.0] - 2026-07-04

**The editor speaks the new directive-body grammar — and formats it for you.** Pairs with addon 0.7.0 (BREAKING): prep GDScript + `return ( <markup> )` inside every `@if`/`@for`/`@while`/`@case` body is now fully understood live — the old bare-markup form flags `GUITKX2103` with the migration message, and a hook call inside a body flags `GUITKX2104`. Markup inside prep values (`var badge = ( <HBox/> )`) gets full intelligence too.

**Format-on-save now ships enabled by default** for `.guitkx`, emitting the Unity-exact spaces-2 canonical style — embedded GDScript is reflowed to match. Also fixed a reformat corruption where nested code at spaces-2 could lose an indent level.

Reinstall **GUITKX 0.8.0** (VS Code + VS 2022, language server 0.8.0).

---

## [0.6.2] - 2026-07-03

**Scan-window completeness, plus instant feedback on a typo the compiler alone couldn't catch.** A cold Godot editor open could still leave a `.guitkx` uncompiled — the startup sweep ran *during* the editor's first filesystem scan, where every mtime read returns 0, so every file looked fresh and nothing retried. Fixed: the initial sweep now waits out the first scan and runs the moment the filesystem is actually readable; a zero mtime now counts as stale, and an empty read of an existing file is held (not treated as clean or as a deletion).

Also new: every generated `.gd` is **parse-checked immediately** after compiling, so an unknown identifier or type error inside a `.guitkx` expression now lands in the editor dock at compile time, instead of waiting for the script to first load at play time.

Update to **Reactive UI 0.6.2**.

---

## [0.6.1] - 2026-07-03

**Cold-open recovery: the ~250-line red wall on a fresh clone is gone.** During the editor's first filesystem scan, every `res://` read of the compiler's vocabulary file came back empty — so every single `.guitkx` in the project logged three red error lines, all at once, on a repo this size. The vocabulary is now **embedded directly in the compiler** (generated from `vocabulary.json`, drift-tested), so production never file-reads it at all — the scan window simply can't hold anything anymore. A held compile (if the environment is ever genuinely not ready) now auto-retries every 2 seconds instead of waiting for a user edit, and is announced once per episode instead of once per file per sweep.

Update to **Reactive UI 0.6.1**.

---

## [IDE 0.7.1] - 2026-07-03

**Enter after a closing tag no longer over-indents.** The indent rule matched any line ending in `>` — including `</VBox>` — so pressing Enter after a closing tag added an extra, unwanted indent level. It now aligns with the tag itself; opening tags, multi-line tags, and `/>` self-closers are unaffected.

Pairs with addon **0.6.1**: the compiler vocabulary is now embedded, so the cold-open red wall (and the stale "unknown element" squiggles it used to pin in VS Code) can no longer happen.

Reinstall **GUITKX 0.7.1** (VS Code + VS 2022).

---

## [0.6.0] - 2026-07-03

**Early markup returns — the Unity way.** A component can now `return ( <markup> )` anywhere, not only as its final statement:

```
component Panel(ready: bool = false) {
	if not ready:
		return ( <Label text="loading" /> )
	return ( <VBox>…</VBox> )
}
```

Each early return's markup gets full validation and live intelligence — parse errors, unknown-tag hints, key checks — exactly like the final return. Code after an *unconditional* early return is unreachable and now dims in editors. `GUITKX2102` narrows to its true meaning: only "the final top-level return isn't markup" — the old false-positive on early returns is gone.

Update to **Reactive UI 0.6.0**.

---

## [IDE 0.7.0] - 2026-07-03

**The editor understands early markup returns, live.** Pairs with addon 0.6.0: `if not ready: return ( <Label /> )` is legal now, React-style, and the guard's markup gets full intelligence — parse errors, unknown-tag did-you-means, key checks, highlighting, everything the final return already had. An unconditional early return dims the dead code after it, including the now-unreachable final return. Diagnostics docs gain the `GUITKX2102` and `GUITKX2508` rows.

Reinstall **GUITKX 0.7.0** (VS Code + VS 2022, language server 0.7.0).

---

## [0.5.1] - 2026-07-03

**The field-triage release** — every defect from the first real-project test of 0.5.0, root-caused and fixed. Highlights: live `GUITKX0105` no longer flags host elements (`<HBox>`, `<Button>`, and every vocabulary alias were squiggling as "unknown component" the moment a workspace scan finished); an early markup return no longer leaks into the embedded-GDScript view and sprays bogus syntax/unreachable errors; `GUITKX2102` now fires live with honest wording instead of only appearing as a stale sidecar entry; and the cold-open error wall (three red lines per file, whole-project, on every fresh clone) collapses to one hold notice plus one recovery line, with generated outputs preserved throughout.

Also new: `GUITKX2508` catches a malformed directive header (`@for (i in 2: int5)`) that used to pass every tier silently and only fail once Godot's own parser choked on the generated code.

Update to **Reactive UI 0.5.1**.

---

## [IDE 0.6.1] - 2026-07-03

**The host-tag storm is fixed.** `<HBox>`, `<Button>`, `<Label>` and every vocabulary alias no longer squiggle as "unknown component" once a workspace scan completes — the live check only ever consulted the project's own components, never the host vocabulary. A typo'd host tag now gets a did-you-mean for the host tag itself. Also: a garbage directive header (`@for (i in 2: int5)`) now flags live as `GUITKX2508` instead of silently compiling into broken GDScript, and stale compiler-sidecar diagnostics collapse into one file-level note instead of piling up at drifted offsets while you type.

Pairs with addon **0.5.1**: the cold-open red wall is two warning lines now, not ~250.

Reinstall **GUITKX 0.6.1** (VS Code + VS 2022, language server 0.6.1).

---

## [0.5.0] - 2026-07-03

**The `.guitkx` syntax & diagnostics parity release.** `.guitkx` now matches Unity ReactiveUIToolKit's grammar feature-for-feature — markup comments (`//`, `/* */`, `<!-- -->`, `{/* */}`), `<Fragment key={...}>`, rules-of-hooks as errors, a working `@uss`/`@theme` directive — and every diagnostic code is renumbered onto Unity's shared numbering scheme (breaking for anything matching on code strings; see the concordance table in the full changelog). The compiler is also fail-loud now: an error can never coexist with a successful compile, and the **last** top-level markup return is the component's real output (Unity `useLastReturn` parity).

Update to **Reactive UI 0.5.0** and re-check anything that matched on old `GUITKX01xx` codes.

---

## [IDE 0.6.0] - 2026-07-03

**Diagnostic codes renumbered onto the Unity-shared table** (pairs with addon 0.5.0) — most visibly, unreachable-after-return is now `GUITKX0107` (was 0114), missing-declaration is `GUITKX2101` (was 0102), and duplicate keys (`GUITKX0026`, was 0113) are errors now. Bundles gdscript-analyzer 0.6.0: embedded-GDScript diagnostics use Godot's own verbatim message text, wrong-arity calls are errors, and unreachable/unused code dims. Names declared in sibling `.guitkx` files now feed the analyzer as virtual libraries, so cross-file references resolve on a fresh clone and a typo'd hook call is an error again. Unknown PascalCase component tags squiggle live with a did-you-mean.

Reinstall **GUITKX 0.6.0** (VS Code + VS 2022, language server 0.6.0).

---

## [IDE 0.5.5] - 2026-07-02

Bundles gdscript-analyzer 0.5.4: a typo'd method on a built-in value — `s.upper()` on a `String` (a Godot-3 rename), `v.zzz` on a `Vector2` — is now an error with a precise squiggle, exactly where Godot itself errors. Works through plain untyped `var s = useState(0)` locals (the analyzer narrows single-assignment locals to their initializer's type), and `Dictionary` `d.key` sugar now types correctly instead of ever false-flagging.

Reinstall **GUITKX 0.5.5** (VS Code + VS 2022).

---

## [0.4.3] - 2026-07-02

**Compiler indentation-anchor fixes, and hook returns the analyzer can actually type-check.** One accidentally-shallow setup line (or an over-indented leading comment) used to shift every other line in the block, producing a broken generated `.gd` plus a cascade of bogus follow-on errors. The reindenter now anchors to the first real (non-blank, non-comment) line and clamps outliers up to it — comments no longer count, so they can no longer fake a "hook called conditionally" warning either.

Also new: `useState`, `useReducer`, and `useTransition` now carry `## @return-tuple(...)` doc tags — inert to Godot, but read by the IDE's analyzer (0.5.3+) as a fixed-shape return type, so `s := useState(0)` makes `s[1]` a typed, checkable `Callable`.

Update to **Reactive UI 0.4.3**.

---

## [IDE 0.5.4] - 2026-07-02

**A typo'd hook call is now flagged live, mapped right onto the typo.** The bundled analyzer only reports "defined nowhere" once it genuinely holds the whole project — so the server now feeds every `.gd` at startup and keeps that view current through a file watcher, arming the check without ever false-flagging a name that only exists in a sibling `.guitkx`'s not-yet-generated output. `GUITKX0108` (multi-root directive body) and `GUITKX0102` (missing `return (...)`) now fire live while typing, precisely ranged, instead of only after a save. Hook returns are typed pairs end-to-end now too — `s := useState(0)` makes `s[1]` a checkable `Callable` with real hover and inlay hints.

Reinstall **GUITKX 0.5.4** (VS Code + VS 2022).

---

## [IDE 0.5.3] - 2026-07-02

### A header typo no longer takes the whole file down with it

0.5.2 *reported* a bad header, but everything downstream still went dark -- markup diagnostics, embedded-GDScript checks, tag highlighting, and completion all vanished the moment the keyword was misspelled. Now the language server **recovers** a near-miss header (`comssponent Foo {` is analyzed as a `component`) so the rest of the file keeps being checked while you fix the typo. Two more robustness wins: a single malformed tag like `<  a>` no longer collapses the whole component's markup analysis (so *other* markup errors still show), and a misspelled `@class_name` directive -- e.g. `@clasaas_name` -- is now flagged as `GUITKX0300` with a did-you-mean instead of being silently ignored.

### Formatting stops leaving spaces in nested code

Format Document now re-indents embedded GDScript to real **tabs by depth**. A nested setup line -- most visibly a lambda body -- used to come back as a tab followed by spaces (`\t    `), which looks like two tabs but is a byte-level tab/space mix; it now normalizes to clean tabs, matching the compiler.

Reinstall **GUITKX 0.5.3** (VS Code + VS 2022).

---

## [0.4.2] - 2026-07-02

### Edits recompile the moment you tab back to Godot

`.guitkx` isn't a type Godot recognizes, so editing one in an external editor didn't reliably tell Godot anything changed -- you'd tab back and nothing recompiled until you closed and reopened the editor. The plugin now recompiles changed `.guitkx` on editor **focus-in**, so returning from VS Code just works. Compile errors are de-duplicated too: Godot's Errors dock is append-only (nothing can clear it mid-session), so the plugin reports each distinct error once -- no more the same error stacking up on every tab-back -- and prints a green "resolved" line when a file starts compiling clean again.

### Formatter matches the compiler on nested indentation

The `.guitkx` formatter re-indents component setup / hook bodies to depth-based tabs (same fix as the editor extension), so a lambda body or an `if`/`for` inside setup formats to clean tabs instead of a tab/space mix.

Update to **Reactive UI 0.4.2** (copy `addons/reactive_ui/` into your project).

---

## [IDE 0.5.2] - 2026-07-02

### One typo no longer blacks out the whole file

The editor's analysis quietly keyed off a *perfect* `component` / `hook` / `module` header -- if it couldn't find one, it skipped everything and reported nothing. So a single slip like `comssponent` (or a mistyped `@class_name`) made every other error, plus hover and completion, silently vanish with no clue why. Now the header is validated **live**: a misspelled keyword gets `GUITKX0102: did you mean 'component'?`, an invalid `@class_name` gets `GUITKX0300`, and a `<` followed by whitespace is flagged as an invalid tag name -- all without a running Godot editor. Previously these only surfaced via the Godot-generated diagnostics sidecar (i.e. only when the Godot editor was open and recompiling).

Reinstall **GUITKX 0.5.2** (VS Code + VS 2022).

---

## [0.4.1] - 2026-07-02

### Indentation stops being a landmine

Mixing tabs and spaces in a component's setup used to break the whole component -- and the worst part is you couldn't *see* it: a tab followed by two spaces renders identically to two tabs, but the compiler compared indentation character-by-character, emitted GDScript with a phantom "unindent doesn't match", and even threw a bogus "hook called in a block" warning. One invisible stray space, whole component dead. The compiler now measures indentation by **depth** (a tab and the inferred space width each count as one level), so tabs and spaces mix freely and still produce valid GDScript. A real hook-in-a-block still warns.

Also fixed: generated `.gd` now regenerate when the **compiler** changes, not just when the `.guitkx` is newer. Before, updating the library left your old generated `.gd` in place (they were newer than their source), so compiler fixes silently never reached you. Now the toolchain fingerprints itself and regenerates everything when it moves.

Update to **Reactive UI 0.4.1** (copy `addons/reactive_ui/` into your project).

---

## [IDE 0.5.1] - 2026-07-02

### The editor stops choking on invisible whitespace

Same fix, editor side: a `.guitkx` that mixes tabs and spaces in its setup no longer lights up VS Code / VS 2022 with a `Mixed use of tabs and spaces` + `expected a declaration` cascade. The embedded-GDScript virtual document the analyzer reads now normalizes setup indentation by depth, matching the compiler -- so the difference you can't see no longer breaks analysis.

Reinstall **GUITKX 0.5.1** (VS Code + VS 2022).

---

## [0.4.0] - 2026-07-01

### Hooks go camelCase -- full React parity (breaking)

Hooks now read exactly like React: `useState`, `useEffect`, `useRef`, `useMemo`, `useCallback`, `useReducer`, `useContext`, `createContext`, `provideContext`, and the rest -- 23 in all. This is the one deliberate **breaking** change: there are no snake_case aliases, so do a `use_state` -> `useState` sweep across your `.guitkx` / `.gd`. As a bonus the compiler now auto-prefixes bare calls for *all* 23 hooks -- before, only 11 were auto-wired to `Hooks.*`. The **router hooks came along too** -- all 17 on `RUIRouter` (`useNavigate`, `useLocation`, `useParams`, `useSearchParams`, `useBlocker`, ...) are camelCase now, so the entire hook surface is consistent.

Alongside the rename, a round of **compiler validation** fixes -- mistakes that used to compile silently and blow up at runtime now get a clear diagnostic:
- A `@for` / `@while` body must return a **single root** (wrap siblings in a fragment `<>...</>`).
- **Duplicate keys** are caught even when the key is an expression (`key={ str(i) }`), not just `key="x"`.
- `@class_name` is **validated** as a real identifier instead of producing a broken `.gd`.
- A misspelled `componeent` gets a **"did you mean 'component'?"** hint.
- `<  a>` (a stray space after `<`) is flagged as an invalid tag name.
- **Unreachable code** after your `return (...)` is flagged -- and dimmed in the editors.

And two long-missing **demos** landed in the gallery: prop spread and the context handle.

Update to **Reactive UI 0.4.0** (copy `addons/reactive_ui/` into your project) and run the snake->camel hook rename.

---

## [Editor 0.2.0] - 2026-07-01

### The in-Godot .guitkx editor gets its own changelog -- and dims dead code

The native Godot editor addon (`addons/reactive_ui_editor`) now versions on its own track, like the IDE extensions. This release **fades unreachable code** after a component's `return (...)` (same as VS Code), and picks up every new compiler validation above *live* -- it renders `RUIGuitkx.compile()` straight into the Problems panel and gutter. Also squashed a batch of "auto brace completion open key already exists" errors that fired on editor load.

Update to **Reactive UI Editor 0.2.0** (copy `addons/reactive_ui_editor/` into your project; it needs `reactive_ui`).

---

## [IDE 0.5.0] - 2026-07-01

### The editor catches up: camelCase hooks, real hook hovers, and faded dead code

The VS Code / VS 2022 extension now speaks the new **camelCase hooks** everywhere -- completion, hover, go-to-definition, and the embedded-GDScript analysis all use `useState` / `useEffect` / `useRef` / ... (migrate your snake_case code alongside the library). Hovering a hook finally shows its **signature** (`useState(initial) -> [value, setter]`) instead of a bare `Callable`, and host-element hover drops the internal `V.*` detail in favor of the Godot class it maps to.

Two more live niceties: **unreachable code** after a `return (...)` is now **dimmed** (faded like GDScript dead code), and **duplicate-key** detection catches expression keys (`key={ str(i) }`), not just literal ones. The parser also flags a stray `<  a>` as an invalid tag name.

Reinstall **GUITKX 0.5.0** (VS Code + VS 2022).

---

## [0.3.0] - 2026-07-01

### React parity, for real -- onClick, prop spread, and context handles

The markup just got a lot more React, and it's all additive -- your existing `.guitkx` keeps working untouched.

**Events read like React now.** Wire a button with `onClick`, a text field or slider with `onChange`, an input's Enter with `onSubmit`, hover/focus with `onPointerEnter` / `onPointerLeave` / `onFocus` / `onBlur`. Each maps to the right Godot signal under the hood -- `onClick` -> `pressed`, and `onChange` is *polymorphic*: it binds whichever of `text_changed` / `value_changed` / `item_selected` / `tab_changed` / `toggled` the control actually has, exactly like React's single `onChange`. The old `on_<signal>` spelling still works as an escape hatch to *any* signal, so nothing you wrote breaks.

**Prop spread.** `<Button {...cfg} onClick={ handle } />` -- spread a dictionary of props onto any element or component, merged left-to-right (later wins), just like JSX.

**Context handles.** `Hooks.create_context(default)` gives you a handle to pass to `provide_context` / `use_context` instead of a bare string key -- no more accidental collisions between two features that both keyed on `"theme"`, plus a default value when nobody provides one. String keys still work if you prefer them.

Update to **Reactive UI 0.3.0** (copy `addons/reactive_ui/` into your project).

---

## [IDE 0.4.0] - 2026-07-01

### The editor speaks React events (and prop spread)

The VS Code / VS 2022 extension caught up to the library's new React-style API. Type `on` on a `<Button>` and completion offers `onClick`, `onChange`, `onPointerDown`, and the rest -- each showing the exact Godot signal it binds and that signal's arguments on hover, with signature help inside the handler and no false "unknown attribute" squiggle. `onChange` is offered per control, so a `<LineEdit>` gets the text-change binding and a `<Tree>` gets selection. And prop spread `{...obj}` is now understood in markup -- highlighted, never flagged, and preserved by the formatter.

Reinstall **GUITKX 0.4.0** (VS Code + VS 2022).

---

## [IDE 0.3.1] - 2026-07-01

### The .guitkx editor experience, debugged -- hover, completion, rename, and formatting that actually work

A focused bug-fix pass on the **VS Code / VS 2022 extension** after real hands-on testing. Eight defects, all in the language server -- the runtime library is untouched (still 0.2.2).

**Hover and completion light up again inside components.** In a component's setup block, hovering a variable or typing for completion (even a hook like `use_state`) was returning *nothing* -- the embedded-GDScript source map was being dropped on CRLF files and whenever the setup ended in a blank line. It now maps line by line, so hover, completion, and go-to-definition work throughout setup. Markup hover also got smarter: it resolves the full word under the cursor against host elements, your own components, and the host's real Godot properties/signals, so `text`, `separation`, `on_pressed`, and `<MyComponent>` all hover instead of silently doing nothing.

**Completion fills the blanks.** A blank child slot, or the inside of an `@for` / `@if` body, used to be misread as embedded GDScript -- so no tags were offered. Now those positions complete host elements **and your project's components** as `<Tag>` suggestions.

**Navigation and rename stop missing the target.** Ctrl+click / find-references / rename now work when the cursor lands on a tag's opening `<` (a mouse ctrl+click on a tab-indented `<Component/>` used to do nothing), while a GDScript comparison like `a < Name` is never mistaken for a tag. And renaming a component that declares `@class_name` now rewrites the `@class_name`, the declaration, and every usage **together** -- previously it left `@class_name` stale and the renamed tags lit up with a bogus "unknown element" (GUITKX0105) error.

**Embedded GDScript is now a first-class citizen.** The GDScript inside `.guitkx` is now **semantically highlighted** by the analyzer (type-aware, just like a real `.gd`) and **formatted** by the same bundled `gdscript-fmt` that formats plain `.gd` files -- so a snippet looks and formats identically whether it lives in a `.gd` or a `.guitkx`. (The optional external `gdformat` dependency is gone.)

**Editing nicety (VS Code).** Pressing Enter after a multi-line opening tag now indents the attributes one level instead of snapping back to the tag's column.

Reinstall **GUITKX 0.3.1** (VS Code + VS 2022) to get all of it.

---

## [0.2.2] - 2026-06-30

### Custom drawing, a real README, and an IDE that now speaks plain GDScript

**Draw anything, anywhere.** Any host element now takes a `draw_fn` -- a `Callable(canvas_item)` that runs during the node's `draw` and issues its `draw_*` calls (lines, rects, polygons, text, whatever you like). Pair it with an optional `redraw_key` to force a repaint without changing the callback. It is the Godot analogue of ReactiveUIToolKit's `OnGenerateVisualContent` / `RedrawKey`, and a register-once trampoline means a fresh closure each render never re-subscribes -- so it stays cheap.

**The README finally tells the truth.** It used to claim a "10 host element MVP." It is rewritten to match what is actually here: 21 hooks, ~14 router hooks, 63 `V.*` factories, the router, signals, Suspense, item-model adapters, custom drawing, and the IDE tooling.

**The extension is now a full GDScript LSP (GUITKX 0.3.0).** Until now the VS Code / VS 2022 extensions only understood `.guitkx`. They now drive **plain `.gd`** files too, through gdscript-analyzer and fully headless (no running Godot editor): diagnostics, completion, hover, go-to-definition, project-wide find-references and rename, formatting, semantic highlighting, inlay hints, code actions, and document symbols. It is **on by default** -- install the extension and your `.gd` files light up. (It runs alongside godot-tools, so disable godot-tools' language server if you want ours to be the one.) Embedded GDScript inside `.guitkx` gained the same find-references / rename / signature-help / inlay / code-actions, and the bundled analyzer moved to **0.5.2** (which added the GDScript formatter + semantic tokens we just wired up).

---

## [0.2.1] - 2026-06-22

### The demo gallery, now in .guitkx — and a VS Code extension that actually turns on

**Every demo is now markup.** The whole `examples/` gallery -- counter, todo, router, the stress tests, all 24 -- is rewritten in `.guitkx` instead of hand-written `V.*` calls, so the demos double as a reference for the markup language. They follow the ReactiveUIToolKit layout: one `component` per file, sub-components as sibling files, and `module` reserved for hook / registry files. The generated `.gd` are git-ignored (the editor regenerates them on save), so the tree shows the source you actually edit.

**The VS Code extension works now.** The published build was shipping without its `vscode-languageclient` dependency (a packaging-flag bug), so it silently failed to start -- no formatting, no completion, no hover. That's fixed, along with the missing "activate on `.guitkx`" trigger and format-on-save defaults. It also now formats `.guitkx` with consistent **tab** indentation (the embedded GDScript requires tabs, so markup + setup no longer mix tabs and spaces) and **flags unknown attributes** on host elements (a typo'd `te`/`xt` on `<Label>` gets a squiggle + did-you-mean). And you can now drop a **`guitkx.config.json`** next to your project (the analogue of `uitkx.config.json`) to tune the formatter -- line width, indent style/size, attribute wrapping. The **VS 2022** extension bundles the very same language server, so the formatter, diagnostics, and `guitkx.config.json` fixes land there as well (the packaging / activation fixes were VS Code-specific).

**IDE polish (0.2.4, both editors).** A follow-up round of editor fixes: the formatter now keeps your blank lines and tidies `if x ==     null` into `== null`; unknown elements/attributes are red errors instead of faint hints; you get autocomplete for `style={ {…} }` keys (`bg_color`, `corner_radius`, …) and `Color.WHITE`-style constants; go-to-definition on a hook/symbol jumps into the library source (with the Godot editor open); and pressing Enter after a `<Tag />` no longer over-indents. Reinstall **GUITKX 0.2.4** to get everything.

**Compiler fix.** A `hook` that declares a return type (`-> Array`, `-> Dictionary`) now keeps it in the generated GDScript, so `var xs := use_thing()` infers its type instead of failing to compile.

Verified on Godot 4.7 -- full suite green: **core 91 / style 25 / router 18+37 / demos 28 / update / guitkx**.

---

## [0.2.0] - 2026-06-22

### A real router, more runtime breadth, and a project-wide bug sweep

**The router grew up.** ReactiveUI for Godot now ships the full React-Router-style component-tree router -- a faithful port of ReactiveUIToolKit's. Declare routes as markup and the library renders the single best match:

```gdscript
V.routes({}, [
    V.route({ "path": "/",      "element": home }),
    V.route({ "path": "/users", "element": users_layout }, [   # a LAYOUT route...
        V.route({ "index": true, "element": pick_a_user }),
        V.route({ "path": ":id", "render": func(m): return user(m.params["id"]) }),
    ]),
    V.route({ "path": "*",      "element": not_found }),
])
```

Nested / layout routes render through `V.outlet()`, `:params` merge down the chain, and matching is React-Router-correct: a leaf route consumes the whole path (so `/` no longer prefix-matches everything and `*` is actually reachable), while a layout matches a prefix. You also get `basename`, query strings, navigation blockers, `V.navigate` (declarative redirect), and `V.nav_link` with active styling. New hooks: `use_navigate`, `use_location`, `use_query`, `use_params`, `use_matches`, `use_resolved_path`, `use_search_params`, `use_go`, `use_can_go`, `use_blocker`, `use_prompt`. The legacy `V.routes({ "routes": [...] })` table still works, and navigate-only widgets still don't re-render on navigation.

**More of the runtime landed.** `V.suspense` (a signal-await / frame-poll boundary, since GDScript has no throw-to-suspend); a process-wide signal registry (`RUISignals` + `use_signal_key`) for shared app state; `V.memo`; per-state StyleBox slots (`hover`/`pressed`/`focus`/`disabled`/`read_only`); a userland `classes: [...]` styling layer (`RUIStyleSheet`); declarative `items` generalized across `ItemList`/`Tree`/`TabBar`/`OptionButton`/`PopupMenu` (selection preserved by identity); a real `use_deferred_value`; plus `use_animate` (Tween), `use_sfx`, and `V.audio`/`V.video`. Raw String children now auto-wrap to Labels.

**The compiler got smarter about expressions.** Control-flow inside an embedded `{expression}` or a lambda now lowers inline -- `@if`/`@elif`/`@else` become a ternary and `@for` becomes `.map` -- so conditional rendering inside `items.map(func(it): return <>@if (it.ok) { ... }</>)` finally compiles. (`@while`/`@match` can't be expressions and now report `GUITKX0113` instead of emitting broken code.)

**Then we audited everything.** An 8-subsystem review with adversarial verification found and fixed 20 confirmed bugs: a `classes`-only element that errored on re-render; `use_signal` freezing its selector at mount; `<Outlet/>` not falling back when a nested route stopped matching; a null-deref if you rendered after unmount; collection state/signals not re-rendering when you passed a fresh-but-equal Array/Dictionary (now Object.is, matching React); duplicate-text item selection; a media one-shot leak for looping streams; and more. 20 regression tests were added. Full suite green: **core 91 / style 25 / guitkx / router 18+37 / demos 28 / update / LSP 31**.

IDE extensions bump to **VS Code 0.2.0 / VS 2022 0.2.0** -- the formatter now handles `return null`-guarded components and the self-close option, and the language server fixes hook-body hover mapping, a `<>...</>` duplicate-key false-positive, parameter completion with comma/colon string defaults, find-references / rename keyword boundaries, and POSIX path resolution.

---
