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
