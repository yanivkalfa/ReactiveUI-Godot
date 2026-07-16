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
} from '@mui/material'
import { CodeBlock } from '../../../components/CodeBlock/CodeBlock'
import Styles from '../../GettingStarted/GettingStartedPage.style'
import {
  EXAMPLE_UITKX,
  EXAMPLE_GENERATED_CLASS,
  EXAMPLE_DIRECTORY,
  EXAMPLE_HOOKS,
  EXAMPLE_STYLES,
  EXAMPLE_TYPES,
  EXAMPLE_UTILS,
  EXAMPLE_STANDALONE,
} from './CompanionFilesPage.example'

export const CompanionFilesPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Companion Files
    </Typography>
    <Typography variant="body1" paragraph>
      The editor plugin compiles every <code>.guitkx</code> file into a <strong>sibling{' '}
      <code>.gd</code> class</strong> — <code>class_name</code>, <code>extends RefCounted</code>, a{' '}
      <code>render()</code> method, and everything else. A component can work with just a single{' '}
      <code>.guitkx</code> file.
    </Typography>
    <Typography variant="body1" paragraph>
      Companion files are <strong>optional</strong> <code>.guitkx</code> files that live next to a
      component and use the <code>hook</code> and <code>module</code> keywords. Use them to extract
      reusable state logic, styles, type definitions, or utility functions. Each companion also
      compiles to its own sibling <code>.gd</code> with its own <code>class_name</code>.
    </Typography>

    <Typography variant="h5" component="h2" gutterBottom>
      The .guitkx component
    </Typography>
    <Typography variant="body1" paragraph>
      Here is a component that uses styles, types, and utility functions defined in companion files
      (referenced by the companion's <code>class_name</code>):
    </Typography>
    <CodeBlock language="jsx" code={EXAMPLE_UITKX} />

    <Typography variant="h5" component="h2" gutterBottom>
      Generated class
    </Typography>
    <Typography variant="body1" paragraph>
      On save, the plugin creates a sibling GDScript class from the <code>.guitkx</code> file. Its
      identity comes from one thing:
    </Typography>
    <List>
      <ListItem disablePadding>
        <ListItemText
          primary={
            <>
              <strong>Class name</strong> — inferred: an <code>@class_name</code> override if
              present, else the first <code>export</code>ed declaration's name, else the first
              declaration's name.
            </>
          }
        />
      </ListItem>
    </List>
    <Typography variant="body1" paragraph>
      There are no C#-style namespaces in GDScript — a global <code>class_name</code> is how the
      class is referenced project-wide. For the example above, the generator produces:
    </Typography>
    <CodeBlock language="gdscript" code={EXAMPLE_GENERATED_CLASS} />

    <Typography variant="h5" component="h2" gutterBottom>
      Directory layout
    </Typography>
    <Typography variant="body1" paragraph>
      Place companion files in the <strong>same directory</strong> as the <code>.guitkx</code>{' '}
      component. Each source produces one sibling <code>.gd</code>:
    </Typography>
    <CodeBlock language="jsx" code={EXAMPLE_DIRECTORY} />

    <Typography variant="h5" component="h2" gutterBottom>
      File types
    </Typography>
    <TableContainer component={Paper} variant="outlined" sx={{ mb: 2 }}>
      <Table size="small">
        <TableHead>
          <TableRow>
            <TableCell><strong>File</strong></TableCell>
            <TableCell><strong>Keyword</strong></TableCell>
            <TableCell><strong>Purpose</strong></TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          <TableRow>
            <TableCell><code>MyComponent.guitkx</code></TableCell>
            <TableCell><code>component</code></TableCell>
            <TableCell>UI markup + setup code</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>MyComponent.hooks.guitkx</code></TableCell>
            <TableCell><code>module</code> + <code>hook</code></TableCell>
            <TableCell>Custom hooks — reusable state logic</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>MyComponent.style.guitkx</code></TableCell>
            <TableCell><code>module</code></TableCell>
            <TableCell>Style dictionaries, colours, sizes</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>MyComponent.types.guitkx</code></TableCell>
            <TableCell><code>module</code></TableCell>
            <TableCell>Enums and shared data shapes used by the component</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>MyComponent.utils.guitkx</code></TableCell>
            <TableCell><code>module</code></TableCell>
            <TableCell>Pure helper / formatting functions</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </TableContainer>
    <Typography variant="body2" paragraph>
      All companion files end in <code>.guitkx</code>. The naming conventions (
      <code>.hooks.</code>, <code>.style.</code>, <code>.utils.</code>) are recommendations, not
      enforced rules — since 0.10 a single file may even hold several declarations. What <em>is</em>{' '}
      enforced is the wiring: mark a companion&apos;s declaration <code>export</code> and{' '}
      <code>import</code> it where it&apos;s used (see the Imports &amp; Exports page) — an implicit
      cross-file reference is a compile error that tells you the exact import to add.
    </Typography>

    <Typography variant="h5" component="h2" gutterBottom>
      Hooks — reusable state logic
    </Typography>
    <Typography variant="body1" paragraph>
      Declare custom hooks inside a <code>module</code> with the <code>hook</code> keyword. Hook
      bodies are pure GDScript — they can call <code>Hooks.useState</code>,{' '}
      <code>Hooks.useEffect</code>, <code>Hooks.useMemo</code>, and any other built-in hook. Use{' '}
      <code>{'-> ReturnType'}</code> to declare the return type:
    </Typography>
    <CodeBlock language="jsx" code={EXAMPLE_HOOKS} />

    <Typography variant="h5" component="h2" gutterBottom>
      Modules — styles
    </Typography>
    <Typography variant="body1" paragraph>
      Use the <code>module</code> keyword to gather styles, constants, and helpers. Give the module
      its own <code>class_name</code> and reference its members from the component (e.g.{' '}
      <code>PlayerCardStyle.CARD</code>):
    </Typography>
    <CodeBlock language="jsx" code={EXAMPLE_STYLES} />

    <Typography variant="h5" component="h2" gutterBottom>
      Modules — type definitions
    </Typography>
    <CodeBlock language="jsx" code={EXAMPLE_TYPES} />

    <Typography variant="h5" component="h2" gutterBottom>
      Modules — utility functions
    </Typography>
    <CodeBlock language="jsx" code={EXAMPLE_UTILS} />

    <Typography variant="h5" component="h2" gutterBottom>
      Standalone modules
    </Typography>
    <Typography variant="body1" paragraph>
      Not everything has to be tied to a component. Standalone modules with a unique name are useful
      for values shared across multiple components:
    </Typography>
    <CodeBlock language="jsx" code={EXAMPLE_STANDALONE} />

    <Typography variant="h5" component="h2" gutterBottom>
      Compile & hot-reload
    </Typography>
    <List>
      <ListItem disablePadding>
        <ListItemText primary="The editor plugin watches EditorFileSystem. When you save a .guitkx file, it compiles the source to its sibling .gd (Foo.guitkx → Foo.gd)." />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText
          primary={
            <>
              While the game is running under <strong>F5</strong>, that compile also drives{' '}
              <strong>Fast Refresh</strong>: the generated script reloads in place and the
              runtime re-renders exactly the components whose script changed — hook state
              survives unless the edit changed a component&apos;s hook-call shape, which is a
              deliberate reset.
            </>
          }
        />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText
          primary={
            <>
              A companion <code>hook</code> or <code>module</code> file reloads the same way,
              but since any component may call into it, editing one triggers a <em>global</em>{' '}
              re-render — every mounted component re-runs (state preserved), not just the one
              file that changed.
            </>
          }
        />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary="A diagnostics sidecar (Foo.guitkx.diags.json) is written alongside the .gd; the IDE tooling reads it for errors and warnings." />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary="Generated .gd files are marked AUTO-GENERATED … do not edit — edit the .guitkx source and let the plugin regenerate." />
      </ListItem>
    </List>
    <Typography variant="body2" paragraph sx={{ mt: 1 }}>
      Fast Refresh only runs while a play session is attached to the editor (F5) — see{' '}
      <strong>Hot Reload (Fast Refresh)</strong> under Tooling for the full mechanism, the
      per-hook state table, and its limitations.
    </Typography>

    <Typography variant="h5" component="h2" gutterBottom>
      When not to use companion files
    </Typography>
    <List>
      <ListItem disablePadding>
        <ListItemText primary="Simple components — if a component has no shared styles or types, it doesn't need any companion files." />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText
          primary={
            <>
              Small helpers — for code that only the component uses, prefer
              setup code before <code>return ()</code> inside the <code>.guitkx</code> file itself.
            </>
          }
        />
      </ListItem>
    </List>
  </Box>
)
