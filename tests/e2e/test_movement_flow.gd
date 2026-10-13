extends RefCounted
## Movement flow, through every layer: keys and the touch stick press the movement actions, the
## local input turns them into commands, the simulation walks the player from tile to tile along a
## known path, zigzagging along a column for straight up and stopping at the grid's edge, and the
## view glides the cube between tiles without jumps. Real key and touch events reach the actions
## too. Time is stepped by hand, so the flow is deterministic.

const STEP: float = 1.0 / 60.0
## Seconds to walk from one tile to the next.
const MOVE_SECONDS: float = float(MovementFeature.MOVE_TICKS) / Simulation.TICKS_PER_SECOND
## Long enough to walk further than the grid allows in any one direction.
const HOLD_STEPS: int = 300
const ACTIONS: Array[String] = ["move_up", "move_down", "move_left", "move_right"]
## Where the touch legs put their finger down, in screen pixels.
const TOUCH_ORIGIN: Vector2 = Vector2(400.0, 300.0)
## The steering finger: not 0, so a check that ignores the index would be caught.
const FINGER: int = 1
const PHYSICAL_KEYS: Dictionary[String, Key] = {
	"move_up": KEY_W,
	"move_down": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
}
const ARROW_KEYS: Dictionary[String, Key] = {
	"move_up": KEY_UP,
	"move_down": KEY_DOWN,
	"move_left": KEY_LEFT,
	"move_right": KEY_RIGHT,
}

var _main: Node
var _cube: PlayerView
var _driver: GameDriver
var _grid: HexGrid
var _trail_view: TrailView
## Every tile the player has stood on in this flow: the start tile and every tile walked onto.
var _walked: Dictionary[Vector2i, bool] = {}
var _stick: TouchStick


func _input() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_down", "move_up")


func run(tree: SceneTree) -> String:
	var path: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return "main scene failed to load"
	_main = scene.instantiate()
	tree.root.add_child(_main)
	await tree.process_frame
	_cube = _main.get_node_or_null("Cube") as PlayerView
	_driver = _main.get_node_or_null("Driver") as GameDriver
	_grid = _main.get_node_or_null("HexGrid") as HexGrid
	_trail_view = _main.get_node_or_null("TrailView") as TrailView
	_stick = _main.get_node_or_null("Hud/TouchStick") as TouchStick
	var nodes: Array[Node] = [_cube, _driver, _grid, _trail_view, _stick]
	if nodes.has(null):
		_main.queue_free()
		return "the main scene needs Cube, Driver, HexGrid, TrailView and Hud/TouchStick"
	# Stepped by hand from here on.
	_driver.set_process(false)
	_cube.set_process(false)
	_trail_view.set_process(false)
	_walked = { _tile(): true }

	var result: String = _check_bindings()
	if result.is_empty():
		result = _check_paths()
	_release_all()
	_main.queue_free()
	await tree.process_frame
	return result


## Every action has exactly its WASD key (by physical position) and its arrow key, and a real key
## event for each one presses the action.
func _check_bindings() -> String:
	for action: String in ACTIONS:
		var physical: Key = PHYSICAL_KEYS[action]
		var arrow: Key = ARROW_KEYS[action]
		var has_physical: bool = false
		var has_arrow: bool = false
		for event: InputEvent in InputMap.action_get_events(action):
			var key: InputEventKey = event as InputEventKey
			if key != null:
				has_physical = has_physical or key.physical_keycode == physical
				has_arrow = has_arrow or key.keycode == arrow
		if not has_physical or not has_arrow:
			return "%s isn't bound to both its WASD key and its arrow key" % action
		if not _press_reaches(
			physical,
			KEY_NONE,
			action,
		) or not _press_reaches(KEY_NONE, arrow, action):
			return "a real key event doesn't press %s" % action
	return ""


## Sends a real key press, checks it pressed the action, and releases it again.
func _press_reaches(physical: Key, logical: Key, action: String) -> bool:
	var press: InputEventKey = InputEventKey.new()
	press.physical_keycode = physical
	press.keycode = logical
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	var pressed: bool = Input.is_action_pressed(action)
	# A fresh event: Godot refuses to parse the same event object twice in one frame.
	var release: InputEventKey = press.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	return pressed


## Each walk starts where the previous one stopped: (1, -1) is the cube's start tile.
func _check_paths() -> String:
	var walks: Array[Walk] = [
		Walk.new(["move_left"], [Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-2, -1)]),
		Walk.new(
			["move_right"],
			[Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(2, -1), Vector2i(3, -1)],
		),
		# Straight up from an odd row starts north-west; the next north-east step would leave the
		# grid.
		Walk.new(["move_up"], [Vector2i(3, -2)]),
		Walk.new(
			["move_down", "move_left"],
			[Vector2i(2, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 2), Vector2i(-2, 3)],
		),
		# Straight up and back down through both row parities: north-west and north-east in turn,
		# then south-east and south-west, each zigzag staying in its column.
		Walk.new(
			["move_up"],
			[Vector2i(-2, 2), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(0, -2),
				Vector2i(1, -3)],
		),
		Walk.new(
			["move_down"],
			[Vector2i(1, -2), Vector2i(0, -1), Vector2i(0, 0), Vector2i(-1, 1), Vector2i(-1, 2),
				Vector2i(-2, 3)],
		),
	]
	for walk: Walk in walks:
		var result: String = _walk(walk.keys, walk.path)
		if not result.is_empty():
			return "holding %s: %s" % [walk.keys, result]
	return _check_touch_paths()


## The touch stick continues from where the keys stopped, at (-2, 3).
func _check_touch_paths() -> String:
	var result: String = _walk_by_touch(
		Vector2(TouchStick.RADIUS, 0.0),
		[Vector2i(-1, 3), Vector2i(0, 3)],
	)
	if not result.is_empty():
		return "dragging right: " + result
	# Screen y grows downwards: dragging up the screen walks up the grid, zigzagging.
	var up: Array[Vector2i] = [
		Vector2i(
			0,
			2,
		), Vector2i(1, 1), Vector2i(1, 0), Vector2i(2, -1), Vector2i(2, -2), Vector2i(3, -3),
	]
	result = _walk_by_touch(Vector2(0.0, -TouchStick.RADIUS), up)
	if not result.is_empty():
		return "dragging up: " + result
	# A short drag stays inside the actions' dead zone and doesn't walk.
	result = _walk_by_touch(Vector2(TouchStick.RADIUS * 0.1, 0.0), [])
	if not result.is_empty():
		return "a tiny drag: " + result
	return _check_touch_details()


## Holds the keys and checks the walk.
func _walk(keys: Array[String], expected: Array[Vector2i]) -> String:
	for key: String in keys:
		Input.action_press(key)
	return _hold(expected, _release_all)


## Touches the screen, drags by `drag` pixels and holds there, the way a thumb steers the touch
## stick, then checks the walk and that lifting the finger stops it.
func _walk_by_touch(drag: Vector2, expected: Array[Vector2i]) -> String:
	_send_touch(FINGER, TOUCH_ORIGIN, true)
	_send_drag(FINGER, TOUCH_ORIGIN + drag)
	if not _stick.is_held():
		return "the touch stick didn't pick up the finger"
	var result: String = _hold(expected, _lift_finger)
	if result.is_empty() and (_stick.is_held() or not _input().is_zero_approx()):
		result = "lifting the finger didn't release the stick and its actions"
	return result


## Keeps the input held long enough to reach the grid's edge, then releases it with `release` and
## checks the tiles visited, in order, and that the drawn position never jumped.
func _hold(expected: Array[Vector2i], release: Callable) -> String:
	# Starts with the tile the walk leaves from; dropped again before comparing.
	var visited: Array[Vector2i] = [_tile()]
	var max_step: float = HexLayout.SIZE * sqrt(3.0) * STEP / MOVE_SECONDS + 0.0001
	var jumped: bool = false
	for _i: int in HOLD_STEPS:
		var before: Vector3 = _cube.position
		_step()
		jumped = jumped or before.distance_to(_cube.position) > max_step
		if visited[visited.size() - 1] != _tile():
			visited.append(_tile())
	release.call()
	_finish_step()
	visited.pop_front()
	if jumped:
		return "the cube jumped instead of gliding"
	if visited != expected:
		return "visited %s, expected %s" % [visited, expected]
	if not _cube.position.is_equal_approx(_cube.tile_position()):
		return "the cube didn't come to rest on its tile"
	for tile: Vector2i in visited:
		_walked[tile] = true
	return _check_trail()


## The trail is exactly the start tile and every tile walked onto so far, and the grid shows those
## tiles, and only those, in the trail color.
func _check_trail() -> String:
	var expected: Array[Vector2i] = []
	expected.assign(_walked.keys())
	expected.sort()
	var trail: TrailFeature = _driver.state.feature(Features.TRAIL) as TrailFeature
	if trail.sorted_tiles() != expected:
		return "the trail is %s, expected %s" % [trail.sorted_tiles(), expected]
	_trail_view.show_state()
	for tile: Vector2i in Hex.disc(_driver.state.grid_radius):
		var color: Color = _trail_view.trail_color if _walked.has(tile) else _grid.tile_color
		if _grid.tile_color_of(tile) != color:
			return "tile %s isn't drawn in the %s color" % [
				tile,
				"trail" if _walked.has(tile) else "tile",
			]
	return ""


func _lift_finger() -> void:
	_send_touch(FINGER, TOUCH_ORIGIN, false)


func _send_touch(finger: int, point: Vector2, pressed: bool, canceled: bool = false) -> void:
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.index = finger
	touch.position = point
	touch.pressed = pressed
	touch.canceled = canceled
	Input.parse_input_event(touch)
	Input.flush_buffered_events()


func _send_drag(finger: int, point: Vector2) -> void:
	var drag: InputEventScreenDrag = InputEventScreenDrag.new()
	drag.index = finger
	drag.position = point
	Input.parse_input_event(drag)
	Input.flush_buffered_events()


## Analog strength, a second finger, a canceled touch, and a key held through a touch.
func _check_touch_details() -> String:
	_send_touch(FINGER, TOUCH_ORIGIN, true)
	_send_drag(FINGER, TOUCH_ORIGIN + Vector2(TouchStick.RADIUS * 0.5, 0.0))
	var strength: float = Input.get_action_raw_strength("move_right")
	# A second finger touching and dragging elsewhere must not take over the steering.
	_send_touch(FINGER + 1, Vector2(900.0, 100.0), true)
	_send_drag(FINGER + 1, Vector2(900.0, 300.0))
	var kept: bool = _stick.steering().is_equal_approx(Vector2(0.5, 0.0))
	_send_touch(FINGER + 1, Vector2(900.0, 300.0), false)
	var still_held: bool = _stick.is_held()
	_send_touch(FINGER, TOUCH_ORIGIN, true, true)
	var canceled: bool = not _stick.is_held() and _input().is_zero_approx()
	if not is_equal_approx(strength, 0.5):
		return "half the drag radius pressed move_right at %f, not 0.5" % strength
	if not kept or not still_held:
		return "a second finger took over or ended the steering"
	if not canceled:
		return "a canceled touch didn't release the stick"
	return _check_key_survives_touch()


## A key held while a finger steers on the other axis stays held after the finger lifts.
func _check_key_survives_touch() -> String:
	Input.action_press("move_left")
	_send_touch(FINGER, TOUCH_ORIGIN, true)
	_send_drag(FINGER, TOUCH_ORIGIN + Vector2(0.0, TouchStick.RADIUS))
	_send_touch(FINGER, TOUCH_ORIGIN, false)
	var held: bool = Input.is_action_pressed("move_left")
	Input.action_release("move_left")
	if not held:
		return "steering by touch released a key held at the same time"
	return _check_driver_timing()


## The driver runs whole ticks from real time: a long frame runs at most MAX_TICKS_PER_FRAME ticks
## and drops the rest, a remainder carries over to the next frame, and tick_fraction says how far
## real time is into the next tick.
func _check_driver_timing() -> String:
	var tick_seconds: float = 1.0 / Simulation.TICKS_PER_SECOND
	var start: int = _driver.state.tick
	_driver.advance(60.0)
	var long_frame_ticks: int = _driver.state.tick - start
	# The capped frame leaves exactly one tick's time, which the next frame runs.
	_driver.advance(0.0)
	start = _driver.state.tick
	_driver.advance(tick_seconds * 0.6)
	var early_ticks: int = _driver.state.tick - start
	var early_fraction: float = _driver.tick_fraction()
	_driver.advance(tick_seconds * 0.6)
	var carried_ticks: int = _driver.state.tick - start
	var carried_fraction: float = _driver.tick_fraction()
	if long_frame_ticks != GameDriver.MAX_TICKS_PER_FRAME:
		return "a 60 s frame ran %d ticks, not %d" % [
			long_frame_ticks,
			GameDriver.MAX_TICKS_PER_FRAME,
		]
	if early_ticks != 0 or not is_equal_approx(early_fraction, 0.6):
		return "0.6 of a tick ran %d ticks with fraction %f" % [early_ticks, early_fraction]
	if carried_ticks != 1 or not is_equal_approx(carried_fraction, 0.2):
		return "the remainder didn't carry over: %d ticks, fraction %f" % [
			carried_ticks,
			carried_fraction,
		]
	return ""


func _finish_step() -> void:
	var steps: int = ceili(MOVE_SECONDS / STEP) + 2
	for _i: int in steps:
		_step()


## One frame: the driver runs the ticks it adds up to, and the view draws the state.
func _step() -> void:
	_driver.advance(STEP)
	_cube.show_state()


## The player's tile in the simulation.
func _tile() -> Vector2i:
	return _driver.state.player_tile


func _release_all() -> void:
	for action: String in ACTIONS:
		Input.action_release(action)


## One leg of the walk: the actions held, and the tiles the cube must visit, in order.
class Walk:
	extends RefCounted

	var keys: Array[String]
	var path: Array[Vector2i]

	func _init(held: Array[String], tiles: Array[Vector2i]) -> void:
		keys = held
		path = tiles
