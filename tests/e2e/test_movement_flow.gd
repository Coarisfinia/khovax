extends RefCounted
## Movement flow, through every layer: keys, the touch stick and a gamepad press the movement
## actions, the local input turns them into commands, the simulation walks the player from tile to
## tile along a known path, zigzagging along a column for straight up and stopping at the grid's
## edge, at a wild monster and at water but not in a forest, and the view glides the player between
## tiles without jumps.
## Real key and touch events reach the actions too. The special attack's key (#410) fires it in the
## local player's next command, once per press, and so do the swap keys and the d-pad (#540), which
## moves nothing. Every action has a controller binding (#779). Time is stepped by hand, so the flow
## is deterministic.

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
## The left stick's direction per action; screen y grows downwards, so up is a negative y.
const STICK: Dictionary[String, Vector2] = {
	"move_up": Vector2(0.0, -1.0),
	"move_down": Vector2(0.0, 1.0),
	"move_left": Vector2(-1.0, 0.0),
	"move_right": Vector2(1.0, 0.0),
}
## The swap actions' keys, by physical position, and d-pad buttons (#540): the d-pad swaps, and
## moving stays on the left stick and the keys.
const SWAP_KEYS: Dictionary[StringName, Key] = {
	&"swap_1": KEY_1,
	&"swap_2": KEY_2,
	&"swap_3": KEY_3,
}
const SWAP_PADS: Dictionary[StringName, JoyButton] = {
	&"swap_1": JOY_BUTTON_DPAD_LEFT,
	&"swap_2": JOY_BUTTON_DPAD_UP,
	&"swap_3": JOY_BUTTON_DPAD_RIGHT,
}
## The free buttons the special attack, the menu and the Survey took (#779). The triggers zoom the
## Survey too, which only the menu's Survey hears (the survey flow).
const PADS: Dictionary[StringName, JoyButton] = {
	&"menu": JOY_BUTTON_START,
	&"survey": JOY_BUTTON_BACK,
}
const TRIGGERS: Dictionary[StringName, JoyAxis] = {
	&"special_attack": JOY_AXIS_TRIGGER_RIGHT,
	&"survey_zoom_in": JOY_AXIS_TRIGGER_RIGHT,
	&"survey_zoom_out": JOY_AXIS_TRIGGER_LEFT,
}
const ARROW_KEYS: Dictionary[String, Key] = {
	"move_up": KEY_UP,
	"move_down": KEY_DOWN,
	"move_left": KEY_LEFT,
	"move_right": KEY_RIGHT,
}

var _main: Node
var _player_view: PlayerView
var _driver: GameDriver
var _grid: HexGrid
var _trail_view: TrailView
## Every tile the player has stood on in this flow: the start tile and every tile walked onto.
var _walked: Dictionary[Vector2i, bool] = {}
var _stick: TouchStick
## Every tick the driver announced while recording, and the moves among their events.
var _announced: Array[int] = []
var _moves: Array[EntityMoved] = []
## Each announced tick's event list as received, and its size then: a later tick must not change
## an earlier tick's list (the simulation reuses its own list every tick).
var _batches: Array[Array] = []
var _batch_sizes: Array[int] = []


func _input() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_down", "move_up")


func run(tree: SceneTree) -> String:
	var path: String = Boot.GAME
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return "main scene failed to load"
	_main = scene.instantiate()
	tree.root.add_child(_main)
	await tree.process_frame
	_player_view = _main.get_node_or_null("Instance/Player") as PlayerView
	_driver = _main.get_node_or_null("Driver") as GameDriver
	_grid = _main.get_node_or_null("Instance/HexGrid") as HexGrid
	_trail_view = _main.get_node_or_null("TrailView") as TrailView
	_stick = _main.get_node_or_null("Hud/TouchStick") as TouchStick
	var nodes: Array[Node] = [_player_view, _driver, _grid, _trail_view, _stick]
	if nodes.has(null):
		_main.queue_free()
		return "the main scene needs Player, Driver, HexGrid, TrailView and Hud/TouchStick"
	# The recording starts from the world without the toad, like a resumed session's.
	FlowSteps.drop_beach_toad(_driver.state)
	# A walk this long passes the wild monster, whose hits would send the player to the spawn
	# (#457).
	_driver.state.set_enabled(WildAttackFeature.ID, false)
	# Stepped by hand from here on.
	_driver.set_process(false)
	_record_afresh()
	_player_view.set_process(false)
	_trail_view.set_process(false)
	var _connected: int = _driver.ticked.connect(_forget_worn)
	_walked = { _tile(): true }

	var result: String = _check_bindings()
	if result.is_empty():
		result = _check_special_key()
	if result.is_empty():
		result = _check_gamepad_bindings()
	if result.is_empty():
		result = _check_paths()
	if result.is_empty():
		result = _check_forest_and_water()
	if result.is_empty():
		result = _check_blocked_by_wild_monster()
	if result.is_empty():
		result = _check_stick_walk()
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


## E presses the special attack, by its physical position; a press fires it in the next command
## only, and one between two ticks still reaches it.
func _check_special_key() -> String:
	if not _press_reaches(KEY_E, KEY_NONE, "special_attack"):
		return "a real E key event doesn't press the special attack"
	var input: LocalInput = _main.get_node("LocalInput") as LocalInput
	var state: GameState = _driver.state
	Input.action_press("special_attack")
	input._process(STEP)
	Input.action_release("special_attack")
	input._process(STEP)
	var fired: bool = input.command(state).special
	if not fired or input.command(state).special:
		return "a press of the special attack didn't fire it in the next command alone"
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


## Every movement action also has its left-stick direction (#11), and no controller button: the
## d-pad swaps the companion instead (#540).
func _check_gamepad_bindings() -> String:
	for i: int in ACTIONS.size():
		var action: String = ACTIONS[i]
		var stick: Vector2 = STICK[action]
		var has_stick: bool = false
		var has_button: bool = false
		for event: InputEvent in InputMap.action_get_events(action):
			var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
			if motion != null:
				# The left stick's own axis for the direction, never another stick or a trigger.
				var axis: JoyAxis = JOY_AXIS_LEFT_X if stick.x != 0.0 else JOY_AXIS_LEFT_Y
				var axis_value: float = stick.x if axis == JOY_AXIS_LEFT_X else stick.y
				var matches: bool = motion.axis == axis and is_equal_approx(
					motion.axis_value,
					axis_value,
				)
				has_stick = has_stick or matches
			has_button = has_button or event is InputEventJoypadButton
		if not has_stick or has_button:
			return "%s isn't bound to its stick direction alone among the controller's" % action
	var problem: String = _check_every_action_on_controller()
	return problem if not problem.is_empty() else _check_swap_bindings()


## Every part of the game can be played with a controller (#438): every action but Godot's own
## `ui_` ones has a controller binding (#779), so a new action can't miss one, and the special
## attack, the menu and the Survey have theirs.
func _check_every_action_on_controller() -> String:
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		var bound: bool = false
		for event: InputEvent in InputMap.action_get_events(action):
			bound = bound or event is InputEventJoypadButton or event is InputEventJoypadMotion
		if not bound:
			return "%s has no controller binding" % action
	var press: InputEventJoypadButton = InputEventJoypadButton.new()
	press.pressed = true
	for action: StringName in PADS:
		press.button_index = PADS[action]
		if not InputMap.event_is_action(press, action):
			return "%s isn't on its controller button" % action
	var pull: InputEventJoypadMotion = InputEventJoypadMotion.new()
	pull.axis_value = 1.0
	for action: StringName in TRIGGERS:
		pull.axis = TRIGGERS[action]
		if not InputMap.event_is_action(pull, action):
			return "%s isn't on its controller trigger" % action
	return ""


## Swapping (#540): keys 1 to 3, by their physical position, and the d-pad's left, up and right
## press swap_1 to swap_3. A press swaps to that place in the carried order in the next command
## only, and so does a tap on the roster (choose_swap); while the game hears no input, neither does.
func _check_swap_bindings() -> String:
	var input: LocalInput = _main.get_node("LocalInput") as LocalInput
	var state: GameState = _driver.state
	Input.action_press("swap_2")
	input._process(STEP)
	Input.action_release("swap_2")
	input._process(STEP)
	var swapped: int = input.command(state).swap
	if swapped != 2 or input.command(state).swap != Command.NO_SWAP:
		return "a press of swap_2 swapped to %d, not 2 in the next command alone" % swapped
	input.choose_swap(3)
	if input.command(state).swap != 3:
		return "a swap chosen on the roster didn't reach the next command"
	input.blocked = true
	input.choose_swap(1)
	var heard: int = input.command(state).swap
	input.blocked = false
	if heard != Command.NO_SWAP or input.command(state).swap != Command.NO_SWAP:
		return "a swap chosen while the game hears no input reached a command"
	# The real presses come last: a press and its release in one frame leave the action just
	# pressed for the rest of that frame, which the press of swap_2 above would hear too.
	for action: StringName in SWAP_KEYS:
		if not _press_reaches(SWAP_KEYS[action], KEY_NONE, action):
			return "a real key event doesn't press %s" % action
		if not _button_reaches(SWAP_PADS[action], action):
			return "a real d-pad press doesn't press %s" % action
	return ""


## Whether a real press of the joypad button presses the action.
func _button_reaches(index: JoyButton, action: StringName) -> bool:
	var press: InputEventJoypadButton = InputEventJoypadButton.new()
	press.button_index = index
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	var pressed: bool = Input.is_action_pressed(action)
	var release: InputEventJoypadButton = press.duplicate() as InputEventJoypadButton
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	return pressed


## The left stick walks too: a slight drift inside the dead zone doesn't, and pushed right from
## (-2, 1), the player runs along the row to the grid's edge, a row below the east exit's tiles
## (#689); letting go stops it.
func _check_stick_walk() -> String:
	_place(Vector2i(-2, 1))
	_send_stick(Vector2(0.15, 0.0))
	var drift: String = _hold([], _send_stick.bind(Vector2.ZERO))
	if not drift.is_empty():
		return "a stick drifting inside the dead zone: " + drift
	_send_stick(Vector2(1.0, 0.0))
	var result: String = _hold(
		[Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
		_send_stick.bind(Vector2.ZERO),
	)
	return "pushing the stick right: " + result if not result.is_empty() else ""


## Moves the left stick to `to`, as a real joypad's events would: one event per axis.
func _send_stick(to: Vector2) -> void:
	_send_axis(JOY_AXIS_LEFT_X, to.x)
	_send_axis(JOY_AXIS_LEFT_Y, to.y)
	Input.flush_buffered_events()


func _send_axis(axis: JoyAxis, value: float) -> void:
	var motion: InputEventJoypadMotion = InputEventJoypadMotion.new()
	motion.axis = axis
	motion.axis_value = value
	Input.parse_input_event(motion)


## Each walk starts where the previous one stopped: (1, -1) is the player's start tile. The walks
## keep off the east edge's tiles from (3, -2) down, which lead out to the glade (#689).
func _check_paths() -> String:
	var walks: Array[Leg] = [
		Leg.new(
			["move_down", "move_left"],
			[Vector2i(0, 0), Vector2i(-1, 1), Vector2i(-2, 2), Vector2i(-3, 3)],
		),
		Leg.new(["move_right"], [Vector2i(-2, 3), Vector2i(-1, 3), Vector2i(0, 3)]),
		# Straight up and back down through both row parities: north-west and north-east in turn,
		# then south-east and south-west, each zigzag staying in its column.
		Leg.new(
			["move_up"],
			[Vector2i(0, 2), Vector2i(1, 1), Vector2i(1, 0), Vector2i(2, -1), Vector2i(2, -2),
				Vector2i(3, -3)],
		),
		Leg.new(["move_left"], [Vector2i(2, -3), Vector2i(1, -3), Vector2i(0, -3)]),
		Leg.new(
			["move_down"],
			[Vector2i(0, -2), Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-2, 1), Vector2i(-2, 2),
				Vector2i(-3, 3)],
		),
	]
	for walk: Leg in walks:
		var result: String = _walk(walk.keys, walk.path)
		if not result.is_empty():
			return "holding %s: %s" % [walk.keys, result]
	return _check_touch_paths()


## The touch stick continues from where the keys stopped, at (-3, 3).
func _check_touch_paths() -> String:
	var result: String = _walk_by_touch(
		Vector2(TouchStick.RADIUS, 0.0),
		[Vector2i(-2, 3), Vector2i(-1, 3), Vector2i(0, 3)],
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
## checks the tiles visited, in order, that the drawn position never jumped, and the character's
## look (#79).
func _hold(expected: Array[Vector2i], release: Callable) -> String:
	# Starts with the tile the walk leaves from; dropped again before comparing.
	var visited: Array[Vector2i] = [_tile()]
	var max_step: float = HexLayout.SIZE * sqrt(3.0) * STEP / MOVE_SECONDS + 0.0001
	var jumped: bool = false
	var ran: bool = false
	for _i: int in HOLD_STEPS:
		var before: Vector3 = _player_view.position
		_step()
		jumped = jumped or before.distance_to(_player_view.position) > max_step
		ran = ran or _player_view.current_clip() == PlayerView.MOVE
		if visited[visited.size() - 1] != _tile():
			visited.append(_tile())
	release.call()
	_finish_step()
	# Where the last step left from: the tile before the last one visited.
	var last_from: Vector2i = visited[maxi(visited.size() - 2, 0)]
	visited.pop_front()
	if jumped:
		return "the player jumped instead of gliding"
	if visited != expected:
		return "visited %s, expected %s" % [visited, expected]
	if not _player_view.position.is_equal_approx(_player_view.tile_position()):
		return "the player didn't come to rest on its tile"
	for tile: Vector2i in visited:
		_walked[tile] = true
	var result: String = _check_look(not expected.is_empty(), ran, last_from)
	return result if not result.is_empty() else _check_trail()


## The character runs while it walks, idles once it stands, and ends up facing the way it last
## walked, turned there smoothly by the frames in between.
func _check_look(walked: bool, ran: bool, last_from: Vector2i) -> String:
	if ran != walked:
		return "the character %s while walking" % ("didn't run" if walked else "ran without")
	if _player_view.current_clip() != PlayerView.IDLE:
		return "the standing character plays %s, not %s" % [
			_player_view.current_clip(),
			PlayerView.IDLE,
		]
	# The model's own front, in the world, points along the last step it walked.
	var front: Vector3 = _player_view.model.global_basis * Vector3.MODEL_FRONT
	var step: Vector3 = _player_view.tile_position() - _player_view.position_on(last_from)
	if walked and front.normalized().dot(step.normalized()) < 0.999:
		return "the character faces %s, not where it walked (%s)" % [front, step]
	return ""


## Forgets a walked tile a wild monster wore off the trail this tick (#422): the walks linger beside
## one. The domination flow checks the wear itself.
func _forget_worn(_tick: int, events: Array[RefCounted]) -> void:
	var trail: Trail = (_driver.state.feature(TrailFeature.ID) as TrailFeature).shared
	for event: RefCounted in events:
		var struck: WildMonsterStruck = event as WildMonsterStruck
		if struck != null and struck.target_id == 0 and not trail.tiles.has(struck.tile):
			var _forgotten: bool = _walked.erase(struck.tile)


## The trail is exactly the start tile and every tile walked onto so far, but those a wild monster
## wore away, and the grid shows those tiles, and only those, in the trail color.
func _check_trail() -> String:
	var expected: Array[Vector2i] = []
	expected.assign(_walked.keys())
	expected.sort()
	var feature: TrailFeature = _driver.state.feature(TrailFeature.ID) as TrailFeature
	var trail: Trail = feature.shared
	if trail.sorted_tiles() != expected:
		return "the trail is %s, expected %s" % [trail.sorted_tiles(), expected]
	_trail_view.show_state()
	var region: Region = _driver.state.region
	for tile: Vector2i in region.sorted_tiles():
		var base: Color = _grid.terrain_color(region.terrain[tile])
		var color: Color = _trail_view.trail_color if _walked.has(tile) else base
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
	return _check_tick_events()


## Views learn about each tick's one-shot events from the driver: every tick exactly once and in
## order, across frames that run no tick, one, several, or part of one, and the moves among the
## events are exactly the walk the player made.
func _check_tick_events() -> String:
	var tick_seconds: float = 1.0 / Simulation.TICKS_PER_SECOND
	var frames: Array[float] = [0.0, tick_seconds, tick_seconds * 3.5, 0.0, tick_seconds * 0.5]
	var start: int = _driver.state.tick
	var from: Vector2i = _tile()
	var action: String = _open_side()
	_announced.clear()
	_moves.clear()
	_batches.clear()
	_batch_sizes.clear()
	if _driver.ticked.connect(_record) != OK:
		return "couldn't listen to the driver's ticks"
	Input.action_press(action)
	for frame: float in frames:
		_driver.advance(frame)
	Input.action_release(action)
	_driver.ticked.disconnect(_record)
	var expected: Array[int] = []
	for tick: int in range(start + 1, _driver.state.tick + 1):
		expected.append(tick)
	if expected.is_empty() or _announced != expected:
		return "the driver announced ticks %s, expected %s" % [_announced, expected]
	for i: int in _batches.size():
		if _batches[i].size() != _batch_sizes[i]:
			return "tick %d's events changed after it was announced" % _announced[i]
	return _check_moves_announced(from)


## The announced moves chain from where the player stood to where it stands now.
func _check_moves_announced(from: Vector2i) -> String:
	if _moves.is_empty():
		return "walking raised no announced move"
	var at: Vector2i = from
	for moved: EntityMoved in _moves:
		if moved.from != at or moved.entity_id != _driver.state.player(0).id:
			return "an announced move doesn't follow the walk: %s to %s" % [moved.from, moved.to]
		at = moved.to
	if at != _tile():
		return "the announced moves end on %s, the player on %s" % [at, _tile()]
	return _check_recording()


## The driver recorded the whole flow, keys and touches alike: saved and loaded, the recording
## plays back to exactly the state the flow ended in.
func _check_recording() -> String:
	_driver.recording.finish(_driver.world)
	var loaded: Replay = ReplayFile.parse(ReplayFile.to_text(_driver.recording))
	var problem: String = loaded.play()
	if not problem.is_empty():
		return "the flow's recording didn't play back: " + problem
	if loaded.played.state_hash() != _driver.world.state_hash():
		return "the flow's recording played back to another state"
	return ""


func _record(tick: int, events: Array[RefCounted]) -> void:
	_announced.append(tick)
	_batches.append(events)
	_batch_sizes.append(events.size())
	for event: RefCounted in events:
		var moved: EntityMoved = event as EntityMoved
		if moved != null:
			_moves.append(moved)


## The side the player can walk to from where it stands: right, unless that is off the region.
func _open_side() -> String:
	var right: int = HexInput.direction_toward(Vector2.RIGHT, _tile())
	var next: Vector2i = _tile() + Hex.DIRECTIONS[right]
	return "move_right" if _driver.state.region.is_walkable(next) else "move_left"


func _finish_step() -> void:
	var steps: int = ceili(MOVE_SECONDS / STEP) + 2
	for _i: int in steps:
		_step()


## One frame: the driver runs the ticks it adds up to, and the view draws the state.
func _step() -> void:
	_driver.advance(STEP)
	_player_view.show_state()
	_player_view.turn(STEP)


## A wild monster blocks the way (#19): walking left along its row from (0, 0) stops on
## (-1, 0), next to the wild monster on (-2, 0), however long the key is held.
func _check_blocked_by_wild_monster() -> String:
	_place(Vector2i.ZERO)
	var result: String = _walk(["move_left"], [Vector2i(-1, 0)])
	if not result.is_empty():
		return "walking toward the wild monster: " + result
	return ""


## Tile kinds (#116): walking right from (0, 0) goes through a forest on (1, 0) and stops there,
## in front of water on (2, 0). The region is given back afterwards.
func _check_forest_and_water() -> String:
	var kept: Region = _driver.state.region
	# A copy (turned by nothing), so the grid redraws the changed tiles in their kinds' colors.
	var region: Region = kept.turned(0)
	region.terrain[Vector2i(1, 0)] = TileKinds.number_of("forest")
	region.terrain[Vector2i(2, 0)] = Region.WATER
	_driver.state.region = region
	_grid.show_state()
	_place(Vector2i.ZERO)
	var result: String = _walk(["move_right"], [Vector2i(1, 0)])
	_driver.state.region = kept
	_grid.show_state()
	if not result.is_empty():
		return "walking through the forest toward water: " + result
	return ""


## Starts the driver's recording afresh from the world as it is now, like a resumed session's: when
## a slow first frame let the driver tick already, those ticks are in the old recording but not in
## this world's start.
func _record_afresh() -> void:
	var world: World = _driver.world
	_driver.recording = Replay.new(world.start_name, world.world_seed)
	_driver.recording.start_world = WorldData.of(world)
	_driver.recording.begin(world)


## Puts the player on `tile` by hand, standing still. Only tiles walked from here on are expected
## on top of the trail.
func _place(tile: Vector2i) -> void:
	var player: Entity = _driver.state.player(0)
	player.tile = tile
	var movement: MovementFeature = _driver.state.feature(MovementFeature.ID) as MovementFeature
	movement.walk(player.id).from = tile
	_player_view.show_state()
	var trails: TrailFeature = _driver.state.feature(TrailFeature.ID) as TrailFeature
	_walked.clear()
	for colored: Vector2i in trails.shared.tiles:
		_walked[colored] = true


## The player's tile in the simulation.
func _tile() -> Vector2i:
	return _driver.state.player(0).tile


func _release_all() -> void:
	for action: String in ACTIONS:
		Input.action_release(action)


## One leg of the walk: the actions held, and the tiles the player must visit, in order.
class Leg:
	extends RefCounted

	var keys: Array[String]
	var path: Array[Vector2i]

	func _init(held: Array[String], tiles: Array[Vector2i]) -> void:
		keys = held
		path = tiles
