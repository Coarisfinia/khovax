extends RefCounted
## Dialog flow (#635): a dialog opens on screen with its speaker's name and first line, and the
## player stands while it's open. A controller reads on with A, moves between the answers with the
## d-pad and chooses one with A; a click (as a tap) chooses the last answer, which ends the dialog.
## Every chosen answer reaches the simulation in the player's command, is raised as DialogAnswered
## naming the dialog and the answer, and is recorded in the session's replay; reading on raises
## nothing, nor does an answer no dialog has. The card follows the simulation's state (#890, #898):
## it moves on or closes once the answer reaches it, also for an answer that came only through the
## commands, as in a replay, even from a line before the one that offers it. While the menu is open
## over a dialog, its buttons rest. A faction's name in a line opens its lexicon page (#959), with a
## controller, a click or a long press on touch, never a tap. A dialog that doesn't exist doesn't
## open. In the glade, Teska
## na Amvrel, the guild's scout, stands east of the start (#557): walking into them talks to them,
## raised as
## NpcTalkedTo, which opens their greeting in the state, saved with the world: a world resumed with
## it open shows the card again. The scout never steps aside, and a held direction talks once,
## until the player stops and walks into them again. A locking dialog holds its player (#912): they
## stand whatever they send, and with every player held the wild monsters pause, until an answer
## closes it; a committing answer holds the player from it on. With a second player free, a held
## player can't be targeted or hurt (#981): a wild monster beside both strikes only the free one,
## and the held one again from the tick after the dialog lets go. A dialog that doesn't hold its
## player can be left (#970): a controller's B or the leave button closes the card, and the player
## walks again; walking away or acting closes the dialog in the state, while bumping into the person
## doesn't, and talking to them again opens it at its first line.

const PROFILE: String = "user://test_dialog_profile.json"
const GREETING: String = "teska_na_amvrel_greeting"
const SCREEN: Vector2i = Vector2i(1152, 648)
## Where Teska na Amvrel stands in the glade, east of the start, and the tile west of them.
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
	if result.is_empty():
		result = _hold_while_locked()
	main.queue_free()
	await tree.process_frame
	SaveStore.remove(PROFILE)
	tree.root.size = kept_size
	return result


## The greeting opens at its first line, by Teska na Amvrel, with one button to read on, which has
## the focus; the player stands while it's open; A reads on to the line with two answers, raising
## nothing, whose faction's name opens its codex page (_open_codex).
func _read_on(tree: SceneTree, driver: GameDriver, screen: DialogScreen) -> String:
	if not screen.open(GREETING) or not driver.input.in_dialog:
		return "Teska na Amvrel's greeting didn't open"
	await tree.process_frame
	if (screen.shown_speaker() != "Teska na Amvrel"
			or not screen.shown_line().begins_with("Careful")):
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
	return await _open_codex(tree, driver, screen)


## The second line names the Amvrel Velmarai (#959) as a link to its lexicon page, which a
## controller, a click and a long press on touch open.
func _open_codex(tree: SceneTree, driver: GameDriver, screen: DialogScreen) -> String:
	var page: CodexPage = screen.get_parent().get_node("CodexPage") as CodexPage
	if (screen.line_links() != ["FACTION:amvrel_velmarai"]
			or not screen.shown_line().begins_with("The Amvrel Velmarai pay")):
		return "the second line showed %s with links %s" % [
			screen.shown_line(),
			screen.line_links(),
		]
	var by_pad: String = _codex_by_controller(page, driver, screen)
	if not by_pad.is_empty():
		return by_pad
	return await _codex_by_pointer(tree, page, driver, screen)


## The d-pad up from the answers reaches the line's names, and A opens the page: the faction's
## name, what the name means, its entry and the player's standing, neutral, while the game hears no
## input. B closes it and gives the focus back to the line, the dialog still on it, and the d-pad
## down goes back to the answers.
static func _codex_by_controller(
	page: CodexPage,
	driver: GameDriver,
	screen: DialogScreen,
) -> String:
	var line: Control = screen.get_node("Card/Rows/Line") as Control
	_press_pad(screen, JOY_BUTTON_DPAD_UP)
	if screen.get_viewport().gui_get_focus_owner() != line:
		return "the d-pad up didn't reach the line's names"
	_press_pad(screen, JOY_BUTTON_A)
	var shown: String = _page_problem(page, driver)
	if not shown.is_empty():
		return "A on the name: " + shown
	_press_pad(screen, JOY_BUTTON_B)
	if page.is_open() or driver.input.blocked or screen.line_index != 1:
		return "B didn't close the page back to the dialog's line"
	if screen.get_viewport().gui_get_focus_owner() != line:
		return "the focus didn't go back to the line"
	_press_pad(screen, JOY_BUTTON_DPAD_DOWN)
	return "" if _focused(screen) == 0 else "the d-pad down from the line didn't reach the answers"


## A click on the name opens the page too, and Escape closes it. On a touch screen a tap on the
## name opens nothing, while a long press does; A then closes it from its focused close button,
## and the d-pad down goes back to the answers.
func _codex_by_pointer(
	tree: SceneTree,
	page: CodexPage,
	driver: GameDriver,
	screen: DialogScreen,
) -> String:
	# The card settles where the line's new height puts it.
	await tree.process_frame
	await tree.process_frame
	var spot: Vector2 = _name_spot(screen.get_node("Card/Rows/Line") as NameLinks)
	_tap(screen, spot, InputEvent.DEVICE_ID_MOUSE)
	var shown: String = _page_problem(page, driver)
	if not shown.is_empty():
		return "a click on the name: " + shown
	var cancel: InputEventAction = InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	screen.get_viewport().push_input(cancel)
	if page.is_open() or not screen.is_open():
		return "Escape didn't close the page back to the dialog"
	await tree.process_frame
	_tap(screen, spot, InputEvent.DEVICE_ID_EMULATION)
	if page.is_open():
		return "a tap on the name opened its page"
	await _hold(tree, screen, spot)
	shown = _page_problem(page, driver)
	if not shown.is_empty():
		return "a long press on the name: " + shown
	_press_pad(screen, JOY_BUTTON_A)
	if page.is_open():
		return "A on the page's close button didn't close it"
	_press_pad(screen, JOY_BUTTON_DPAD_DOWN)
	return "" if _focused(screen) == 0 else "the d-pad down didn't go back to the answers"


## Why the open codex page isn't the Amvrel Velmarai's lexicon page, or "".
static func _page_problem(page: CodexPage, driver: GameDriver) -> String:
	if not page.is_open() or not driver.input.blocked:
		return "the page didn't open, or the game still hears input"
	var gloss: String = page.gloss.get_parsed_text()
	if (page.heading.text != CodexPage.LEXICON_TEXT
			or page.title.text != "Amvrel Velmarai"
			or gloss != "Amvrel Velmarai: the guild of those who chart"
			or not page.entry.text.begins_with("A guild of mapmakers")
			or page.standing.text != CodexPage.NEUTRAL_TEXT):
		return "the page showed %s, %s, %s" % [page.title.text, gloss, page.standing.text]
	return ""


## Where the line shows the middle of "Amvrel", the first word of its link, in the viewport.
static func _name_spot(line: NameLinks) -> Vector2:
	var font: Font = line.get_theme_font("normal_font")
	var size: int = line.get_theme_font_size("normal_font_size")
	var before: float = font.get_string_size("The ", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var word: float = font.get_string_size("Amvrel", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var middle: Vector2 = Vector2(before + word / 2.0, font.get_height(size) / 2.0)
	return line.get_global_rect().position + middle


## Presses the left button at `at` and lets go at once, from `device`: the mouse, or a touch as
## Godot emulates a mouse from it.
static func _tap(screen: DialogScreen, at: Vector2, device: int) -> void:
	var press: InputEventMouseButton = _left_button(at, device)
	screen.get_viewport().push_input(press)
	var lift: InputEventMouseButton = press.duplicate() as InputEventMouseButton
	lift.pressed = false
	screen.get_viewport().push_input(lift)


## Rests a touch on `at` for longer than a long press takes, then lifts it.
static func _hold(tree: SceneTree, screen: DialogScreen, at: Vector2) -> void:
	var press: InputEventMouseButton = _left_button(at, InputEvent.DEVICE_ID_EMULATION)
	screen.get_viewport().push_input(press)
	await tree.create_timer(NameLinks.LONG_PRESS_MS / 1000.0 + 0.2).timeout
	var lift: InputEventMouseButton = press.duplicate() as InputEventMouseButton
	lift.pressed = false
	screen.get_viewport().push_input(lift)


## The left button pressed at `at`, from `device`.
static func _left_button(at: Vector2, device: int) -> InputEventMouseButton:
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.device = device
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = at
	press.pressed = true
	return press


## The d-pad moves the focus down to the second answer and back up; A chooses the first, which
## leads to the line about Lumwen Hoal and is raised for the player as DialogAnswered, also into the
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
		return "asking about Lumwen Hoal showed %s" % [screen.choices()]
	var code: int = DialogFeature.code(GREETING, "ask_about_lumwen_hoal")
	if (answered.size() != 1
			or answered[0].answer != "ask_about_lumwen_hoal"
			or answered[0].slot != 0):
		return "asking about Lumwen Hoal raised %d answers" % answered.size()
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


## A click on the Lumwen Hoal line's one answer chooses it, which ends the dialog: the card closes,
## the player can walk again, and the answer is raised.
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
	driver.input.choose_answer(DialogFeature.code(GREETING, "ask_about_lumwen_hoal"))
	var _asked: Array[DialogAnswered] = _answered(driver)
	if screen.line_index != 2:
		return "an answer through the commands moved the card to line %d" % screen.line_index
	driver.input.choose_answer(DialogFeature.code(GREETING, "promise_to_look"))
	var _promised: Array[DialogAnswered] = _answered(driver)
	if screen.is_open() or driver.input.in_dialog:
		return "the last answer through the commands didn't close the card"
	return ""


## In the glade, the player walks east with the keys into Teska na Amvrel, who stops them: that
## talks to the scout once, for the player, and opens the scout's greeting.
func _talk_to_scout(
	tree: SceneTree,
	main: Node,
	driver: GameDriver,
	screen: DialogScreen,
) -> String:
	driver.instance = FlowSteps.GLADE
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
	if talked[0].npc != "teska_na_amvrel" or talked[0].slot != 0 or talked[0].dialog != GREETING:
		return "talking named %s and %s for slot %d" % [
			talked[0].npc,
			talked[0].dialog,
			talked[0].slot,
		]
	if not screen.is_open() or screen.shown_speaker() != "Teska na Amvrel":
		return "talking to the scout didn't open their greeting"
	var resumed: String = _resume_open(driver, screen)
	if not resumed.is_empty():
		return resumed
	return await _leave_and_walk_away(tree, main, driver, screen)


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


## The scout's greeting, open on the card and not holding the player: a controller's B closes the
## card, though the state keeps the greeting open; the player walks west with the keys, which closes
## it; walking back into the scout opens it at its first line again, and the leave button closes the
## card too.
func _leave_and_walk_away(
	tree: SceneTree,
	main: Node,
	driver: GameDriver,
	screen: DialogScreen,
) -> String:
	var dialogs: DialogFeature = driver.state.feature(DialogFeature.ID) as DialogFeature
	_press_pad(screen, JOY_BUTTON_B)
	if screen.is_open() or driver.input.in_dialog or dialogs.dialog_of(0) != GREETING:
		return "B didn't leave the card with the greeting still open in the state"
	_hold_key(driver, &"move_left", MovementFeature.MOVE_TICKS * 2)
	if not dialogs.dialog_of(0).is_empty() or driver.state.player(0).tile == BESIDE_SCOUT:
		return "walking away left the greeting open, or didn't walk"
	_hold_key(driver, &"move_right", MovementFeature.MOVE_TICKS * 6)
	(main.get_node("EventBus") as EventBus).flush()
	await tree.process_frame
	if not screen.is_open() or screen.line_index != 0 or dialogs.line_of(0) != 0:
		return "talking to the scout again didn't open the greeting at its first line"
	var leave: Button = screen.get_node("Card/Rows/Header/Leave") as Button
	if not leave.visible:
		return "the greeting, which doesn't hold the player, showed no leave button"
	leave.pressed.emit()
	if screen.is_open() or driver.input.in_dialog:
		return "the leave button didn't close the card"
	return ""


## Holds the action `action` down for `ticks` of the driver's ticks, then lets go.
static func _hold_key(driver: GameDriver, action: StringName, ticks: int) -> void:
	Input.action_press(action)
	for _tick: int in ticks:
		driver.advance(1.0 / Simulation.TICKS_PER_SECOND)
	Input.action_release(action)


## A player walking on into the scout talks only once; stopping and walking into them again talks
## again.
static func _talk_once_while_held() -> String:
	var state: GameState = InstanceBlueprints.create(FlowSteps.GLADE, 3, 1)
	var _walked: Array[RefCounted] = FlowSteps.walk(state, [Vector2i(1, 0), BESIDE_SCOUT])
	var talks: Array[int] = []
	for move: int in [EAST, EAST, EAST, Command.NO_MOVE, EAST]:
		Simulation.step(state, FlowSteps.command(move))
		talks.append(_talked(state.events).size())
	if talks != [1, 0, 0, 0, 1] or state.player(0).tile != BESIDE_SCOUT:
		return "walking on into the scout talked %s, standing on %s" % [talks, state.player(0).tile]
	return _close_on_walk_away()


## A greeting that doesn't hold the player stays open while they bump into the scout, and moves on
## by an answer; stepping west closes it, from any line. Talking to the scout again opens it at its
## first line, and firing closes it too.
static func _close_on_walk_away() -> String:
	var state: GameState = InstanceBlueprints.create(FlowSteps.GLADE, 3, 1)
	var dialogs: DialogFeature = state.feature(DialogFeature.ID) as DialogFeature
	var _walked: Array[RefCounted] = FlowSteps.walk(state, [Vector2i(1, 0), BESIDE_SCOUT])
	Simulation.step(state, FlowSteps.command(EAST))
	Simulation.step(state, FlowSteps.command(EAST))
	Simulation.step(state, _answering(DialogFeature.code(GREETING, "ask_about_lumwen_hoal")))
	if dialogs.dialog_of(0) != GREETING or dialogs.line_of(0) != 2:
		return "bumping into the scout closed the greeting, or the answer didn't move it on"
	_walked = FlowSteps.walk(state, [Vector2i(1, 0)])
	if not dialogs.dialog_of(0).is_empty():
		return "walking away didn't close the greeting"
	_walked = FlowSteps.walk(state, [BESIDE_SCOUT])
	Simulation.step(state, FlowSteps.command(EAST))
	if dialogs.dialog_of(0) != GREETING or dialogs.line_of(0) != 0:
		return "talking to the scout again didn't open the greeting at its first line"
	var firing: Array[Command] = FlowSteps.command(Command.NO_MOVE)
	firing[0].special = true
	Simulation.step(state, firing)
	if not dialogs.dialog_of(0).is_empty():
		return "firing didn't close the greeting"
	return ""


## The scout's greeting, made to lock, holds the player once talked to: walking west leaves them
## beside the scout, and the wild monsters pause, with them alone in the glade. Leaving the scout
## frees them, and the wild monsters go on. Made not to lock, it holds nobody until the answer
## asking about Lumwen Hoal, made to commit, is chosen.
static func _hold_while_locked() -> String:
	var state: GameState = _held_by_scout(1)
	var dialogs: DialogFeature = state.feature(DialogFeature.ID) as DialogFeature
	var west: int = Hex.DIRECTIONS.find(Vector2i(-1, 0))
	for _tick: int in MovementFeature.MOVE_TICKS * 2:
		Simulation.step(state, FlowSteps.command(west))
	var wild: Feature = state.feature(WildMonsterFeature.ID)
	if not dialogs.holds(0) or state.player(0).tile != BESIDE_SCOUT or wild.enabled:
		return "the locking greeting didn't hold the player still with the wild monsters paused"
	Simulation.step(state, _answering(DialogFeature.code(GREETING, "leave_scout")))
	Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
	if dialogs.holds(0) or not dialogs.dialog_of(0).is_empty() or not wild.enabled:
		return "leaving the scout didn't free the player and the wild monsters"
	dialogs.locking[GREETING] = false
	dialogs.committing[DialogFeature.code(GREETING, "ask_about_lumwen_hoal")] = true
	Simulation.step(state, FlowSteps.command(EAST))
	var talked: bool = dialogs.dialog_of(0) == GREETING and not dialogs.holds(0)
	Simulation.step(state, _answering(DialogFeature.code(GREETING, "ask_about_lumwen_hoal")))
	if not talked or not dialogs.holds(0) or dialogs.line_of(0) != 2:
		return "the committing answer didn't hold the player from it on"
	return _held_untouched()


## Two players in the glade, the first held by the scout's greeting made to lock, the second free
## beside them, and a wild monster beside both: it strikes only the free player, and the held one's
## health doesn't change. Once leaving the scout frees the first player, it strikes them again.
static func _held_untouched() -> String:
	var state: GameState = _held_by_scout(2)
	var dialogs: DialogFeature = state.feature(DialogFeature.ID) as DialogFeature
	var held: Entity = state.player(0)
	var free: Entity = state.player(1)
	var monster: Entity = state.entity(
		(state.feature(WildMonsterFeature.ID) as WildMonsterFeature).monsters[0],
	)
	var beside: Array[Vector2i] = _beside_both(state, held.tile)
	if not dialogs.holds(0) or beside.is_empty():
		return "the locking greeting didn't hold the first player, or no tile lies beside them"
	free.tile = beside[0]
	(state.feature(MovementFeature.ID) as MovementFeature).add_walk(free)
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	var hp: int = health.hp_of(state, held.id)
	var struck: Array[int] = _strikes(state, monster, beside[1], Command.NO_ANSWER)
	if struck.has(held.id) or not struck.has(free.id) or health.hp_of(state, held.id) != hp:
		return "a wild monster struck %s, with the held player at %d HP of %d" % [
			struck,
			health.hp_of(state, held.id),
			hp,
		]
	struck = _strikes(state, monster, beside[1], DialogFeature.code(GREETING, "leave_scout"))
	if not struck.has(held.id):
		return "the player the greeting let go wasn't struck again: %s" % [struck]
	return ""


## The glade with `players` players, the first beside Teska na Amvrel, whose greeting, made to
## lock, holds them once they've walked into the scout.
static func _held_by_scout(players: int) -> GameState:
	var state: GameState = InstanceBlueprints.create(FlowSteps.GLADE, 3, players)
	(state.feature(DialogFeature.ID) as DialogFeature).locking[GREETING] = true
	var _walked: Array[RefCounted] = FlowSteps.walk(state, [Vector2i(1, 0), BESIDE_SCOUT])
	Simulation.step(state, FlowSteps.command(EAST))
	return state


## Two tiles beside `tile` that are beside each other, walkable and free, or none.
static func _beside_both(state: GameState, tile: Vector2i) -> Array[Vector2i]:
	var open: Array[Vector2i] = []
	for direction: Vector2i in Hex.DIRECTIONS:
		if FlowSteps.walkable_for_players(state, tile + direction):
			open.append(tile + direction)
	for first: Vector2i in open:
		for second: Vector2i in open:
			if Hex.distance(first, second) == 1:
				return [first, second]
	var none: Array[Vector2i] = []
	return none


## Who `monster` strikes over two strikes' ticks, kept on `tile` and with both players standing, the
## first choosing the answer `code` on the first tick, by target entity id.
static func _strikes(state: GameState, monster: Entity, tile: Vector2i, code: int) -> Array[int]:
	var movement: MovementFeature = state.feature(MovementFeature.ID) as MovementFeature
	var targets: Array[int] = []
	for tick: int in WildAttackFeature.STRIKE_TICKS * 2:
		monster.tile = tile
		movement.add_walk(monster)
		var commands: Array[Command] = FlowSteps.commands([Command.NO_MOVE, Command.NO_MOVE])
		if tick == 0:
			commands[0].answer = code
		Simulation.step(state, commands)
		for event: RefCounted in state.events:
			var hit: WildMonsterStruck = event as WildMonsterStruck
			if hit != null and hit.monster_id == monster.id:
				targets.append(hit.target_id)
	return targets


## One tick's commands with only the player in slot 0, standing and choosing the answer `code`.
static func _answering(code: int) -> Array[Command]:
	var commands: Array[Command] = FlowSteps.command(Command.NO_MOVE)
	commands[0].answer = code
	return commands


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


## The dialog card's buttons, in order: its answers or its read-on button, not the leave button.
static func _buttons(screen: DialogScreen) -> Array[Button]:
	var found: Array[Button] = []
	for child: Node in screen.get_node("Card/Rows/Choices").get_children():
		found.append(child as Button)
	return found


## Which of the card's buttons has the focus, or -1.
static func _focused(screen: DialogScreen) -> int:
	return _buttons(screen).find(screen.get_viewport().gui_get_focus_owner())
