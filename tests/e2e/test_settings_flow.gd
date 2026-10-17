extends RefCounted
## Settings flow (#161): every graphics setting starts at Auto, which picks the project's value for
## this platform and says so in its label; a player's choice takes effect at once and survives a
## restart; and choosing Auto again hands the setting back. Anti-aliasing is the first: MSAA and the
## ink pass's smoothing together. In the game, the menu's Settings tab (#355, #362) does all that:
## the `menu` action opens the menu, easing in; while it's open the player's keys don't walk and,
## by default, single player pauses (#302): no tick runs. The tab lists every setting, each on Auto
## at first; a step changes one and keeps it, its Auto button hands it back; turning the pause off
## lets the ticks run on behind the menu; the rows fit a phone's screen; and the action closes the
## menu, easing out, and the game goes on.

const SETTINGS_PATH: String = "user://test_settings.json"
const STEP: float = 1.0 / Simulation.TICKS_PER_SECOND

var _tree: SceneTree


func run(tree: SceneTree) -> String:
	_tree = tree
	_forget()
	var msaa_before: Viewport.MSAA = tree.root.msaa_3d
	var result: String = _check_auto()
	if result.is_empty():
		result = _check_choice_kept()
	if result.is_empty():
		result = _check_back_to_auto()
	if result.is_empty():
		result = await _check_menu()
	tree.root.msaa_3d = msaa_before
	_forget()
	return result


## A new player's anti-aliasing is Auto: the project's MSAA for this platform, on screen and in the
## label, with the ink smoothed unless MSAA is off.
func _check_auto() -> String:
	var graphics: Graphics = _start()
	var auto: int = ProjectSettings.get_setting_with_override(Graphics.MSAA_SETTING)
	var label: String = graphics.anti_aliasing_label()
	var problem: String = _check_applied(graphics, auto)
	graphics.free()
	if not problem.is_empty():
		return "Auto: " + problem
	if not label.begins_with("Auto (") or _label_of(auto) not in label:
		return "Auto's label is %s" % label
	return ""


## Turning anti-aliasing off takes effect at once, drops the "Auto" from the label and survives a
## restart.
func _check_choice_kept() -> String:
	var graphics: Graphics = _start()
	var problem: String = graphics.choose_anti_aliasing(Viewport.MSAA_DISABLED)
	if problem.is_empty():
		problem = _check_applied(graphics, Viewport.MSAA_DISABLED)
	var label: String = graphics.anti_aliasing_label()
	graphics.free()
	if not problem.is_empty():
		return "choosing off: " + problem
	if label != "Off":
		return "the chosen setting's label is %s" % label
	var restarted: Graphics = _start()
	problem = _check_applied(restarted, Viewport.MSAA_DISABLED)
	restarted.free()
	if not problem.is_empty():
		return "after a restart: " + problem
	return ""


## Choosing Auto again hands the setting back, also after a restart.
func _check_back_to_auto() -> String:
	var graphics: Graphics = _start()
	var problem: String = graphics.choose_auto(Graphics.ANTI_ALIASING)
	if problem.is_empty():
		problem = _check_applied(graphics, Graphics.auto_anti_aliasing())
	graphics.free()
	if not problem.is_empty():
		return "choosing Auto again: " + problem
	var restarted: Graphics = _start()
	problem = _check_applied(restarted, Graphics.auto_anti_aliasing())
	var label: String = restarted.anti_aliasing_label()
	restarted.free()
	if not problem.is_empty() or not label.begins_with("Auto ("):
		return "Auto again, after a restart: %s (%s)" % [problem, label]
	return ""


## The settings menu in the game, its settings kept in the test's file.
func _check_menu() -> String:
	_forget()
	var main: Node = await FlowGame.start(_tree)
	var graphics: Graphics = main.get_node("Graphics") as Graphics
	graphics.settings_path = SETTINGS_PATH
	graphics.settings = Settings.new()
	graphics.apply()
	var menu: GameMenu = main.get_node("Hud/GameMenu") as GameMenu
	var driver: GameDriver = FlowGame.held_driver(main)
	var result: String = await _open_menu(menu)
	if result.is_empty():
		result = _menu_holds_game(driver, true)
	if result.is_empty():
		result = _menu_choices(menu, graphics, main.get_node("SurveyChoice") as SurveyChoice)
	if result.is_empty():
		result = _menu_pause_choice(menu, driver)
	if result.is_empty():
		result = _menu_on_screens(menu)
	if result.is_empty():
		result = await _close_menu(menu)
	if result.is_empty():
		result = _menu_holds_game(driver, false)
	main.queue_free()
	await _tree.process_frame
	return result


## The `menu` action opens the menu, easing in, and its Settings tab lists every setting, each on
## Auto.
func _open_menu(menu: GameMenu) -> String:
	if menu.is_open() or menu.opacity() > 0.0:
		return "the menu shows before it's opened"
	_press_menu(menu)
	if not menu.is_open() or menu.opacity() >= 1.0:
		return "the menu action doesn't open the menu, or it snaps open"
	await _tree.create_timer(GameMenu.FADE_SECONDS * 2.0).timeout
	if menu.opacity() < 1.0:
		return "the menu doesn't finish easing in"
	var shown: Dictionary[String, String] = menu.settings.shown
	var listed: Array[String] = []
	for setting: String in shown:
		listed.append(setting)
	var settings: Array[String] = [
		Graphics.ANTI_ALIASING,
		SurveyChoice.PLACE_SETTING,
		SurveyChoice.ZOOM_SETTING,
		GameMenu.PAUSE_SETTING,
	]
	if listed != settings:
		return "the Settings tab lists %s, not every setting" % [listed]
	for setting: String in listed:
		if not shown[setting].begins_with("Auto ("):
			return "%s isn't on Auto at first: %s" % [setting, shown[setting]]
	return ""


## While the menu is open (`open`), the player's keys don't walk and no tick runs; once it's
## closed, both go on.
func _menu_holds_game(driver: GameDriver, open: bool) -> String:
	Input.action_press("move_right")
	var walks: bool = driver.input.command(driver.state).move != Command.NO_MOVE
	Input.action_release("move_right")
	var tick: int = driver.world.tick
	driver.advance(STEP)
	var ticked: bool = driver.world.tick > tick
	if walks == open or ticked == open:
		return "with the menu %s, the keys %s walk and the ticks %s run" % [
			"open" if open else "closed",
			"do" if walks else "don't",
			"do" if ticked else "don't",
		]
	return ""


## Stepping anti-aliasing on and the Survey's place back takes effect and keeps them;
## anti-aliasing's Auto button hands it back.
func _menu_choices(menu: GameMenu, graphics: Graphics, survey: SurveyChoice) -> String:
	var tab: SettingsTab = menu.settings
	var choices: Array[int] = Graphics.ANTI_ALIASING_CHOICES
	var next: int = choices[posmod(choices.find(Graphics.auto_anti_aliasing()) + 1, choices.size())]
	tab.button(Graphics.ANTI_ALIASING, "Next").pressed.emit()
	var problem: String = _check_applied(graphics, next)
	if problem.is_empty() and tab.shown[Graphics.ANTI_ALIASING] != _label_of(next):
		problem = "the menu shows anti-aliasing as %s" % tab.shown[Graphics.ANTI_ALIASING]
	var place: int = posmod(SurveyChoice.AUTO_PLACE - 1, SurveyChoice.Place.size())
	tab.button(SurveyChoice.PLACE_SETTING, "Previous").pressed.emit()
	var kept: Settings = Settings.load_from(SETTINGS_PATH)
	if problem.is_empty() and (survey.place_shown() != place
			or kept.chosen.get(SurveyChoice.PLACE_SETTING) != place
			or kept.chosen.get(Graphics.ANTI_ALIASING) != next):
		problem = "the menu's choices aren't followed or kept: %s" % [kept.chosen]
	tab.button(Graphics.ANTI_ALIASING, "Auto").pressed.emit()
	if problem.is_empty():
		problem = _check_applied(graphics, Graphics.auto_anti_aliasing())
	kept = Settings.load_from(SETTINGS_PATH)
	if problem.is_empty() and (kept.chosen.has(Graphics.ANTI_ALIASING)
			or not tab.shown[Graphics.ANTI_ALIASING].begins_with("Auto (")):
		problem = "the menu's Auto doesn't hand anti-aliasing back: %s" % [kept.chosen]
	return problem


## Turning the pause off lets the ticks run on behind the open menu, and keeps that; its Auto
## button pauses the game again.
func _menu_pause_choice(menu: GameMenu, driver: GameDriver) -> String:
	var tab: SettingsTab = menu.settings
	tab.button(GameMenu.PAUSE_SETTING, "Next").pressed.emit()
	var tick: int = driver.world.tick
	driver.advance(STEP)
	if driver.world.tick == tick or tab.shown[GameMenu.PAUSE_SETTING] != "Off":
		return "with the pause off, the open menu still holds the ticks"
	var kept: Settings = Settings.load_from(SETTINGS_PATH)
	if kept.chosen.get(GameMenu.PAUSE_SETTING) != 0:
		return "the pause choice isn't kept: %s" % [kept.chosen]
	tab.button(GameMenu.PAUSE_SETTING, "Auto").pressed.emit()
	tick = driver.world.tick
	driver.advance(STEP)
	if driver.world.tick != tick or not menu.pauses():
		return "the pause's Auto doesn't pause the game again"
	return ""


## The settings' rows fit a phone held either way and a desktop screen.
func _menu_on_screens(menu: GameMenu) -> String:
	for screen: Vector2 in [Vector2(360.0, 640.0), Vector2(640.0, 360.0), Vector2(1920.0, 1080.0)]:
		menu.lay_out(screen)
		var width: float = menu.settings.rows_width()
		if width <= 0.0 or width > screen.x - 2.0 * GameMenu.MARGIN:
			return "the settings' rows are %d pixels wide on a %s screen" % [width, screen]
	return ""


## The `menu` action closes the menu again, easing out.
func _close_menu(menu: GameMenu) -> String:
	_press_menu(menu)
	if menu.is_open() or menu.opacity() <= 0.0:
		return "the menu action doesn't close the menu, or it snaps shut"
	await _tree.create_timer(GameMenu.FADE_SECONDS * 2.0).timeout
	if menu.opacity() > 0.0:
		return "the menu doesn't finish easing out"
	return ""


func _press_menu(menu: GameMenu) -> void:
	var pressed: InputEventAction = InputEventAction.new()
	pressed.action = &"menu"
	pressed.pressed = true
	menu.get_viewport().push_input(pressed)


## Graphics as the main scene has it, reading the test's settings file.
func _start() -> Graphics:
	var ink: InkOutline = InkOutline.new()
	var graphics: Graphics = Graphics.new()
	graphics.settings_path = SETTINGS_PATH
	graphics.ink = ink
	graphics.add_child(ink)
	_tree.root.add_child(graphics)
	return graphics


func _check_applied(graphics: Graphics, msaa: int) -> String:
	if graphics.anti_aliasing() != msaa or _tree.root.msaa_3d != msaa:
		return "MSAA is %d on screen and %d in the settings, expected %d" % [
			_tree.root.msaa_3d,
			graphics.anti_aliasing(),
			msaa,
		]
	if graphics.ink.is_smoothed() != (msaa != Viewport.MSAA_DISABLED):
		return "the ink's smoothing doesn't follow MSAA %d" % msaa
	return ""


func _label_of(msaa: int) -> String:
	if msaa == Viewport.MSAA_DISABLED:
		return "Off"
	return "%d× MSAA" % (1 << msaa)


func _forget() -> void:
	SaveStore.remove(SETTINGS_PATH)
