import type { FC } from 'react'
import {
  Alert,
  Box,
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

const COMPONENT_SAMPLE = `@class_name ButtonShowcase

component ButtonShowcase() {
  var s = use_state(true)
  return (
    <VBox style={ {"separation": 8} }>
      <Label text={ "Enabled: %s" % s[0] } />
      <Button
        text={ "Disable" if s[0] else "Enable" }
        onClick={ func(): s[1].call(func(prev): return not prev) }
      />
      <Button
        text="Secondary action"
        disabled={ not s[0] }
        onClick={ func(): print("Clicked") }
      />
    </VBox>
  )
}`

/* ------------------------------------------------------------------ */
/*  Component catalog                                                  */
/* ------------------------------------------------------------------ */

type CompEntry = { name: string; factory: string; desc: string }

const containers: CompEntry[] = [
  { name: 'Control', factory: 'V.control', desc: 'Universal base container — the div of Godot UI' },
  { name: 'VBox', factory: 'V.vbox', desc: 'Vertical box container (VBoxContainer)' },
  { name: 'HBox', factory: 'V.hbox', desc: 'Horizontal box container (HBoxContainer)' },
  { name: 'Grid', factory: 'V.grid', desc: 'Grid layout container (GridContainer)' },
  { name: 'Margin', factory: 'V.margin', desc: 'Adds padding around children (MarginContainer)' },
  { name: 'Panel', factory: 'V.panel', desc: 'Styled background panel (PanelContainer)' },
  { name: 'Center', factory: 'V.center', desc: 'Centers its child (CenterContainer)' },
  { name: 'Scroll', factory: 'V.scroll', desc: 'Scrollable container (ScrollContainer)' },
  { name: 'Tabs', factory: 'V.tabs', desc: 'Tabbed container (TabContainer)' },
  { name: 'Aspect', factory: 'V.aspect', desc: 'Keeps child at a fixed aspect ratio' },
  { name: 'Foldable', factory: 'V.foldable', desc: 'Collapsible container (FoldableContainer)' },
]

const display: CompEntry[] = [
  { name: 'Label', factory: 'V.label', desc: 'Single- or multi-line text' },
  { name: 'RichText', factory: 'V.rich_text', desc: 'BBCode-formatted text (RichTextLabel)' },
  { name: 'ColorRect', factory: 'V.color_rect', desc: 'Solid colour rectangle' },
  { name: 'TextureRect', factory: 'V.texture_rect', desc: 'Displays a Texture2D' },
  { name: 'NinePatch', factory: 'V.nine_patch', desc: 'Nine-patch texture (NinePatchRect)' },
  { name: 'ProgressBar', factory: 'V.progress_bar', desc: 'Determinate progress indicator' },
]

const buttons: CompEntry[] = [
  { name: 'Button', factory: 'V.button', desc: 'Standard clickable button' },
  { name: 'CheckBox', factory: 'V.check_box', desc: 'Checkbox / boolean toggle' },
  { name: 'CheckButton', factory: 'V.check_button', desc: 'Switch-style boolean toggle' },
  { name: 'OptionButton', factory: 'V.option_button', desc: 'Dropdown / popup selector' },
  { name: 'MenuButton', factory: 'V.menu_button', desc: 'Button that opens a PopupMenu' },
  { name: 'LinkButton', factory: 'V.link_button', desc: 'Text-link-style button' },
  { name: 'TextureButton', factory: 'V.texture_button', desc: 'Button drawn from textures' },
]

const textInputs: CompEntry[] = [
  { name: 'LineEdit', factory: 'V.line_edit', desc: 'Single-line text input' },
  { name: 'TextEdit', factory: 'V.text_edit', desc: 'Multi-line text input' },
  { name: 'CodeEdit', factory: 'V.code_edit', desc: 'Code editor input (syntax-aware)' },
  { name: 'SpinBox', factory: 'V.spin_box', desc: 'Numeric input with stepper' },
]

const pickers: CompEntry[] = [
  { name: 'HSlider', factory: 'V.h_slider', desc: 'Horizontal range slider' },
  { name: 'VSlider', factory: 'V.v_slider', desc: 'Vertical range slider' },
  { name: 'ColorPicker', factory: 'V.color_picker', desc: 'Full colour picker' },
  { name: 'ColorPickerButton', factory: 'V.color_picker_button', desc: 'Button that opens a colour picker' },
]

const dataViews: CompEntry[] = [
  { name: 'ItemList', factory: 'V.item_list', desc: 'Selectable list, reconciled by item identity' },
  { name: 'Tree', factory: 'V.tree', desc: 'Hierarchical tree (item-model control)' },
  { name: 'TabBar', factory: 'V.tab_bar', desc: 'Standalone tab strip (item-model control)' },
  { name: 'MenuBar', factory: 'V.menu_bar', desc: 'Application-style menu bar' },
]

const media: CompEntry[] = [
  { name: 'Audio', factory: 'V.audio', desc: 'AudioStreamPlayer wrapper' },
  { name: 'Video', factory: 'V.video', desc: 'VideoStreamPlayer wrapper' },
]

const framework: CompEntry[] = [
  { name: 'Fragment', factory: 'V.fragment', desc: 'Invisible grouping wrapper (no host node)' },
  { name: 'Portal', factory: 'V.portal', desc: 'Renders children under an external Node target' },
  { name: 'Suspense', factory: 'V.suspense', desc: 'Shows a fallback while async content loads' },
  { name: 'ErrorBoundary', factory: 'V.error_boundary', desc: 'Shows a fallback on an imperative toggle' },
  { name: 'Memo', factory: 'V.memo', desc: 'Memoized function component (skips unchanged renders)' },
]

const router: CompEntry[] = [
  { name: 'Router', factory: 'V.router', desc: 'Provides router context to its subtree' },
  { name: 'Routes', factory: 'V.routes', desc: 'Ranked first-match route switch' },
  { name: 'Route', factory: 'V.route', desc: 'A single route definition (path + element)' },
  { name: 'Outlet', factory: 'V.outlet', desc: 'Renders the matched nested route' },
  { name: 'NavLink', factory: 'V.nav_link', desc: 'Active-aware navigation link' },
  { name: 'Link', factory: 'V.link', desc: 'Navigation button' },
]

const allCategories = [
  { label: 'Containers & Layout', rows: containers },
  { label: 'Display', rows: display },
  { label: 'Buttons & Toggles', rows: buttons },
  { label: 'Text Input', rows: textInputs },
  { label: 'Pickers & Sliders', rows: pickers },
  { label: 'Item-Model Controls', rows: dataViews },
  { label: 'Media', rows: media },
  { label: 'Framework Components', rows: framework },
  { label: 'Router', rows: router },
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
  { name: 'on<Signal>', type: 'Callable', desc: 'Event handler — camelCase (onClick, onChange, …) or native on_<signal>' },
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
      <code>.guitkx</code> markup. Use intrinsic tag names for built-in controls and PascalCase names
      for your own components. Each host tag has a matching <code>V.*</code> factory for authoring in
      plain GDScript. For the full per-element property reference, see the data-driven{' '}
      <strong>Components</strong> reference; this page is the conceptual overview.
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
                  <TableCell><code>{`<${c.name}>`}</code></TableCell>
                  <TableCell>{c.desc}</TableCell>
                  <TableCell><code>{c.factory}</code></TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </TableContainer>
      </Box>
    ))}

    <Alert severity="info" sx={{ mt: 2 }}>
      Any Godot control not listed above is one <code>V.h("SomeControl", props)</code> away — the
      generic host factory creates any <code>Control</code> subclass by its Godot class name.
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
        Event handlers use React-parity camelCase (<code>onClick</code>, <code>onChange</code>,{' '}
        <code>onSubmit</code>, <code>onFocus</code>, …) and map to Godot signals. See the{' '}
        <strong>Events &amp; Input Handling</strong> page for the complete mapping.
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
          <ListItemText primary="Each .guitkx file contains exactly one component; the @class_name becomes the generated GDScript class." />
        </ListItem>
      </List>
    </Box>
  </Box>
)
