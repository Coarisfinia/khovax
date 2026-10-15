extends Node
## The test builds' mode (#61, #102): in the test APK and the test web build, the game plays the
## device e2e flow instead of waiting for a player, prints KHOVAX_E2E: PASS or FAIL with the reason
## for CI to read (from the device log on Android, from the browser console on the web), and quits.
## Only the test builds have it: their export presets ("Android Test", "Web Test") add the
## TEST_BUILD feature and carry the flow (tests/apk/). In every other build this does nothing. No
## launch flag is needed: Android starts the game through a launcher activity that drops intent
## extras.

## The export feature only the test builds' presets set.
const TEST_BUILD: String = "e2e_test"
const FLOW: String = "res://tests/apk/apk_flow.gd"


func _ready() -> void:
	if not OS.has_feature(TEST_BUILD):
		return
	if not ResourceLoader.exists(FLOW):
		_report("this build has no device test flow")
		return
	# The main scene comes up after the autoloads.
	await get_tree().process_frame
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


func _report(result: String) -> void:
	# CI reads the result from the log, which is where print goes on Android and on the web.
	# gdstyle:ignore=quality/no-debug-print
	print("KHOVAX_E2E: " + ("PASS" if result.is_empty() else "FAIL " + result))
	get_tree().quit(0 if result.is_empty() else 1)
