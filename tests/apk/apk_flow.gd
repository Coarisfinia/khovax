extends RefCounted
## The one e2e flow on the APK (#61): the main scene, a fixed seed, and the touch stick walking the
## player, tick by tick, so the game is exactly the same everywhere. It checks that the player
## walked, the trail grew and the camera follows, and that the game ended in exactly the expected
## state. It runs on an Android emulator in CI (started by game/test_mode.gd in the test APK), and
## headless in the required check (tests/e2e/test_apk_flow.gd), which also pins EXPECTED_HASH: a
## pass on the device means Android plays the very same game.

## With the flow's result: "" when it passed, or why it failed.
signal finished(result: String)

const SEED: int = 7
const STEP: float = 1.0 / Simulation.TICKS_PER_SECOND
## The finger's drags from where it touched down, in RADIUS units, and the ticks each one is held.
const LEGS: Array[Vector2] = [Vector2(1.0, 0.0), Vector2(0.0, -1.0), Vector2(-1.0, 0.0)]
const LEG_TICKS: int = 20
const FINGER: int = 0
## The state hash after the scripted walk; when a rule change alters it on purpose, update it with
## the golden replays (see AGENTS.md).
const EXPECTED_HASH: int = 3_313_556_164


## Runs the flow in `main` (the running main scene) and announces the result with `finished`.
## Callers that only load this script by path (the APK's test mode) start it this way.
func begin(main: Node, tree: SceneTree) -> void:
	finished.emit(await run(main, tree))


## Walks the scripted path in `main` and returns why it failed, or "". Real time passes once at the
## end, for the camera to follow.
func run(main: Node, tree: SceneTree) -> String:
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var camera: Camera3D = main.get_node("Camera3D") as Camera3D
	var origin: Vector2 = main.get_viewport().get_visible_rect().size / 2.0
	driver.set_process(false)
	driver.start(SEED)
	var start: Vector2i = driver.state.player(0).tile
	var camera_before: Vector3 = camera.global_position
	_touch(origin, true)
	for leg: Vector2 in LEGS:
		_drag(origin + leg * TouchStick.RADIUS)
		_run_ticks(driver, LEG_TICKS)
	_touch(origin, false)
	_run_ticks(driver, LEG_TICKS)
	# Frames pass in real time here, so the views and the camera catch up with the state.
	await tree.create_timer(1.5).timeout
	return _result(driver, camera, start, camera_before)


func _result(
	driver: GameDriver,
	camera: Camera3D,
	start: Vector2i,
	camera_before: Vector3,
) -> String:
	var player: Entity = driver.state.player(0)
	var trails: TrailFeature = driver.state.feature(Features.TRAIL) as TrailFeature
	if player.tile == start or trails.trail(player.id).tiles.size() < 3:
		return "the touch stick didn't walk the player (on %s, from %s)" % [player.tile, start]
	if camera.global_position.is_equal_approx(camera_before):
		return "the camera didn't follow the player"
	if driver.state.state_hash() != EXPECTED_HASH:
		return "the game ended in state %d, expected %d" % [
			driver.state.state_hash(),
			EXPECTED_HASH,
		]
	return ""


func _run_ticks(driver: GameDriver, ticks: int) -> void:
	for _tick: int in ticks:
		driver.advance(STEP)


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
