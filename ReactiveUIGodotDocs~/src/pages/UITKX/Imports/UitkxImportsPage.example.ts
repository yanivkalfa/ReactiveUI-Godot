// Code samples for the Imports page. Kept in a sibling module so the page component stays prose.

export const EXAMPLE_IMPORT_BASIC = `import { StatusChip } from "./status_chip"
import { DoomGameScreenHooks, DoomHudStyles } from "~/demos/doom/doom_game_screen.hooks"

export component Hud(level: int = 1) {
	var styles = DoomHudStyles.for_level(level)
	return (
		<PanelContainer>
			<StatusChip label={styles.title} />
		</PanelContainer>
	)
}`

export const EXAMPLE_SPECIFIERS = `import { Card } from "./card"          # sibling file
import { Panel } from "../shared/panel"  # relative, up a directory
import { Theme } from "~/ui/theme"       # ~/ = the project UI source root`

export const EXAMPLE_EXPORT = `# A file may hold several declarations. \`export\` makes one reachable across files;
# the binding (the file's class_name) is the @class_name override, else the first exported decl.

export component Hud() {
	return ( <LocalRow /> )
}

component LocalRow() {        # no export = file-private, unreachable from other files
	return ( <Label text="row" /> )
}

export hook use_blink(interval: float) -> Dictionary { … }

export module HudStyles { … }`

export const EXAMPLE_CONFIG = `{
  "root": "res://ui",
  "formatter": { "indentStyle": "tab" }
}`

export const EXAMPLE_MIGRATE = `godot --headless --path . --script res://tests/guitkx_migrate.gd`
