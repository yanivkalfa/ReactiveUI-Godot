import type { FC } from 'react'
import { Box, Link, Typography } from '@mui/material'
import { CodeBlock } from '../../components/CodeBlock/CodeBlock'
import Styles from '../GettingStarted/GettingStartedPage.style'
import {
  MIGRATE_0_10_CMD,
  MIGRATE_0_10_BEFORE_AFTER,
  MIGRATE_0_9_CMD,
  MIGRATE_0_9_EXAMPLES,
} from './MigrationsPage.example'

const REPO = 'https://github.com/yanivkalfa/ReactiveUI-Godot/blob/master'

export const MigrationsPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Migrations
    </Typography>
    <Typography variant="body1" paragraph>
      Every breaking release ships a <strong>codemod</strong> that rewrites your project in place —
      run one command, review the diff, done. Both codemods ship inside the addon
      (<code>addons/reactive_ui/dev/</code>), are idempotent (safe to re-run), and never touch your
      hand-written <code>.gd</code> scripts&apos; logic. The full step-by-step guides live in the
      repository; this page is the quick path.
    </Typography>

    {/* ── 0.9 → 0.10 ─────────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" gutterBottom sx={{ mt: 3 }}>
      0.9 → 0.10 — imports &amp; exports
    </Typography>
    <Typography variant="body1" paragraph>
      0.10 makes cross-file references explicit and strict: referencing another file&apos;s
      component/hook/module now requires an <code>import</code>, and the target must be{' '}
      <code>export</code>ed. The codemod exports every declaration and writes the import lines for
      each file&apos;s references:
    </Typography>
    <CodeBlock language="bash" code={MIGRATE_0_10_CMD} />
    <CodeBlock language="jsx" code={MIGRATE_0_10_BEFORE_AFTER} />
    <Typography variant="body1" paragraph sx={{ mt: 2 }}>
      Hand-written <code>class_name</code> scripts stay <em>ambient</em> (no import needed), and
      anything that still errors afterwards tells you the exact line to add. Details, edge cases,
      and the after-migration error table:{' '}
      <Link href={`${REPO}/MIGRATION-0.10.md`} target="_blank" rel="noopener">
        MIGRATION-0.10.md
      </Link>{' '}
      — grammar reference on the Imports &amp; Exports page.
    </Typography>

    {/* ── 0.8 → 0.9 ──────────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" gutterBottom sx={{ mt: 3 }}>
      0.8 → 0.9 — naming is 1:1 loyal to Godot
    </Typography>
    <Typography variant="body1" paragraph>
      0.9 renamed the whole vocabulary to the official Godot names — tags are class names,
      events are <code>on</code> + PascalCase(signal), style keys are the exact property/theme
      names. The codemod has a dry-run mode; everything it can&apos;t rewrite safely it lists for
      you, and every removed name fails loudly with its exact replacement:
    </Typography>
    <CodeBlock language="bash" code={MIGRATE_0_9_CMD} />
    <CodeBlock language="jsx" code={MIGRATE_0_9_EXAMPLES} />
    <Typography variant="body1" paragraph sx={{ mt: 2 }}>
      Full rename tables and the manual-review list:{' '}
      <Link href={`${REPO}/MIGRATION-0.9.md`} target="_blank" rel="noopener">
        MIGRATION-0.9.md
      </Link>
      .
    </Typography>

    <Typography variant="body2" paragraph sx={{ mt: 2 }}>
      Upgrading across both? Run them in order: the 0.9 codemod first, then the 0.10 one.
    </Typography>
  </Box>
)
