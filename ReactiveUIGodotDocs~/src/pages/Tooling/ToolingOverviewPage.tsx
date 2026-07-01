import type { FC } from 'react'
import { Box, Typography } from '@mui/material'
import Styles from './ToolingOverviewPage.style'

export const ToolingOverviewPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Tooling
    </Typography>
    <Typography variant="body1">
      Utilities that ship with ReactiveUITK: <code>HMR</code> for instant live editing,{' '}
      <code>Router</code> for navigation, and <code>Signals</code> for shared state.
    </Typography>
  </Box>
)
