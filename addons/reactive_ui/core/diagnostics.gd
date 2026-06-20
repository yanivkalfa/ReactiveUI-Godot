class_name RUIDiagnostics
extends RefCounted
## Opt-in render/commit metrics. Toggle `RUIDiagnostics.enabled = true`, then read the
## counters or `report()`. The reconciler feeds these. Analogue of ReactiveUIToolKit's
## diagnostics / WhyDidYouRender (lightweight counter form).

static var enabled := false
static var renders := 0       ## component render-fn invocations (excludes bailouts)
static var commits := 0       ## commit passes
static var placements := 0    ## host nodes inserted
static var updates := 0       ## host nodes prop-diffed
static var deletions := 0     ## subtrees removed

static func reset() -> void:
	renders = 0
	commits = 0
	placements = 0
	updates = 0
	deletions = 0

static func on_render() -> void: if enabled: renders += 1
static func on_commit() -> void: if enabled: commits += 1
static func on_placement() -> void: if enabled: placements += 1
static func on_update() -> void: if enabled: updates += 1
static func on_deletion() -> void: if enabled: deletions += 1

static func report() -> Dictionary:
	return {
		"renders": renders, "commits": commits, "placements": placements,
		"updates": updates, "deletions": deletions,
	}
