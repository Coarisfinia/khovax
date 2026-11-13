extends RefCounted
## The one e2e flow on the devices (#61, #102): the main scene, a fixed seed, and the touch stick
## walking the player, tick by tick, so the game is exactly the same everywhere: from the glade's
## start, where the world starts (#712), out through its north exit into the forest, a few steps in,
## and back (#139, #152). It checks that the player walked into the forest and back, the trail grew
## and the camera follows, and keeps the game's final state hash. It runs on an Android emulator,
## in headless Chrome and on the Linux build in CI (started by game/test_mode.gd in the test
## builds), and headless (tests/e2e/test_apk_flow.gd). CI compares each device's final hash with
## the headless one for the same commit (#876): a pass on a device means it plays the very same
## game. On the web it then saves the error log with a controller's press alone (#1598), which the
## web e2e job checks arrives as a download.

## With the flow's result: "" when it passed, or why it failed.
signal finished(result: String)

const SEED: int = 7
const STEP: float = 1.0 / Simulation.TICKS_PER_SECOND
## The finger's drags from where it touched down, in RADIUS units, and the ticks each one is held:
## from the start on (0, 0) a step northeast, then northwest onto the exit on (1, -5), through it
## into the forest and on, then southeast all the way back out into the glade.
const LEGS: Array[Vector2] = [
	Vector2(0.5, -0.866),
	Vector2(-0.5, -0.866),
	Vector2(0.5, 0.866),
]
const LEG_TICKS: Array[int] = [6, 42, 48]
## Ticks the finger rests lifted after the last leg.
const REST_TICKS: int = 20
const FINGER: int = 0
## The instances the walk goes through, named here because the device builds leave out the e2e
## flows' FlowSteps (#915).
const GLADE: String = "lumwen_hoal"
const FOREST: String = "morwe_wudhen"
## The Credits tab, whose error log button the web flow presses, and what its note says first.
const CREDITS: String = "res://slices/credits/ui/credits_tab.tscn"
const BROWSER_MAY_ASK: String = "Your browser may ask to allow the download"

## The game's state hash when the walk ended, which game/test_mode.gd reports with the result.
var final_hash: int = 0
## Every instance the player stood in during the walk.
var _visited: Dictionary[String, bool] = {}


## Runs the flow in `main` (the running main scene) and announces the result with `finished`.
## Callers that only load this script by path (the test builds' mode) start it this way.
func begin(main: Node, tree: SceneTree) -> void:
	finished.emit(await run(main, tree))


## Walks the scripted path in `main` and returns why it failed, or "". Each tick waits for its
## real time, so the walk plays at the game's speed and the web e2e job's video shows it.
func run(main: Node, tree: SceneTree) -> String:
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var camera: Camera3D = main.get_node("Camera3D") as Camera3D
	var origin: Vector2 = main.get_viewport().get_visible_rect().size / 2.0
	driver.set_process(false)
	# Where the world starts, also under the e2e runner, whose flows start in the playground.
	driver.instance = GLADE
	driver.start(SEED)
	_visited.clear()
	var start: Vector2i = driver.state.player(0).tile
	var camera_before: Vector3 = camera.global_position
	_touch(origin, true)
	await _play(driver, tree, origin, 0, 0)
	# Frames pass in real time here, so the views and the camera catch up with the state.
	await tree.create_timer(1.5).timeout
	final_hash = driver.state.state_hash()
	var result: String = _result(driver, camera, start, camera_before)
	if result.is_empty():
		result = _save_log_by_controller(main)
	return result if not result.is_empty() else _check_pack_folder()


func _result(
	driver: GameDriver,
	camera: Camera3D,
	start: Vector2i,
	camera_before: Vector3,
) -> String:
	if not _visited.has(FOREST):
		return "the walk never reached the forest: %s" % [_visited.keys()]
	if driver.world.instance_of(0) != GLADE:
		return "the walk didn't come back into the glade"
	var player: Entity = driver.state.player(0)
	var trails: TrailFeature = driver.state.feature(TrailFeature.ID) as TrailFeature
	if player.tile == start or trails.shared.tiles.size() < 3:
		return "the touch stick didn't walk the player (on %s, from %s)" % [player.tile, start]
	if camera.global_position.is_equal_approx(camera_before):
		return "the camera didn't follow the player"
	return ""


## Plays the walk from tick `tick` of leg `leg` on, one tick per its real time: each leg drags the
## finger, then the finger lifts for one more leg's ticks. Recursive, since the ticks come one
## after another by design.
func _play(driver: GameDriver, tree: SceneTree, origin: Vector2, leg: int, tick: int) -> void:
	if leg > LEGS.size():
		return
	if tick == 0 and leg < LEGS.size():
		_drag(origin + LEGS[leg] * TouchStick.RADIUS)
	elif tick == 0:
		_touch(origin, false)
	driver.advance(STEP)
	_visited[driver.world.instance_of(0)] = true
	await tree.create_timer(STEP).timeout
	if tick + 1 < (LEG_TICKS[leg] if leg < LEGS.size() else REST_TICKS):
		await _play(driver, tree, origin, leg, tick + 1)
	else:
		await _play(driver, tree, origin, leg + 1, 0)


## On the web, saves the error log the way a player with only a controller does (#1598): the
## Credits tab's save button, focused, pressed with a controller's A. The page has had no click or
## key press, so the browser has to let the download through without any user activation;
## src/game-web-e2e/web_e2e.py checks that it arrives and holds the log. Then the tab has to show
## the note under the button (#1817). Elsewhere the button hides, and nothing is saved.
func _save_log_by_controller(main: Node) -> String:
	if not OS.has_feature("web"):
		return ""
	var page: Node = (load(CREDITS) as PackedScene).instantiate()
	main.add_child(page)
	var save: ErrorLogButton = page.get_node("ErrorLog") as ErrorLogButton
	if not save.visible:
		page.queue_free()
		return "the error log's save button doesn't show on the web"
	save.grab_focus()
	_press_a(true)
	_press_a(false)
	var result: String = _log_note(page)
	page.queue_free()
	return result


## After the save the Credits tab says, under the button, that the browser may ask to allow the
## download, which a controller can't answer, and shows the log's newest lines, for a player with
## only a controller to read or photograph (#1817).
static func _log_note(page: Node) -> String:
	var note: Label = page.get_node_or_null("ErrorLogNote") as Label
	if note == null or not note.is_visible_in_tree():
		return "after the save the Credits tab shows no note under the error log's button"
	var logged: String = FileAccess.get_file_as_string(ErrorLog.PATH).strip_edges()
	var newest: String = logged.get_slice("\n", logged.get_slice_count("\n") - 1)
	if not note.text.contains(BROWSER_MAY_ASK) or not note.text.contains(newest):
		return (
			"the note under the error log's button doesn't say the browser may ask and show the"
			+ " log's newest line (%s): %s" % [newest, note.text]
		)
	return ""


## The folder a player's resource packs are found in (#1942): on Android the app's folder on the
## shared storage, which a player reaches over USB, never the private `user://`, and the game can
## write and read a file there; everywhere else `user://packs/`.
func _check_pack_folder() -> String:
	var folder: String = PackFolder.path()
	if not OS.has_feature("android"):
		var off: bool = folder != PackFolder.USER
		return "the packs folder isn't user://packs/: " + folder if off else ""
	if folder.begins_with("user://") or folder.begins_with(OS.get_user_data_dir()):
		return "on Android the packs folder is the app's private storage: " + folder
	if not folder.contains("/Android/data/") or not folder.ends_with("/packs/"):
		return "on Android the packs folder isn't the app's shared storage folder: " + folder
	var probe: String = folder + "probe.txt"
	var file: FileAccess = FileAccess.open(probe, FileAccess.WRITE)
	if file == null:
		return "the packs folder on Android can't be written: " + folder
	var _stored: bool = file.store_string("pack")
	file.close()
	var read: String = FileAccess.get_file_as_string(probe)
	var _removed: Error = DirAccess.remove_absolute(probe)
	return "" if read == "pack" else "the packs folder on Android can't be read: " + folder


func _press_a(pressed: bool) -> void:
	var press: InputEventJoypadButton = InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_A
	press.pressed = pressed
	Input.parse_input_event(press)
	Input.flush_buffered_events()


func _touch(point: Vector2, pressed: bool) -> void:
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.index = FINGER
	touch.position = point
	touch.pressed = pressed
	Input.parse_input_event(touch)
	Input.flush_buffered_events()


func _drag(point: Vector2) -> void:
	var drag: InputEventScreenDrag = InputEventScreenDrag.new()
	drag.index = FINGER
	drag.position = point
	Input.parse_input_event(drag)
	Input.flush_buffered_events()
