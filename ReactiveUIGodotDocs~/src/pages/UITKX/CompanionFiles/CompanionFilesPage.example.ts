export const EXAMPLE_UITKX = `import { PlayerCardStyle } from "./PlayerCard.style"
import { PlayerCardUtils } from "./PlayerCard.utils"

export component PlayerCard(player: PlayerInfo) {
  var health_color = PlayerCardStyle.HEALTH_GREEN \\
    if player.health > player.max_health / 2 \\
    else PlayerCardStyle.DAMAGE_RED

  return (
    <VBoxContainer>
      <Label text={ player.name } />
      <Label text={ PlayerCardUtils.format_health(player.health, player.max_health) }
             style={ {"font_color": health_color} } />
      <Label text={ PlayerCardUtils.rank_label(player.rank) } />
    </VBoxContainer>
  )
}`

export const EXAMPLE_GENERATED_CLASS = `# Auto-generated sibling: PlayerCard.gd (simplified)
class_name PlayerCard          # ← inferred: first exported declaration
extends RefCounted
## AUTO-GENERATED from PlayerCard.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
    var player = props.get("player")   # ← from the component parameter
    ...`

export const EXAMPLE_DIRECTORY = `res://ui/PlayerCard/
  PlayerCard.guitkx            # component      -> PlayerCard.gd
  PlayerCard.hooks.guitkx      # hooks module   -> PlayerCard.hooks.gd (optional)
  PlayerCard.style.guitkx      # styles module  -> PlayerCard.style.gd (optional)
  PlayerCard.utils.guitkx      # utilities      -> PlayerCard.utils.gd (optional)`

export const EXAMPLE_HOOKS = `# PlayerCard.hooks.guitkx
export module PlayerCardHooks {
  hook use_player_animation(player: PlayerInfo) -> Dictionary {
    var opacity = Hooks.useState(1.0)
    var flashing = Hooks.useState(false)

    Hooks.useEffect(func():
      if player.health <= 0:
        flashing[1].call(true)
        opacity[1].call(0.5)
      return Callable()
    , [player.health])

    return { "opacity": opacity[0], "flashing": flashing[0] }
  }
}`

export const EXAMPLE_STYLES = `# PlayerCard.style.guitkx
export module PlayerCardStyle {
  static var HEALTH_GREEN := Color(0.2, 0.8, 0.3)
  static var DAMAGE_RED   := Color(0.9, 0.2, 0.2)
  static var AVATAR_SIZE  := 64.0

  static var CARD := {
    "bg_color": Color(0.10, 0.10, 0.18),
    "corner_radius_all": 8,
    "content_margin_all": 8,
    "separation": 8,
  }
}`

export const EXAMPLE_TYPES = `# PlayerCard.types.guitkx
export module PlayerCardTypes {
  enum PlayerRank { BRONZE, SILVER, GOLD, DIAMOND }

  # A plain typed dictionary shape used by the component.
  # (GDScript has no init-only structs; use a Dictionary or a small class.)
  static func make_player(name: String, health: int, max_health: int, rank: int) -> Dictionary:
    return { "name": name, "health": health, "max_health": max_health, "rank": rank }
}`

export const EXAMPLE_UTILS = `# PlayerCard.utils.guitkx
import { PlayerCardTypes } from "./PlayerCard.types"

export module PlayerCardUtils {
  static func format_health(current: int, max: int) -> String:
    return "%d / %d HP" % [current, max]

  static func rank_label(rank: int) -> String:
    match rank:
      PlayerCardTypes.PlayerRank.DIAMOND: return "★ Diamond"
      PlayerCardTypes.PlayerRank.GOLD:    return "● Gold"
      PlayerCardTypes.PlayerRank.SILVER:  return "○ Silver"
      _:                                  return "· Bronze"
}`

export const EXAMPLE_STANDALONE = `# SharedColors.guitkx — standalone module, not tied to a specific component
export module SharedColors {
  static var GOLD   := Color(1.0, 0.84, 0.0)
  static var SILVER := Color(0.75, 0.75, 0.75)
}`
