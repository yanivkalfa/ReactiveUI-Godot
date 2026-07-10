# Reactive UI (React for Godot)

React-style reactive UI for Godot 4, in plain GDScript: function components, hooks
(`useState` / `useEffect` / `useMemo` / …), a fiber reconciler with keyed reconciliation and
bailouts, a router, typed styling — and the **`.guitkx`** JSX-like markup language that compiles
to plain `.gd` at save time and hot-reloads running games (Fast Refresh with hook-state
preservation).

- **Repository / full documentation:** https://github.com/yanivkalfa/ReactiveUI-Godot
- **Issues:** https://github.com/yanivkalfa/ReactiveUI-Godot/issues
- **Changelog:** `CHANGELOG.md` (in this folder)
- **License:** MIT (`LICENSE`, in this folder)

## Install

1. Get the addon, either way:
   - **From the Asset Library:** open the **AssetLib** tab in the editor, search **"Reactive UI"**,
     then **Download → Install** (keep the `addons/reactive_ui/` folder).
   - **Manually:** copy `addons/reactive_ui/` into your project's `res://addons/`.
2. Enable **Reactive UI** under *Project → Project Settings → Plugins*.
3. Optional but recommended: the **Reactive UI Editor** addon (a separate Asset Library entry —
   search **"Reactive UI Editor"**) adds an in-editor `.guitkx` authoring experience — highlighting,
   live diagnostics, completion, hover, go-to-definition. VS Code users get the same (plus
   embedded-GDScript analysis) from the **GUITKX** extension on the marketplace.

Requires **Godot 4.4+** (tested on 4.7).

## Quick start

Create `hello.guitkx` anywhere in your project:

```
component Hello {
  var count = useState(0)
  return (
    <VBox style={ {"separation": 8} }>
      <Label text={ "clicked %d times" % count[0] } />
      <Button text="click me" onClick={ func(): count[1].call(count[0] + 1) } />
    </VBox>
  )
}
```

Saving it generates a sibling `hello.gd` (the addon's watcher compiles automatically). Mount it
from any scene script:

```gdscript
var root := RUIReconciler.create_root(self)
root.render(V.fc(V.comp("res://hello.gd"), {}))
```

With a game running (F5), edits to `.guitkx` hot-reload in place — state included.

## What's in the box

- `core/` — the reactive engine: V factories, virtual nodes, hooks, fiber reconciler, signals,
  router, Fast Refresh runtime.
- `guitkx/` — the `.guitkx` compiler, formatter, lexer, and diagnostics (GUITKX#### codes).
- `plugin.gd` — the editor watcher: compiles `.guitkx` on save, sweeps orphaned outputs, pushes
  hot reloads to running games.

Everything is plain GDScript — no native binaries, no dependencies.
