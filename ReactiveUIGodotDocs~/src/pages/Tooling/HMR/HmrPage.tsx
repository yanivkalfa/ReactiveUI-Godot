import type { FC } from 'react'
import {
  Box,
  List,
  ListItem,
  ListItemText,
  Typography,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  Alert,
} from '@mui/material'
import Styles from './HmrPage.style'

const Section: FC<{ title: string; children: React.ReactNode }> = ({ title, children }) => (
  <Box>
    <Typography variant="h5" component="h2" gutterBottom>
      {title}
    </Typography>
    {children}
  </Box>
)

export const HmrPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Live Reload
    </Typography>
    <Typography variant="body1" paragraph>
      Editing a <code>.guitkx</code> file and saving it updates the running UI in
      the Godot editor without a manual rebuild. This works by riding Godot&apos;s
      own GDScript hot-reload — there is no separate HMR subsystem to configure.
    </Typography>
    <Alert severity="info" sx={{ mb: 1 }}>
      This is deliberately different from the Unity reference&apos;s HMR. Godot has
      no Roslyn / domain-reload / assembly-swap machinery, and the library needs
      none: a <code>.guitkx</code> compiles to a real sibling <code>.gd</code>{' '}
      script that Godot compiles and reloads for free.
    </Alert>

    <Section title="Quick Start">
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<>Enable the <strong>reactive_ui</strong> editor plugin (<strong>Project → Project Settings → Plugins</strong>). The runtime works without it; the plugin is what compiles <code>.guitkx</code>.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>Edit and save any <code>.guitkx</code> file.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>The plugin regenerates the sibling <code>.gd</code> and nudges the editor filesystem; Godot hot-reloads the script and the mounted UI updates in place.</>} />
        </ListItem>
      </List>
    </Section>

    <Section title="How It Works">
      <Typography variant="body1" paragraph>
        The toolchain is a single <code>@tool EditorPlugin</code>{' '}
        (<code>addons/reactive_ui/plugin.gd</code>):
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<>On enable, the plugin subscribes to <code>EditorFileSystem.filesystem_changed</code> and compiles all <code>.guitkx</code> under <code>res://</code>.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>Each <code>Foo.guitkx</code> is lexed, parsed, and lowered by <code>RUIGuitkxCodegen</code> to a sibling <code>Foo.gd</code> — a real GDScript source file with a <code>render(props, children)</code> function.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>The plugin calls <code>EditorFileSystem.update_file()</code> on the emitted <code>.gd</code> so Godot picks it up.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>Godot recompiles and hot-reloads the <code>.gd</code> script itself — the library does not swap delegates or reload assemblies. The next reactive render runs the new <code>render</code> body.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>An mtime staleness guard makes the loop self-terminating: writing the <code>.gd</code> makes it newer than its <code>.guitkx</code>, so the next <code>filesystem_changed</code> finds nothing stale and stops. A re-entry guard prevents overlapping compiles.</>} />
        </ListItem>
      </List>
      <Typography variant="body1" paragraph>
        Because the generated <code>.gd</code> is an ordinary script, everything
        that follows — reload, error reporting, the debugger — is stock Godot
        behaviour, not a bespoke pipeline.
      </Typography>
    </Section>

    <Section title="State Across a Reload">
      <Typography variant="body1" paragraph>
        Reactive state lives in each component&apos;s <code>RUIComponentState</code>{' '}
        (a positional array of hook slots) held by the reconciler, <em>not</em> on
        the script instance. So a re-render after a script reload runs the new{' '}
        <code>render</code> body against the existing hook slots, and the table
        below describes how each hook behaves:
      </Typography>
      <TableContainer component={Paper} variant="outlined" sx={Styles.table}>
        <Table size="small">
          <TableHead>
            <TableRow>
              <TableCell><strong>Hook</strong></TableCell>
              <TableCell><strong>Behaviour after a reload / re-render</strong></TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            <TableRow>
              <TableCell><code>use_state</code> / <code>use_reducer</code></TableCell>
              <TableCell>Current values are retained in the slot; the setter / dispatch identity is stable.</TableCell>
            </TableRow>
            <TableRow>
              <TableCell><code>use_ref</code></TableCell>
              <TableCell>The <code>{'{ "current": … }'}</code> box is preserved; <code>current</code> is unchanged.</TableCell>
            </TableRow>
            <TableRow>
              <TableCell><code>use_effect</code> / <code>use_layout_effect</code></TableCell>
              <TableCell>The factory is refreshed with the new closure; it re-runs (after cleanup) when its deps change.</TableCell>
            </TableRow>
            <TableRow>
              <TableCell><code>use_memo</code> / <code>use_callback</code></TableCell>
              <TableCell>Recomputed with the new function body when deps change; the cached value survives otherwise.</TableCell>
            </TableRow>
            <TableRow>
              <TableCell><code>use_context</code></TableCell>
              <TableCell>Stateless — reads the current provider value without occupying a slot; always reflects the latest value.</TableCell>
            </TableRow>
            <TableRow>
              <TableCell><code>use_stable_callback</code> / <code>use_stable_action</code></TableCell>
              <TableCell>Wrapper identity preserved; the inner closure is silently replaced with the new body.</TableCell>
            </TableRow>
            <TableRow>
              <TableCell><code>use_signal</code> / <code>use_signal_key</code></TableCell>
              <TableCell>Re-bound each render; the subscription persists (or re-subscribes if the signal instance changed).</TableCell>
            </TableRow>
            <TableRow>
              <TableCell><code>use_deferred_value</code></TableCell>
              <TableCell>Recalculated from the new upstream value on the next render.</TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </TableContainer>
      <Alert severity="warning" sx={{ mt: 2 }}>
        The hooks contract still applies. If an edit changes the number, order, or
        kind of hooks, the positional-slot model desyncs. In debug builds the
        hook-order validator (<code>RUIConfig.enable_hook_validation</code>)
        detects this across renders and reports it via <code>RUIDiagnostics</code>{' '}
        + <code>push_error</code>. Re-mount the component (or restart the scene) to
        reset its slots cleanly.
      </Alert>
    </Section>

    <Section title="Companion Files">
      <Typography variant="body1" paragraph>
        Companion <code>.guitkx</code> files compile to sibling <code>.gd</code>s
        the same way, and reload the same way:
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<><strong>Hook files</strong> (e.g. <code>MyComponent.hooks.guitkx</code>, a <code>hook use_foo(...) {'{ … }'}</code> declaration) — heavy logic (game loops, effects) that a sibling <code>.guitkx</code> imports. Edit and save to reload the hook body.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><strong>Style / utility modules</strong> (e.g. <code>MyComponent.style.guitkx</code>, a <code>module {'{ … }'}</code> of <code>const</code> / <code>static</code> style values or helper functions) — recompiled to a <code>.gd</code> and reloaded by Godot.</>} />
        </ListItem>
      </List>
    </Section>

    <Section title="New Components">
      <Typography variant="body1" paragraph>
        Creating a brand-new <code>.guitkx</code> just works: the plugin&apos;s{' '}
        <code>compile_all</code> pass picks it up on the next{' '}
        <code>filesystem_changed</code>, emits its sibling <code>.gd</code>, and
        Godot loads it as a normal script. Reference it from a parent with{' '}
        <code>{'V.fc(preload("res://…/Child.guitkx").render, { … })'}</code> — the
        compiled <code>.gd</code> is a real class, so <code>preload</code> and hot
        reload both work with no registry step.
      </Typography>
    </Section>

    <Section title="Mounting a Component">
      <Typography variant="body1" paragraph>
        A component is mounted onto a container node with{' '}
        <code>ReactiveRoot.create(container, V.fc(Comp.render))</code>. That root
        keeps its component states alive across reloads, which is exactly why hook
        state persists when the underlying <code>.gd</code> is recompiled.
      </Typography>
    </Section>

    <Section title="Limitations">
      <TableContainer component={Paper} variant="outlined" sx={Styles.table}>
        <Table size="small">
          <TableHead>
            <TableRow>
              <TableCell><strong>Limitation</strong></TableCell>
              <TableCell><strong>Details</strong></TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            <TableRow>
              <TableCell>Hook signature changes reset state</TableCell>
              <TableCell>
                Adding / removing / reordering hooks desyncs the positional slots;
                re-mount the component to recover cleanly.
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>Compile errors block the update</TableCell>
              <TableCell>
                A <code>GUITKX####</code> error emits a stub <code>.gd</code> that{' '}
                <code>push_error</code>s; fix the error and re-save to resume.
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>Editor-plugin scope</TableCell>
              <TableCell>
                Compilation is driven by the <code>@tool EditorPlugin</code>, so
                it runs in the editor. For a running game, the reload path is
                Godot&apos;s standard script reload of the already-generated{' '}
                <code>.gd</code>.
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>Reload granularity is per-script</TableCell>
              <TableCell>
                Godot reloads at the <code>.gd</code> level; the reactive render
                then reconciles only what changed in the vnode tree.
              </TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </TableContainer>
    </Section>

    <Section title="Troubleshooting">
      <Typography variant="h6" component="h3" gutterBottom>
        Changes don&apos;t appear
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<>Confirm the <strong>reactive_ui</strong> editor plugin is enabled.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary="Confirm the file is saved, and look for a [guitkx] compiled -> … line in the Output panel." />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>Check for <code>[guitkx]</code> <code>push_error</code> / <code>push_warning</code> messages, or read the sibling <code>.guitkx.diags.json</code>.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>Verify the file is under <code>res://</code> (the scanned root).</>} />
        </ListItem>
      </List>

      <Typography variant="h6" component="h3" gutterBottom sx={{ mt: 2 }}>
        State is lost after an edit
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary="The hook order or count likely changed — this desyncs the positional hook slots." />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>Check the Output for a <code>[Hooks][order]</code> message and re-mount the component (restart the scene).</>} />
        </ListItem>
      </List>
    </Section>
  </Box>
)
