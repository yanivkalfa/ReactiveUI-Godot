export const UITKX_ROUTER_EXAMPLE = `@class_name RouterDemo

component RouterDemo() {
  var navigate = RUIRouter.use_navigate()
  var search = RUIRouter.use_search_params()   // [query, setter]

  var ACTIVE := { "font_color": Color(1.0, 0.85, 0.3) }
  var IDLE := { "font_color": Color(0.7, 0.7, 0.8) }

  return (
    <Router basename="/app">
      <VBox style={ {"separation": 8} }>
        // NavLink applies active_style when its target matches the location.
        <NavLink to="/" end={ true } label="Home" style={ IDLE } active_style={ ACTIVE } />
        <NavLink to="/about" label="About" style={ IDLE } active_style={ ACTIVE } />
        <NavLink to="/users" label="Users" style={ IDLE } active_style={ ACTIVE } />

        <Button text="Open profile 42"
                onClick={ func(): navigate.call("/users/42?tab=profile") } />

        // Routes picks the single best match using RR's ranking algorithm.
        { V.routes({}, [
            // Index route — matches the parent path exactly.
            V.route({ "index": true, "element": V.label({ "text": "Landing route" }) }),

            V.route({ "path": "/about", "element": V.label({ "text": "About route" }) }),

            // Layout route — element wraps the matched child via <Outlet/>.
            V.route({ "path": "/users", "element": V.fc(UsersLayout.render) }, [
                V.route({ "index": true, "element": V.label({ "text": "Pick a user" }) }),
                V.route({ "path": ":id", "element": V.fc(UserDetails.render) }),
            ]),

            // Declarative redirect (replace = true by default).
            V.route({ "path": "/old", "element": V.navigate({ "to": "/about" }) }),

            V.route({ "path": "*", "element": V.label({ "text": "Not found" }) }),
        ]) }
      </VBox>
    </Router>
  )
}`

export const UITKX_ROUTER_LAYOUT_EXAMPLE = `@class_name UsersLayout

component UsersLayout() {
  return (
    <VBox style={ {"separation": 8} }>
      <Label text="Users header" />
      // Nested route content renders here.
      <Outlet />
    </VBox>
  )
}`

export const UITKX_ROUTER_DETAILS_EXAMPLE = `@class_name UserDetails

component UserDetails() {
  var params = RUIRouter.use_params()       // { "id": "42", ... }
  var matches = RUIRouter.use_matches()     // breadcrumb chain (root -> current)
  return (
    <Label text={ "User id: %s" % str(params.get("id")) } />
  )
}`
