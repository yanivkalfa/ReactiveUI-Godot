## [0.2.1] - 2026-06-22

### The demo gallery, now in .guitkx — and a VS Code extension that actually turns on

**Every demo is now markup.** The whole `examples/` gallery -- counter, todo, router, the stress tests, all 24 -- is rewritten in `.guitkx` instead of hand-written `V.*` calls, so the demos double as a reference for the markup language. They follow the ReactiveUIToolKit layout: one `component` per file, sub-components as sibling files, and `module` reserved for hook / registry files. The generated `.gd` are git-ignored (the editor regenerates them on save), so the tree shows the source you actually edit.

**The VS Code extension works now.** The published build was shipping without its `vscode-languageclient` dependency (a packaging-flag bug), so it silently failed to start -- no formatting, no completion, no hover. That's fixed, along with the missing "activate on `.guitkx`" trigger and format-on-save defaults. Reinstall **GUITKX 0.2.2** to get language support back.

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
