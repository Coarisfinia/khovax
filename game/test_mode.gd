extends Node
## The APK's test mode (#61): started with --khovax-apk-test (on Android, through the launch
## intent's command_line_params), the game plays the APK's e2e flow instead of waiting for a
## player, prints KHOVAX_APK_E2E: PASS or FAIL with the reason for CI to read from the device log,
## and quits. Only the test APK has it: its export preset adds the TEST_BUILD feature and carries
## the
## flow (tests/apk/). In every other build, and without the flag, this does nothing.

const FLAG: String = "--khovax-apk-test"
## The export feature only the test APK's preset ("Android Test") sets.
const TEST_BUILD: String = "apk_test"
const FLOW: String = "res://tests/apk/apk_flow.gd"


func _ready() -> void:
	if not OS.has_feature(TEST_BUILD) or not OS.get_cmdline_args().has(FLAG):
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
	# gdstyle:ignore=quality/no-debug-print
	# CI reads the result from the device log, which is where print goes on Android.
	print("KHOVAX_APK_E2E: " + ("PASS" if result.is_empty() else "FAIL " + result))
	get_tree().quit(0 if result.is_empty() else 1)
