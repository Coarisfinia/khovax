extends Node
## The APK's test mode (#61): in the test APK, the game plays the APK's e2e flow instead of waiting
## for a player, prints KHOVAX_APK_E2E: PASS or FAIL with the reason for CI to read from the device
## log, and quits. Only the test APK has it: its export preset ("Android Test") adds the TEST_BUILD
## feature and carries the flow (tests/apk/). In every other build this does nothing. No launch
## flag is needed: Android starts the game through a launcher activity that drops intent extras.

## The export feature only the test APK's preset sets.
const TEST_BUILD: String = "apk_test"
const FLOW: String = "res://tests/apk/apk_flow.gd"


func _ready() -> void:
	if not OS.has_feature(TEST_BUILD):
		return
	if not ResourceLoader.exists(FLOW):
		_report("this build has no APK test flow")
		return
	# The main scene comes up after the autoloads.
	await get_tree().process_frame
	var flow: Object = (load(FLOW) as GDScript).new()
	var done: Signal = Signal(flow, "finished")
	flow.call("begin", get_tree().current_scene, get_tree())
	var result: String = await done
	_report(result)


func _report(result: String) -> void:
	# CI reads the result from the device log, which is where print goes on Android.
	# gdstyle:ignore=quality/no-debug-print
	print("KHOVAX_APK_E2E: " + ("PASS" if result.is_empty() else "FAIL " + result))
	get_tree().quit(0 if result.is_empty() else 1)
