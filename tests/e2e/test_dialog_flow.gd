extends RefCounted
## Dialog flow (#635): a dialog opens on screen with its speaker's name and first line, and the
## player stands while it's open. A controller reads on with A, moves between the answers with the
## d-pad and chooses one with A; a click (as a tap) chooses the last answer, which ends the dialog.
## Every chosen answer reaches the simulation in the player's command, is raised as DialogAnswered
## naming the dialog and the answer, and is recorded in the session's replay; reading on raises
## nothing, nor does an answer no dialog has. The card follows the simulation's state (#890, #898):
## it moves on or closes once the answer reaches it, also for an answer that came only through the
## commands, as in a replay, even from a line before the one that offers it. While the menu is open
## over a dialog, its buttons rest. A dialog that doesn't exist doesn't open. In the glade, the
## guild scout stands east of the start (#557): walking into them talks to them, raised as
## NpcTalkedTo, which opens their greeting in the state, saved with the world: a world resumed with
## it open shows the card again. The scout never steps aside, and a held direction talks once,
## until the player stops and walks into them again.

const PROFILE: String = "user://test_dialog_profile.json"
const GREETING: String = "guild_scout_greeting"
const SCREEN: Vector2i = Vector2i(1152, 648)
## Where the guild scout stands in the glade, east of the start, and the tile west of them.
const SCOUT: Vector2i = Vector2i(3, 0)
const BESIDE_SCOUT: Vector2i = Vector2i(2, 0)
const EAST: int = 0

## Every event the session announced since the flow last looked.
var _heard: Array[RefCounted] = []
## The world's events, handed to the dialog screen.
var _bus: EventBus


func run(tree: SceneTree) -> String:
	# A desktop screen: the headless window is too small for the card to lie on it, and the click
	# must land on its button.
	var kept_size: Vector2i = tree.root.size
	tree.root.size = SCREEN
	var main: Node = await FlowGame.start(tree, PROFILE)
	var driver: GameDriver = FlowGame.held_driver(main)
	var screen: DialogScreen = main.get_node("Hud/DialogScreen") as DialogScreen
	var _connected: int = driver.ticked.connect(_hear)
	_bus = main.get_node("EventBus") as EventBus
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
	if result.is_empty():
		result = _follow_commands(driver, screen)
	if result.is_empty():
		result = await _talk_to_scout(tree, main, driver, screen)
	if result.is_empty():
		result = _talk_once_while_held()
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
	var answered: Array[DialogAnswered] = _answered(driver)
	if screen.line_index != 2 or screen.choices() != ["I'll take a look."]:
		return "asking about the glade showed %s" % [screen.choices()]
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
	if not screen.is_open():
		return "the click closed the card before the simulation had the answer"
	var answered: Array[DialogAnswered] = _answered(driver)
	if screen.is_open() or driver.input.in_dialog:
		return "the last answer didn't end the dialog"
	if answered.size() != 1 or answered[0].answer != "promise_to_look":
		return "the click raised %d answers" % answered.size()
	return ""


## Answers that come only through the commands, as in a replay, move the card too: one sent while
## the card still shows the first line skips to where it leads, and the last one closes the card.
func _follow_commands(driver: GameDriver, screen: DialogScreen) -> String:
	var _opened: bool = screen.open(GREETING)
	driver.input.choose_answer(DialogFeature.code(GREETING, "ask_about_glade"))
	var _asked: Array[DialogAnswered] = _answered(driver)
	if screen.line_index != 2:
		return "an answer through the commands moved the card to line %d" % screen.line_index
	driver.input.choose_answer(DialogFeature.code(GREETING, "promise_to_look"))
	var _promised: Array[DialogAnswered] = _answered(driver)
	if screen.is_open() or driver.input.in_dialog:
		return "the last answer through the commands didn't close the card"
	return ""


## In the glade, the player walks east with the keys into the guild scout, who stops them: that
## talks to the scout once, for the player, and opens the scout's greeting.
func _talk_to_scout(
	tree: SceneTree,
	main: Node,
	driver: GameDriver,
	screen: DialogScreen,
) -> String:
	driver.instance = InstanceBlueprints.GLADE
	driver.start(0)
	_heard.clear()
	Input.action_press("move_right")
	for _tick: int in MovementFeature.MOVE_TICKS * 4:
		driver.advance(1.0 / Simulation.TICKS_PER_SECOND)
	Input.action_release("move_right")
	(main.get_node("EventBus") as EventBus).flush()
	await tree.process_frame
	var talked: Array[NpcTalkedTo] = _talked(_heard)
	if driver.state.player(0).tile != BESIDE_SCOUT or talked.size() != 1:
		return "walking into the scout from %s talked %d times" % [
			driver.state.player(0).tile,
			talked.size(),
		]
	if talked[0].npc != "guild_scout" or talked[0].slot != 0 or talked[0].dialog != GREETING:
		return "talking named %s and %s for slot %d" % [
			talked[0].npc,
			talked[0].dialog,
			talked[0].slot,
		]
	if not screen.is_open() or screen.shown_speaker() != "Guild Scout":
		return "talking to the scout didn't open their greeting"
	return _resume_open(driver, screen)


## The scout's greeting is open in the state at its first line, and saved with the world: leaving
## it closes the card, and resuming the saved world opens it again at the first line.
func _resume_open(driver: GameDriver, screen: DialogScreen) -> String:
	var dialogs: DialogFeature = driver.state.feature(DialogFeature.ID) as DialogFeature
	if dialogs.dialog_of(0) != GREETING or dialogs.line_of(0) != 0:
		return "the state holds %s at line %d" % [dialogs.dialog_of(0), dialogs.line_of(0)]
	var saved: Dictionary = WorldData.of(driver.world)
	driver.input.choose_answer(DialogFeature.code(GREETING, "leave_scout"))
	var _left: Array[DialogAnswered] = _answered(driver)
	if screen.is_open() or not dialogs.dialog_of(0).is_empty():
		return "leaving the scout didn't close their greeting"
	var restored: World = WorldData.to_world(saved, BlueprintSource.new())
	var problem: String = restored.problem
	if problem.is_empty():
		problem = driver.resume(restored)
	driver.advance(1.0 / Simulation.TICKS_PER_SECOND)
	if not problem.is_empty() or not screen.is_open() or screen.line_index != 0:
		return "the resumed world didn't show its open greeting: %s" % problem
	return ""


## A player walking on into the scout talks only once; stopping and walking into them again talks
## again.
static func _talk_once_while_held() -> String:
	var state: GameState = InstanceBlueprints.create(InstanceBlueprints.GLADE, 3, 1)
	var _walked: Array[RefCounted] = FlowSteps.walk(state, [Vector2i(1, 0), BESIDE_SCOUT])
	var talks: Array[int] = []
	for move: int in [EAST, EAST, EAST, Command.NO_MOVE, EAST]:
		Simulation.step(state, FlowSteps.command(move))
		talks.append(_talked(state.events).size())
	if talks != [1, 0, 0, 0, 1] or state.player(0).tile != BESIDE_SCOUT:
		return "walking on into the scout talked %s, standing on %s" % [talks, state.player(0).tile]
	return ""


## The NpcTalkedTo events among `events`.
static func _talked(events: Array[RefCounted]) -> Array[NpcTalkedTo]:
	var talked: Array[NpcTalkedTo] = []
	for event: RefCounted in events:
		if event is NpcTalkedTo:
			talked.append(event as NpcTalkedTo)
	return talked


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


## Runs a few ticks, hands their events out, and returns the DialogAnswered events raised in them.
func _answered(driver: GameDriver) -> Array[DialogAnswered]:
	_heard.clear()
	for _tick: int in 3:
		driver.advance(1.0 / Simulation.TICKS_PER_SECOND)
	_bus.flush()
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
