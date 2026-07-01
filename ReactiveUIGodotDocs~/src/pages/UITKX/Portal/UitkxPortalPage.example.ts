export const PORTAL_BASIC = `@class_name ModalDemo

component ModalDemo() {
  var show = use_state(false)
  var mounted = use_state(false)
  var target = use_ref(null)   // the host subtree we portal INTO

  // The target node only exists after the first commit, so flip a flag from a
  // mount effect and render the portal on the next pass.
  use_effect(func():
    mounted[1].call(true)
    return Callable()
  , [])

  var overlay = null
  if show[0] and mounted[0] and target["current"] != null:
    overlay = V.portal(target["current"], [
      V.vbox({ "style": { "separation": 8, "pad": 16 } }, [
        V.label({ "text": "I am a modal!" }),
        V.button({ "text": "Close", "onClick": func(): show[1].call(false) }),
      ]),
    ])

  return (
    <HBox style={ {"separation": 16} }>
      <VBox style={ {"expand_h": true, "separation": 8} }>
        // Logical parent — the portal is DECLARED here...
        <Button text="Open Modal" onClick={ func(): show[1].call(true) } />
        { overlay }
      </VBox>
      // ...but MOUNTED into this panel (captured with a ref).
      <Panel ref={ target } style={ {"min_size": Vector2(280, 160)} } />
    </HBox>
  )
}`

export const PORTAL_TARGET = `# V.portal takes a live Godot Node as its target. The two common ways to get one:

# 1. Capture a node rendered elsewhere in the SAME tree, with a ref:
var target = use_ref(null)
# <Panel ref={ target } />           # in markup
V.portal(target["current"], [ ...children ])

# 2. Reach a node OUTSIDE the reactive tree (an overlay CanvasLayer in your
#    scene) via the mount viewport or an autoload:
var overlay := get_tree().root.get_node("UI/OverlayLayer")
V.portal(overlay, [ ...children ])`
