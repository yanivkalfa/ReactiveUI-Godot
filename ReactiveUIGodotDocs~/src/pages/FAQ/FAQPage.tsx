import type { FC } from 'react'
import { Box, Typography } from '@mui/material'
import Styles from './FAQPage.style'

export const FAQPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Frequently Asked Questions
    </Typography>

    {/* ── General ──────────────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      General
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      What is ReactiveUI?
    </Typography>
    <Typography variant="body2" paragraph>
      ReactiveUI is a React-style UI framework for Godot, written in GDScript. You build
      interfaces from <strong>function components</strong> and <strong>hooks</strong>, and a
      fiber reconciler diffs a virtual tree against the live Godot <code>Control</code> tree,
      applying only the minimal changes. It ships as a Godot addon whose runtime lives entirely
      in <code>addons/reactive_ui/</code>.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      What is <code>.guitkx</code>?
    </Typography>
    <Typography variant="body2" paragraph>
      <code>.guitkx</code> is the optional markup language — JSX-style tags, hooks, and control
      flow (<code>@if</code>, <code>@for</code>, <code>@match</code>) in one file. A{' '}
      <code>@tool</code> editor plugin compiles each <code>.guitkx</code> into a sibling{' '}
      <code>.gd</code> render function on save. You can also skip markup entirely and write
      components directly against the <code>V</code> factory API in plain GDScript.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      Which Godot versions are supported?
    </Typography>
    <Typography variant="body2" paragraph>
      Godot <strong>4.2</strong> and above (the 4.x <code>Control</code> / <code>Theme</code> /{' '}
      <code>StyleBox</code> APIs the framework builds on). The runtime is pure GDScript with no
      GDExtension dependency, so it runs anywhere the Godot editor and its export templates run.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      How is this different from plain Godot Control nodes?
    </Typography>
    <Typography variant="body2" paragraph>
      You describe <em>what</em> the UI should look like for the current state and let the
      reconciler figure out the node operations. State lives in hooks (<code>use_state</code>,{' '}
      <code>use_reducer</code>, <code>use_signal</code>) instead of being scattered across node
      references and manual <code>show()</code>/<code>hide()</code>/<code>queue_free()</code> calls.
      Under the hood it is still ordinary Godot <code>Control</code> nodes — nothing exotic.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      Does it add runtime overhead?
    </Typography>
    <Typography variant="body2" paragraph>
      Rendering is synchronous and only runs when state changes — there is no per-frame diff of a
      static UI. Each update diffs the affected subtree and applies the minimal set of node
      changes. For very large trees you can enable time-slicing
      (<code>RUIConfig.time_slicing = true</code>) to chunk the render phase across frames; the
      commit stays atomic. For typical menus and HUDs the overhead is negligible.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      When should I use it — and when not?
    </Typography>
    <Typography variant="body2" paragraph>
      Reach for it for state-heavy, frequently-changing UI: menus, inventories, settings screens,
      HUDs, editor tools. For a handful of static labels and a button, a hand-built scene is
      simpler. It composes fine with the rest of your game — mount reactive roots only where the
      declarative model pays off.
    </Typography>

    {/* ── Authoring ────────────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Authoring
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      How do I mount a component?
    </Typography>
    <Typography variant="body2" paragraph>
      Call <code>ReactiveRoot.create(container, V.fc(MyComponent.render))</code> from a script on
      the <code>Control</code> that should host the UI (typically in <code>_ready()</code>), and
      call <code>unmount()</code> on the returned root in <code>_exit_tree()</code>. The container
      is any Godot <code>Control</code> or <code>Node</code>.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      What do event handlers look like?
    </Typography>
    <Typography variant="body2" paragraph>
      Use React-style camelCase names — <code>onClick</code>, <code>onChange</code>,{' '}
      <code>onSubmit</code>, <code>onFocus</code>, <code>onBlur</code>,{' '}
      <code>onPointerDown</code>. They map to the underlying Godot signals for you. The native{' '}
      <code>on_&lt;signal&gt;</code> form (e.g. <code>on_pressed</code>) also works as an escape
      hatch, but prefer the camelCase aliases in your components.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      Can I use plain GDScript inside a component?
    </Typography>
    <Typography variant="body2" paragraph>
      Yes. The setup code above the <code>return</code> is ordinary GDScript — declare variables,
      call methods, load resources, read game state. Attribute values inside markup accept any
      GDScript expression via the <code>{'{expr}'}</code> braces.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      Why must hooks be called at the top level?
    </Typography>
    <Typography variant="body2" paragraph>
      Hooks (<code>use_state</code>, <code>use_effect</code>, <code>use_signal</code>, …) are
      matched to storage slots by call order. They must be called unconditionally at the top of
      the component — never inside <code>@if</code>, <code>@for</code>, or an event handler — so
      the order is identical on every render. In debug builds{' '}
      <code>RUIConfig.enable_hook_validation</code> detects order mismatches and warns loudly.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      How do I share state across components?
    </Typography>
    <Typography variant="body2" paragraph>
      For local state use <code>use_state</code> / <code>use_reducer</code>. For app-wide state
      use <strong>signals</strong>: create a <code>RUISignal</code> store, then read it in any
      component with the <code>use_signal</code> hook — every subscriber re-renders when the value
      changes, with no prop-drilling. Context (<code>use_context</code>) is available for
      scoped-tree sharing.
    </Typography>

    {/* ── Styling & Assets ─────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Styling &amp; Assets
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      How do I style elements — is there CSS/USS?
    </Typography>
    <Typography variant="body2" paragraph>
      No — Godot has no USS/CSS, and neither does this library. You pass a{' '}
      <code>style</code> Dictionary on any element and <code>RUIStyle</code> maps it onto Godot{' '}
      <code>Control</code> properties, size flags, and <code>Theme</code>/<code>StyleBox</code>{' '}
      overrides (e.g. <code>{'{ "bg_color": Color(0.1,0.1,0.18), "corner_radius": 8, "pad": 12 }'}</code>).
      For shared bundles, register named styles with <code>RUIStyleSheet</code> and reference them
      through the <code>classes</code> prop. See the <em>Styling</em> page.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      How do I load textures, fonts, and themes?
    </Typography>
    <Typography variant="body2" paragraph>
      With Godot&apos;s native <code>preload()</code> / <code>load()</code> on a{' '}
      <code>res://</code> path. The resulting <code>Texture2D</code>, <code>FontFile</code>,{' '}
      <code>Theme</code>, or <code>StyleBox</code> goes straight into markup, an attribute, or a{' '}
      <code>style</code> dict. There is no separate asset importer or registry — see the{' '}
      <em>Assets</em> page.
    </Typography>

    {/* ── Editor & Tooling ─────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Editor &amp; Tooling
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      Do I need any external editor to use the library?
    </Typography>
    <Typography variant="body2" paragraph>
      No. The <code>.guitkx</code> → <code>.gd</code> compiler runs inside the Godot editor as a{' '}
      <code>@tool</code> plugin, so components compile on save regardless of where you type. An
      external editor extension only adds the authoring experience — highlighting, completion,
      diagnostics — on top.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      Which editors have <code>.guitkx</code> language support?
    </Typography>
    <Typography variant="body2" paragraph>
      <strong>VS Code</strong> and <strong>Visual Studio</strong> have extensions with syntax
      highlighting, completion, hover, diagnostics, and formatting, backed by a language server
      that embeds the Rust GDScript analyzer. A full <strong>in-editor Godot addon</strong> with
      the same capabilities is on the roadmap — see the <em>Roadmap</em> page.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      Can I write components without <code>.guitkx</code> at all?
    </Typography>
    <Typography variant="body2" paragraph>
      Yes. <code>.guitkx</code> is a convenience layer that compiles to GDScript. You can author
      the same components by hand against the <code>V</code> factory
      (<code>V.vbox</code>, <code>V.label</code>, <code>V.button</code>, …) in a normal{' '}
      <code>.gd</code> file — no build step, no extension required.
    </Typography>

    {/* ── Troubleshooting ──────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Troubleshooting
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      My UI stopped updating after I changed state — why?
    </Typography>
    <Typography variant="body2" paragraph>
      Re-render is triggered by calling a state setter, not by mutating a value in place. Use the
      setter returned from <code>use_state</code> (<code>state[1].call(new_value)</code>) rather
      than reassigning the underlying variable, and set signal values through the store so
      subscribers are notified.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      I get a hook-order warning in the console — what does it mean?
    </Typography>
    <Typography variant="body2" paragraph>
      A hook was called conditionally, so the call order differs between renders. Move every hook
      to the top level of the component, before any <code>@if</code>/<code>@for</code>/return, so
      they run in the same order every time. This validation is on in debug builds via{' '}
      <code>RUIConfig.enable_hook_validation</code>.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      Godot logs a &quot;maximum render depth exceeded&quot; error — what happened?
    </Typography>
    <Typography variant="body2" paragraph>
      A component updated its own state unconditionally during setup, creating an infinite
      render loop. The reconciler caps re-render restarts (25) and stops the runaway. Move the
      state update into an event handler or a <code>use_effect</code> instead of running it every
      render.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      A style like <code>bg_color</code> has no effect — why?
    </Typography>
    <Typography variant="body2" paragraph>
      The StyleBox keys (<code>bg_color</code>, <code>border_*</code>, <code>corner_radius</code>,{' '}
      <code>pad</code>) need a control with a primary stylebox slot — <code>Panel</code>,{' '}
      <code>Button</code>, <code>LineEdit</code>, <code>ProgressBar</code>. On a bare{' '}
      <code>Label</code> or a plain box container they warn once and do nothing. Wrap the content
      in a <code>Panel</code> to get a background.
    </Typography>
  </Box>
)
