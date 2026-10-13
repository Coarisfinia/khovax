extends RefCounted
## Movement flow: the movement actions walk the cube from tile to tile along a known path, gliding
## between tiles without jumps, zigzagging along a column for straight up, and stopping at the
## grid's edge. Real key events reach the actions too. Time is stepped by hand, so the flow is
## deterministic.

const STEP: float = 1.0 / 60.0
## Long enough to walk further than the grid allows in any one direction.
const HOLD_STEPS: int = 300
const ACTIONS: Array[String] = ["move_up", "move_down", "move_left", "move_right"]
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
var _cube: HexPiece
var _mover: HexMover
var _grid: HexGrid


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
	_cube = _main.get_node_or_null("Cube") as HexPiece
	_mover = _main.get_node_or_null("Cube/Mover") as HexMover
	_grid = _main.get_node_or_null("HexGrid") as HexGrid
	if _cube == null or _mover == null or _grid == null:
		_main.queue_free()
		return "the main scene needs a HexPiece Cube, its HexMover child Mover, and a HexGrid"
	# Stepped by hand from here on.
	_mover.set_process(false)

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
	return ""


## Holds the keys long enough to reach the grid's edge and checks the tiles visited, in order,
## and that the drawn position never jumps.
func _walk(keys: Array[String], expected: Array[Vector2i]) -> String:
	for key: String in keys:
		Input.action_press(key)
	# Starts with the tile the walk leaves from; dropped again before comparing.
	var visited: Array[Vector2i] = [_cube.tile]
	var max_step: float = Hex.SIZE * sqrt(3.0) * STEP / HexMover.STEP_SECONDS + 0.0001
	var jumped: bool = false
	for _i: int in HOLD_STEPS:
		var before: Vector3 = _cube.position
		_mover.advance(STEP, _input())
		jumped = jumped or before.distance_to(_cube.position) > max_step
		if visited[visited.size() - 1] != _cube.tile:
			visited.append(_cube.tile)
	_release_all()
	_finish_step()
	visited.pop_front()
	if jumped:
		return "the cube jumped instead of gliding"
	if visited != expected:
		return "visited %s, expected %s" % [visited, expected]
	if not _cube.position.is_equal_approx(_cube.tile_position()):
		return "the cube didn't come to rest on its tile"
	return ""


func _finish_step() -> void:
	var steps: int = ceili(HexMover.STEP_SECONDS / STEP) + 1
	for _i: int in steps:
		_mover.advance(STEP, Vector2.ZERO)


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
