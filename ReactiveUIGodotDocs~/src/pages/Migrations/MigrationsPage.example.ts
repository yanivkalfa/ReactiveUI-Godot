// Code samples for the Migrations page.

export const MIGRATE_0_10_CMD = `godot --headless --path . --script res://addons/reactive_ui/dev/migrate_0_10_0.gd`

export const MIGRATE_0_10_BEFORE_AFTER = `# BEFORE (0.9 — implicit cross-file references)
component Panel() {
  var b = HudHooks.use_blink(0.5)
  return ( <StatusChip /> )
}

# AFTER (0.10 — the codemod writes this for you)
import { HudHooks } from "./hud.hooks"
import { StatusChip } from "./status_chip"

export component Panel() {
  var b = HudHooks.use_blink(0.5)
  return ( <StatusChip /> )
}`

export const MIGRATE_0_9_CMD = `# dry run first (prints what would change, writes nothing):
godot --headless --path . --script res://addons/reactive_ui/dev/migrate_0_9_0.gd -- --dry-run
# then for real:
godot --headless --path . --script res://addons/reactive_ui/dev/migrate_0_9_0.gd`

export const MIGRATE_0_9_EXAMPLES = `<VBox>            ->  <VBoxContainer>
<RichText>        ->  <RichTextLabel>
onClick={...}     ->  onPressed={...}
onChange={...}    ->  onValueChanged={...} / onTextChanged={...} (per signal)
"fill": true      ->  "anchors_preset": Control.PRESET_FULL_RECT`
