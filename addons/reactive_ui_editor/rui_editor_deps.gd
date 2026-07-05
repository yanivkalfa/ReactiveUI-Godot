@tool
class_name RUIEditorDeps
extends RefCounted
## Dependency handshake against the `reactive_ui` runtime addon (parity plan S1/S2/F9).
##
## This editor addon REQUIRES reactive_ui (compiler/formatter/lexer). Referencing its global
## classes from a script that loads while the dependency is absent is a hard, unfriendly compile
## failure — so plugin.gd checks HERE first and only then loads the editor scripts (which may use
## the RUIGuitkx* classes directly). This file itself must never name them.

## Oldest reactive_ui this editor is tested against. 0.5.0 pairs with 0.8.4: the Problems panel's
## project scope and the sidecar overlay read the sweep's refs/2106/2107 verdicts, and mixed-version
## reports are not worth debugging — the two assets release together.
const MIN_REACTIVE_UI := "0.8.4"

const _DEP_DIR := "res://addons/reactive_ui"
const _DEP_CFG := _DEP_DIR + "/plugin.cfg"
const _COMPILER := _DEP_DIR + "/guitkx/guitkx.gd"
const _FORMATTER := _DEP_DIR + "/guitkx/guitkx_formatter.gd"

## { ok: bool, reason: String, version: String } — reason is user-facing when not ok.
static func satisfied() -> Dictionary:
	if not FileAccess.file_exists(_DEP_CFG):
		return {
			"ok": false, "version": "",
			"reason": "The 'Reactive UI' addon (addons/reactive_ui) is not installed. " +
				"Install it from the Godot Asset Store, then re-enable this plugin.",
		}
	var ver := installed_version()
	if ver != "" and _version_lt(ver, MIN_REACTIVE_UI):
		return {
			"ok": false, "version": ver,
			"reason": "Reactive UI %s is installed, but this editor needs %s or newer. Update the 'Reactive UI' addon." % [ver, MIN_REACTIVE_UI],
		}
	for p in [_COMPILER, _FORMATTER]:
		if not FileAccess.file_exists(p):
			return {
				"ok": false, "version": ver,
				"reason": "The 'Reactive UI' addon looks incomplete (missing %s). Reinstall it." % p,
			}
	return { "ok": true, "reason": "", "version": ver }

static func installed_version() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(_DEP_CFG) != OK:
		return ""
	return str(cfg.get_value("plugin", "version", ""))

## Numeric semver compare (lexicographic would say "0.10.0" < "0.8.0").
static func _version_lt(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var na := int(pa[i]) if i < pa.size() else 0
		var nb := int(pb[i]) if i < pb.size() else 0
		if na != nb:
			return na < nb
	return false
