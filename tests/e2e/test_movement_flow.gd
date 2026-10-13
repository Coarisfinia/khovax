extends RefCounted
## Movement flow: the movement actions walk the cube from tile to tile along a known path, gliding
## between tiles without jumps, zigzagging along a column for straight up, and stopping at the
## grid's edge. Real key events reach the actions too. Time is stepped by hand, so the flow is
## deterministic.

const STEP: float = 1.0 / 60.0
## Long enough to walk further than the grid allows in any one direction.
const HOLD_STEPS: int = 300
const ACTIONS: Array[String] = ["move_up", "move_down", "move_left", "move_right"]

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
		return "the main scene needs a HexPiece Cube with a HexMover child named Mover, and a HexGrid"
	# Stepped by hand from here on.
	_mover.set_process(false)

	var result: String = _check_key_reaches_action()
	if result.is_empty():
		result = _check_paths()
	_release_all()
	_main.queue_free()
	await tree.process_frame
	return result


func _check_key_reaches_action() -> String:
	for action: String in ACTIONS:
		if not InputMap.has_action(action) or InputMap.action_get_events(action).size() < 2:
			return "action %s is missing or lacks its key and arrow events" % action
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_D
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	var pressed: bool = Input.is_action_pressed("move_right")
	key.pressed = false
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	if not pressed:
		return "pressing D doesn't press move_right"
	return ""


## Each walk starts where the previous one stopped: (1, -1) is the cube's start tile.
func _check_paths() -> String:
	var walks: Array[Dictionary] = [
		{ "keys": ["move_left"], "path": [Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-2, -1)] },
		{"keys": ["move_right"], "path": [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
				Vector2i(2, -1), Vector2i(3, -1)]},
		# Straight up from an odd row starts north-west; the next north-east step would leave the
		# grid.
		{ "keys": ["move_up"], "path": [Vector2i(3, -2)] },
		{"keys": ["move_down", "move_left"], "path": [Vector2i(2, -1), Vector2i(1, 0),
				Vector2i(0, 1), Vector2i(-1, 2), Vector2i(-2, 3)]},
	]
	for walk: Dictionary in walks:
		var keys: Array[String] = []
		keys.assign(walk["keys"])
		var expected: Array[Vector2i] = []
		expected.assign(walk["path"])
		var result: String = _walk(keys, expected)
		if not result.is_empty():
			return "holding %s: %s" % [keys, result]
	return ""


## Holds the keys long enough to reach the grid's edge and checks the tiles visited, in order,
## and that the drawn position never jumps.
func _walk(keys: Array[String], expected: Array[Vector2i]) -> String:
	for key: String in keys:
		Input.action_press(key)
	var visited: Array[Vector2i] = []
	var max_step: float = Hex.SIZE * sqrt(3.0) * STEP / HexMover.STEP_SECONDS + 0.0001
	var jumped: bool = false
	for _i: int in HOLD_STEPS:
		var before: Vector3 = _cube.position
		_mover.advance(STEP, _input())
		jumped = jumped or before.distance_to(_cube.position) > max_step
		if visited.is_empty() or visited[visited.size() - 1] != _cube.tile:
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
