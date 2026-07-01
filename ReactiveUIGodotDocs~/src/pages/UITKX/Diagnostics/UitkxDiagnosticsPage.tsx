import type { FC } from 'react'
import {
  Box,
  Chip,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Typography,
} from '@mui/material'
import Styles from '../Reference/UitkxReferencePage.style'

type Sev = 'Error' | 'Warning' | 'Hint'
type DiagRow = { code: string; sev: Sev; title: string; fix: React.ReactNode }

const sevColor: Record<Sev, 'error' | 'warning' | 'info'> = {
  Error: 'error',
  Warning: 'warning',
  Hint: 'info',
}

const DiagTable: FC<{ rows: DiagRow[] }> = ({ rows }) => (
  <TableContainer>
    <Table size="small" sx={Styles.table}>
      <TableHead>
        <TableRow>
          <TableCell>Code</TableCell>
          <TableCell>Severity</TableCell>
          <TableCell>Title</TableCell>
          <TableCell>How to fix</TableCell>
        </TableRow>
      </TableHead>
      <TableBody>
        {rows.map((r) => (
          <TableRow key={r.code}>
            <TableCell>
              <Chip label={r.code} size="small" color={sevColor[r.sev]} variant="outlined" />
            </TableCell>
            <TableCell>
              <Chip label={r.sev} size="small" color={sevColor[r.sev]} />
            </TableCell>
            <TableCell>{r.title}</TableCell>
            <TableCell>{r.fix}</TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  </TableContainer>
)

/* ── Parser diagnostics (GUITKX0300–0306) ───────────────────────────── */
const parserRows: DiagRow[] = [
  { code: 'GUITKX0300', sev: 'Error', title: 'Unexpected / missing token', fix: <>Malformed attributes, a missing component / hook name, or an attribute value that is neither a string nor a <code>{'{expr}'}</code>. Check the syntax near the reported line.</> },
  { code: 'GUITKX0301', sev: 'Error', title: 'Unclosed tag', fix: <>Add a matching closing tag, or use self-closing syntax (<code>{'<Foo />'}</code>).</> },
  { code: 'GUITKX0302', sev: 'Error', title: 'Mismatched closing tag', fix: <>The closing tag name must match the opening tag (<code>{'</Foo>'}</code> for <code>{'<Foo>'}</code>).</> },
  { code: 'GUITKX0303', sev: 'Error', title: 'Missing block / unexpected EOF', fix: <>A <code>component</code>, <code>hook</code>, <code>module</code>, directive, or <code>@match</code> is missing its <code>{'{ ... }'}</code> body (or the file ended mid-tag). Close the block.</> },
  { code: 'GUITKX0304', sev: 'Error', title: 'Unclosed brace / paren', fix: <>An unclosed <code>{'{expr}'}</code>, <code>(...)</code> param list, <code>return (</code>, directive body, or <code>@match</code> body. Balance the delimiters.</> },
  { code: 'GUITKX0305', sev: 'Warning', title: 'Unknown @directive', fix: <>Valid directives: <code>@if</code>, <code>@else</code>, <code>@for</code>, <code>@while</code>, <code>@match</code>, <code>@case</code>, <code>@default</code> (and the file directives <code>@class_name</code>, <code>@extends</code>, <code>@use</code>).</> },
  { code: 'GUITKX0306', sev: 'Error', title: 'Directive shape error', fix: <>A directive expects <code>(...)</code>, or an <code>@match</code> body expects <code>@case (...) {'{ }'}</code> / <code>@default {'{ }'}</code> arms. Fix the directive header.</> },
]

/* ── Structural / semantic diagnostics (GUITKX0102–0113) ─────────────── */
const structuralRows: DiagRow[] = [
  { code: 'GUITKX0102', sev: 'Error', title: 'No declaration / no markup return', fix: <>The file has no <code>component</code>, <code>hook</code>, or <code>module</code> declaration, or a <code>component</code> has no <code>return ( ... )</code> (only <code>return null</code>). Add the declaration / return.</> },
  { code: 'GUITKX0103', sev: 'Warning', title: 'component name differs from file name', fix: <>Rename the <code>component</code> to match the file (a <code>Foo.guitkx</code> should declare <code>component Foo()</code>), or rename the file.</> },
  { code: 'GUITKX0104', sev: 'Warning', title: 'Duplicate sibling key', fix: <>Ensure each sibling element has a unique <code>key</code> value.</> },
  { code: 'GUITKX0106', sev: 'Warning', title: 'Loop element missing key', fix: <>An element inside <code>@for</code> / <code>@while</code> has no <code>key</code>. Add <code>key={'{...}'}</code> with a stable unique identifier so reordered children reconcile correctly.</> },
  { code: 'GUITKX0108', sev: 'Error', title: 'Multiple root elements', fix: <>A component must return exactly one root element. Wrap siblings in a container (<code>{'<VBox>'}</code>, <code>{'<HBox>'}</code>) or a fragment (<code>{'<>…</>'}</code>).</> },
  { code: 'GUITKX0110', sev: 'Error', title: 'Invalid module', fix: <>A <code>module</code> has no component / hook declarations, or a <code>module</code> is nested inside another. Give the module content, and keep modules top-level.</> },
  { code: 'GUITKX0112', sev: 'Error', title: 'Duplicate declaration in module', fix: <>Two declarations in the same <code>module</code> share a name. Rename one.</> },
  { code: 'GUITKX0113', sev: 'Error', title: 'Statement used in an embedded expression', fix: <>A statement (e.g. a control-flow directive) cannot be lowered inside an embedded <code>{'{expr}'}</code> / JSX-value. Lift it to the top-level markup return, or use <code>.map()</code> for lists.</> },
]

/* ── Runtime hook validation (GUITKX0013) ────────────────────────────── */
const runtimeRows: DiagRow[] = [
  { code: 'GUITKX0013', sev: 'Warning', title: 'Hook called conditionally / in a block', fix: <>Hooks must run unconditionally at the top of setup — never inside an <code>@if</code> / loop / nested lambda. The runtime hook-order validator (gated by <code>RUIConfig.enable_hook_validation</code>) also detects an order / count change across renders and reports it via <code>RUIDiagnostics</code> + <code>push_error</code>.</> },
]

export const UitkxDiagnosticsPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Diagnostics Reference
    </Typography>
    <Typography variant="body1" paragraph>
      Every diagnostic code emitted by the <code>.guitkx</code> compiler and the
      language server, with severity, meaning, and how to fix it. Compile-time
      diagnostics are written to a sibling <code>&lt;file&gt;.guitkx.diags.json</code>{' '}
      and surfaced as <code>push_error</code> / <code>push_warning</code> in the
      Godot output; the same checks run live in the editor extension.
    </Typography>

    {/* ── Parser Diagnostics ────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Parser Diagnostics
    </Typography>
    <Typography variant="body2" paragraph>
      Emitted when the lexer / parser encounters malformed markup syntax.
    </Typography>
    <DiagTable rows={parserRows} />

    {/* ── Structural / Semantic Diagnostics ─────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Structural &amp; Semantic Diagnostics
    </Typography>
    <Typography variant="body2" paragraph>
      Emitted after parsing, when validating the component / hook / module
      structure and the reconciliation keys.
    </Typography>
    <DiagTable rows={structuralRows} />

    {/* ── Runtime hook validation ───────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Runtime Hook Validation
    </Typography>
    <Typography variant="body2" paragraph>
      Emitted at runtime (in debug builds by default) when hooks are used in a
      way that breaks the positional-slot model.
    </Typography>
    <DiagTable rows={runtimeRows} />
  </Box>
)
