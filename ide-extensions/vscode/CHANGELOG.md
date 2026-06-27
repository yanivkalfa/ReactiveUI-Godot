# Changelog

## [0.2.5] - 2026-06-27
- Embedded-GDScript intelligence (completion, hover, and go-to-definition inside {expr}/setup blocks) is now analyzed in-process by gdscript-analyzer, with no running Godot editor or TCP connection required, so it works fully offline. Go-to-definition now resolves same-file symbols (the previous Godot-proxy path could not). The `guitkx.enableGodotProxy` and `guitkx.godotLanguageServerPort` settings are replaced by a single `guitkx.enableEmbeddedAnalysis` toggle (the legacy `enableGodotProxy` value is still honored for back-compat).

## [0.2.4] - 2026-06-22
- Formatting: an authored blank line at the start or end of a component/hook setup block is now preserved (it was being stripped), and runs of 2+ spaces in embedded GDScript are collapsed to one outside strings/comments (e.g. `if x ==     null` becomes `if x == null`).
- Diagnostics: an unknown element (GUITKX0105) and an unknown host attribute (GUITKX0107) are now reported as Errors (a red squiggle) instead of a faint hint / a warning.
- Completion: style-dict keys (`bg_color`, `corner_radius`, `pad`, `separation`, `expand_h`, `font_size`, the theme channels, the per-state slots, …) are offered inside a `style={ {…} }` (or `*_style`) dictionary; common built-in constants (`Color.WHITE`, `Vector2.ZERO`, …) complete after `Type.`; and go-to-definition on an embedded GDScript symbol now forwards to Godot's language server (jumping to the library `.gd`, e.g. `use_ref` → core/hooks.gd) when the editor is running.
- Pressing Enter after a self-closing tag (`<Label … />`) no longer indents one level too deep (the indentation rule was matching any line ending in `>`, including `/>`).

## [0.2.3] - 2026-06-22
- Formatting now always uses tab indentation for `.guitkx` (the embedded GDScript requires tabs, and the compiler emits tabs), so the markup and the embedded setup no longer mix indentation units — previously, with an editor configured for spaces, a deeper setup line kept its authored tab and produced a "2 spaces + tab" indent. Diagnostics: unknown attributes on a host element are now flagged (e.g. a typo'd `te` / `xt` on `<Label>`) with a did-you-mean suggestion, validated against the bundled Godot ClassDB property + signal data; component tags (which take arbitrary props) are not flagged, and the check is skipped when the ClassDB dump is unavailable so it never false-flags.
- Formatter configuration: a project `guitkx.config.json` (Prettier-style walk-up, the analogue of ReactiveUIToolKit's `uitkx.config.json`) now overrides the formatter — `printWidth`, `indentStyle` ("tab" | "space"), `indentSize`, `singleAttributePerLine`, `insertSpaceBeforeSelfClose`. Tab indentation is the default when no config is present.

## [0.2.2] - 2026-06-22
- Fixed the published VSIX shipping without its `vscode-languageclient` runtime dependency (a `vsce package --no-dependencies` bug — there is no bundler in the pipeline, so the flag dropped the dependency), which made the extension fail to activate: no formatting, completion, or hover. The dependency is now bundled. Also added the missing `onLanguage:guitkx` activation event, editor defaults for `.guitkx` (format-on-save + the GUITKX document formatter + tab indentation), and a "Restart Language Server" command.

## [0.2.1] - 2026-06-22
- Renamed the extension to just "GUITKX" (it was "GUITKX (ReactiveUI for Godot)", which truncated to "GUITKX (React..." in the editor UI) and added the Godot logo as the extension / marketplace icon.

## [0.2.0] - 2026-06-22
- Formatter: components whose render is guarded by an early `return null` (e.g. `if not ready: return null` before the real markup return) are now formatted instead of being left verbatim, and the multi-attribute wrap path honors the `insertSpaceBeforeSelfClose` option (it previously always inserted the space).
- Language server: hover and completion inside a `hook` body now map to the correct embedded-GDScript offset (the body is no longer mis-mapped after re-indentation); a `<>...</>` fragment no longer raises a false GUITKX0104 duplicate-key warning across its siblings; and parameter completion is now noncode-aware, so a string default containing a comma or colon (e.g. `label: String = "a, b"`) no longer drops the parameters declared after it.
- find-references and rename now use the exact jsx-as-value keyword boundaries the compiler uses (return / else / and only), so they never edit a `<Name` that the compiler reads as a less-than comparison (e.g. after `if`, `in`, `not`, `await`, `yield`, or `or`).
- Control-flow inside an embedded expression that cannot be lowered to an expression (`@while` / `@match`) now reports GUITKX0113 through the compiler-diagnostics sidecar; `@if`/`@elif`/`@else` and `@for` inside a `{expression}` or a lambda now compile correctly (inline ternary / .map).
- Fixed file-path resolution on Linux/macOS: go-to-definition and the compiler-diagnostics sidecar no longer drop the leading slash when converting a `file://` URI to a filesystem path (the POSIX path was previously relative, so cross-file reads failed).

## [0.1.0] - 2026-06-21
- Initial release. Syntax highlighting and language intelligence for .guitkx markup (ReactiveUI for Godot): a self-contained TextMate grammar that colors both the JSX-like markup and the embedded GDScript; markup completion and hover for host-element tags, structural/common attributes, control-flow directives (@if/@elif/@else/@for/@while/@match/@case/@default) and per-element event handlers, served from the bundled schema; and embedded-GDScript completion/hover forwarded to Godot's built-in GDScript language server (TCP, engine port 6005) through a synthetic virtual .gd document with a length-preserving source map. Structural diagnostics (unbalanced braces) ship today; the Godot proxy degrades gracefully when the editor is not running so the markup features always work.
- VS Code extension drives the TypeScript language server over stdio; configurable via guitkx.godotLanguageServerPort and guitkx.enableGodotProxy. Packages to a self-contained .vsix (the Node server is bundled, no runtime to install).
