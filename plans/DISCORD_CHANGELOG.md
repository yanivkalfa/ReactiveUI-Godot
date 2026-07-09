## [0.8.6] - 2026-07-08

**A reconciler + style-layer performance pass, plus a packaging fix so an Asset Library install ships only the addon.** Two opt-in fast paths for lists: `reuse_by_slot` (a new host prop) lets a parent whose keyed leaf children are positionally stable reconcile them by slot — reused and patched in place instead of torn down and recreated when their keys change, the React-correct way to express slot reuse without dropping key semantics elsewhere; and `RUIConfig.host_node_pool` (on by default) recycles destroyed leaf host nodes through a per-class pool and re-diffs them on reuse, cutting node churn on lists that add/remove often. Under the hood, keyed child reconciliation is now mark-and-sweep (a member key map + per-fiber `matched_pass` flag, no per-frame key map/matched-set allocation), and `Style.apply` allocates far less — no more throwaway per-node dictionaries and `.keys()` copies for unchanged theme channels.

Also fixed: an Asset Library / `git archive` install no longer leaks repo tooling (`.claude/`, stray notes, `export_presets.cfg`) into your project — the `.gitattributes` export map was a stale denylist and is now an allowlist, so only `addons/reactive_ui` ships and new top-level files can never silently leak again. (#67)

Update to **Reactive UI 0.8.6** (copy `addons/reactive_ui/` into your project).

---

## [0.8.5] - 2026-07-06

**A correctness sweep across the `.guitkx` compiler, formatter, and Fast Refresh — no API changes.** A full audit turned up (and this release fixes) 7 confirmed bugs. The big one: every scan that locates a component/directive body, a `@match` body, or a `return ( ... )` window used to treat markup content as plain GDScript — so a literal `#` in element text (`Score #3`), a hex color, or a markup comment (`//`, `/* */`, `<!-- -->`) containing `}`/`)` could miscount the delimiters being balanced and silently shift where a body was believed to end (a miscompile, not just a parse error). These scans now understand markup lexis by default, switching to GDScript lexis only inside `{expr}` islands and directive headers.

Also fixed: the formatter no longer corrupts the interior of a triple-quoted string or drops blank lines inside a directive body's prep code; a truncated closing tag at the very end of a window now fails cleanly instead of scanning past it; an attribute value with an embedded `"` now falls back to verbatim instead of risking a corrupting re-emit; `@uss`/`@theme` no longer false-flags a `uid://` resource path as missing; and Fast Refresh's component-vs-module classification is no longer a fragile source-text guess (a comment containing `static func render(` could fool it) — generated components now carry an unambiguous marker read via reflection.

Also documented (not changed): hook dependency-array comparison is value-based (deep `==`), not identity-based like React's `Object.is` — intentional, now called out in the README.

Update to **Reactive UI 0.8.5** (copy `addons/reactive_ui/` into your project).

**Tooling:** GUITKX **0.8.7** (VS Code + VS 2022) picks up the same compiler/formatter fixes byte-for-byte, and `guitkx.*` settings now apply live. Editor addon **0.6.2** now warns once per file when a syntax error makes format-on-save skip, instead of silently no-op'ing (needs `reactive_ui` 0.8.5+).

---

## [0.8.4] - 2026-07-05

**Compiler and watcher hardening — no API changes.** The compiler's component-reference accumulator (the `refs` map persisted into each `.diags.json` sidecar for dangling-reference detection, GUITKX2107) is no longer a static: `compile()` now owns a per-call dictionary threaded through the emit context, so re-entrancy and future threading are structurally a non-issue rather than resting on an unstated "compiles never interleave" invariant. Sidecar output is byte-for-byte unchanged.

Also fixed on the watcher: `push_error` dock entries used to navigate to the watcher's own script instead of your `.guitkx`, so the watcher now prints a linkified `res://` line next to them (line-level navigation for the same diagnostics lives in the editor addon's Problems panel); and a file deleted then recreated with the same broken content now reports its errors again, instead of being suppressed by a stale "last reported errors" entry.

Update to **Reactive UI 0.8.4** (copy `addons/reactive_ui/` into your project).

**Tooling:** Ships alongside **Reactive UI Editor 0.5.0** — the M2 "daily-driver parity" milestone of the in-Godot `.guitkx` editor (see its own changelog).

---

## [0.8.3] - 2026-07-05

**The addon is now fully self-contained for store installs.** Acting on the first user feedback from the Asset Library listing: a store download no longer drops README/CHANGELOG/LICENSE at your project root (where they could collide with your own files) — `addons/reactive_ui/` now carries its own addon-focused `README.md`, a mirrored `CHANGELOG.md`, and its `LICENSE`, and the repository-root copies are excluded from release archives. No runtime code changes.

Update to **Reactive UI 0.8.3** (copy `addons/reactive_ui/` into your project).

**Tooling:** Ships alongside the new **Reactive UI Editor 0.4.0** (a separate asset) — the in-Godot `.guitkx` editor gains go-to-definition, find, cross-file diagnostics, rich hover, and a long list of data-safety guarantees (see `addons/reactive_ui_editor/CHANGELOG.md`).

---

## [0.8.2] - 2026-07-04

**The dangling-reference guard from 0.8.1 now catches a deleted *folder*, not just a deleted file.** Removing a component's whole folder takes its generated output down with it — so nothing was stale, and nothing dependent looked stale either, which meant `GUITKX2107` sat quiet until some unrelated save nudged the watch poll. The poll now compares each tracked file's sidecar references against reality every tick and goes hot the moment they disagree in either direction, settling the instant they match again — no spinning, no waiting on a coincidental save.

Pairs with **GUITKX IDE 0.8.6**, which fixes the matching VS Code-side gap (folder-delete events were being filtered out before they ever reached the extension).

Update to **Reactive UI 0.8.2** (copy `addons/reactive_ui/` into your project).

**Tooling:** GUITKX **0.8.5 → 0.8.6** (VS Code + VS 2022) — deleting a component's whole folder now evicts its index entries and un-harvests its generated classes, squiggling dangling references live (0.8.5 shipped the handler; 0.8.6 fixed it never firing, on both the fast `**` watcher and the addon's poll).

---

## [0.8.1] - 2026-07-04

**Renaming or deleting a `.guitkx` no longer leaks its generated output — and components stop depending on the global class registry at all.** Two related hardening passes:

**Orphan cleanup + `GUITKX2106`.** Renaming a component used to leave its old generated `.gd` behind — still declaring the same `class_name`, now a duplicate that broke resolution project-wide. The sweep now detects and removes orphaned generated output by its `AUTO-GENERATED` header (hand-written scripts are never touched). Copy-pasting a `.guitkx` is caught too: the incumbent keeps compiling, the copy errors with `GUITKX2106` and writes nothing, so a duplicate class can never reach disk.

**Generated code now references other components by *path*, not by global class name.** `<Card />` compiles to `V.fc(V.comp("res://ui/card.gd"), …)` — a lazy, cached, path-based resolver — instead of `Card.render`. This removes an entire failure class: a component created mid-session, an editor rescan lag, or a self-recursive component graph can no longer break resolution. Brand-new components even **hot-link into a running game** the moment you reference them, no restart needed. Hand-written `class_name` components keep the classic form.

**`GUITKX2107`** flags a dangling reference — deleting or renaming a component now errors at every tag that still points to it, and heals automatically once you restore it or edit the reference away.

Update to **Reactive UI 0.8.1**.

**Tooling:** GUITKX **0.8.2 → 0.8.4** (VS Code + VS 2022) — compiler-only errors now reach VS Code via the `.diags.json` sidecar watch; deleting or renaming a component squiggles every consumer live (pairs `GUITKX2107`); and deletions evict the index even while the file's tab stays open.

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

**Tooling:** Editor addon **0.3.0** — the native in-Godot `.guitkx` editor gains completion (host tags, your components, event names resolved via live `ClassDB`, `@`-directives) and hover, both read against the running engine's `ClassDB`, toggleable in Project Settings. Embedded-GDScript intelligence inside `{expr}` stays VS Code/VS 2022-only.

---

## [0.7.1] - 2026-07-04

**The watcher now provably notices your saves.** A `.guitkx` saved from an external editor was never guaranteed to recompile — editor focus-in and Godot's own `filesystem_changed` were the only triggers, and neither reliably fires for an external save. Worse, a sweep that found nothing stale printed nothing, so "plugin dead" and "nothing to do" looked identical in the Output panel.

Fixed with a **standing 2-second watch poll** that sweeps the moment any `.guitkx` changes on disk — no focus dance, no restart required. Same-second saves (mtimes are whole seconds) are now broken by content hash instead of silently skipped, and the very first sweep of a session always prints a proof-of-life line, so a silent Output after startup now genuinely means the plugin isn't running.

Update to **Reactive UI 0.7.1**.

**Tooling:** GUITKX **0.8.1** (VS Code + VS 2022) — fixes a false-positive `GUITKX0108` multi-root error on valid directive bodies; the live scanner now walks only each `return`'s markup span, matching the compiler.

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

**Tooling:** GUITKX **0.8.0** (VS Code + VS 2022) speaks the new directive-body grammar live — prep GDScript + `return ( <markup> )` fully understood, old bare-markup flags `GUITKX2103`, a hook in a body flags `GUITKX2104`. Format-on-save ships **enabled by default**, emitting the Unity-exact spaces-2 style.

---

## [0.6.2] - 2026-07-03

**Scan-window completeness, plus instant feedback on a typo the compiler alone couldn't catch.** A cold Godot editor open could still leave a `.guitkx` uncompiled — the startup sweep ran *during* the editor's first filesystem scan, where every mtime read returns 0, so every file looked fresh and nothing retried. Fixed: the initial sweep now waits out the first scan and runs the moment the filesystem is actually readable; a zero mtime now counts as stale, and an empty read of an existing file is held (not treated as clean or as a deletion).

Also new: every generated `.gd` is **parse-checked immediately** after compiling, so an unknown identifier or type error inside a `.guitkx` expression now lands in the editor dock at compile time, instead of waiting for the script to first load at play time.

Update to **Reactive UI 0.6.2**.

---

## [0.6.1] - 2026-07-03

**Cold-open recovery: the ~250-line red wall on a fresh clone is gone.** During the editor's first filesystem scan, every `res://` read of the compiler's vocabulary file came back empty — so every single `.guitkx` in the project logged three red error lines, all at once, on a repo this size. The vocabulary is now **embedded directly in the compiler** (generated from `vocabulary.json`, drift-tested), so production never file-reads it at all — the scan window simply can't hold anything anymore. A held compile (if the environment is ever genuinely not ready) now auto-retries every 2 seconds instead of waiting for a user edit, and is announced once per episode instead of once per file per sweep.

Update to **Reactive UI 0.6.1**.

**Tooling:** GUITKX **0.7.1** (VS Code + VS 2022) — Enter after a closing tag (`</VBox>`) no longer over-indents; and the embedded compiler vocabulary means the cold-open red wall (and its stale "unknown element" squiggles) can no longer happen.

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

**Tooling:** GUITKX **0.7.0** (VS Code + VS 2022) understands early markup returns live — `if not ready: return ( <Label/> )` gets full intelligence, and an unconditional early return dims the dead code after it. Adds the `GUITKX2102`/`GUITKX2508` diagnostics.

---

## [0.5.1] - 2026-07-03

**The field-triage release** — every defect from the first real-project test of 0.5.0, root-caused and fixed. Highlights: live `GUITKX0105` no longer flags host elements (`<HBox>`, `<Button>`, and every vocabulary alias were squiggling as "unknown component" the moment a workspace scan finished); an early markup return no longer leaks into the embedded-GDScript view and sprays bogus syntax/unreachable errors; `GUITKX2102` now fires live with honest wording instead of only appearing as a stale sidecar entry; and the cold-open error wall (three red lines per file, whole-project, on every fresh clone) collapses to one hold notice plus one recovery line, with generated outputs preserved throughout.

Also new: `GUITKX2508` catches a malformed directive header (`@for (i in 2: int5)`) that used to pass every tier silently and only fail once Godot's own parser choked on the generated code.

Update to **Reactive UI 0.5.1**.

**Tooling:** GUITKX **0.6.1** (VS Code + VS 2022) — host tags (`<HBox>`, `<Button>`, aliases) no longer squiggle as "unknown component" after a workspace scan; a garbage directive header flags `GUITKX2508` live; and stale sidecar diagnostics collapse into one file-level note.

---

## [0.5.0] - 2026-07-03

**The `.guitkx` syntax & diagnostics parity release.** `.guitkx` now matches Unity ReactiveUIToolKit's grammar feature-for-feature — markup comments (`//`, `/* */`, `<!-- -->`, `{/* */}`), `<Fragment key={...}>`, rules-of-hooks as errors, a working `@uss`/`@theme` directive — and every diagnostic code is renumbered onto Unity's shared numbering scheme (breaking for anything matching on code strings; see the concordance table in the full changelog). The compiler is also fail-loud now: an error can never coexist with a successful compile, and the **last** top-level markup return is the component's real output (Unity `useLastReturn` parity).

Update to **Reactive UI 0.5.0** and re-check anything that matched on old `GUITKX01xx` codes.

**Tooling:** GUITKX **0.6.0** (VS Code + VS 2022) renumbers diagnostics onto the Unity-shared table and bundles gdscript-analyzer 0.6.0 — Godot's verbatim messages, wrong-arity as errors, cross-file names from sibling `.guitkx` resolving on a fresh clone, unknown PascalCase tags squiggled with a did-you-mean.

---

## [0.4.3] - 2026-07-02

**Compiler indentation-anchor fixes, and hook returns the analyzer can actually type-check.** One accidentally-shallow setup line (or an over-indented leading comment) used to shift every other line in the block, producing a broken generated `.gd` plus a cascade of bogus follow-on errors. The reindenter now anchors to the first real (non-blank, non-comment) line and clamps outliers up to it — comments no longer count, so they can no longer fake a "hook called conditionally" warning either.

Also new: `useState`, `useReducer`, and `useTransition` now carry `## @return-tuple(...)` doc tags — inert to Godot, but read by the IDE's analyzer (0.5.3+) as a fixed-shape return type, so `s := useState(0)` makes `s[1]` a typed, checkable `Callable`.

Update to **Reactive UI 0.4.3**.

**Tooling:** GUITKX **0.5.4 → 0.5.5** (VS Code + VS 2022) — a typo'd hook call is flagged live mapped onto the typo; `GUITKX0108`/`GUITKX0102` fire while typing; hook returns are typed pairs (`s[1]` a checkable `Callable`); and gdscript-analyzer 0.5.4 flags a typo'd method on a built-in (`s.upper()`) exactly where Godot does.

---

## [0.4.2] - 2026-07-02

### Edits recompile the moment you tab back to Godot

`.guitkx` isn't a type Godot recognizes, so editing one in an external editor didn't reliably tell Godot anything changed -- you'd tab back and nothing recompiled until you closed and reopened the editor. The plugin now recompiles changed `.guitkx` on editor **focus-in**, so returning from VS Code just works. Compile errors are de-duplicated too: Godot's Errors dock is append-only (nothing can clear it mid-session), so the plugin reports each distinct error once -- no more the same error stacking up on every tab-back -- and prints a green "resolved" line when a file starts compiling clean again.

### Formatter matches the compiler on nested indentation

The `.guitkx` formatter re-indents component setup / hook bodies to depth-based tabs (same fix as the editor extension), so a lambda body or an `if`/`for` inside setup formats to clean tabs instead of a tab/space mix.

Update to **Reactive UI 0.4.2** (copy `addons/reactive_ui/` into your project).

**Tooling:** GUITKX **0.5.2 → 0.5.3** (VS Code + VS 2022) — a misspelled `component`/`@class_name` header no longer blacks out the whole file (it's flagged with a did-you-mean and analysis recovers), a single malformed tag no longer collapses markup analysis, and Format Document re-indents embedded GDScript to clean tabs by depth.

---

## [0.4.1] - 2026-07-02

### Indentation stops being a landmine

Mixing tabs and spaces in a component's setup used to break the whole component -- and the worst part is you couldn't *see* it: a tab followed by two spaces renders identically to two tabs, but the compiler compared indentation character-by-character, emitted GDScript with a phantom "unindent doesn't match", and even threw a bogus "hook called in a block" warning. One invisible stray space, whole component dead. The compiler now measures indentation by **depth** (a tab and the inferred space width each count as one level), so tabs and spaces mix freely and still produce valid GDScript. A real hook-in-a-block still warns.

Also fixed: generated `.gd` now regenerate when the **compiler** changes, not just when the `.guitkx` is newer. Before, updating the library left your old generated `.gd` in place (they were newer than their source), so compiler fixes silently never reached you. Now the toolchain fingerprints itself and regenerates everything when it moves.

Update to **Reactive UI 0.4.1** (copy `addons/reactive_ui/` into your project).

**Tooling:** GUITKX **0.5.1** (VS Code + VS 2022) — a `.guitkx` mixing tabs and spaces in setup no longer lights up with a `Mixed use of tabs and spaces` cascade; the embedded-GDScript virtual document normalizes setup indentation by depth, matching the compiler.

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

**Tooling:** GUITKX **0.5.0** (VS Code + VS 2022) speaks camelCase hooks everywhere with real signature hovers, and dims dead code after `return (...)`. Editor addon **0.2.0** now versions on its own track, fades unreachable code, and renders every new compiler validation live into the Problems panel.

---

## [0.3.0] - 2026-07-01

### React parity, for real -- onClick, prop spread, and context handles

The markup just got a lot more React, and it's all additive -- your existing `.guitkx` keeps working untouched.

**Events read like React now.** Wire a button with `onClick`, a text field or slider with `onChange`, an input's Enter with `onSubmit`, hover/focus with `onPointerEnter` / `onPointerLeave` / `onFocus` / `onBlur`. Each maps to the right Godot signal under the hood -- `onClick` -> `pressed`, and `onChange` is *polymorphic*: it binds whichever of `text_changed` / `value_changed` / `item_selected` / `tab_changed` / `toggled` the control actually has, exactly like React's single `onChange`. The old `on_<signal>` spelling still works as an escape hatch to *any* signal, so nothing you wrote breaks.

**Prop spread.** `<Button {...cfg} onClick={ handle } />` -- spread a dictionary of props onto any element or component, merged left-to-right (later wins), just like JSX.

**Context handles.** `Hooks.create_context(default)` gives you a handle to pass to `provide_context` / `use_context` instead of a bare string key -- no more accidental collisions between two features that both keyed on `"theme"`, plus a default value when nobody provides one. String keys still work if you prefer them.

Update to **Reactive UI 0.3.0** (copy `addons/reactive_ui/` into your project).

**Tooling:** GUITKX **0.4.0** (VS Code + VS 2022) speaks the new React events — typing `on` on a `<Button>` offers `onClick`/`onChange`/… each showing the exact Godot signal it binds, and prop spread `{...obj}` is understood and preserved by the formatter.

---

## [0.2.2] - 2026-06-30

### Custom drawing, a real README, and an IDE that now speaks plain GDScript

**Draw anything, anywhere.** Any host element now takes a `draw_fn` -- a `Callable(canvas_item)` that runs during the node's `draw` and issues its `draw_*` calls (lines, rects, polygons, text, whatever you like). Pair it with an optional `redraw_key` to force a repaint without changing the callback. It is the Godot analogue of ReactiveUIToolKit's `OnGenerateVisualContent` / `RedrawKey`, and a register-once trampoline means a fresh closure each render never re-subscribes -- so it stays cheap.

**The README finally tells the truth.** It used to claim a "10 host element MVP." It is rewritten to match what is actually here: 21 hooks, ~14 router hooks, 63 `V.*` factories, the router, signals, Suspense, item-model adapters, custom drawing, and the IDE tooling.

**The extension is now a full GDScript LSP (GUITKX 0.3.0).** Until now the VS Code / VS 2022 extensions only understood `.guitkx`. They now drive **plain `.gd`** files too, through gdscript-analyzer and fully headless (no running Godot editor): diagnostics, completion, hover, go-to-definition, project-wide find-references and rename, formatting, semantic highlighting, inlay hints, code actions, and document symbols. It is **on by default** -- install the extension and your `.gd` files light up. (It runs alongside godot-tools, so disable godot-tools' language server if you want ours to be the one.) Embedded GDScript inside `.guitkx` gained the same find-references / rename / signature-help / inlay / code-actions, and the bundled analyzer moved to **0.5.2** (which added the GDScript formatter + semantic tokens we just wired up).

**Tooling:** GUITKX **0.3.1** (VS Code + VS 2022) — hover/completion work inside components again, blank child slots and `@for`/`@if` bodies complete tags, nav/rename stop missing tab targets, and embedded GDScript is now highlighted and formatted by the bundled `gdscript-fmt`.

---

## [0.2.1] - 2026-06-22

### The demo gallery, now in .guitkx

**Every demo is now markup.** The whole `examples/` gallery — counter, todo, router, the stress tests, all 24 — is rewritten in `.guitkx` instead of hand-written `V.*` calls, so the demos double as a reference for the markup language. They follow the ReactiveUIToolKit layout: one `component` per file, sub-components as sibling files, `module` reserved for hook/registry files. Generated `.gd` are git-ignored (regenerated on save).

**Compiler fix.** A `hook` that declares a return type (`-> Array`, `-> Dictionary`) now keeps it in the generated GDScript, so `var xs := use_thing()` infers its type.

Verified on Godot 4.7 — full suite green: **core 91 / style 25 / router 18+37 / demos 28 / update / guitkx**.

Update to **Reactive UI 0.2.1** (copy `addons/reactive_ui/`).

**Tooling:** GUITKX **0.2.4** (VS Code + VS 2022) — the VS Code extension actually starts now (a missing `vscode-languageclient` dep + activation trigger fixed); it formats `.guitkx` with consistent tab indentation, flags unknown attributes with a did-you-mean, autocompletes `style={}` keys and `Color.*` constants, and reads a `guitkx.config.json` for formatter options.

---

## [0.2.0] - 2026-06-22

### A real router, and much more runtime breadth

**The router grew up.** ReactiveUI for Godot now ships the full React-Router-style component-tree router — a faithful port of ReactiveUIToolKit's. Declare routes as markup and the library renders the single best match; nested/layout routes render through `V.outlet()`, `:params` merge down the chain, and matching is React-Router-correct (a leaf consumes the whole path, a layout matches a prefix). You also get `basename`, query strings, navigation blockers, `V.navigate`, `V.nav_link` with active styling, and 11 new router hooks (`use_navigate`, `use_location`, `use_params`, `use_blocker`, …).

**More runtime landed.** `V.suspense`; a process-wide signal registry (`RUISignals` + `use_signal_key`); `V.memo`; per-state StyleBox slots; a userland `classes: [...]` layer (`RUIStyleSheet`); declarative `items` across `ItemList`/`Tree`/`TabBar`/`OptionButton`/`PopupMenu`; `use_deferred_value`; plus `use_animate`, `use_sfx`, and `V.audio`/`V.video`. Raw String children auto-wrap to Labels.

**Smarter compiler, then a full audit.** Control-flow inside `{expr}`/lambdas now lowers inline (`@if` → ternary, `@for` → `.map`). An 8-subsystem review with adversarial verification found and fixed **20 confirmed bugs** (+20 regression tests) — a `classes`-only re-render crash, `use_signal` freezing its selector at mount, `<Outlet/>` fallback, a post-unmount null-deref, fresh-but-equal Array/Dictionary now Object.is like React, and more. Full suite green: **core 91 / style 25 / router 18+37 / demos 28 / update / LSP 31**.

Update to **Reactive UI 0.2.0** (copy `addons/reactive_ui/`).

**Tooling:** VS Code **0.2.0** / VS 2022 **0.2.0** — the formatter handles `return null`-guarded components and self-close; the language server fixes hook-body hover mapping, a `<>…</>` duplicate-key false-positive, parameter completion with comma/colon defaults, find-references/rename keyword boundaries, and POSIX path resolution.
