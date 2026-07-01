import type { FC } from 'react'
import { Box, List, ListItem, ListItemText, Typography } from '@mui/material'
import { CodeBlock } from '../../../components/CodeBlock/CodeBlock'
import Styles from '../../Router/RouterPage.style'
import {
  UITKX_ROUTER_DETAILS_EXAMPLE,
  UITKX_ROUTER_EXAMPLE,
  UITKX_ROUTER_LAYOUT_EXAMPLE,
} from './UitkxRouterPage.example'

export const UitkxRouterPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Router
    </Typography>
    <Typography variant="body1" paragraph>
      The library ships a lightweight, in-memory router inspired by React Router, built on the
      reactive core (context + hooks). Routing is authored directly in your component tree — you
      compose <code>{'<Router>'}</code>, <code>{'<Route>'}</code>, links, and routed child
      components as part of the returned UI. The pieces are exposed as{' '}
      <code>V.router</code> / <code>V.route</code> / <code>V.routes</code> /{' '}
      <code>V.outlet</code> / <code>V.navigate</code> / <code>V.nav_link</code> /{' '}
      <code>V.link</code> factories (and the corresponding markup tags{' '}
      <code>{'<Router>'}</code>, <code>{'<Route>'}</code>, <code>{'<Outlet/>'}</code>,{' '}
      <code>{'<NavLink>'}</code>).
    </Typography>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Core concepts
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<><code>{'<Router>'}</code> establishes routing context and history for the subtree. The optional <code>basename</code> prop prefixes every URL. Provide a custom <code>history</code> (an <code>RUIHistory</code>) or an <code>initial</code> path.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>{'<Routes>'}</code> ranks its child <code>{'<Route>'}</code>s and renders the single best match (RR-v6 behaviour, first-match-wins by score).</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>{'<Route>'}</code> matches the current path and decides what to render via its <code>element</code> vnode or a <code>render</code> callback. Supports <code>index</code>, <code>case_sensitive</code>, <code>exact</code>, and layout-route composition with child <code>{'<Route>'}</code>s + <code>{'<Outlet/>'}</code>.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>{'<Outlet/>'}</code> is the render-slot inside a layout route — the matched nested route renders here (falling back to the outlet&apos;s own children).</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>{'<NavLink>'}</code> renders a navigation button with active-state styling (<code>active_style</code>).</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>{'<Navigate to=...>'}</code> performs a declarative redirect from an effect after commit (defaults to <code>replace = true</code>).</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>The <code>RUIRouter.use_*</code> hooks expose imperative navigation, location data, search params, blockers, and breadcrumbs from any descendant component.</>} />
        </ListItem>
      </List>
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Basic example
      </Typography>
      <Typography variant="body1" paragraph>
        The example below shows the full RR-v6-parity surface:{' '}
        <code>{'<Router basename>'}</code>, ranked <code>{'<Routes>'}</code>, an{' '}
        <code>index</code> route, a layout route with <code>{'<Outlet/>'}</code>, a declarative
        redirect, and the search-params / breadcrumb hooks. The route table takes vnode/callback
        props rather than markup children, so it is written as an embedded{' '}
        <code>{'{ V.routes(...) }'}</code> expression.
      </Typography>
      <CodeBlock language="gdscript" code={UITKX_ROUTER_EXAMPLE} />
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Routes — ranked first-match-wins
      </Typography>
      <Typography variant="body1" paragraph>
        <code>{'<Routes>'}</code> (via <code>V.routes</code>) is the deterministic selector. It
        walks its child <code>{'<Route>'}</code> declarations, scores each one with the same
        ranking algorithm React Router uses (static segments beat dynamic <code>:params</code>,
        which beat splats), and renders only the highest-ranked match. Ties break by declaration
        order. Use it whenever more than one route could match the same path — it eliminates the
        &quot;two routes both matched&quot; foot-gun of a bare <code>{'<Route>'}</code>. A{' '}
        <code>V.routes</code> call also accepts the legacy table form{' '}
        <code>{'{ "routes": [ { "path", "component" }, ... ] }'}</code>, kept working for
        back-compat.
      </Typography>
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Layout routes and Outlet
      </Typography>
      <Typography variant="body1" paragraph>
        A <code>{'<Route>'}</code> with both an <code>element</code> and child{' '}
        <code>{'<Route>'}</code>s becomes a <em>layout route</em>. Its <code>element</code>{' '}
        renders as a wrapper, and the matched child renders wherever you place an{' '}
        <code>{'<Outlet/>'}</code> inside that wrapper. The wrapper sees the matched child through
        context, so there is no prop-drilling — this mirrors React Router v6.
      </Typography>
      <CodeBlock language="gdscript" code={UITKX_ROUTER_LAYOUT_EXAMPLE} />
      <Typography variant="body1" paragraph>
        Pass a value with <code>{'V.outlet({ "context": value })'}</code> and read it in
        descendants with <code>RUIRouter.use_outlet_context()</code>, the same way RR&apos;s{' '}
        <code>useOutletContext</code> works.
      </Typography>
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Index and case-sensitive routes
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<><code>index={'{true}'}</code> — the route matches the parent path exactly (no extra segment). Setting both <code>index</code> and <code>path</code> on the same route logs an actionable error via <code>RUIDiagnostics</code> / <code>push_error</code> and drops the path (the port cannot throw; it degrades).</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>case_sensitive={'{true}'}</code> — opt in to case-sensitive segment matching for that route. The default is case-insensitive.</>} />
        </ListItem>
      </List>
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Reading route params
      </Typography>
      <Typography variant="body1" paragraph>
        Inside a routed component, <code>RUIRouter.use_params()</code> returns the captured{' '}
        <code>:params</code> (a defensive copy of the merged parent chain), and{' '}
        <code>RUIRouter.use_matches()</code> returns the ordered chain of route matches from root
        to current — handy for breadcrumbs and analytics.
      </Typography>
      <CodeBlock language="gdscript" code={UITKX_ROUTER_DETAILS_EXAMPLE} />
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        NavLink — active-state links
      </Typography>
      <Typography variant="body1" paragraph>
        <code>{'V.nav_link({ "to": "/about", "label": "About", "active_style": {...} })'}</code>{' '}
        renders a <code>Button</code> that navigates on press and applies{' '}
        <code>active_style</code> (instead of <code>style</code>) when its target matches the
        current location. The activation rules mirror RR&apos;s <code>NavLink</code> — including
        the special case where <code>to=&quot;/&quot;</code> is only active when the path is
        exactly <code>&quot;/&quot;</code> (otherwise Home would highlight everywhere). Use{' '}
        <code>end={'{true}'}</code> to require an exact match for non-root paths and{' '}
        <code>case_sensitive={'{true}'}</code> for case-sensitive comparison. For a plain,
        non-active-aware link, use <code>V.link</code>.
      </Typography>
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Navigate — declarative redirects
      </Typography>
      <Typography variant="body1" paragraph>
        <code>{'V.navigate({ "to": "/welcome" })'}</code> performs a redirect. It runs from a{' '}
        <code>useEffect</code> after commit (never from inside render) and defaults to{' '}
        <code>replace = true</code> so redirects don&apos;t grow the history stack — perfect for a{' '}
        <code>{'V.route({ "path": "/", "element": V.navigate({ "to": "/dashboard" }) })'}</code>{' '}
        pattern. Pass <code>state</code> to forward navigation state along.
      </Typography>
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        basename
      </Typography>
      <Typography variant="body1" paragraph>
        <code>{'V.router({ "basename": "/app" })'}</code> tells the router that{' '}
        <code>/app</code> is the application root. Inbound locations have the prefix stripped
        before matching (so <code>use_location()</code> is app-relative), and outbound navigations
        re-attach it. Useful when an app is mounted under a path segment.
      </Typography>
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Navigation and history
      </Typography>
      <Typography variant="body1" paragraph>
        By default <code>{'<Router>'}</code> uses an in-memory <code>RUIHistory</code>. You can
        provide a custom instance via the <code>history</code> prop to control how locations are
        stored or synchronised. Inside components, use{' '}
        <code>RUIRouter.use_navigate()</code> to push or replace locations, and{' '}
        <code>RUIRouter.use_go()</code> / <code>RUIRouter.use_can_go(delta)</code> to implement
        back/forward UI. Use <code>RUIRouter.use_blocker(blocker, enabled)</code> (or the
        convenience wrapper <code>RUIRouter.use_prompt(when, message)</code>) to prevent
        navigation while a confirmation is pending.
      </Typography>
      <Typography variant="body1" paragraph>
        Nesting two <code>{'<Router>'}</code> elements in the same tree is not allowed — mirrors
        RR&apos;s <code>invariant(!useInRouterContext())</code>. Because GDScript cannot throw a
        catchable exception, the port logs an actionable error (via <code>RUIDiagnostics</code> /{' '}
        <code>push_error</code>) and degrades: the inner router shadows the outer for its subtree.
        Use a single root <code>{'<Router>'}</code> and compose <code>{'<Route>'}</code>s
        underneath it.
      </Typography>
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Reading route data — the hooks
      </Typography>
      <Typography variant="body1" paragraph>
        Call these from any descendant component:
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RUIRouter.use_location()</code> — the current path String (re-renders on navigation). <code>use_location_info()</code> returns the full <code>RUIRouterLocation</code> (path, query, state).</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RUIRouter.use_params()</code> — the captured path parameters for the matched route.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RUIRouter.use_query()</code> — a defensive copy of the decoded query dictionary.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RUIRouter.use_search_params()</code> — a <code>[query, setter]</code> pair. The setter <code>(next, replace := false)</code> preserves the path and replaces only the query string (RR&apos;s <code>useSearchParams</code> equivalent).</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RUIRouter.use_navigation_state()</code> — the opaque state object passed during navigation.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RUIRouter.use_route_match()</code> — the nearest <code>RUIRouteMatch</code> (matched path, pattern, params).</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RUIRouter.use_matches()</code> — the ordered chain of matches root → current, for breadcrumbs and analytics.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RUIRouter.use_navigation_base()</code> / <code>use_resolved_path(to)</code> — the base for relative navigation, and the absolute path <code>use_navigate</code> would dispatch for <code>to</code>.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RUIRouter.use_outlet_context()</code> — the value handed down by the closest <code>{'V.outlet({ "context": ... })'}</code>.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RUIRouter.use_navigate(replace := false)</code> — returns <code>func(path, state := null) -&gt; bool</code>. It reads only the stable nav context, so navigate-only widgets do <em>not</em> re-render on every location change.</>} />
        </ListItem>
      </List>
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Nested routes
      </Typography>
      <Typography variant="body1" paragraph>
        Layout routes are the recommended way to nest. A parent <code>{'<Route>'}</code> with both
        an <code>element</code> and child <code>{'<Route>'}</code>s renders its element as a
        wrapper and projects the matched child into the descendant <code>{'<Outlet/>'}</code>.
        Child routes may use relative paths (for example <code>&quot;profile&quot;</code> or{' '}
        <code>&quot;:id/edit&quot;</code>) and are resolved against the parent match automatically —
        no need to repeat the parent prefix. This matches React Router v6.
      </Typography>
    </Box>
  </Box>
)
