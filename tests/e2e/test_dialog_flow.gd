extends RefCounted
## Dialog flow (#635): a dialog opens on screen with its speaker's name and first line, and the
## player stands while it's open. A controller reads on with A, moves between the answers with the
## d-pad and chooses one with A; a click (as a tap) chooses the last answer, which ends the dialog.
## Every chosen answer reaches the simulation in the player's command, is raised as DialogAnswered
## naming the dialog and the answer, and is recorded in the session's replay; reading on raises
## nothing, nor does an answer no dialog has. While the menu is open over a dialog, its buttons
## rest. A dialog that doesn't exist doesn't open.

const PROFILE: String = "user://test_dialog_profile.json"
const GREETING: String = "guild_scout_greeting"
const SCREEN: Vector2i = Vector2i(1152, 648)

## Every event the session announced since the flow last looked.
var _heard: Array[RefCounted] = []


func run(tree: SceneTree) -> String:
	# A desktop screen: the headless window is too small for the card to lie on it, and the click
	# must land on its button.
	var kept_size: Vector2i = tree.root.size
	tree.root.size = SCREEN
	var main: Node = await FlowGame.start(tree, PROFILE)
	var driver: GameDriver = FlowGame.held_driver(main)
	var screen: DialogScreen = main.get_node("Hud/DialogScreen") as DialogScreen
	var _connected: int = driver.ticked.connect(_hear)
	tree.call("expect_warning", "no dialog no_such_dialog")
	var opened: bool = screen.open("no_such_dialog")
	var result: String = "a dialog that doesn't exist opened" if opened else ""
	if result.is_empty():
		result = await _read_on(tree, driver, screen)
	if result.is_empty():
		result = await _choose_with_controller(tree, driver, screen)
	if result.is_empty():
		result = await _rest_under_menu(tree, main, driver, screen)
	if result.is_empty():
		result = await _choose_with_click(tree, driver, screen)
	main.queue_free()
	await tree.process_frame
	SaveStore.remove(PROFILE)
	tree.root.size = kept_size
	return result


## The greeting opens at its first line, by the guild scout, with one button to read on, which has
## the focus; the player stands while it's open; A reads on to the line with two answers, raising
## nothing.
func _read_on(tree: SceneTree, driver: GameDriver, screen: DialogScreen) -> String:
	if not screen.open(GREETING) or not driver.input.in_dialog:
		return "the guild scout's greeting didn't open"
	await tree.process_frame
	if screen.shown_speaker() != "Guild Scout" or not screen.shown_line().begins_with("Careful"):
		return "the greeting showed %s saying %s" % [screen.shown_speaker(), screen.shown_line()]
	if screen.choices() != [DialogScreen.READ_ON_TEXT] or _focused(screen) != 0:
		return "the first line offered %s, focused %d" % [screen.choices(), _focused(screen)]
	Input.action_press("move_right")
	var standing: Command = driver.input.command(driver.state)
	Input.action_release("move_right")
	if standing.move != Command.NO_MOVE:
		return "the player walked while the dialog was open"
	_press_pad(screen, JOY_BUTTON_A)
	if screen.line_index != 1 or screen.choices().size() != 2:
		return "A didn't read on to the line with answers: %s" % [screen.choices()]
	if _answered(driver).size() > 0:
		return "reading on raised an answer"
	return ""


## The d-pad moves the focus down to the second answer and back up; A chooses the first, which
## leads to the line about the glade and is raised for the player as DialogAnswered, also into the
## replay. An answer no dialog has raises nothing.
func _choose_with_controller(
	tree: SceneTree,
	driver: GameDriver,
	screen: DialogScreen,
) -> String:
	await tree.process_frame
	_press_pad(screen, JOY_BUTTON_DPAD_DOWN)
	var down: int = _focused(screen)
	_press_pad(screen, JOY_BUTTON_DPAD_UP)
	if down != 1 or _focused(screen) != 0:
		return "the d-pad moved the focus to %d and back to %d" % [down, _focused(screen)]
	_press_pad(screen, JOY_BUTTON_A)
	if screen.line_index != 2 or screen.choices() != ["I'll take a look."]:
		return "asking about the glade showed %s" % [screen.choices()]
	var answered: Array[DialogAnswered] = _answered(driver)
	var code: int = DialogFeature.code(GREETING, "ask_about_glade")
	if answered.size() != 1 or answered[0].answer != "ask_about_glade" or answered[0].slot != 0:
		return "asking about the glade raised %d answers" % answered.size()
	if answered[0].dialog != GREETING or answered[0].entity_id != driver.state.player(0).id:
		return "the answer named %s for entity %d" % [answered[0].dialog, answered[0].entity_id]
	if not driver.recording.changes.has(code):
		return "the replay didn't record the answer"
	driver.input.choose_answer(code + 1)
	if _answered(driver).size() > 0:
		return "an answer no dialog has was raised"
	return ""


## While the menu is open over the dialog, its buttons rest; closed again, they work.
func _rest_under_menu(
	tree: SceneTree,
	main: Node,
	driver: GameDriver,
	screen: DialogScreen,
) -> String:
	var menu: GameMenu = main.get_node("Hud/GameMenu") as GameMenu
	menu.toggle()
	await tree.process_frame
	var resting: bool = _all_resting(screen)
	menu.toggle()
	# Until the menu has faded out, its sheet's tabs still take clicks.
	await tree.create_timer(GameMenu.FADE_SECONDS * 2.0).timeout
	# The menu let real time reach the driver again: the flow steps the world itself.
	driver.set_process(false)
	var working: bool = _buttons(screen).all(_works)
	if not resting or not working:
		return "the dialog's buttons didn't rest under the menu, or didn't work after it"
	return ""


## A click on the glade line's one answer chooses it, which ends the dialog: the card closes, the
## player can walk again, and the answer is raised.
func _choose_with_click(
	tree: SceneTree,
	driver: GameDriver,
	screen: DialogScreen,
) -> String:
	await tree.process_frame
	var at: Vector2 = _buttons(screen)[0].get_global_rect().get_center()
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = at
	click.pressed = true
	screen.get_viewport().push_input(click)
	var lift: InputEventMouseButton = click.duplicate() as InputEventMouseButton
	lift.pressed = false
	screen.get_viewport().push_input(lift)
	if screen.is_open() or driver.input.in_dialog:
		return "the last answer didn't end the dialog"
	var answered: Array[DialogAnswered] = _answered(driver)
	if answered.size() != 1 or answered[0].answer != "promise_to_look":
		return "the click raised %d answers" % answered.size()
	return ""


## Presses and lets go of a controller's `button`, as the screen's viewport hears it.
static func _press_pad(screen: DialogScreen, button: JoyButton) -> void:
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.button_index = button
	pad.pressed = true
	screen.get_viewport().push_input(pad)
	var lift: InputEventJoypadButton = pad.duplicate() as InputEventJoypadButton
	lift.pressed = false
	screen.get_viewport().push_input(lift)


func _hear(_tick: int, events: Array[RefCounted]) -> void:
	_heard.append_array(events)


## Runs a few ticks and returns the DialogAnswered events raised in them.
func _answered(driver: GameDriver) -> Array[DialogAnswered]:
	_heard.clear()
	for _tick: int in 3:
		driver.advance(1.0 / Simulation.TICKS_PER_SECOND)
	var answered: Array[DialogAnswered] = []
	for event: RefCounted in _heard:
		if event is DialogAnswered:
			answered.append(event as DialogAnswered)
	return answered


## Whether every button on the card rests.
static func _all_resting(screen: DialogScreen) -> bool:
	for button: Button in _buttons(screen):
		if _works(button):
			return false
	return true


static func _works(button: Button) -> bool:
	return not button.disabled


## The dialog card's buttons, in order.
static func _buttons(screen: DialogScreen) -> Array[Button]:
	var found: Array[Button] = []
	for child: Node in screen.find_children("*", "Button", true, false):
		found.append(child as Button)
	return found


## Which of the card's buttons has the focus, or -1.
static func _focused(screen: DialogScreen) -> int:
	return _buttons(screen).find(screen.get_viewport().gui_get_focus_owner())
