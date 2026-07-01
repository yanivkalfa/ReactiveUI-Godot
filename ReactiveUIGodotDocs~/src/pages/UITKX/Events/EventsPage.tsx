import type { FC } from 'react'
import {
  Alert,
  Box,
  Chip,
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
import {
  EVENTS_CHANGE_EXAMPLE,
  EVENTS_CLICK_EXAMPLE,
  EVENTS_FOCUS_EXAMPLE,
  EVENTS_GEOMETRY_EXAMPLE,
  EVENTS_KEYBOARD_EXAMPLE,
  EVENTS_NATIVE_EXAMPLE,
  EVENTS_POINTER_EXAMPLE,
  EVENTS_SUBMIT_EXAMPLE,
} from './EventsPage.example'

const styles = {
  root: { display: 'flex', flexDirection: 'column', gap: 2 },
  section: { mt: 2 },
  list: { pl: 2 },
} as const

/* ------------------------------------------------------------------ */
/*  React-name -> Godot-signal mapping (from host_config.gd)          */
/* ------------------------------------------------------------------ */

type EventRow = { prop: string; signal: string; arg: string; note?: string }

const pointerEvents: EventRow[] = [
  { prop: 'onClick', signal: 'pressed', arg: '(none)', note: 'Button family' },
  { prop: 'onPointerDown', signal: 'button_down', arg: '(none)' },
  { prop: 'onPointerUp', signal: 'button_up', arg: '(none)' },
  { prop: 'onPointerEnter', signal: 'mouse_entered', arg: '(none)' },
  { prop: 'onPointerLeave', signal: 'mouse_exited', arg: '(none)' },
]

const focusEvents: EventRow[] = [
  { prop: 'onFocus', signal: 'focus_entered', arg: '(none)' },
  { prop: 'onBlur', signal: 'focus_exited', arg: '(none)' },
]

const inputEvents: EventRow[] = [
  {
    prop: 'onChange',
    signal: 'item_selected · value_changed · text_changed · tab_changed · toggled',
    arg: 'varies',
    note: 'Polymorphic — first matching signal wins',
  },
  { prop: 'onInput', signal: 'text_changed', arg: 'String' },
  { prop: 'onSubmit', signal: 'text_submitted', arg: 'String', note: 'LineEdit — fired on Enter' },
]

const geometryEvents: EventRow[] = [
  { prop: 'onResize', signal: 'resized', arg: '(none)' },
]

const allEvents = [
  { label: 'Pointer / Click', rows: pointerEvents },
  { label: 'Focus', rows: focusEvents },
  { label: 'Change & Input', rows: inputEvents },
  { label: 'Geometry', rows: geometryEvents },
]

/* ------------------------------------------------------------------ */
/*  Main page                                                         */
/* ------------------------------------------------------------------ */

export const EventsPage: FC = () => (
  <Box sx={styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Events &amp; Input Handling
    </Typography>
    <Typography variant="body1" paragraph>
      Event handlers are just props. Under the hood the host config connects each
      handler prop to a Godot <code>signal</code> on the underlying{' '}
      <code>Control</code>, and disconnects it again when the prop is removed or
      the node unmounts — you never touch <code>connect()</code> /{' '}
      <code>disconnect()</code> yourself. There are two spellings, and both are
      first-class:
    </Typography>
    <Box component="ul" sx={styles.list}>
      <li>
        <strong>React camelCase (canonical)</strong> — <code>onClick</code>,{' '}
        <code>onChange</code>, <code>onSubmit</code>, <code>onInput</code>,{' '}
        <code>onFocus</code>, <code>onBlur</code>, <code>onPointerDown</code> /{' '}
        <code>Up</code> / <code>Enter</code> / <code>Leave</code>,{' '}
        <code>onResize</code>. These are mapped to the right Godot signal for
        you, and <code>onChange</code> is polymorphic.
      </li>
      <li>
        <strong>Native escape hatch</strong> — <code>on_&lt;signal&gt;</code>{' '}
        binds verbatim to <em>any</em> signal on the node (e.g.{' '}
        <code>on_gui_input</code>, <code>on_id_pressed</code>,{' '}
        <code>on_item_activated</code>). This reaches signals the aliases do not
        cover.
      </li>
    </Box>

    {/* ── Event handler reference ───────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        React event names and the signals they bind
      </Typography>
      <Typography variant="body1" paragraph>
        Any prop that starts with <code>on</code> followed by an uppercase letter
        (<code>onClick</code>) or with <code>on_</code> (<code>on_gui_input</code>)
        is treated as an event handler. A camelCase name not in the table below
        falls back to a plain <code>camelCase → snake_case</code> transform:{' '}
        <code>onValueChanged</code> binds to the <code>value_changed</code>{' '}
        signal. The handler receives exactly the arguments the Godot signal
        emits.
      </Typography>

      {allEvents.map((group) => (
        <Box key={group.label} sx={{ mb: 2 }}>
          <Typography variant="h6" gutterBottom>
            {group.label}
          </Typography>
          <TableContainer component={Paper} variant="outlined">
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell><strong>Prop</strong></TableCell>
                  <TableCell><strong>Godot signal</strong></TableCell>
                  <TableCell><strong>Handler argument</strong></TableCell>
                  <TableCell><strong>Notes</strong></TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {group.rows.map((r) => (
                  <TableRow key={r.prop}>
                    <TableCell><code>{r.prop}</code></TableCell>
                    <TableCell><code>{r.signal}</code></TableCell>
                    <TableCell><code>{r.arg}</code></TableCell>
                    <TableCell>
                      {r.note && <Chip label={r.note} size="small" />}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TableContainer>
        </Box>
      ))}
    </Box>

    {/* ── Click ─────────────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Click handling
      </Typography>
      <Typography variant="body1" paragraph>
        <code>onClick</code> binds to the <code>pressed</code> signal on the{' '}
        <code>Button</code> family (<code>Button</code>, <code>CheckBox</code>,{' '}
        <code>CheckButton</code>, <code>OptionButton</code>, …). Godot&apos;s{' '}
        <code>pressed</code> signal carries no arguments, so the handler takes
        none — read whatever you need from component state or a ref instead.
      </Typography>
      <CodeBlock language="gdscript" code={EVENTS_CLICK_EXAMPLE} />
    </Box>

    {/* ── onChange (polymorphic) ────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        onChange — one name, many controls
      </Typography>
      <Typography variant="body1" paragraph>
        <code>onChange</code> is <strong>polymorphic</strong>, the way React&apos;s{' '}
        <code>onChange</code> is element-sensitive. The host config tries a
        prioritized list of candidate signals —{' '}
        <code>item_selected</code>, <code>value_changed</code>,{' '}
        <code>text_changed</code>, <code>tab_changed</code>,{' '}
        <code>toggled</code> — and connects the <em>first one the node actually
        has</em>. So the same <code>onChange</code> prop works on a slider, an{' '}
        <code>OptionButton</code>, a <code>CheckButton</code>, a{' '}
        <code>TabBar</code>, or a <code>LineEdit</code>, and your handler receives
        that signal&apos;s native argument (a <code>float</code>, an index, a{' '}
        <code>bool</code>, a <code>String</code>, …).
      </Typography>
      <Alert severity="info" sx={{ mb: 2 }}>
        Order matters: more-specific signals come first, so an{' '}
        <code>OptionButton</code> (which is also a <code>Button</code>, and thus
        also has <code>toggled</code>) still binds <code>onChange</code> to{' '}
        <code>item_selected</code>, not <code>toggled</code>.
      </Alert>
      <CodeBlock language="gdscript" code={EVENTS_CHANGE_EXAMPLE} />
    </Box>

    {/* ── onInput / onSubmit ────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Text input — onInput &amp; onSubmit
      </Typography>
      <Typography variant="body1" paragraph>
        For text controls, <code>onInput</code> is an explicit alias for{' '}
        <code>text_changed</code> (fires on every keystroke, passing the new{' '}
        <code>String</code>), and <code>onSubmit</code> binds to{' '}
        <code>text_submitted</code> (fires when the user presses Enter). Setting{' '}
        <code>text</code> from state every render is safe — the host config
        preserves the caret position on <code>LineEdit</code> /{' '}
        <code>TextEdit</code>, so a controlled input never jumps to column 0
        mid-typing.
      </Typography>
      <CodeBlock language="gdscript" code={EVENTS_SUBMIT_EXAMPLE} />
    </Box>

    {/* ── Pointer ───────────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Pointer events
      </Typography>
      <Typography variant="body1" paragraph>
        <code>onPointerEnter</code> / <code>onPointerLeave</code> map to{' '}
        <code>mouse_entered</code> / <code>mouse_exited</code>, and{' '}
        <code>onPointerDown</code> / <code>onPointerUp</code> map to a{' '}
        <code>BaseButton</code>&apos;s <code>button_down</code> /{' '}
        <code>button_up</code>. These Godot signals pass no arguments. For raw
        pointer position, buttons, or motion, use the native{' '}
        <code>on_gui_input</code> escape hatch and inspect the{' '}
        <code>InputEvent</code> (see below).
      </Typography>
      <CodeBlock language="gdscript" code={EVENTS_POINTER_EXAMPLE} />
    </Box>

    {/* ── Focus ─────────────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Focus tracking
      </Typography>
      <Typography variant="body1" paragraph>
        <code>onFocus</code> / <code>onBlur</code> map to Godot&apos;s{' '}
        <code>focus_entered</code> / <code>focus_exited</code>. Combine them with
        an inline <code>style</code> to give focused controls a distinct look.
      </Typography>
      <CodeBlock language="gdscript" code={EVENTS_FOCUS_EXAMPLE} />
    </Box>

    {/* ── Geometry ──────────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Geometry / resize
      </Typography>
      <Typography variant="body1" paragraph>
        <code>onResize</code> binds to a <code>Control</code>&apos;s{' '}
        <code>resized</code> signal. Like most Godot layout signals it carries no
        payload, so capture the node with a <code>ref</code> and read its{' '}
        <code>size</code> inside the handler.
      </Typography>
      <CodeBlock language="gdscript" code={EVENTS_GEOMETRY_EXAMPLE} />
    </Box>

    {/* ── Keyboard ──────────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Keyboard input
      </Typography>
      <Typography variant="body1" paragraph>
        Godot Controls do not expose per-key signals. Reach the raw input stream
        with the native <code>on_gui_input</code> handler (which binds to the{' '}
        <code>gui_input</code> signal) and match on <code>InputEventKey</code>.
        Make sure the control can take focus (<code>focus_mode</code>) so it
        receives GUI input.
      </Typography>
      <CodeBlock language="gdscript" code={EVENTS_KEYBOARD_EXAMPLE} />
    </Box>

    {/* ── Native escape hatch ───────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        The native <code>on_&lt;signal&gt;</code> escape hatch
      </Typography>
      <Typography variant="body1" paragraph>
        Not every Godot signal has a React alias — and you should not need one.
        Any prop written as <code>on_&lt;signal&gt;</code> connects verbatim to
        that signal on the node, with no alias table and no polymorphism. That is
        how you reach <code>id_pressed</code> on a <code>PopupMenu</code>,{' '}
        <code>item_activated</code> on a <code>Tree</code> or{' '}
        <code>ItemList</code>, <code>gui_input</code> for raw{' '}
        <code>InputEvent</code>s, or any custom signal on your own scene. The
        handler receives exactly the arguments that signal emits.
      </Typography>
      <CodeBlock language="gdscript" code={EVENTS_NATIVE_EXAMPLE} />
      <Alert severity="info" sx={{ mt: 2 }}>
        A handler prop whose value is not a valid <code>Callable</code>, or whose
        resolved signal does not exist on the node, is skipped with a{' '}
        <code>push_warning</code> naming the prop and the signal it tried — so
        typos surface loudly instead of failing silently.
      </Alert>
    </Box>
  </Box>
)
