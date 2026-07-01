import type { FC } from 'react'
import { useState } from 'react'
import {
  Accordion,
  AccordionDetails,
  AccordionSummary,
  Box,
  Chip,
  Link,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Typography,
} from '@mui/material'
import ExpandMoreIcon from '@mui/icons-material/ExpandMore'
import { CodeBlock } from '../../components/CodeBlock/CodeBlock'
import { getHostElement, type HostElement, type HostProp, type HostSignal } from '../../hostElements'
import { HOST_CONTENT } from '../../hostContent'
import Styles from './ComponentPage.style'

// ---------------------------------------------------------------------------
// React-event → Godot-signal resolution (mirrors the LSP binding logic)
// ---------------------------------------------------------------------------

/**
 * Resolve which Godot signal a React-parity event name binds to on a given
 * element. `onChange` is polymorphic: it picks the first candidate signal the
 * element actually exposes. Returns the matched signal, or undefined when the
 * element has no such signal (a defensive case — curated `events` shouldn't hit it).
 */
const resolveSignal = (event: string, signals: HostSignal[]): HostSignal | undefined => {
  const has = (name: string) => signals.find((s) => s.name === name)
  switch (event) {
    case 'onClick':
      return has('pressed')
    case 'onChange': {
      // First of these the element carries wins (item lists, ranges, text, tabs, toggles).
      const candidates = ['item_selected', 'value_changed', 'text_changed', 'tab_changed', 'toggled']
      for (const name of candidates) {
        const s = has(name)
        if (s) return s
      }
      return undefined
    }
    case 'onSubmit':
      return has('text_submitted')
    case 'onPointerDown':
      return has('button_down')
    case 'onPointerUp':
      return has('button_up')
    case 'onFocus':
      return has('focus_entered')
    case 'onBlur':
      return has('focus_exited')
    case 'onPointerEnter':
      return has('mouse_entered')
    case 'onPointerLeave':
      return has('mouse_exited')
    case 'onResize':
      return has('resized')
    default:
      return undefined
  }
}

/** Format a signal's argument list, e.g. `(int index)` or `()`. */
const formatArgs = (signal: HostSignal | undefined): string => {
  if (!signal || signal.args.length === 0) return '()'
  return `(${signal.args.map((a) => `${a.type} ${a.name}`).join(', ')})`
}

// ---------------------------------------------------------------------------
// Sub-sections
// ---------------------------------------------------------------------------

const EventsTable: FC<{ element: HostElement }> = ({ element }) => (
  <TableContainer>
    <Table size="small">
      <TableHead>
        <TableRow>
          <TableCell sx={{ fontWeight: 700 }}>Event</TableCell>
          <TableCell sx={{ fontWeight: 700 }}>Godot signal</TableCell>
          <TableCell sx={{ fontWeight: 700 }}>Arguments</TableCell>
        </TableRow>
      </TableHead>
      <TableBody>
        {element.events.map((event) => {
          const signal = resolveSignal(event, element.signals)
          return (
            <TableRow key={event}>
              <TableCell>
                <code>{event}</code>
              </TableCell>
              <TableCell>
                {signal ? <code>{signal.name}</code> : <Typography variant="body2" color="text.secondary">—</Typography>}
              </TableCell>
              <TableCell>
                <code>{formatArgs(signal)}</code>
              </TableCell>
            </TableRow>
          )
        })}
      </TableBody>
    </Table>
  </TableContainer>
)

const PropsTable: FC<{ entries: HostProp[] }> = ({ entries }) => (
  <TableContainer>
    <Table size="small">
      <TableHead>
        <TableRow>
          <TableCell sx={{ fontWeight: 700 }}>Property</TableCell>
          <TableCell sx={{ fontWeight: 700 }}>Type</TableCell>
        </TableRow>
      </TableHead>
      <TableBody>
        {entries.map((p) => (
          <TableRow key={p.name}>
            <TableCell>
              <code>{p.name}</code>
            </TableCell>
            <TableCell>
              {p.enum ? (
                <Box sx={{ display: 'flex', flexDirection: 'column', gap: 0.5 }}>
                  <code>{p.type}</code>
                  <Typography variant="caption" color="text.secondary">
                    enum: {p.enum}
                  </Typography>
                </Box>
              ) : (
                <code>{p.type}</code>
              )}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  </TableContainer>
)

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export const ComponentPage: FC<{ tag: string }> = ({ tag }) => {
  const element = getHostElement(tag)
  const content = HOST_CONTENT[tag]
  const [baseOpen, setBaseOpen] = useState(false)

  if (!element) {
    return (
      <Box sx={Styles.root}>
        <Typography variant="h4" component="h1" gutterBottom>
          {tag}
        </Typography>
        <Typography variant="body1">Unknown host element.</Typography>
      </Box>
    )
  }

  const ownProps = element.props.filter((p) => !p.inherited)
  const inheritedProps = element.props.filter((p) => p.inherited)
  const godotClassUrl = `https://docs.godotengine.org/en/stable/classes/class_${element.godotClass.toLowerCase()}.html`

  return (
    <Box sx={Styles.root}>
      <Box sx={{ display: 'flex', alignItems: 'baseline', gap: 1.5, flexWrap: 'wrap' }}>
        <Typography variant="h4" component="h1" gutterBottom>
          {element.tag}
        </Typography>
        <Typography variant="body2" color="text.secondary" sx={{ whiteSpace: 'nowrap' }}>
          <code>{element.factory}</code> ({element.godotClass})
        </Typography>
      </Box>

      {content && (
        <Typography variant="body1" paragraph>
          {content.blurb}
        </Typography>
      )}

      {content && (
        <Box sx={Styles.section}>
          <Typography variant="h5" component="h2" gutterBottom>
            Usage
          </Typography>
          <CodeBlock language="jsx" code={content.guitkx} />
          {content.gd && (
            <Box sx={{ mt: 2 }}>
              <Typography variant="subtitle2" sx={{ mb: 1, opacity: 0.7 }}>
                GDScript (factory call)
              </Typography>
              <CodeBlock language="python" code={content.gd} />
            </Box>
          )}
        </Box>
      )}

      {element.events.length > 0 && (
        <Box sx={Styles.section}>
          <Typography variant="h5" component="h2" gutterBottom>
            Events
          </Typography>
          <Typography variant="body2" paragraph sx={{ opacity: 0.7 }}>
            React-parity event handlers bind to the underlying Godot signal shown below. The native{' '}
            <code>on_&lt;signal&gt;</code> spelling also works as an escape hatch.
          </Typography>
          <EventsTable element={element} />
        </Box>
      )}

      <Box sx={Styles.section}>
        <Box sx={{ display: 'flex', alignItems: 'baseline', gap: 1 }}>
          <Typography variant="h5" component="h2" gutterBottom>
            Properties
          </Typography>
          <Chip label={`${element.props.length} total`} size="small" variant="outlined" />
        </Box>
        <Typography variant="body2" paragraph sx={{ opacity: 0.7 }}>
          Property names are the Godot names (snake_case), set as attributes in markup or keys in a
          factory call.
        </Typography>

        {ownProps.length > 0 && <PropsTable entries={ownProps} />}

        {inheritedProps.length > 0 && (
          <Accordion
            expanded={baseOpen}
            onChange={() => setBaseOpen(!baseOpen)}
            disableGutters
            sx={{ mt: 2, boxShadow: 'none', '&:before': { display: 'none' } }}
          >
            <AccordionSummary expandIcon={<ExpandMoreIcon />}>
              <Typography variant="subtitle2">
                Inherited properties ({inheritedProps.length})
              </Typography>
            </AccordionSummary>
            <AccordionDetails>
              <PropsTable entries={inheritedProps} />
            </AccordionDetails>
          </Accordion>
        )}
      </Box>

      <Box sx={Styles.section}>
        <Typography variant="h5" component="h2" gutterBottom>
          Godot reference
        </Typography>
        <Typography variant="body1" paragraph>
          See the{' '}
          <Link href={godotClassUrl} target="_blank" rel="noreferrer">
            {element.godotClass} class reference
          </Link>{' '}
          in the official Godot documentation for the full property, method, and signal surface.
        </Typography>
      </Box>
    </Box>
  )
}
