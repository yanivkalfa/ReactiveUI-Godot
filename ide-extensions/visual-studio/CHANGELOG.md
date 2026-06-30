# Changelog

## [0.3.1] - 2026-07-01
- Hover, completion, and go-to-definition now work for embedded GDScript in a component's setup block (the lines before `return (...)`). They were returning nothing — including hooks like `use_state` — because the setup region's source map was dropped on CRLF files or when the block ended in a blank line; it is now mapped line by line.
- Hover in markup now resolves the full identifier under the cursor against host elements, your own components, and the host element's ClassDB properties and signals. Previously it only matched a host tag at the exact end of its name, so attributes (`text`, `separation`, `on_pressed`, …) and component tags hovered to nothing.
- Completion now fires at a blank markup position — an empty child slot or inside an `@for`/`@if` body — and offers your project's components as `<Tag>` suggestions. Those positions were being misread as embedded GDScript, so nothing was offered.
- Go-to-definition, find-references, and rename now work when the cursor sits on a tag's opening `<` (not only inside the name), so a mouse ctrl+click on a tab-indented `<Component/>` resolves. A GDScript comparison such as `a < Name` is never mistaken for a tag.
- Renaming a component that declares `@class_name` now rewrites the `@class_name` directive, the declaration, and every `<Tag>` usage together. It previously left `@class_name` stale, so the renamed usages reported a dangling `GUITKX0105` 'unknown element' error.
- Embedded GDScript inside `.guitkx` is now semantically highlighted by the analyzer (type-aware), the same way a real `.gd` file is, instead of grammar-only colouring.
- Embedded GDScript inside `.guitkx` is now formatted by the bundled analyzer — the same `gdscript-fmt` that formats plain `.gd` files — so a snippet formats identically in a `.gd` and in `.guitkx`. The optional external `gdformat` dependency is gone.

## [0.3.0] - 2026-06-30
- The extension now drives plain `.gd` files through gdscript-analyzer, not just `.guitkx` markup: diagnostics, completion, hover, go-to-definition, project-wide find-references and rename, signature help, inlay hints, code actions, document symbols, formatting, and semantic highlighting, all headless with no running Godot editor. It is ON by default; the new `guitkx.enableGdscriptAnalysis` setting turns it off. Because it runs alongside the godot-tools extension, disable godot-tools' language server to avoid duplicate diagnostics on `.gd` files.
- Embedded GDScript inside `.guitkx` now also gets find-references, project-wide rename (correct-or-refuse), signature help, inlay hints, and code actions, on top of the existing completion, hover, diagnostics, and go-to-definition.
- Upgraded the bundled GDScript analyzer to 0.5.2, which exposes GDScript formatting and semantic highlighting, now wired for `.gd` via Format Document and semantic tokens.

## [0.2.6] - 2026-06-28
- Go-to-definition now resolves across files fully offline (no running Godot editor): a library symbol such as a hook's `use_ref` now jumps to its real implementation in `core/hooks.gd`, landing on the declaration in that file. Previously only same-file symbols resolved headlessly; cross-file navigation required a running Godot editor.
- Upgraded the bundled GDScript analyzer to 0.4.0: navigation and diagnostics now cross the extension boundary as native objects, and each navigation target reports its file directly, making cross-file go-to-definition faster and more robust.

## [0.2.5] - 2026-06-27
- Embedded-GDScript intelligence (completion, hover, and go-to-definition inside {expr}/setup blocks) is now analyzed in-process by gdscript-analyzer, with no running Godot editor or TCP connection required, so it works fully offline. Go-to-definition now resolves same-file symbols (the previous Godot-proxy path could not). The `guitkx.enableGodotProxy` and `guitkx.godotLanguageServerPort` settings are replaced by a single `guitkx.enableEmbeddedAnalysis` toggle (the legacy `enableGodotProxy` value is still honored for back-compat).
- Embedded-GDScript type and parse diagnostics (e.g. integer division, type mismatch, syntax errors) now surface as squiggles inside {expr}/setup blocks, mapped back into the .guitkx source. Unresolved library/cross-file symbols never warn (the analyzer treats them as the Unknown seam), so this adds real diagnostics with no false positives.

## [0.2.4] - 2026-06-22
- Formatting: an authored blank line at the start or end of a component/hook setup block is now preserved (it was being stripped), and runs of 2+ spaces in embedded GDScript are collapsed to one outside strings/comments (e.g. `if x ==     null` becomes `if x == null`).
- Diagnostics: an unknown element (GUITKX0105) and an unknown host attribute (GUITKX0107) are now reported as Errors (a red squiggle) instead of a faint hint / a warning.
- Completion: style-dict keys (`bg_color`, `corner_radius`, `pad`, `separation`, `expand_h`, `font_size`, the theme channels, the per-state slots, …) are offered inside a `style={ {…} }` (or `*_style`) dictionary; common built-in constants (`Color.WHITE`, `Vector2.ZERO`, …) complete after `Type.`; and go-to-definition on an embedded GDScript symbol now forwards to Godot's language server (jumping to the library `.gd`, e.g. `use_ref` → core/hooks.gd) when the editor is running.

## [0.2.3] - 2026-06-22
- Formatting now always uses tab indentation for `.guitkx` (the embedded GDScript requires tabs, and the compiler emits tabs), so the markup and the embedded setup no longer mix indentation units — previously, with an editor configured for spaces, a deeper setup line kept its authored tab and produced a "2 spaces + tab" indent. Diagnostics: unknown attributes on a host element are now flagged (e.g. a typo'd `te` / `xt` on `<Label>`) with a did-you-mean suggestion, validated against the bundled Godot ClassDB property + signal data; component tags (which take arbitrary props) are not flagged, and the check is skipped when the ClassDB dump is unavailable so it never false-flags.
- Formatter configuration: a project `guitkx.config.json` (Prettier-style walk-up, the analogue of ReactiveUIToolKit's `uitkx.config.json`) now overrides the formatter — `printWidth`, `indentStyle` ("tab" | "space"), `indentSize`, `singleAttributePerLine`, `insertSpaceBeforeSelfClose`. Tab indentation is the default when no config is present.

## [0.2.1] - 2026-06-22
- Renamed the extension to just "GUITKX" (it was "GUITKX (ReactiveUI for Godot)", which truncated to "GUITKX (React..." in the editor UI) and added the Godot logo as the extension / marketplace icon.

## [0.2.0] - 2026-06-22
- Formatter: components whose render is guarded by an early `return null` (e.g. `if not ready: return null` before the real markup return) are now formatted instead of being left verbatim, and the multi-attribute wrap path honors the `insertSpaceBeforeSelfClose` option (it previously always inserted the space).
- Language server: hover and completion inside a `hook` body now map to the correct embedded-GDScript offset (the body is no longer mis-mapped after re-indentation); a `<>...</>` fragment no longer raises a false GUITKX0104 duplicate-key warning across its siblings; and parameter completion is now noncode-aware, so a string default containing a comma or colon (e.g. `label: String = "a, b"`) no longer drops the parameters declared after it.
- find-references and rename now use the exact jsx-as-value keyword boundaries the compiler uses (return / else / and only), so they never edit a `<Name` that the compiler reads as a less-than comparison (e.g. after `if`, `in`, `not`, `await`, `yield`, or `or`).
- Control-flow inside an embedded expression that cannot be lowered to an expression (`@while` / `@match`) now reports GUITKX0113 through the compiler-diagnostics sidecar; `@if`/`@elif`/`@else` and `@for` inside a `{expression}` or a lambda now compile correctly (inline ternary / .map).

## [0.1.0] - 2026-06-21
- Initial release. Syntax highlighting and language intelligence for .guitkx markup (ReactiveUI for Godot): a self-contained TextMate grammar that colors both the JSX-like markup and the embedded GDScript; markup completion and hover for host-element tags, structural/common attributes, control-flow directives (@if/@elif/@else/@for/@while/@match/@case/@default) and per-element event handlers, served from the bundled schema; and embedded-GDScript completion/hover forwarded to Godot's built-in GDScript language server (TCP, engine port 6005) through a synthetic virtual .gd document with a length-preserving source map. Structural diagnostics (unbalanced braces) ship today; the Godot proxy degrades gracefully when the editor is not running so the markup features always work.
- Visual Studio 2022 extension registers the TextMate grammar via .pkgdef (VS does not colorize over LSP) and drives the same Node language server through an ILanguageClient. Requires Node.js on PATH.
