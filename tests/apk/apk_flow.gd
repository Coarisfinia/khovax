extends RefCounted
## The one e2e flow on the devices (#61, #102): the main scene, a fixed seed, and the touch stick
## walking the player, tick by tick, so the game is exactly the same everywhere: out through the
## basic instance's east exit into the glade, a few steps in, and back (#139, #152). It checks that
## the player walked into the glade and back, the trail grew and the camera follows, and that the
## game ended in exactly the expected state. It runs on an Android emulator and in headless Chrome
## in CI (started by
## game/test_mode.gd in the test APK and the test web build), and headless in the required check
## (tests/e2e/test_apk_flow.gd), which also pins EXPECTED_HASH: a pass on a device means it plays
## the very same game.

## With the flow's result: "" when it passed, or why it failed.
signal finished(result: String)

const SEED: int = 7
const STEP: float = 1.0 / Simulation.TICKS_PER_SECOND
## The finger's drags from where it touched down, in RADIUS units, and the ticks each one is held:
## from the start on (1, -1) a step east, a step northeast onto the exit on (3, -2), east through it
## into the glade and on, then west all the way back out into the basic instance.
const LEGS: Array[Vector2] = [
	Vector2(1.0, 0.0),
	Vector2(0.5, -0.866),
	Vector2(1.0, 0.0),
	Vector2(-1.0, 0.0),
]
const LEG_TICKS: Array[int] = [6, 6, 30, 48]
## Ticks the finger rests lifted after the last leg.
const REST_TICKS: int = 20
const FINGER: int = 0
## The state hash after the scripted walk; when a rule change alters it on purpose, update it with
## the golden replays (see AGENTS.md).
const EXPECTED_HASH: int = 2_303_524_187

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
	driver.start(SEED)
	_visited.clear()
	var start: Vector2i = driver.state.player(0).tile
	var camera_before: Vector3 = camera.global_position
	_touch(origin, true)
	await _play(driver, tree, origin, 0, 0)
	# Frames pass in real time here, so the views and the camera catch up with the state.
	await tree.create_timer(1.5).timeout
	return _result(driver, camera, start, camera_before)


func _result(
	driver: GameDriver,
	camera: Camera3D,
	start: Vector2i,
	camera_before: Vector3,
) -> String:
	if not _visited.has(InstanceBlueprints.GLADE):
		return "the walk never reached the glade: %s" % [_visited.keys()]
	if driver.world.instance_of(0) != InstanceBlueprints.BASIC:
		return "the walk didn't come back into the basic instance"
	var player: Entity = driver.state.player(0)
	var trails: TrailFeature = driver.state.feature(Features.TRAIL) as TrailFeature
	if player.tile == start or trails.shared.tiles.size() < 3:
		return "the touch stick didn't walk the player (on %s, from %s)" % [player.tile, start]
	if camera.global_position.is_equal_approx(camera_before):
		return "the camera didn't follow the player"
	if driver.state.state_hash() != EXPECTED_HASH:
		return "the game ended in state %d, expected %d" % [
			driver.state.state_hash(),
			EXPECTED_HASH,
		]
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
