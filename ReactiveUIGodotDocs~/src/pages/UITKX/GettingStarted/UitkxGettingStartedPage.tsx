import type { FC } from 'react'
import { Alert, Box, List, ListItem, ListItemText, Typography } from '@mui/material'
import { CodeBlock } from '../../../components/CodeBlock/CodeBlock'
import Styles from '../../GettingStarted/GettingStartedPage.style'
import {
  UITKX_HELLO_WORLD_BOOTSTRAP,
  UITKX_HELLO_WORLD_COMPONENT,
  UITKX_INSTALL_URL,
  UITKX_EDITOR_BOOTSTRAP,
} from './UitkxGettingStartedPage.example'

export const UitkxGettingStartedPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      .guitkx Getting Started
    </Typography>
    <Typography variant="body1" paragraph>
      You write function-style <code>.guitkx</code> components and the editor plugin compiles each
      one to a sibling <code>.gd</code> class automatically — no boilerplate needed. Supported Godot
      versions: <strong>Godot 4.2+</strong> (tested through 4.5). It&apos;s pure GDScript — no
      GDExtension or build step, and it works in the <strong>standard</strong> Godot editor.
    </Typography>

    <Typography variant="h5" component="h2" gutterBottom>
      Install the addon
    </Typography>
    <List>
      <ListItem disablePadding>
        <ListItemText
          primary="From the Asset Library: open the AssetLib tab, search “Reactive UI”, then Download → Install (keep the addons/reactive_ui/ folder). The editor tooling ships as a separate asset — search “Reactive UI Editor” to add it too."
          secondary="Or, manually: copy the addons/reactive_ui/ folder into your project's res://addons/ directory."
        />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary="Enable the plugin under Project Settings → Plugins to turn on .guitkx compile-on-save." />
      </ListItem>
    </List>
    <CodeBlock language="jsx" code={UITKX_INSTALL_URL} />
    <Typography variant="body1" paragraph>
      The library is plain GDScript with global <code>class_name</code>s (<code>V</code>,{' '}
      <code>Hooks</code>, <code>ReactiveRoot</code>, …), so the runtime is available immediately — no
      plugin enable is required if you author components in plain <code>.gd</code>. Enabling the
      plugin only adds the optional <code>.guitkx</code> editor integration: it watches the{' '}
      <code>EditorFileSystem</code> and generates a sibling <code>.gd</code> for each{' '}
      <code>.guitkx</code> on save.
    </Typography>

    <Typography variant="h5" component="h2" gutterBottom>
      1. Create a .guitkx component
    </Typography>
    <Typography variant="body1" paragraph>
      Each <code>.guitkx</code> file contains exactly one component (or module/hook). The{' '}
      <code>@class_name</code> becomes the generated GDScript <code>class_name</code> (e.g.{' '}
      <code>HelloWorld.guitkx</code> defines <code>component HelloWorld</code>). Setup code goes at
      the top; the component returns markup.
    </Typography>
    <CodeBlock language="jsx" code={UITKX_HELLO_WORLD_COMPONENT} />
    <Typography variant="body1" paragraph>
      When you save, the plugin emits a complete GDScript class (<code>HelloWorld.gd</code>) that{' '}
      <code>extends RefCounted</code> and exposes a{' '}
      <code>static func render(props, children) -&gt; RUIVNode</code> method. The generated file is
      marked <code>AUTO-GENERATED … do not edit</code>. You don't need to create any companion file
      for this to work.
    </Typography>

    <Typography variant="h5" component="h2" gutterBottom>
      2. Mount it
    </Typography>
    <Typography variant="body1" paragraph>
      <code>V.fc(HelloWorld.render)</code> wraps the generated <code>render</code> method as a
      function-component <code>RUIVNode</code> — the reconciler's entry point into your component
      tree. Mount it under any <code>Control</code> with <code>ReactiveRoot.create</code>:
    </Typography>
    <CodeBlock language="gdscript" code={UITKX_HELLO_WORLD_BOOTSTRAP} />
    <Typography variant="body1" paragraph>
      <code>ReactiveRoot.create(container, root_vnode)</code> mounts under <code>container</code> and
      renders. <strong>Hold onto the returned <code>ReactiveRoot</code></strong> (for example in a
      member variable) — it owns the reconciler. Call <code>_app.unmount()</code> to tear down and
      run all cleanup functions.
    </Typography>

    <Typography variant="h5" component="h2" gutterBottom>
      Mounting via a scene node
    </Typography>
    <Typography variant="body1" paragraph>
      If you prefer mounting through a node in the scene, use <code>ReactiveRootNode</code> — a{' '}
      <code>Control</code> that mounts on <code>_ready</code> and unmounts on <code>_exit_tree</code>{' '}
      automatically, so you don't have to hold a reference yourself:
    </Typography>
    <CodeBlock language="gdscript" code={UITKX_EDITOR_BOOTSTRAP} />

    <Alert severity="info" sx={{ mb: 2 }}>
      Keep the game running with <strong>F5</strong> and edit <code>HelloWorld.guitkx</code> again
      — the change appears in the live UI within a couple of seconds, and any hook state (like a
      counter's count) survives the edit. See <strong>Hot Reload (Fast Refresh)</strong> under
      Tooling for how it works and its limits.
    </Alert>

    <Typography variant="h5" component="h2" gutterBottom>
      Companion files (optional)
    </Typography>
    <Typography variant="body1" paragraph>
      The generator produces everything a component needs, but you can optionally add companion{' '}
      <code>.guitkx</code> files using the <code>hook</code> and <code>module</code> keywords to
      extract reusable state logic, styles, types, or utilities. See the{' '}
      <strong>Companion Files</strong> page for details.
    </Typography>
  </Box>
)
