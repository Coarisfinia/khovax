extends RefCounted
## Settings flow (#161): every graphics setting starts at Auto, which picks the project's value for
## this platform and says so in its label; a player's choice takes effect at once and survives a
## restart; and choosing Auto again hands the setting back. Anti-aliasing is the first: MSAA and the
## ink pass's smoothing together. In the game, the settings menu (#355) does all that: the `menu`
## action opens it, easing in; it lists every setting, each on Auto at first; a step changes one
## and keeps it, its Auto button hands it back; it fits a phone's screen; and the action closes it,
## easing out.

const SETTINGS_PATH: String = "user://test_settings.json"

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
	var menu: SettingsMenu = main.get_node("Hud/SettingsMenu") as SettingsMenu
	var result: String = await _open_menu(menu)
	if result.is_empty():
		result = _menu_choices(menu, graphics, main.get_node("SurveyChoice") as SurveyChoice)
	if result.is_empty():
		result = _menu_on_screens(menu)
	if result.is_empty():
		result = await _close_menu(menu)
	main.queue_free()
	await _tree.process_frame
	return result


## The `menu` action opens the menu, easing in, and it lists every setting, each on Auto.
func _open_menu(menu: SettingsMenu) -> String:
	if menu.is_open() or menu.opacity() > 0.0:
		return "the settings menu shows before it's opened"
	_press_menu(menu)
	if not menu.is_open() or menu.opacity() >= 1.0:
		return "the menu action doesn't open the settings menu, or it snaps open"
	await _tree.create_timer(SettingsMenu.FADE_SECONDS * 2.0).timeout
	if menu.opacity() < 1.0:
		return "the settings menu doesn't finish easing in"
	var listed: Array[String] = []
	for setting: String in menu.shown:
		listed.append(setting)
	var settings: Array[String] = [
		Graphics.ANTI_ALIASING,
		SurveyChoice.PLACE_SETTING,
		SurveyChoice.ZOOM_SETTING,
	]
	if listed != settings:
		return "the settings menu lists %s, not every setting" % [listed]
	for setting: String in listed:
		if not menu.shown[setting].begins_with("Auto ("):
			return "%s isn't on Auto at first: %s" % [setting, menu.shown[setting]]
	return ""


## Stepping anti-aliasing on and the Survey's place back takes effect and keeps them;
## anti-aliasing's
## Auto button hands it back.
func _menu_choices(menu: SettingsMenu, graphics: Graphics, survey: SurveyChoice) -> String:
	var choices: Array[int] = Graphics.ANTI_ALIASING_CHOICES
	var next: int = choices[posmod(choices.find(Graphics.auto_anti_aliasing()) + 1, choices.size())]
	menu.button(Graphics.ANTI_ALIASING, "Next").pressed.emit()
	var problem: String = _check_applied(graphics, next)
	if problem.is_empty() and menu.shown[Graphics.ANTI_ALIASING] != _label_of(next):
		problem = "the menu shows anti-aliasing as %s" % menu.shown[Graphics.ANTI_ALIASING]
	var place: int = posmod(SurveyChoice.AUTO_PLACE - 1, SurveyChoice.Place.size())
	menu.button(SurveyChoice.PLACE_SETTING, "Previous").pressed.emit()
	var kept: Settings = Settings.load_from(SETTINGS_PATH)
	if problem.is_empty() and (survey.place_shown() != place
			or kept.chosen.get(SurveyChoice.PLACE_SETTING) != place
			or kept.chosen.get(Graphics.ANTI_ALIASING) != next):
		problem = "the menu's choices aren't followed or kept: %s" % [kept.chosen]
	menu.button(Graphics.ANTI_ALIASING, "Auto").pressed.emit()
	if problem.is_empty():
		problem = _check_applied(graphics, Graphics.auto_anti_aliasing())
	kept = Settings.load_from(SETTINGS_PATH)
	if problem.is_empty() and (kept.chosen.has(Graphics.ANTI_ALIASING)
			or not menu.shown[Graphics.ANTI_ALIASING].begins_with("Auto (")):
		problem = "the menu's Auto doesn't hand anti-aliasing back: %s" % [kept.chosen]
	return problem


## The menu fits on a phone held either way and on a desktop screen.
func _menu_on_screens(menu: SettingsMenu) -> String:
	for screen: Vector2 in [Vector2(360.0, 640.0), Vector2(640.0, 360.0), Vector2(1920.0, 1080.0)]:
		menu.lay_out(screen)
		if not Rect2(Vector2.ZERO, screen).encloses(menu.panel_rect()):
			return "the settings menu %s doesn't fit a %s screen" % [menu.panel_rect(), screen]
	return ""


## The `menu` action closes the menu again, easing out.
func _close_menu(menu: SettingsMenu) -> String:
	_press_menu(menu)
	if menu.is_open() or menu.opacity() <= 0.0:
		return "the menu action doesn't close the settings menu, or it snaps shut"
	await _tree.create_timer(SettingsMenu.FADE_SECONDS * 2.0).timeout
	if menu.opacity() > 0.0:
		return "the settings menu doesn't finish easing out"
	return ""


func _press_menu(menu: SettingsMenu) -> void:
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
