import type { FC } from 'react'
import {
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

const styles = {
  root: { display: 'flex', flexDirection: 'column', gap: 2 },
  section: { mt: 2 },
} as const

type HookSig = {
  name: string
  signature: string
  returns: string
  category: string
  note?: string
}

const hooks: HookSig[] = [
  // State
  {
    name: 'use_state',
    signature: '(initial = null)',
    returns: '[value, set]',
    category: 'State',
    note: 'set accepts a value or func(old) -> new',
  },
  {
    name: 'use_reducer',
    signature: '(reducer: Callable, initial = null)',
    returns: '[state, dispatch]',
    category: 'State',
    note: 'reducer(state, action) -> new_state',
  },
  // Effects
  {
    name: 'use_effect',
    signature: '(effect: Callable, deps = null)',
    returns: 'void',
    category: 'Effects',
    note: 'Passive — runs after commit',
  },
  {
    name: 'use_layout_effect',
    signature: '(effect: Callable, deps = null)',
    returns: 'void',
    category: 'Effects',
    note: 'Synchronous — runs before paint',
  },
  // Memoization
  {
    name: 'use_memo',
    signature: '(factory: Callable, deps: Array = [])',
    returns: 'value',
    category: 'Memoization',
  },
  {
    name: 'use_callback',
    signature: '(cb: Callable, deps: Array = [])',
    returns: 'Callable',
    category: 'Memoization',
    note: 'use_memo(func(): return cb, deps)',
  },
  {
    name: 'use_deferred_value',
    signature: '(value, deps = null)',
    returns: 'deferred_value',
    category: 'Memoization',
    note: 'Lags one frame at low priority',
  },
  // Refs
  {
    name: 'use_ref',
    signature: '(initial = null)',
    returns: '{ "current": initial }',
    category: 'Refs',
    note: 'Stable box; wire to the ref prop for a Control',
  },
  {
    name: 'use_imperative_handle',
    signature: '(factory: Callable, deps: Array = [])',
    returns: 'handle',
    category: 'Refs',
    note: 'Alias of use_memo(factory, deps)',
  },
  // Context
  {
    name: 'Hooks.create_context',
    signature: '(default_value = null, name = "")',
    returns: 'RUIContext',
    category: 'Context',
    note: 'Handle for provide/use_context (React createContext)',
  },
  {
    name: 'use_context',
    signature: '(handle_or_key)',
    returns: 'value | default | null',
    category: 'Context',
    note: 'Handle or String; handle returns its default when unprovided; no hook slot',
  },
  {
    name: 'Hooks.provide_context',
    signature: '(handle_or_key, value)',
    returns: 'void',
    category: 'Context',
    note: 'Handle (recommended) or String; exposes value to this fiber’s subtree',
  },
  // Stable functions
  {
    name: 'use_stable_callback',
    signature: '(cb: Callable)',
    returns: 'Callable',
    category: 'Stable functions',
    note: '0-arg; identity never changes',
  },
  {
    name: 'use_stable_func',
    signature: '(cb: Callable)',
    returns: 'Callable',
    category: 'Stable functions',
    note: 'Alias of use_stable_callback',
  },
  {
    name: 'use_stable_action',
    signature: '(cb: Callable)',
    returns: 'Callable',
    category: 'Stable functions',
    note: '1-arg; identity never changes',
  },
  // Concurrency
  {
    name: 'use_transition',
    signature: '()',
    returns: '[is_pending, start_transition]',
    category: 'Concurrency',
    note: 'Synchronous renderer: is_pending is always false',
  },
  // Signals
  {
    name: 'use_signal',
    signature: '(sig: RUISignal, selector = null, comparer = null)',
    returns: 'value | slice',
    category: 'Signals',
    note: 'Subscribe + re-render; optional selector/comparer',
  },
  {
    name: 'use_signal_key',
    signature: '(key: String, initial = null, selector = null, comparer = null)',
    returns: 'value | slice',
    category: 'Signals',
    note: 'Process-wide keyed signal (RUISignals registry)',
  },
  // Animation / Media
  {
    name: 'use_tween',
    signature: '(ref: Dictionary, property: String, to, duration: float, deps: Array = [])',
    returns: 'void',
    category: 'Animation & Media',
    note: 'Tweens a mounted node property via Godot Tween',
  },
  {
    name: 'use_tween_value',
    signature: '(from, to, duration: float, on_update: Callable, deps: Array = [])',
    returns: 'void',
    category: 'Animation & Media',
    note: 'Drives on_update(value); animate without re-render',
  },
  {
    name: 'use_animate',
    signature: '(ref: Dictionary, tracks: Array, autoplay := true, deps: Array = [])',
    returns: 'void',
    category: 'Animation & Media',
    note: 'Plays property tracks on a node via a Tween',
  },
  {
    name: 'use_sfx',
    signature: '(bus := "Master")',
    returns: 'Callable',
    category: 'Animation & Media',
    note: 'Returns func(stream, volume_db, pitch_scale) one-shot player',
  },
  // Platform
  {
    name: 'use_safe_area',
    signature: '()',
    returns: '{ left, top, right, bottom }',
    category: 'Platform',
    note: 'Device safe-area insets (pixels)',
  },
]

const categories = [...new Set(hooks.map((h) => h.category))]

const categoryColors: Record<string, 'primary' | 'secondary' | 'success' | 'warning' | 'info' | 'error'> = {
  State: 'primary',
  Effects: 'secondary',
  Memoization: 'success',
  Refs: 'info',
  Context: 'warning',
  'Stable functions': 'error',
  Concurrency: 'success',
  Signals: 'primary',
  'Animation & Media': 'secondary',
  Platform: 'info',
}

export const HooksAPIPage: FC = () => (
  <Box sx={styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Hooks API Reference
    </Typography>
    <Typography variant="body1" paragraph>
      Complete reference of every hook exposed by the <code>Hooks</code> class
      (<code>addons/reactive_ui/core/hooks.gd</code>). In <code>.guitkx</code>{' '}
      markup, bare <code>use_*</code> calls are auto-prefixed to{' '}
      <code>Hooks.*</code>; in GDScript they are static methods, e.g.{' '}
      <code>Hooks.use_state(0)</code>. Hooks return plain GDScript values —
      Arrays, Dictionaries, and <code>Callable</code>s — not custom types.
    </Typography>

    {categories.map((cat) => (
      <Box key={cat} sx={styles.section}>
        <Typography variant="h5" component="h2" gutterBottom>
          {cat}
        </Typography>
        <TableContainer component={Paper} variant="outlined">
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell><strong>Hook</strong></TableCell>
                <TableCell><strong>Parameters</strong></TableCell>
                <TableCell><strong>Returns</strong></TableCell>
                <TableCell><strong>Notes</strong></TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {hooks
                .filter((h) => h.category === cat)
                .map((h, i) => (
                  <TableRow key={`${h.name}-${i}`}>
                    <TableCell>
                      <code>{h.name}</code>
                    </TableCell>
                    <TableCell><code>{h.signature}</code></TableCell>
                    <TableCell><code>{h.returns}</code></TableCell>
                    <TableCell>
                      {h.note && (
                        <Chip
                          label={h.note}
                          size="small"
                          color={categoryColors[cat] ?? 'default'}
                          variant="outlined"
                        />
                      )}
                    </TableCell>
                  </TableRow>
                ))}
            </TableBody>
          </Table>
        </TableContainer>
      </Box>
    ))}

    {/* ── Return shapes ────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Return shapes
      </Typography>

      <Typography variant="h6" gutterBottom>
        use_state / use_reducer
      </Typography>
      <CodeBlock
        language="jsx"
        code={`# use_state -> [value, set]
var count = use_state(0)
count[0]                      # current value
count[1].call(5)             # set to a value
count[1].call(func(c): return c + 1)   # functional updater (reads latest)

# use_reducer -> [state, dispatch]
var r = use_reducer(reducer, 0)
r[0]                          # current state
r[1].call("inc")             # dispatch an action`}
      />

      <Typography variant="h6" gutterBottom sx={{ mt: 2 }}>
        use_ref box
      </Typography>
      <CodeBlock
        language="jsx"
        code={`# A stable Dictionary box; mutating .current never re-renders.
var box = use_ref(0)
box["current"] += 1

# Wire the same box to a host element's ref prop to capture its Control.
var node_ref = use_ref(null)   # after commit: node_ref["current"] is the Control`}
      />

      <Typography variant="h6" gutterBottom sx={{ mt: 2 }}>
        use_safe_area insets
      </Typography>
      <CodeBlock
        language="jsx"
        code={`# Dictionary of pixel insets from DisplayServer.get_display_safe_area().
{ "left": int, "top": int, "right": int, "bottom": int }`}
      />
    </Box>

    {/* ── Configuration ────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Configuration
      </Typography>
      <Typography variant="body1" paragraph>
        Runtime validation is controlled by static flags on <code>RUIConfig</code>{' '}
        (both default to <code>OS.is_debug_build()</code>):
      </Typography>
      <CodeBlock
        language="jsx"
        code={`static var RUIConfig.enable_hook_validation     # hook-order mismatch detection
static var RUIConfig.enable_strict_diagnostics  # state-update-during-render warning`}
      />
    </Box>
  </Box>
)
