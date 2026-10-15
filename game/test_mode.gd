extends Node
## The test builds' mode (#61, #102, #113): in a test build, the game plays the device e2e flow
## instead of waiting for a player, prints KHOVAX_E2E: PASS or FAIL with the reason for CI to read
## (from the device log, the browser console or stdout), and quits with it as the exit code. Only
## the test builds have it: their export presets in export_presets.cfg add the TEST_BUILD feature
## and carry the flow (tests/apk/). In every other build this does nothing. No launch flag is
## needed: Android starts the game through a launcher activity that drops intent extras.

## The export feature only the test builds' presets set.
const TEST_BUILD: String = "e2e_test"
const FLOW: String = "res://tests/apk/apk_flow.gd"


func _ready() -> void:
	if not OS.has_feature(TEST_BUILD):
		return
	# The flow plays a fresh world from a fixed seed: it never resumes or overwrites a saved one.
	# Autoloads are ready before the main scene, so its keeper never sees the default.
	WorldKeeper.default_path = ""
	if not ResourceLoader.exists(FLOW):
		_report("this build has no device test flow")
		return
	# The main scene comes up after the autoloads.
	await get_tree().process_frame
	_cheapest_frames(get_tree().current_scene)
	# Any error logged during the flow fails it: a script error in it would end it with "", a pass.
	var errors: ErrorCounter = ErrorCounter.new()
	OS.add_logger(errors)
	var flow: Object = (load(FLOW) as GDScript).new()
	var done: Signal = Signal(flow, "finished")
	flow.call("begin", get_tree().current_scene, get_tree())
	var result: String = await done
	OS.remove_logger(errors)
	if result.is_empty() and errors.count > 0:
		result = "%d error(s) logged during the flow" % errors.count
	_report(result)


## Turns anti-aliasing off for the flow, without saving it (#193): the flow waits real time for
## every tick, and a CI browser draws WebGL on the CPU, where MSAA and the ink pass's smoothing are
## the costliest work per pixel; on a busy runner they slowed frames enough to run out of time. The
## flow's checks and hash don't depend on the look.
static func _cheapest_frames(main: Node) -> void:
	var graphics: Graphics = main.get_node_or_null("Graphics") as Graphics
	if graphics != null:
		graphics.settings.chosen[Graphics.ANTI_ALIASING] = Viewport.MSAA_DISABLED
		graphics.apply()


func _report(result: String) -> void:
	# CI reads the result from the log, which is where print goes on Android and on the web.
	# gdstyle:ignore=quality/no-debug-print
	print("KHOVAX_E2E: " + ("PASS" if result.is_empty() else "FAIL " + result))
	get_tree().quit(0 if result.is_empty() else 1)
