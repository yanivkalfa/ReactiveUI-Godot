import type { FC } from 'react'
import {
  Box,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Typography,
} from '@mui/material'
import { CodeBlock } from '../../../components/CodeBlock/CodeBlock'
import Styles from './UitkxReferencePage.style'

const DIRECTIVE_HEADER_EXAMPLE = `@class_name MyButton
@uss "res://ui/theme.tres"

component MyButton(label: String = "Click") {
  return (
    <Button text={ label } onClick={ func(): print("clicked") } />
  )
}`

const FUNCTION_STYLE_EXAMPLE = `@class_name Counter

component Counter(label: String = "Count") {
  var s = useState(0)
  var count = s[0]
  return (
    <VBox>
      <Label text={ "%s: %d" % [label, count] } />
      <Button text="+" onClick={ func(): s[1].call(count + 1) } />
    </VBox>
  )
}`

const CONTROL_FLOW_EXAMPLE = `<VBox>
  @if (is_logged_in) {
    <Label text="Welcome back!" />
  } @elif (is_guest) {
    <Label text="Browsing as guest" />
  } @else {
    <Button text="Log in" onClick={ func(): login() } />
  }

  @for (item in items) {
    <Label key={ item.id } text={ item.name.to_upper() }
      style={ {"font_color": Color.GREEN if item.active else Color.GRAY} } />
  }

  @for (i in count) {
    <Label key={ str(i) } text={ "Row %d" % i } />
  }

  @match (mode) {
    @case ("dark")  { <Label text="Dark mode" /> }
    @case ("light") { <Label text="Light mode" /> }
    @default        { <Label text="Unknown mode" /> }
  }
</VBox>`

const PROP_SPREAD_EXAMPLE = `component Toolbar(cfg: Dictionary = {}) {
  var base := { "text": "Save", "disabled": false }

  return (
    <VBox>
      # Spread a variable of props, then add an explicit handler.
      <Button {...base} onClick={ func(): save() } />

      # Explicit prop first, spread overrides it (later wins).
      <Button text="Placeholder" {...cfg} />

      # Spread first as defaults; the trailing onClick always wins.
      <Button {...cfg} text="Cancel" onClick={ func(): cancel() } />

      # Spread works on components too.
      <Card {...base} title={ "Details" } />
    </VBox>
  )
}`

const EXPRESSION_EXAMPLE = `<Label text={ "Count: %d" % count } />
<Button onClick={ func(): s[1].call(count + 1) } />
<VBox>
  { my_custom_node }
  { a_node if cond else b_node }
  # This is a line comment
</VBox>

// A raw expression (instead of markup) can be the whole return body:
{ V.router({ "initial": "/" }, [V.fc(App.render)]) }`

export const UitkxReferencePage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      .guitkx Language Reference
    </Typography>
    <Typography variant="body1" paragraph>
      Complete reference for the <code>.guitkx</code> markup language — declarations, directives,
      control flow, and expressions. A <code>.guitkx</code> file compiles to a sibling GDScript{' '}
      <code>.gd</code> class.
    </Typography>

    {/* ── Declarations ─────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Declarations
    </Typography>
    <Typography variant="body2" paragraph>
      A <code>.guitkx</code> file declares exactly one of three kinds. Each becomes a static function
      (or set of functions) on the generated class.
    </Typography>
    <TableContainer>
      <Table size="small" sx={Styles.table}>
        <TableHead>
          <TableRow>
            <TableCell>Keyword</TableCell>
            <TableCell>Syntax</TableCell>
            <TableCell>Purpose</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          <TableRow>
            <TableCell><code>component</code></TableCell>
            <TableCell><code>component Name(param: Type = default) {'{ … }'}</code></TableCell>
            <TableCell>A UI component. Compiles to <code>static func render(props, children)</code>.</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>hook</code></TableCell>
            <TableCell><code>hook use_thing(args) -&gt; Type {'{ … }'}</code></TableCell>
            <TableCell>A reusable custom hook (inside a <code>module</code> block).</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>module</code></TableCell>
            <TableCell><code>module Name {'{ … }'}</code></TableCell>
            <TableCell>A container for styles, types, utilities, and hooks.</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </TableContainer>

    {/* ── Preamble Directives ──────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Preamble Directives
    </Typography>
    <Typography variant="body2" paragraph>
      Preamble directives appear at the top of a <code>.guitkx</code> file, before any declaration.
      They configure the generated GDScript class.
    </Typography>
    <TableContainer>
      <Table size="small" sx={Styles.table}>
        <TableHead>
          <TableRow>
            <TableCell>Directive</TableCell>
            <TableCell>Syntax</TableCell>
            <TableCell>Description</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          <TableRow>
            <TableCell><code>@class_name</code></TableCell>
            <TableCell><code>@class_name MyButton</code></TableCell>
            <TableCell>Override the generated GDScript <code>class_name</code> (defaults to the declaration name).</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>@uss</code></TableCell>
            <TableCell><code>@uss "res://ui/theme.tres"</code></TableCell>
            <TableCell>Associate a <code>Theme</code>/<code>StyleBox</code> resource path (reserved).</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </TableContainer>
    <CodeBlock language="jsx" code={DIRECTIVE_HEADER_EXAMPLE} />

    {/* ── Function-Style Components ──────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Function-Style Components
    </Typography>
    <Typography variant="body2" paragraph>
      Components use a <code>component Name {'{ … }'}</code> syntax with optional typed parameters.
      Parameters are read from the <code>props</code> dictionary in the generated{' '}
      <code>render</code> method (with the declared default when a prop is absent).
    </Typography>
    <TableContainer>
      <Table size="small" sx={Styles.table}>
        <TableHead>
          <TableRow>
            <TableCell>Feature</TableCell>
            <TableCell>Syntax</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          <TableRow>
            <TableCell>Declaration</TableCell>
            <TableCell><code>component Name() {'{ … }'}</code></TableCell>
          </TableRow>
          <TableRow>
            <TableCell>With parameters</TableCell>
            <TableCell><code>component Name(label: String = "default") {'{ … }'}</code></TableCell>
          </TableRow>
          <TableRow>
            <TableCell>Setup code</TableCell>
            <TableCell>GDScript statements + hook calls before <code>return</code></TableCell>
          </TableRow>
          <TableRow>
            <TableCell>Return</TableCell>
            <TableCell><code>return ( &lt;markup /&gt; )</code> — a single root, or a raw <code>{'{ expr }'}</code></TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </TableContainer>
    <CodeBlock language="jsx" code={FUNCTION_STYLE_EXAMPLE} />

    {/* ── Markup Control Flow ────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Markup Control Flow
    </Typography>
    <TableContainer>
      <Table size="small" sx={Styles.table}>
        <TableHead>
          <TableRow>
            <TableCell>Directive</TableCell>
            <TableCell>Syntax</TableCell>
            <TableCell>Notes</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          <TableRow>
            <TableCell><code>@if / @elif / @else</code></TableCell>
            <TableCell><code>@if (cond) {'{ … }'} @elif (cond) {'{ … }'} @else {'{ … }'}</code></TableCell>
            <TableCell>Conditional rendering</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>@for</code></TableCell>
            <TableCell><code>@for (item in list) {'{ … }'}</code></TableCell>
            <TableCell>Loop — direct children should have a <code>key</code></TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>@while</code></TableCell>
            <TableCell><code>@while (cond) {'{ … }'}</code></TableCell>
            <TableCell>While loop</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>@match / @case / @default</code></TableCell>
            <TableCell><code>@match (val) {'{ @case ("a") { … } @default { … } }'}</code></TableCell>
            <TableCell>Compiles to a GDScript <code>match</code> statement</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </TableContainer>
    <CodeBlock language="jsx" code={CONTROL_FLOW_EXAMPLE} />
    <Typography variant="body2" paragraph sx={{ mt: 2 }}>
      Each directive body contains <strong>bare markup</strong> (no <code>return</code> wrapper), and
      setup statements may precede the markup inside the block. Control-flow directives are{' '}
      <strong>statement-level</strong>: <code>@if</code>, <code>@for</code>, and <code>@match</code>{' '}
      appear directly among markup children, not inside a <code>{'{ expr }'}</code> value. For
      inline conditional values, use a GDScript ternary (<code>a if cond else b</code>) inside a{' '}
      <code>{'{ … }'}</code> expression instead.
    </Typography>

    {/* ── Expressions & Values ───────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Expressions & Values
    </Typography>
    <TableContainer>
      <Table size="small" sx={Styles.table}>
        <TableHead>
          <TableRow>
            <TableCell>Syntax</TableCell>
            <TableCell>Example</TableCell>
            <TableCell>Description</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          <TableRow>
            <TableCell><code>{'{ expr }'}</code></TableCell>
            <TableCell><code>{'<VBox>{ my_node }</VBox>'}</code></TableCell>
            <TableCell>
              A GDScript expression in <strong>markup-child</strong> position. It may evaluate to an{' '}
              <code>RUIVNode</code>, an <code>Array</code> of vnodes (rendered as siblings), a{' '}
              <code>String</code> (rendered as a label), or <code>null</code> (renders nothing).
            </TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>{'attr={ expr }'}</code></TableCell>
            <TableCell><code>{'text={ "Count: %d" % count }'}</code></TableCell>
            <TableCell>A GDScript expression as an attribute value</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>"literal"</code></TableCell>
            <TableCell><code>text="hello"</code></TableCell>
            <TableCell>Plain string attribute</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>{'onXxx={ func: … }'}</code></TableCell>
            <TableCell><code>{'onClick={ func(): do_it() }'}</code></TableCell>
            <TableCell>An event handler — a <code>Callable</code> connected to the mapped signal</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>{'{...obj}'}</code></TableCell>
            <TableCell><code>{'<Button {...cfg} onClick={ f } />'}</code></TableCell>
            <TableCell>
              Prop spread — merges a <code>Dictionary</code> of props onto the element (React&apos;s{' '}
              <code>{'{...obj}'}</code>). See <strong>Prop spread</strong> below.
            </TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>name</code> (bare)</TableCell>
            <TableCell><code>disabled</code></TableCell>
            <TableCell>Boolean shorthand — a valueless attribute is <code>true</code>.</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code># comment</code></TableCell>
            <TableCell><code># TODO</code></TableCell>
            <TableCell>GDScript line comment (to end of line)</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>{'<>…</>'}</code></TableCell>
            <TableCell><code>{'<>'}{'<Label /><Label />'}{'</>'}</code></TableCell>
            <TableCell>Fragment — groups multiple elements without a host node</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </TableContainer>
    <CodeBlock language="jsx" code={EXPRESSION_EXAMPLE} />

    {/* ── Structural attributes ──────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Structural Attributes
    </Typography>
    <Typography variant="body2" paragraph>
      These three attributes are accepted on every host element, alongside any property of the
      underlying Godot node and the <code>on*</code> event handlers.
    </Typography>
    <TableContainer>
      <Table size="small" sx={Styles.table}>
        <TableHead>
          <TableRow>
            <TableCell>Attribute</TableCell>
            <TableCell>Example</TableCell>
            <TableCell>Description</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          <TableRow>
            <TableCell><code>key</code></TableCell>
            <TableCell><code>{'key={ item.id }'}</code></TableCell>
            <TableCell>Stable identity for keyed reconciliation (required on loop children).</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>ref</code></TableCell>
            <TableCell><code>{'ref={ my_ref }'}</code></TableCell>
            <TableCell>A <code>{'{ "current": … }'}</code> box or <code>Callable(node)</code> that receives the live node.</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>style</code></TableCell>
            <TableCell><code>{'style={ {"separation": 8} }'}</code></TableCell>
            <TableCell>Inline style dictionary (see the <strong>Styling</strong> pages).</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </TableContainer>

    {/* ── Event handlers ─────────────────────────────────────────────── */}
    <Box sx={{ my: 3, p: 2, borderLeft: '4px solid', borderColor: 'info.main', bgcolor: 'action.hover' }}>
      <Typography variant="subtitle2" sx={{ fontWeight: 600, mb: 1 }}>
        Event handler attributes
      </Typography>
      <Typography variant="body2" paragraph sx={{ mb: 1 }}>
        Event handlers use React-parity camelCase and map to Godot signals:{' '}
        <code>onClick</code> → <code>pressed</code>, <code>onSubmit</code> →{' '}
        <code>text_submitted</code>, <code>onFocus</code> → <code>focus_entered</code>,{' '}
        <code>onBlur</code> → <code>focus_exited</code>,{' '}
        <code>onPointerDown</code>/<code>Up</code>/<code>Enter</code>/<code>Leave</code>, and{' '}
        <code>onResize</code> → <code>resized</code>. <code>onChange</code> is polymorphic — it binds
        to <code>text_changed</code>, <code>value_changed</code>, <code>item_selected</code>,{' '}
        <code>tab_changed</code>, or <code>toggled</code> depending on the control. Any other{' '}
        <code>onXxxYyy</code> maps to the <code>xxx_yyy</code> signal. The native{' '}
        <code>on_&lt;signal&gt;</code> spelling is also accepted as an escape hatch.
      </Typography>
    </Box>

    {/* ── Prop spread ────────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Prop Spread <code>{'{...obj}'}</code>
    </Typography>
    <Typography variant="body2" paragraph>
      Spread a <code>Dictionary</code> of props onto an element with <code>{'{...obj}'}</code>, exactly
      like React&apos;s spread. It works on <strong>host elements and components alike</strong>, and{' '}
      <code>obj</code> is any GDScript expression that evaluates to a <code>Dictionary</code> — a
      literal, a prop, a variable, or a hook result.
    </Typography>
    <Typography variant="body2" paragraph>
      Spreads and explicit attributes merge <strong>left-to-right, later wins</strong>, preserving
      source order. So <code>{'<Button text="Hi" {...cfg} onClick={ f } />'}</code> lets{' '}
      <code>cfg</code> override the literal <code>text</code>, while the trailing{' '}
      <code>onClick</code> always wins over any <code>onClick</code> inside <code>cfg</code>. Put a
      spread <em>last</em> to have it win, or <em>first</em> to treat it as defaults that explicit
      props override.
    </Typography>
    <CodeBlock language="jsx" code={PROP_SPREAD_EXAMPLE} />
    <Typography variant="body2" paragraph sx={{ mt: 1 }}>
      A spread compiles to <code>V._spread_all([...])</code>, which merges the ordered segments into a
      single props <code>Dictionary</code> at render time. Elements with no spread keep the plain
      dictionary-literal fast path unchanged.
    </Typography>

    {/* ── Modules & Hooks ────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Modules & Hooks
    </Typography>
    <Typography variant="body2" paragraph>
      Reusable logic lives in a <code>module</code>. Inside it, use the <code>hook</code> keyword to
      declare custom hooks (which may call built-in hooks via <code>Hooks.*</code>), plus static
      constants and helper functions. When a module's name matches a component, it extends that
      component's generated class. See the <strong>Companion Files</strong> page for the full model.
    </Typography>
    <CodeBlock language="jsx" code={`module PlayerCard {
  const HEALTH_GREEN := Color(0.2, 0.8, 0.3)

  static func format_health(current: int, max: int) -> String:
    return "%d / %d HP" % [current, max]

  hook use_flash(active: bool) -> bool {
    var s = Hooks.useState(false)
    Hooks.useEffect(func():
      s[1].call(active)
      return Callable()
    , [active])
    return s[0]
  }
}`} />

    {/* ── Rules & Gotchas ────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Rules & Gotchas
    </Typography>
    <Typography component="ul" variant="body2">
      <li><code>@class_name</code> and <code>@uss</code> must appear before the declaration keyword.</li>
      <li>Hook calls must be unconditional at component top level — not inside <code>@if</code>, <code>@for</code>, etc.</li>
      <li>Control-flow directive bodies contain bare markup; setup statements go before the markup inside the block.</li>
      <li>Direct children of <code>@for</code> need a <code>key</code> attribute for stable reconciliation.</li>
      <li>Components must return a single root element (or a single raw <code>{'{ expr }'}</code>).</li>
      <li>The declaration name should match the file / <code>@class_name</code> (e.g. <code>MyButton.guitkx</code> defines <code>component MyButton</code>).</li>
      <li><code>@match</code> is a statement-level directive; it can't be embedded inside a <code>{'{ expr }'}</code> attribute or child value.</li>
    </Typography>
  </Box>
)
