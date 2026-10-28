extends RefCounted
## Movement flow, through every layer: keys, the touch stick and a gamepad press the movement
## actions, the local input turns them into commands, the simulation walks the player from tile to
## tile along a known path, zigzagging along a column for straight up and stopping at the grid's
## edge, at a wild monster and at water but not in a forest, and the view glides the player between
## tiles without jumps.
## Real key and touch events reach the actions too. The special attack's key (#410) fires it in the
## local player's next command, once per press, and so does the interact key (#696), and so do the
## swap keys and the d-pad (#540), which
## moves nothing. Every action has a controller binding (#779). A click on a tile walks the player
## there on their own (#1508); a key stops that walk, and a touch's emulated click, a tile off the
## region or a click while the menu is open walks nowhere. Time is stepped by hand, so the flow is
## deterministic.

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

	var steps: Array[Callable] = [
		_check_bindings,
		_check_special_key,
		_check_gamepad_bindings,
		_check_paths,
		_check_forest_and_water,
		_check_blocked_by_wild_monster,
		_check_stick_walk,
		_check_move_hint,
	]
	var result: String = ""
	for step: Callable in steps:
		result = step.call()
		if not result.is_empty():
			break
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
	return _check_interact_key()


## F and a controller's A press interact (#696), by F's physical position; a press reaches the next
## command only.
func _check_interact_key() -> String:
	if not _press_reaches(KEY_F, KEY_NONE, "interact"):
		return "a real F key event doesn't press interact"
	var pad: bool = false
	for event: InputEvent in InputMap.action_get_events("interact"):
		var button: InputEventJoypadButton = event as InputEventJoypadButton
		pad = pad or (button != null and button.button_index == JOY_BUTTON_A)
	if not pad:
		return "a controller's A doesn't press interact"
	var input: LocalInput = _main.get_node("LocalInput") as LocalInput
	var state: GameState = _driver.state
	Input.action_press("interact")
	input._process(STEP)
	Input.action_release("interact")
	input._process(STEP)
	var interacting: bool = input.command(state).interact
	if not interacting or input.command(state).interact:
		return "a press of interact didn't reach the next command alone"
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
## There is one swap action for each place a player carries (#936).
func _check_swap_bindings() -> String:
	if LocalInput.SWAP_ACTIONS.size() != CarryRequest.MOST_CARRIED:
		return "%d swap actions for %d carried places" % [
			LocalInput.SWAP_ACTIONS.size(), CarryRequest.MOST_CARRIED,
		]
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


## A click on a walkable tile two steps east of (0, 0) walks the player there on their own, through
## the focus picker as the mouse gives it, with the instance shifted off the world's origin, and the
## walk ends there. A short, still touch walks there too, and a key pressed on the way stops it at
## once. A touch's emulated click, a click while the menu is open and a tap off the region walk
## nowhere.
func _check_tap_walk() -> String:
	var picker: FocusPicker = _main.get_node("FocusPicker") as FocusPicker
	var input: LocalInput = _driver.input
	var target: Vector2i = _tap_target()
	_place(Vector2i.ZERO)
	# The instance shifted by a tile, as one beyond an exit is: the click is read in its own
	# coordinates.
	# Headless, the screen is tiny: every wild monster's figure would show within a pick's reach.
	picker.wild_view.visible = false
	picker.instance.position = HexLayout.to_world(Vector2i(1, 0))
	var click: InputEventMouseButton = _click_on(picker, target)
	picker._unhandled_input(click)
	(picker.instance as InstanceRoot).show_state()
	if click.position == Vector2(-1.0, -1.0):
		return "the tile to click, %s, isn't on the screen" % target
	click = _click_on(picker, target)
	for _frame: int in ceili(MOVE_SECONDS / STEP) * 3 + 2:
		_step()
	if _tile() != target or input.tap_walk.walking:
		return "a click on %s walked the player to %s" % [target, _tile()]
	_place(Vector2i.ZERO)
	_tap(picker, click.position)
	_one_tick()
	var started: bool = input.tap_walk.walking
	Input.action_press("move_left")
	_one_tick()
	Input.action_release("move_left")
	if not started or input.tap_walk.walking:
		return "a tap didn't walk, or a key pressed on the way didn't stop the walk"
	_finish_step()
	_place(Vector2i.ZERO)
	input.blocked = true
	picker._unhandled_input(click)
	input.tap_tile(target)
	input.blocked = false
	_one_tick()
	var still: bool = not input.tap_walk.walking
	click.device = InputEvent.DEVICE_ID_EMULATION
	picker._unhandled_input(click)
	_one_tick()
	still = still and not input.tap_walk.walking
	input.tap_tile(Vector2i(1000, 1000))
	_finish_step()
	picker.wild_view.visible = true
	if not still or _tile() != Vector2i.ZERO or input.tap_walk.walking:
		return "an emulated click, a click in the menu or one off the region walked the player"
	return ""


## The left mouse button held on the world walks toward the cursor (#1567): held still on a tile
## east of (0, 0) past a click's time, the player heads east, and with the cursor moved west of the
## player, west; letting go stops the walk. A key steers over the held button at once. Held on
## while the menu opens, it walks no more after the menu closes (_check_hold_over_menu). A click
## let go at once still walks to its tile.
func _check_hold_walk() -> String:
	var picker: FocusPicker = _main.get_node("FocusPicker") as FocusPicker
	var input: LocalInput = _driver.input
	var target: Vector2i = _tap_target()
	picker.wild_view.visible = false
	_place(Vector2i.ZERO)
	_hold_on(picker, target)
	if input.tap_walk.walking or _shown_x() <= 0.0:
		return "a held click east of the player didn't walk toward the cursor, east"
	var east: float = _shown_x()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = _click_on(picker, _tile() + Hex.DIRECTIONS[3] * 2).position
	picker._input(motion)
	_hold_frames(picker, ceili(MOVE_SECONDS / STEP) * 2)
	if _shown_x() >= east:
		return "moving the cursor west of the player didn't turn the held walk west"
	var release: InputEventMouseButton = _click_on(picker, target)
	release.pressed = false
	picker._input(release)
	_finish_step()
	var stopped: Vector2i = _tile()
	_hold_frames(picker, ceili(MOVE_SECONDS / STEP) * 2)
	if _tile() != stopped:
		return "letting go of the held button didn't stop the walk"
	_place(Vector2i.ZERO)
	_hold_on(picker, target)
	_finish_step()
	var held_from: float = _shown_x()
	Input.action_press("move_left")
	_hold_frames(picker, ceili(MOVE_SECONDS / STEP) * 2)
	Input.action_release("move_left")
	if _shown_x() >= held_from:
		return "a key pressed while the button is held didn't take over"
	if not _check_hold_over_menu(picker, release):
		return "the button held on over the menu walked on after it closed"
	_place(Vector2i.ZERO)
	picker._unhandled_input(_click_on(picker, target))
	picker._input(release)
	_hold_frames(picker, ceili(MOVE_SECONDS / STEP) * 3 + 2)
	picker.wild_view.visible = true
	if _tile() != target:
		return "a click let go at once didn't walk to %s but to %s" % [target, _tile()]
	return ""


## A click dragged past a click's reach and let go before the next frame is no click: the walk to
## its tile, two steps away, stops before its first step.
func _check_drag_let_go_at_once() -> String:
	var picker: FocusPicker = _main.get_node("FocusPicker") as FocusPicker
	var target: Vector2i = _tap_target()
	picker.wild_view.visible = false
	_place(Vector2i.ZERO)
	var press: InputEventMouseButton = _click_on(picker, target)
	picker._unhandled_input(press)
	var drag: InputEventMouseMotion = InputEventMouseMotion.new()
	drag.position = press.position + Vector2(FocusPicker.TAP_PIXELS * 4.0, 0.0)
	picker._input(drag)
	press.pressed = false
	picker._input(press)
	_hold_frames(picker, ceili(MOVE_SECONDS / STEP) * 3 + 2)
	picker.wild_view.visible = true
	if _tile() == target or _driver.input.tap_walk.walking:
		return "a click dragged off and let go before the next frame still walked to its tile"
	return ""


## Whether the held left mouse button walks no more once the menu opened and closed over it, until
## it's let go with `release`.
func _check_hold_over_menu(picker: FocusPicker, release: InputEventMouseButton) -> bool:
	_driver.input.blocked = true
	_hold_frames(picker, 2)
	_driver.input.blocked = false
	_hold_frames(picker, 2)
	_finish_step()
	var at_menu: Vector2i = _tile()
	_hold_frames(picker, ceili(MOVE_SECONDS / STEP) * 2)
	picker._input(release)
	return _tile() == at_menu


## Presses the left mouse button on `tile` through `picker` and keeps it held past a click's time,
## and a step's more: the player walks toward it then.
func _hold_on(picker: FocusPicker, tile: Vector2i) -> void:
	picker._unhandled_input(_click_on(picker, tile))
	_hold_frames(picker, ceili(FocusPicker.TAP_SECONDS / STEP) + ceili(MOVE_SECONDS / STEP) + 2)


## `frames` frames with the mouse button's hold followed in each, as the picker's _process does.
func _hold_frames(picker: FocusPicker, frames: int) -> void:
	for _frame: int in frames:
		picker._process(STEP)
		_step()


## How far east the player stands, on the screen's x.
func _shown_x() -> float:
	return HexLayout.to_world(_tile()).x


## The walkable tile two steps east of (0, 0) to click: (2, 0) unless it's closed.
func _tap_target() -> Vector2i:
	for tile: Vector2i in [Vector2i(2, -1), Vector2i(1, 1)]:
		if (not _driver.state.region.is_walkable(Vector2i(2, 0))
				and _driver.state.region.is_walkable(tile)):
			return tile
	return Vector2i(2, 0)


## A left click, as the mouse gives it, where `picker`'s camera shows `tile` of the instance now;
## at (-1, -1), off the screen, when the camera doesn't show it.
func _click_on(picker: FocusPicker, tile: Vector2i) -> InputEventMouseButton:
	var shown: Vector3 = picker.instance.to_global(HexLayout.to_world(tile))
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(-1.0, -1.0)
	if picker.camera.is_position_in_frustum(shown):
		click.position = picker.camera.unproject_position(shown)
	return click


## Frames enough for the driver to run one tick, and not two: each check after it sees the input
## sent before it in a command.
func _one_tick() -> void:
	for _frame: int in ceili(1.0 / Simulation.TICKS_PER_SECOND / STEP):
		_step()


## A short, still touch on `point` through `picker`: down and up on the same point.
func _tap(picker: FocusPicker, point: Vector2) -> void:
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.index = FINGER
	touch.position = point
	touch.pressed = true
	picker._unhandled_input(touch)
	touch.pressed = false
	picker._unhandled_input(touch)


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


## The move hint (#1222): until the player first walks, the glyphs that walk them stand just under
## them, W over S with A and D beside it with a keyboard, the left stick alone with a controller and
## a drag alone on touch. The first step notes the walk in their profile (MoveHintTie), and the
## hint fades.
func _check_move_hint() -> String:
	var hint: MoveHint = _main.get_node("Hud/MoveHint") as MoveHint
	hint.set_process(false)
	# Whatever this flow walked before, the hint starts here as a new game's does.
	hint.keeper.started()
	hint.alpha = 1.0
	var shown: Array = FlowInput.glyphs_by_device(func() -> Array: return _move_hint_shown(hint))
	var expected: Array = [
		[
			InputGlyphs.KEYS[KEY_W],
			InputGlyphs.KEYS[KEY_A],
			InputGlyphs.KEYS[KEY_S],
			InputGlyphs.KEYS[KEY_D],
		],
		[InputGlyphs.AXES[JOY_AXIS_LEFT_X]],
		[InputGlyphs.GESTURES[&"move_up"]],
	]
	if shown != expected:
		return "the move hint didn't show W, A, S and D, the left stick and a drag"
	var kept: DeviceInUse.Device = DeviceInUse.device
	DeviceInUse.device = DeviceInUse.Device.KEYBOARD
	hint.show_state()
	DeviceInUse.device = kept
	var up: Rect2 = hint.shown[&"move_up"]
	var down: Rect2 = hint.shown[&"move_down"]
	var keys_lie: bool = up.position.x == down.position.x and up.end.y < down.position.y
	keys_lie = keys_lie and hint.shown[&"move_left"].end.x < down.position.x
	keys_lie = keys_lie and hint.shown[&"move_right"].position.x > down.end.x
	var feet: Vector2 = hint.camera.unproject_position(hint.figure.global_position)
	var under: bool = up.position.y > feet.y and up.position.x < feet.x and up.end.x > feet.x
	if not keys_lie or not under:
		return "the move hint's keys didn't lie as on a keyboard, just under the player"
	Input.action_press(_open_side())
	_finish_step()
	_release_all()
	_finish_step()
	if not hint.keeper.walked or hint.keeper.beside() != { MoveHintKeeper.KEY: true }:
		return "the player's first walk wasn't kept in their profile"
	hint.fade(MoveHint.FADE_SECONDS / 2.0)
	if hint.alpha <= 0.0 or hint.alpha >= 1.0:
		return "the move hint didn't fade once the player walked"
	hint.fade(MoveHint.FADE_SECONDS)
	hint.show_state()
	return "" if hint.shown.is_empty() else "the move hint still showed after fading"


## The move hint's glyphs, in its actions' order.
func _move_hint_shown(hint: MoveHint) -> Array:
	hint.show_state()
	var glyphs: Array = []
	for action: StringName in MoveHint.CELLS:
		if hint.glyphs.has(action):
			glyphs.append(hint.glyphs[action])
	return glyphs


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
## (-1, 0), next to the wild monster on (-2, 0), however long the key is held. Then walking to a
## clicked tile.
func _check_blocked_by_wild_monster() -> String:
	_place(Vector2i.ZERO)
	var result: String = _walk(["move_left"], [Vector2i(-1, 0)])
	if not result.is_empty():
		return "walking toward the wild monster: " + result
	result = _check_tap_walk()
	if result.is_empty():
		result = _check_hold_walk()
	return result if not result.is_empty() else _check_drag_let_go_at_once()


## Tile kinds (#116): walking right from (0, 0) goes through a forest on (1, 0) and stops there,
## in front of water on (2, 0). The region is given back afterwards.
func _check_forest_and_water() -> String:
	var kept: Region = _driver.state.region
	# A copy (turned by nothing), so the grid redraws the changed tiles in their kinds' colors.
	var region: Region = kept.turned(0)
	region.terrain[Vector2i(1, 0)] = "forest"
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
