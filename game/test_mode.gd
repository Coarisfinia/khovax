extends Node
## The test builds' mode (#61, #102, #113): in a test build, the game plays the device e2e flow
## instead of waiting for a player, prints KHOVAX_E2E: PASS with the game's final state hash, or
## FAIL with the reason, for CI to read (from the device log, the browser console or stdout) and
## compare with the headless run's hash (#876), and quits with it as the exit code. Only
## the test builds have it: their export presets in export_presets.cfg add the TEST_BUILD feature
## and carry the flow. In every other build this does nothing. No launch flag is needed: Android
## starts the game through a launcher activity that drops intent extras.
##
## Which flow it plays comes from outside the game's code (#551), so no game script names tests/:
## the FLOW_VARIABLE environment variable first, so CI can start any flow on a desktop or Linux
## test build, and otherwise the FLOW_SETTING project setting, empty in project.godot and filled
## for the TEST_BUILD feature with the device flow, since Android and the browser pass the game no
## environment.

## The export feature only the test builds' presets set.
const TEST_BUILD: String = "e2e_test"
const FLOW_VARIABLE: String = "KHOVAX_E2E_FLOW"
const FLOW_SETTING: String = "khovax/e2e_flow"


func _ready() -> void:
	if not OS.has_feature(TEST_BUILD):
		return
	# The flow plays a fresh world from a fixed seed: it never resumes or overwrites a saved one.
	# Autoloads are ready before the main scene, so its keeper never sees the default.
	WorldKeeper.default_path = ""
	# Autoloads are ready before the main scene is loaded, so its driver starts on this seed.
	GameDriver.fixed_seed = 0
	var flow_path: String = _flow_path()
	if flow_path.is_empty() or not ResourceLoader.exists(flow_path):
		_report("this build has no test flow at '%s'" % flow_path)
		return
	# The boot scene comes up after the autoloads, starts the game once it has loaded (#243), and
	# leaves once its fog has lifted. The flow waits for that: the fog stops touches while it hides
	# the game, and on a slow device the flow's first touches would land on it.
	await get_tree().process_frame
	var boot: Boot = get_tree().current_scene as Boot
	if boot != null:
		await boot.tree_exited
	_cheapest_frames(get_tree().current_scene)
	# Any error logged during the flow fails it: a script error in it would end it with "", a pass.
	# Content that fails to load while the flow waits for it counts too.
	var errors: ErrorCounter = ErrorCounter.new()
	OS.add_logger(errors)
	# The flow plays with all the content read (#816), as the headless run does (run_e2e.gd): a walk
	# holding at an exit while the boot's background fill still runs would play out by this
	# device's speed and end in another hash.
	ContentFill.wait()
	var flow: Object = (load(flow_path) as GDScript).new()
	var done: Signal = Signal(flow, "finished")
	flow.call("begin", get_tree().current_scene, get_tree())
	var result: String = await done
	OS.remove_logger(errors)
	if result.is_empty() and errors.count > 0:
		result = "%d error(s) logged during the flow" % errors.count
	_report(result, str(flow.get("final_hash")))


## The flow to play: the environment's, or else the one the project setting names.
static func _flow_path() -> String:
	var from_environment: String = OS.get_environment(FLOW_VARIABLE)
	if not from_environment.is_empty():
		return from_environment
	return str(ProjectSettings.get_setting_with_override(FLOW_SETTING))


## Turns anti-aliasing off for the flow, without saving it (#193): the flow waits real time for
## every tick, and a CI browser draws WebGL on the CPU, where MSAA and the ink pass's smoothing are
## the costliest work per pixel; on a busy runner they slowed frames enough to run out of time. The
## flow's checks and hash don't depend on the look.
static func _cheapest_frames(main: Node) -> void:
	var graphics: Graphics = main.get_node_or_null("Graphics") as Graphics
	if graphics != null:
		graphics.settings.chosen[Graphics.ANTI_ALIASING] = Viewport.MSAA_DISABLED
		graphics.apply()


## Prints the result, with the flow's final state hash on a pass.
func _report(result: String, final_hash: String = "") -> void:
	# CI reads the result from the log, which is where print goes on Android and on the web.
	# gdstyle:ignore=quality/no-debug-print
	print("KHOVAX_E2E: " + ("PASS " + final_hash if result.is_empty() else "FAIL " + result))
	get_tree().quit(0 if result.is_empty() else 1)
