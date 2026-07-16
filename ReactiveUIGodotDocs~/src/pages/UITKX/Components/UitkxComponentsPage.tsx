import type { FC } from 'react'
import {
  Alert,
  Box,
  Chip,
  List,
  ListItem,
  ListItemText,
  Paper,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Typography,
} from '@mui/material'
import { CodeBlock } from '../../../components/CodeBlock/CodeBlock'
import Styles from '../../Components/ComponentPage.style'

const COMPONENT_SAMPLE = `component ButtonShowcase() {
  var s = useState(true)
  return (
    <VBoxContainer style={ {"separation": 8} }>
      <Label text={ "Enabled: %s" % s[0] } />
      <Button
        text={ "Disable" if s[0] else "Enable" }
        onPressed={ func(): s[1].call(func(prev): return not prev) }
      />
      <Button
        text="Secondary action"
        disabled={ not s[0] }
        onPressed={ func(): print("Clicked") }
      />
    </VBoxContainer>
  )
}`

// V.*-only primitives (no markup tag) are reached via an embedded { expr } inside an
// otherwise-normal .guitkx component — never as a fictitious <Tag>.
const FRAMEWORK_EXAMPLE = `component App {
  var ready = useState(false)
  return (
    <VBoxContainer>
      { V.suspense(
          { "fallback": V.fc(Spinner.render), "is_ready": useCallback(func(): return ready[0], [ready[0]]) },
          [ V.fc(Content.render) ]) }
    </VBoxContainer>
  )
}`

/* ------------------------------------------------------------------ */
/*  Component catalog                                                  */
/* ------------------------------------------------------------------ */

// `hasTag` defaults to true (a real `<Name>` markup element backed by host_tags in
// vocabulary.json). Set it to `false` for a V.* factory that has NO corresponding markup
// tag — it can only be reached via an embedded `{ V.foo(...) }` expression inside a .guitkx
// component's setup/markup, never written as `<Name>`.
type CompEntry = { name: string; factory: string; desc: string; hasTag?: false }

const containers: CompEntry[] = [
  { name: 'Control', factory: 'V.Control', desc: 'Universal base container — the div of Godot UI' },
  { name: 'VBoxContainer', factory: 'V.VBoxContainer', desc: 'Vertical box container' },
  { name: 'HBoxContainer', factory: 'V.HBoxContainer', desc: 'Horizontal box container' },
  { name: 'BoxContainer', factory: 'V.BoxContainer', desc: 'Box container with a vertical flag (new in 0.9.0)' },
  { name: 'GridContainer', factory: 'V.GridContainer', desc: 'Grid layout container' },
  { name: 'MarginContainer', factory: 'V.MarginContainer', desc: 'Adds padding around children' },
  { name: 'PanelContainer', factory: 'V.PanelContainer', desc: 'Container with a themed panel background' },
  { name: 'CenterContainer', factory: 'V.CenterContainer', desc: 'Centers its child' },
  { name: 'ScrollContainer', factory: 'V.ScrollContainer', desc: 'Scrollable container' },
  { name: 'FlowContainer', factory: 'V.FlowContainer', desc: 'Wrapping flow layout — also HFlowContainer / VFlowContainer (new in 0.9.0)' },
  { name: 'TabContainer', factory: 'V.TabContainer', desc: 'Tabbed container' },
  { name: 'SplitContainer', factory: 'V.SplitContainer', desc: 'Draggable split — also HSplitContainer / VSplitContainer (new in 0.9.0)' },
  { name: 'AspectRatioContainer', factory: 'V.AspectRatioContainer', desc: 'Keeps child at a fixed aspect ratio' },
  { name: 'FoldableContainer', factory: 'V.FoldableContainer', desc: 'Collapsible container' },
  { name: 'SubViewportContainer', factory: 'V.SubViewportContainer', desc: 'Displays a SubViewport (new in 0.9.0)' },
]

const display: CompEntry[] = [
  { name: 'Label', factory: 'V.Label', desc: 'Single- or multi-line text' },
  { name: 'RichTextLabel', factory: 'V.RichTextLabel', desc: 'BBCode-formatted text' },
  { name: 'Panel', factory: 'V.Panel', desc: 'Plain themed rectangle — no layout (new in 0.9.0; the container is PanelContainer)' },
  { name: 'ColorRect', factory: 'V.ColorRect', desc: 'Solid colour rectangle' },
  { name: 'TextureRect', factory: 'V.TextureRect', desc: 'Displays a Texture2D' },
  { name: 'NinePatchRect', factory: 'V.NinePatchRect', desc: 'Nine-patch texture' },
  { name: 'ReferenceRect', factory: 'V.ReferenceRect', desc: 'Debug outline rectangle (new in 0.9.0)' },
  { name: 'ProgressBar', factory: 'V.ProgressBar', desc: 'Determinate progress indicator' },
]

const buttons: CompEntry[] = [
  { name: 'Button', factory: 'V.Button', desc: 'Standard clickable button' },
  { name: 'CheckBox', factory: 'V.CheckBox', desc: 'Checkbox / boolean toggle' },
  { name: 'CheckButton', factory: 'V.CheckButton', desc: 'Switch-style boolean toggle' },
  { name: 'OptionButton', factory: 'V.OptionButton', desc: 'Dropdown / popup selector' },
  { name: 'MenuButton', factory: 'V.MenuButton', desc: 'Button that opens a PopupMenu' },
  { name: 'LinkButton', factory: 'V.LinkButton', desc: 'Text-link-style button' },
  { name: 'TextureButton', factory: 'V.TextureButton', desc: 'Button drawn from textures' },
]

const textInputs: CompEntry[] = [
  { name: 'LineEdit', factory: 'V.LineEdit', desc: 'Single-line text input' },
  { name: 'TextEdit', factory: 'V.TextEdit', desc: 'Multi-line text input' },
  { name: 'CodeEdit', factory: 'V.CodeEdit', desc: 'Code editor input (syntax-aware)' },
  { name: 'SpinBox', factory: 'V.SpinBox', desc: 'Numeric input with stepper' },
]

const pickers: CompEntry[] = [
  { name: 'HSlider', factory: 'V.HSlider', desc: 'Horizontal range slider' },
  { name: 'VSlider', factory: 'V.VSlider', desc: 'Vertical range slider' },
  { name: 'HScrollBar', factory: 'V.HScrollBar', desc: 'Horizontal scroll bar (new in 0.9.0)' },
  { name: 'VScrollBar', factory: 'V.VScrollBar', desc: 'Vertical scroll bar (new in 0.9.0)' },
  { name: 'ColorPicker', factory: 'V.ColorPicker', desc: 'Full colour picker' },
  { name: 'ColorPickerButton', factory: 'V.ColorPickerButton', desc: 'Button that opens a colour picker' },
  { name: 'VirtualJoystick', factory: 'V.VirtualJoystick', desc: 'On-screen touch joystick (new in 0.9.0)' },
]

const dataViews: CompEntry[] = [
  { name: 'ItemList', factory: 'V.ItemList', desc: 'Selectable list, reconciled by item identity' },
  { name: 'Tree', factory: 'V.Tree', desc: 'Hierarchical tree (item-model control)' },
  { name: 'TabBar', factory: 'V.TabBar', desc: 'Standalone tab strip (item-model control)' },
  { name: 'MenuBar', factory: 'V.MenuBar', desc: 'Application-style menu bar' },
]

const media: CompEntry[] = [
  { name: 'AudioStreamPlayer', factory: 'V.AudioStreamPlayer', desc: 'Plays an AudioStream' },
  { name: 'VideoStreamPlayer', factory: 'V.VideoStreamPlayer', desc: 'Plays a VideoStream' },
]

const framework: CompEntry[] = [
  { name: 'Fragment', factory: 'V.fragment', desc: 'Invisible grouping wrapper (no host node)' },
  { name: 'Portal', factory: 'V.portal', desc: 'Renders children under an external Node target', hasTag: false },
  { name: 'Suspense', factory: 'V.suspense', desc: 'Shows a fallback while async content loads', hasTag: false },
  { name: 'ErrorBoundary', factory: 'V.error_boundary', desc: 'Shows a fallback on an imperative toggle', hasTag: false },
  { name: 'Memo', factory: 'V.memo', desc: 'Memoized function component (skips unchanged renders)', hasTag: false },
]

const router: CompEntry[] = [
  { name: 'Router', factory: 'V.router', desc: 'Provides router context to its subtree', hasTag: false },
  { name: 'Routes', factory: 'V.routes', desc: 'Ranked first-match route switch', hasTag: false },
  { name: 'Route', factory: 'V.route', desc: 'A single route definition (path + element)', hasTag: false },
  { name: 'Outlet', factory: 'V.outlet', desc: 'Renders the matched nested route', hasTag: false },
  { name: 'NavLink', factory: 'V.nav_link', desc: 'Active-aware navigation link', hasTag: false },
  { name: 'Link', factory: 'V.link', desc: 'Navigation button', hasTag: false },
]

type Category = { label: string; rows: CompEntry[]; note?: string; example?: string }

const allCategories: Category[] = [
  { label: 'Containers & Layout', rows: containers },
  { label: 'Display', rows: display },
  { label: 'Buttons & Toggles', rows: buttons },
  { label: 'Text Input', rows: textInputs },
  { label: 'Pickers & Sliders', rows: pickers },
  { label: 'Item-Model Controls', rows: dataViews },
  {
    label: 'Media',
    rows: media,
    note:
      'AudioStreamPlayer and VideoStreamPlayer wrap Godot scene nodes — use the tag ' +
      '(<AudioStreamPlayer stream={ clip } autoplay />) or the factory from an embedded ' +
      'expression, e.g. { V.AudioStreamPlayer({ "stream": clip, "autoplay": true }) }.',
  },
  {
    label: 'Framework Components',
    rows: framework,
    note:
      'Fragment is a real markup element (<Fragment>). Portal, Suspense, ErrorBoundary, and Memo are ' +
      'NOT — each is reached by calling its V.* factory from an embedded { expr } inside a .guitkx ' +
      "component's markup, for example:",
    example: FRAMEWORK_EXAMPLE,
  },
  {
    label: 'Router',
    rows: router,
    note:
      'None of the router primitives have a markup tag — build the provider and route table with ' +
      'V.router(...), V.routes(...), V.route(...), V.outlet(...), V.navigate(...), V.nav_link(...), ' +
      'and V.link(...) from an embedded expression. See the Router page for a complete example.',
  },
]

/* ------------------------------------------------------------------ */
/*  Universal structural attributes                                    */
/* ------------------------------------------------------------------ */

type PropRow = { name: string; type: string; desc: string }

const baseProps: PropRow[] = [
  { name: 'key', type: 'Variant', desc: 'Stable identity for keyed reconciliation' },
  { name: 'ref', type: 'Callable | Dictionary', desc: 'Receives the live Godot node (Callable(node) or a { "current": … } box)' },
  { name: 'style', type: 'Dictionary', desc: 'Inline style dictionary (RUIStyle shorthands + theme channels)' },
  { name: 'classes', type: 'String | Array', desc: 'Named style-set class names registered with RUIStyleSheet' },
  { name: '<any node property>', type: 'Variant', desc: 'Any property of the underlying Control (text, disabled, editable, …) is set directly' },
  { name: 'on<Signal>', type: 'Callable', desc: 'Event handler — on + PascalCase(signal name) (onPressed, onValueChanged, …) or native on_<signal>' },
]

/* ------------------------------------------------------------------ */
/*  Page                                                               */
/* ------------------------------------------------------------------ */

export const UitkxComponentsPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Components Overview
    </Typography>
    <Typography variant="body1" paragraph>
      Reactive UI wraps every Godot <code>Control</code> as a declarative host element you can use in{' '}
      <code>.guitkx</code> markup. From 0.9.0 the element names are <strong>1:1 the official Godot
      class names</strong> — <code>{'<VBoxContainer>'}</code>, <code>{'<Label>'}</code>,{' '}
      <code>{'<PanelContainer>'}</code> — and each curated element has a matching{' '}
      <code>V.ClassName</code> factory for authoring in plain GDScript. Beyond the curated set,{' '}
      <strong>any instantiable Godot <code>Node</code> class is a valid tag</strong> (an open
      vocabulary resolved via <code>ClassDB</code>) — <code>{'<GraphEdit />'}</code> just works. Use
      distinct PascalCase names for your own components. For the full per-element property
      reference, see the data-driven <strong>Components</strong> reference; this page is the
      conceptual overview.
    </Typography>

    <CodeBlock language="jsx" code={COMPONENT_SAMPLE} />

    {/* ── Categorized component catalog ────────────────────────── */}
    {allCategories.map((cat) => (
      <Box key={cat.label} sx={{ mt: 2 }}>
        <Typography variant="h5" component="h2" gutterBottom>
          {cat.label}
        </Typography>
        <TableContainer component={Paper} variant="outlined">
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell><strong>Element</strong></TableCell>
                <TableCell><strong>Description</strong></TableCell>
                <TableCell><strong>Factory</strong></TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {cat.rows.map((c) => (
                <TableRow key={c.name}>
                  <TableCell>
                    {c.hasTag === false ? (
                      <>
                        <code>{c.name}</code>{' '}
                        <Chip label="V.* only — no markup tag" size="small" variant="outlined" />
                      </>
                    ) : (
                      <code>{`<${c.name}>`}</code>
                    )}
                  </TableCell>
                  <TableCell>{c.desc}</TableCell>
                  <TableCell><code>{c.factory}</code></TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </TableContainer>
        {cat.note && (
          <Alert severity="info" sx={{ mt: 1 }}>
            {cat.note}
          </Alert>
        )}
        {cat.example && (
          <Box sx={{ mt: 1 }}>
            <CodeBlock language="jsx" code={cat.example} />
          </Box>
        )}
      </Box>
    ))}

    <Alert severity="info" sx={{ mt: 2 }}>
      The catalog above is the <em>curated</em> set (each with a <code>V.ClassName</code> factory).
      Any other instantiable Godot <code>Node</code> class is a valid tag too —{' '}
      <code>{'<GraphEdit />'}</code>, <code>{'<TextureProgressBar />'}</code>, … — resolved through{' '}
      <code>ClassDB</code> at runtime, or one <code>V.h("SomeControl", props)</code> away in plain
      GDScript.
    </Alert>

    {/* ── Universal structural attributes ──────────────────────── */}
    <Box sx={{ mt: 3 }}>
      <Typography variant="h5" component="h2" gutterBottom>
        Universal attributes
      </Typography>
      <Typography variant="body1" paragraph>
        Every host element accepts these attributes in addition to the properties of its underlying
        Godot node:
      </Typography>
      <TableContainer component={Paper} variant="outlined">
        <Table size="small">
          <TableHead>
            <TableRow>
              <TableCell><strong>Attribute</strong></TableCell>
              <TableCell><strong>Type</strong></TableCell>
              <TableCell><strong>Description</strong></TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {baseProps.map((p) => (
              <TableRow key={p.name}>
                <TableCell><code>{p.name}</code></TableCell>
                <TableCell><code>{p.type}</code></TableCell>
                <TableCell>{p.desc}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </TableContainer>
      <Alert severity="info" sx={{ mt: 1 }}>
        Event handler names are <code>on</code> + PascalCase(signal name) — <code>onPressed</code>{' '}
        → <code>pressed</code>, <code>onTextChanged</code> → <code>text_changed</code>,{' '}
        <code>onItemSelected</code> → <code>item_selected</code> — and the rule works for every
        signal of every node. See the <strong>Events &amp; Input Handling</strong> page.
      </Alert>
    </Box>

    {/* ── Authoring guidelines ─────────────────────────────────── */}
    <Box sx={{ mt: 3 }}>
      <Typography variant="h5" component="h2" gutterBottom>
        Authoring guidelines
      </Typography>
      <List>
        <ListItem disablePadding>
          <ListItemText primary="Prefer direct tag attributes over hand-building props dictionaries when authoring .guitkx." />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary="Keep setup code small and close to the returned markup tree." />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary="Custom component names must be PascalCase and must not collide with built-in tag names." />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary="A .guitkx file can hold one or more declarations; the generated GDScript class name is inferred from them (an @class_name directive can override it, but rarely needs to)." />
        </ListItem>
      </List>
    </Box>
  </Box>
)
