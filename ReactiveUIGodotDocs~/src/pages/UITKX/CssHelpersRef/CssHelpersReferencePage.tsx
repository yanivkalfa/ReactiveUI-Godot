import type { FC } from 'react'
import {
  Alert,
  Box,
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

const styles = {
  root: { display: 'flex', flexDirection: 'column', gap: 2 },
  section: { mt: 2 },
} as const

type StyleRow = { name: string; mapsTo: string; notes: string }

/* ------------------------------------------------------------------ */
/*  Data tables — mirrored from RUIStyle (core/style.gd) + schema.ts   */
/*  Godot has no USS/CSS. Styling = Control props + size flags         */
/*  (layout) and Theme overrides / StyleBox (paint). The `style` dict  */
/*  maps onto all of that.                                             */
/* ------------------------------------------------------------------ */

const styleBoxKeys: StyleRow[] = [
  { name: 'bg_color', mapsTo: 'StyleBoxFlat.bg_color', notes: 'Background fill (Color)' },
  { name: 'border_color', mapsTo: 'StyleBoxFlat.border_color', notes: 'Border color (Color)' },
  { name: 'border_width', mapsTo: 'border_width_* (all sides)', notes: 'int, all four sides' },
  { name: 'corner_radius', mapsTo: 'corner_radius_* (all corners)', notes: 'int, all four corners' },
  { name: 'pad', mapsTo: 'content_margin_* (all sides)', notes: 'float, inner padding' },
]

const stateSlots: StyleRow[] = [
  { name: 'hover', mapsTo: 'hover StyleBox slot', notes: 'Nested style dict → StyleBoxFlat' },
  { name: 'pressed', mapsTo: 'pressed StyleBox slot', notes: 'Nested style dict → StyleBoxFlat' },
  { name: 'focus', mapsTo: 'focus StyleBox slot', notes: 'Nested style dict → StyleBoxFlat' },
  { name: 'disabled', mapsTo: 'disabled StyleBox slot', notes: 'Nested style dict → StyleBoxFlat' },
  { name: 'read_only', mapsTo: 'read_only StyleBox slot', notes: 'LineEdit/TextEdit' },
]

const themeChannels: StyleRow[] = [
  { name: 'colors', mapsTo: 'add_theme_color_override', notes: '{ name: Color }' },
  { name: 'constants', mapsTo: 'add_theme_constant_override', notes: '{ name: int }' },
  { name: 'fonts', mapsTo: 'add_theme_font_override', notes: '{ name: Font }' },
  { name: 'font_sizes', mapsTo: 'add_theme_font_size_override', notes: '{ name: int }' },
  { name: 'icons', mapsTo: 'add_theme_icon_override', notes: '{ name: Texture2D }' },
  { name: 'styleboxes', mapsTo: 'add_theme_stylebox_override', notes: '{ name: StyleBox }' },
]

const sizing: StyleRow[] = [
  { name: 'min_width', mapsTo: 'custom_minimum_size.x', notes: 'float' },
  { name: 'min_height', mapsTo: 'custom_minimum_size.y', notes: 'float' },
  { name: 'min_size', mapsTo: 'custom_minimum_size', notes: 'Vector2' },
  { name: 'fill', mapsTo: 'PRESET_FULL_RECT anchors', notes: 'bool — fill parent (top-level mount)' },
  { name: 'expand_h', mapsTo: 'size_flags_horizontal', notes: 'bool → SIZE_EXPAND_FILL' },
  { name: 'expand_v', mapsTo: 'size_flags_vertical', notes: 'bool → SIZE_EXPAND_FILL' },
  { name: 'grow_h / h_align', mapsTo: 'size_flags_horizontal', notes: 'int or "fill"/"expand"/"center"/"begin"/"end"' },
  { name: 'grow_v / v_align', mapsTo: 'size_flags_vertical', notes: 'int or "fill"/"expand"/"center"/"begin"/"end"' },
]

const transform: StyleRow[] = [
  { name: 'modulate', mapsTo: 'Control.modulate', notes: 'Color (tints children too)' },
  { name: 'self_modulate', mapsTo: 'Control.self_modulate', notes: 'Color (self only)' },
  { name: 'rotation', mapsTo: 'Control.rotation', notes: 'float degrees (converted to radians)' },
  { name: 'scale', mapsTo: 'Control.scale', notes: 'Vector2' },
  { name: 'pivot', mapsTo: 'pivot_offset', notes: 'Vector2' },
  { name: 'z_index', mapsTo: 'Control.z_index', notes: 'int' },
]

const visibility: StyleRow[] = [
  { name: 'visible', mapsTo: 'Control.visible', notes: 'bool' },
  { name: 'clip', mapsTo: 'clip_contents', notes: 'bool' },
  { name: 'mouse_filter', mapsTo: 'mouse_filter', notes: 'int or "stop"/"pass"/"ignore"' },
  { name: 'tooltip', mapsTo: 'tooltip_text', notes: 'String' },
]

const text: StyleRow[] = [
  { name: 'color / font_color', mapsTo: 'font_color theme override', notes: 'Color' },
  { name: 'font', mapsTo: 'font theme override', notes: 'Font' },
  { name: 'font_size', mapsTo: 'font_size theme override', notes: 'int' },
  { name: 'outline_color', mapsTo: 'font_outline_color override', notes: 'Color' },
  { name: 'outline_size', mapsTo: 'outline_size theme constant', notes: 'int' },
]

const spacing: StyleRow[] = [
  { name: 'separation', mapsTo: 'separation theme constant', notes: 'int (box containers)' },
  { name: 'h_separation', mapsTo: 'h_separation theme constant', notes: 'int (grid/flow)' },
  { name: 'v_separation', mapsTo: 'v_separation theme constant', notes: 'int (grid/flow)' },
  { name: 'margin', mapsTo: 'margin_* theme constants', notes: 'int (MarginContainer, all sides)' },
]

const allGroups: { label: string; rows: StyleRow[] }[] = [
  { label: 'StyleBox (combined into one StyleBoxFlat)', rows: styleBoxKeys },
  { label: 'Per-state StyleBox slots', rows: stateSlots },
  { label: 'Generic theme channels (reach any theme item)', rows: themeChannels },
  { label: 'Sizing & layout (size flags)', rows: sizing },
  { label: 'Transform', rows: transform },
  { label: 'Visibility & input', rows: visibility },
  { label: 'Text & font', rows: text },
  { label: 'Container spacing', rows: spacing },
]

/* ------------------------------------------------------------------ */
/*  Component                                                         */
/* ------------------------------------------------------------------ */

const StyleTable: FC<{ rows: StyleRow[] }> = ({ rows }) => (
  <TableContainer component={Paper} variant="outlined" sx={{ mb: 2 }}>
    <Table size="small">
      <TableHead>
        <TableRow>
          <TableCell><strong>Key</strong></TableCell>
          <TableCell><strong>Maps to</strong></TableCell>
          <TableCell><strong>Notes</strong></TableCell>
        </TableRow>
      </TableHead>
      <TableBody>
        {rows.map((r) => (
          <TableRow key={r.name}>
            <TableCell><code>{r.name}</code></TableCell>
            <TableCell><code>{r.mapsTo}</code></TableCell>
            <TableCell>{r.notes}</TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  </TableContainer>
)

export const CssHelpersReferencePage: FC = () => (
  <Box sx={styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Style Helpers Reference
    </Typography>
    <Typography variant="body1" paragraph>
      Godot has no USS/CSS, so there is no CssHelpers class. Instead, the{' '}
      <code>style</code> prop on any host element takes a plain{' '}
      <strong>Dictionary</strong>, and <code>RUIStyle</code>{' '}
      (<code>core/style.gd</code>) maps its keys onto Godot Control properties,
      size flags, Theme overrides, and StyleBox. This page is the vocabulary of
      that dictionary.
    </Typography>
    <CodeBlock language="jsx" code={`# Apply an inline style dict on any host element:
<Panel style={ {
  "bg_color": Color("#1e1e1e"),
  "corner_radius": 8,
  "border_width": 1,
  "border_color": Color(0.3, 0.3, 0.35),
  "pad": 12,
  "min_size": Vector2(240, 120),
} } />

# Per-state slots use nested dicts; theme channels reach any item by name:
<Button text="OK" style={ {
  "bg_color": Color(0.2, 0.4, 0.9),
  "corner_radius": 6,
  "hover": { "bg_color": Color(0.3, 0.5, 1.0) },
  "pressed": { "bg_color": Color(0.15, 0.3, 0.7) },
  "colors": { "font_color": Color.WHITE },
} } />`} />

    <Alert severity="info" sx={{ mt: 1 }}>
      Anything not listed here (anchors, offsets, <code>custom_minimum_size</code>,
      etc.) is a plain Control property — set it as a normal prop on the element,
      not inside <code>style</code>. Reusable named style sets live in an{' '}
      <code>RUIStyleSheet</code> and are attached via the <code>classes</code>{' '}
      prop (inline <code>style</code> wins over classes).
    </Alert>

    <Typography variant="body1" sx={{ mt: 2 }}>
      Three layers of coverage, least to most explicit:
    </Typography>

    {allGroups.map((group) => (
      <Box key={group.label} sx={styles.section}>
        <Typography variant="h6" gutterBottom>
          {group.label}
        </Typography>
        <StyleTable rows={group.rows} />
      </Box>
    ))}

    <Alert severity="info" sx={{ mt: 2 }}>
      The StyleBox keys (<code>bg_color</code>, <code>border_*</code>,{' '}
      <code>corner_radius</code>, <code>pad</code>) are combined into a single{' '}
      <code>StyleBoxFlat</code> applied to the control&apos;s primary slot
      (Panel: <code>panel</code>, Button: <code>normal</code>, LineEdit:{' '}
      <code>normal</code>, ProgressBar: <code>background</code>). Requesting them
      on a control with no stylebox slot (e.g. a bare <code>Label</code>) warns
      once. When a shorthand and a theme channel don&apos;t cover what you need,
      the generic <code>styleboxes</code> channel reaches any theme StyleBox by
      name for 100% coverage.
    </Alert>
  </Box>
)
