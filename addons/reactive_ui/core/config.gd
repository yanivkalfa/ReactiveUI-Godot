class_name RUIConfig
extends RefCounted
## Global reactive-UI configuration.
##
## Time-slicing is OFF by default — synchronous renders are simplest and fast for normal
## UIs. Turn it on for very large trees that would otherwise stutter on a big update: the
## render phase is then chunked across frames (commit stays atomic). Ports the frame-budget
## idea from ReactiveUIToolKit's RenderScheduler.
##
##   RUIConfig.time_slicing = true
##   RUIConfig.frame_budget_ms = 8.0   # work per frame before parking until the next one

static var time_slicing := false
static var frame_budget_ms := 8.0
