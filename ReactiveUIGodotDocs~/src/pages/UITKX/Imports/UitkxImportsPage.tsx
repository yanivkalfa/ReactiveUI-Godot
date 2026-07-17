import type { FC } from 'react'
import { Box, Typography, Table, TableBody, TableCell, TableContainer, TableHead, TableRow, Paper } from '@mui/material'
import { CodeBlock } from '../../../components/CodeBlock/CodeBlock'
import Styles from '../../GettingStarted/GettingStartedPage.style'
import {
  EXAMPLE_IMPORT_BASIC,
  EXAMPLE_SPECIFIERS,
  EXAMPLE_EXPORT,
  EXAMPLE_CONFIG,
  EXAMPLE_MIGRATE,
} from './UitkxImportsPage.example'

export const UitkxImportsPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Imports &amp; Exports
    </Typography>
    <Typography variant="body1" paragraph>
      A <code>.guitkx</code> file declares the other files it depends on with an{' '}
      <code>import</code> line, and marks what other files may use with <code>export</code>.
      Cross-file resolution is <strong>strict</strong>: referencing another component, hook, or
      module without importing it is an error that tells you the exact import to add.
    </Typography>

    <Typography variant="h5" component="h2" gutterBottom sx={{ mt: 3 }}>
      Importing
    </Typography>
    <Typography variant="body1" paragraph>
      Imports go in the file preamble (before the first declaration), in any order relative to{' '}
      <code>@class_name</code> / <code>@uss</code>. Only named imports are supported — no default
      import, no <code>import *</code>.
    </Typography>
    <CodeBlock language="jsx" code={EXAMPLE_IMPORT_BASIC} />
    <Typography variant="body1" paragraph sx={{ mt: 2 }}>
      Specifiers are <strong>relative</strong> (<code>./</code>, <code>../</code>) or{' '}
      <strong>root-aliased</strong> (<code>~/</code>), and always <strong>extensionless</strong>{' '}
      (<code>.guitkx</code> is implied). Engine-native <code>res://</code> / <code>uid://</code> are
      not valid import specifiers — they remain valid in <code>@uss</code> / <code>@theme</code>{' '}
      asset positions, which now also accept <code>~/</code>.
    </Typography>
    <CodeBlock language="jsx" code={EXAMPLE_SPECIFIERS} />

    <Typography variant="h5" component="h2" gutterBottom sx={{ mt: 3 }}>
      Exporting &amp; multiple declarations
    </Typography>
    <Typography variant="body1" paragraph>
      Add <code>export</code> to make a declaration reachable from other files. A single file may
      now hold <strong>several</strong> top-level declarations — components, hooks, and modules
      together. The file&apos;s binding (its generated <code>class_name</code>) is the{' '}
      <code>@class_name</code> override, else the first exported declaration. Declarations without{' '}
      <code>export</code> are file-private.
    </Typography>
    <CodeBlock language="jsx" code={EXAMPLE_EXPORT} />
    <Typography variant="body1" paragraph sx={{ mt: 2 }}>
      Component imports stay lazy (they resolve by path, at first render), so cross-file component{' '}
      <strong>cycles are legal</strong>. Value imports (hooks and modules) are eager{' '}
      <code>const</code> preloads, so a value-import <strong>cycle is an error</strong> that prints
      the full chain.
    </Typography>

    <Typography variant="h5" component="h2" gutterBottom sx={{ mt: 3 }}>
      The <code>~/</code> root
    </Typography>
    <Typography variant="body1" paragraph>
      <code>~/</code> resolves against your project&apos;s UI source root — the <code>root</code>{' '}
      key in the nearest <code>guitkx.config.json</code> (walking up from the file), defaulting to{' '}
      <code>res://</code>. The nearest config wins with no merge.
    </Typography>
    <CodeBlock language="json" code={EXAMPLE_CONFIG} />

    <Typography variant="h5" component="h2" gutterBottom sx={{ mt: 3 }}>
      Migrating an existing project
    </Typography>
    <Typography variant="body1" paragraph>
      A one-command codemod adds <code>export</code> to every declaration and writes the import
      lines for each file&apos;s cross-file references. It is idempotent and re-runnable, and it
      leaves hand-written <code>class_name</code> scripts alone (they are ambient).
    </Typography>
    <CodeBlock language="bash" code={EXAMPLE_MIGRATE} />

    <Typography variant="h5" component="h2" gutterBottom sx={{ mt: 3 }}>
      Diagnostics
    </Typography>
    <Typography variant="body1" paragraph>
      Import mistakes surface as <code>GUITKX2300</code>–<code>GUITKX2309</code>:
    </Typography>
    <TableContainer component={Paper} sx={{ mb: 2 }}>
      <Table size="small">
        <TableHead>
          <TableRow>
            <TableCell>Code</TableCell>
            <TableCell>Meaning</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          {[
            ['GUITKX2300', 'Unknown import specifier — no file at that path'],
            ['GUITKX2301', 'Name is not exported by the target — add `export`'],
            ['GUITKX2302', 'Name is not declared in the target file'],
            ['GUITKX2303', 'Duplicate import of the same name'],
            ['GUITKX2304', 'Unused import (warning)'],
            ['GUITKX2305', 'Referenced but not imported — add the import'],
            ['GUITKX2306', 'Value-import cycle (prints the chain)'],
            ['GUITKX2307', 'Used like a component/hook but no file exports it'],
            ['GUITKX2308', 'Import crosses a module/root boundary'],
            ['GUITKX2309', 'Import must appear before the first declaration'],
          ].map(([code, meaning]) => (
            <TableRow key={code}>
              <TableCell><code>{code}</code></TableCell>
              <TableCell>{meaning}</TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </TableContainer>
  </Box>
)
