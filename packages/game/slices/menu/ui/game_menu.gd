class_name GameMenu
extends Control
## The game's one menu (#362): fullscreen and opaque, with a tab for each part of it, gameplay
## first, then system (_build_sheet). The `menu` action (Escape, a controller's Start, #779) opens
## and closes it, and on touch screens a small button does, at the top's middle, or at the top of
## the quest list's side above it on a screen held upright (#1465), showing the glyph of that key
## or button while a keyboard or a controller is in use there (#1192); the close button at its top
## right and `ui_cancel` (a controller's B) close it (#554). It eases in and out, never snaps.
## While a carried monster has a knot of its development web to take (KnotMark, #1443), that button
## shows on every device, saying so in words and with the knot's shape in place of its own icon:
## clicked, tapped or with the `menu` action, whose glyph it shows, it opens the menu, whose
## Character tab marks the monster's row and takes the knot on its web.
## While it's open the game hears no input: the player stands, the touch stick rests, and the
## Survey's keys and pinch zoom only the Survey tab's Survey. By default it pauses single player
## (#302), a setting the player can change; co-op never pauses (GameDriver.pause). Its text grows
## with the screen, so it stays readable on a phone. The names its tabs show as links (NameLinks:
## the Character tab's factions, the Survey tab's holder, #1447) raise its `name_selected` and
## `name_shown`, which the main scene ties to the codex, a slice after this one.

## A name with a codex page was selected in a tab: the kind of its tag and its id.
signal name_selected(kind: String, id: String)
## A tab showed a name with a codex page: the player met it (#1174).
signal name_shown(kind: String, id: String)
## The tabs' rows were made `width` pixels wide (`lay_out`): the tabs handed in follow it.
signal tabs_fitted(width: float)
## How far the open button, its badge included, reaches down from the top of `side_column`, or 0
## while it leaves the column's top free (`lay_out`): the quest list there makes room below it
## (#1465).
signal side_room(below: float)

## The pause setting, its choices (pause_choices) saved by number: never reorder them.
const PAUSE_SETTING: String = "pause_in_menu"
const PAUSE_COUNT: int = 2
const PAUSE_ON: int = 1
const AUTO_PAUSE: int = PAUSE_ON
const FADE_SECONDS: float = 0.25
## The Character tab, laid out in its scene (#437). This tab and the Settings tab are
## loaded when the menu is built, not preloaded: their scripts name `GameMenu` (directly or through
## a panel), so a preload here makes a load cycle that Godot's script check reports as a scene
## referencing a non-existent script (#964).
const CHARACTER_TAB: String = "res://slices/menu/ui/character_tab.tscn"
## The Controls tab, laid out in its scene (#1414).
const CONTROLS_TAB: PackedScene = preload("res://slices/input_prompts/ui/controls_tab.tscn")
## The Credits tab, laid out in its scene (#437).
const CREDITS_TAB: PackedScene = preload("res://slices/credits/ui/credits_tab.tscn")
## The Settings tab, laid out in its scene (#437).
const SETTINGS_TAB: String = "res://slices/settings/ui/settings_tab.tscn"
## The Survey tab, laid out in its scene (#437).
const SURVEY_TAB: PackedScene = preload("res://slices/survey/ui/survey_tab.tscn")
## The text's size as a share of the screen's shorter side, and never smaller than this.
const FONT_SHARE: float = 0.03
const MIN_FONT: int = 16
## How wide the settings' rows are, in font sizes, at most the screen's width less the margins.
const WIDTH_FONTS: float = 24.0
const MARGIN: float = SurveyChoice.MARGIN
## A button's smallest side, in font sizes, so a finger can hit it.
const BUTTON_FONTS: float = 2.2
## The open and close buttons' icons (#459): white shapes, drawn in ink by the UI's theme.
const OPEN_ICON: String = "icon_hamburger_menu"
const CLOSE_ICON: String = "icon_cancel"
## The close button's node name; its words on hover (_build_sheet) say what it does, since it
## shows only its icon, and its glyph the key (#583).
const CLOSE_NAME: String = "Close"

## The driver, which holds its ticks while the menu pauses the game.
@export var driver: Session
## The local player's input, which the menu blocks while it's open.
@export var input: LocalInput
## Whose settings the Settings tab shows; it keeps every setting's choice (Settings' one owner).
@export var graphics: Graphics
## The Survey's place and zoom, which are settings.
@export var survey: SurveyChoice
## The touch stick and the Survey's pinch hear touches before the menu can take them, so they
## rest while it's open.
@export var stick: TouchStick
@export var pinch: SurveyPinch

## The column at the top's side that the open button stands above on a screen held upright, the
## quest list's: given a screen's size, its place on it (#1465). game/ hands it in (#1614), since
## the quests' slice comes after the menu's, and ties `side_room` to the list.
var side_column: Callable
## The Character tab.
var character: CharacterTab
## The Settings tab.
var settings: SettingsTab
## The Survey tab.
var survey_tab: SurveyTab
## Everything the menu shows when open: the opaque sheet over the whole screen.
var _sheet: PanelContainer
var _open_button: Button
var _open: bool = false
var _fade: Tween
var _font_size: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Laid out before the quest list, which makes room for the open button in the same frame
	# (#1465).
	process_priority = -1
	# A copy of the UI's theme: the menu scales its own font with the screen.
	theme = UiTheme.theme().duplicate()
	var more_tabs: Array[Node] = get_children()
	_open_button = MenuWidgets.with_icon(
		MenuWidgets.button(open_text(), toggle),
		ResourcePacks.texture(OPEN_ICON),
	)
	_open_button.visible = DisplayServer.is_touchscreen_available()
	var _glyph: ActionGlyph = ActionGlyph.badge(_open_button, &"menu")
	add_child(_open_button)
	_build_sheet(more_tabs)
	# Once the sheet is in the tree, so the Settings tab has its submenus.
	if survey != null:
		survey.add_rows(settings)
	if graphics != null:
		var pause: String = tr("Pause in single player")
		settings.add_auto_row(SettingsTab.GAME, PAUSE_SETTING, pause, pause_label, step_pause)
	_add_host_settings()
	# Once the sheet is in the tree too: the Character tab builds its panels when it's ready.
	for named: Control in [character.factions, survey_tab]:
		_relay_names(named)


func _process(_delta: float) -> void:
	show_knot(knot_waits())
	lay_out(get_viewport_rect().size)
	if _sheet.visible:
		settings.refresh()


func _unhandled_input(event: InputEvent) -> void:
	# Cancel (a controller's B) only closes: while the menu is closed, the game keeps it.
	if event.is_action_pressed("menu") or (_open and event.is_action_pressed("ui_cancel")):
		toggle()
		get_viewport().set_input_as_handled()
	elif _open:
		# The game's own keys rest while the menu is open; the Survey tab took the zoom's first.
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _open


## Opens the menu if it's closed and closes it if it's open, easing either way.
func toggle() -> void:
	_open = not _open
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP if _open else Control.MOUSE_FILTER_IGNORE
	_follow()
	if _fade != null:
		_fade.kill()
	settings.refresh()
	character.refresh()
	_sheet.visible = true
	_fade = _sheet.create_tween()
	var _eased: PropertyTweener = _fade.tween_property(
		_sheet,
		"modulate:a",
		1.0 if _open else 0.0,
		FADE_SECONDS,
	)
	if not _open:
		var _hidden: CallbackTweener = _fade.tween_callback(_sheet.hide)


## Whether an open menu pauses single player: the player's choice, or Auto's (on).
func pauses() -> bool:
	return _pause().value() == PAUSE_ON


## The pause setting as the Settings tab shows it: "On", or "Auto (On)" while Auto picks it.
func pause_label() -> String:
	var pause: SettingChoice = _pause()
	return pause.label(pause_choices()[pause.value()])


## The pause setting's choices as the Settings tab names them, in the order they're saved.
func pause_choices() -> Array[String]:
	return [tr("Off"), tr("On")]


## Steps the pause setting `steps` choices on, round after the last, and keeps it; returns why it
## couldn't be saved, or "".
func step_pause(steps: int) -> String:
	_pause().step(steps)
	return graphics.save_settings()


## Sizes the text to a screen of `screen` pixels, the open button at the top's middle (tests lay
## it out for other screens than their own this way). On a screen held upright the quest list and
## the Survey's corner leave no room between them there, so the button goes at the top of the
## list's side and the list makes room for it below (#1465).
func lay_out(screen: Vector2) -> void:
	var font: int = maxi(MIN_FONT, roundi(minf(screen.x, screen.y) * FONT_SHARE))
	if font != _font_size:
		_font_size = font
		theme.default_font_size = font
		_size_buttons(self)
		# Every button's icon in the menu, those of rows it builds later too (#584).
		theme.set_constant("icon_max_width", "Button", roundi(font * MenuWidgets.ICON_FONTS))
		character.fit(font)
	# The close button stands beside the tabs, so they have its width less.
	var room: float = screen.x - 4.0 * MARGIN - font * BUTTON_FONTS
	var width: float = minf(font * WIDTH_FONTS, room)
	settings.fit(width)
	# Beside the detail pane, the monsters' lines need the same width again, as far as it fits.
	var beside: bool = screen.x > screen.y
	character.fit_width(minf(2.0 * width, room) if beside else width)
	character.place_details(beside)
	tabs_fitted.emit(width)
	controls_tab().fit(width)
	_open_button.size = Vector2.ZERO
	_open_button.position = Vector2((screen.x - _open_button.size.x) / 2.0, MARGIN)
	if not side_column.is_valid():
		return
	var list_room: float = 0.0
	if screen.y > screen.x:
		var column: Rect2 = side_column.call(screen)
		var left: bool = column.get_center().x < screen.x / 2.0
		# On the right, its glyph's badge hanging past its corner stays on the screen too.
		var extent: Rect2 = with_badge(_open_button)
		_open_button.position = Vector2(
			column.position.x if left else column.end.x - extent.end.x,
			column.position.y,
		)
		if _open_button.visible:
			list_room = extent.end.y
	side_room.emit(list_room)


## What `shown` covers, from its top left: itself and its glyph's badge hanging past its corner.
static func with_badge(shown: Control) -> Rect2:
	var covered: Rect2 = Rect2(Vector2.ZERO, shown.size)
	for child: Node in shown.get_children():
		if child is Control and (child as Control).visible:
			covered = covered.merge((child as Control).get_rect())
	return covered


## How far the menu has faded in: 0 while hidden, 1 when fully shown.
func opacity() -> float:
	return _sheet.modulate.a if _sheet.visible else 0.0


## Blocks the game's input while the menu is open and pauses single player if the setting says so.
func _follow() -> void:
	if input != null:
		input.blocked = _open
	if driver != null:
		driver.pause(_open and pauses())
	if stick != null:
		stick.let_go()
		stick.set_process_input(not _open)
	if pinch != null:
		pinch.let_go()
		pinch.in_menu = survey_tab.view if _open else null
	# The pointer that rested on the tab's Survey is gone with it (#1298): a reopened menu shows no
	# quest card until the pointer moves onto an arrow again.
	if not _open and survey_tab != null and survey_tab.view != null:
		survey_tab.view.let_go()


## The sheet: the tabs over the whole screen, `more_tabs` after the gameplay ones, and the button
## that closes the menu at its top right, beside the tabs, so it's the same on every tab (#554).
func _build_sheet(more_tabs: Array[Node]) -> void:
	_sheet = PanelContainer.new()
	_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sheet.add_theme_stylebox_override("panel", UiTheme.sheet(MARGIN))
	_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.visible = false
	_sheet.modulate.a = 0.0
	var row: HBoxContainer = HBoxContainer.new()
	var tabs: TabContainer = TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# No panel of its own: the tabs' pages lie on the sheet, so the ink text stays on the fog.
	tabs.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	character = (load(CHARACTER_TAB) as PackedScene).instantiate() as CharacterTab
	character.driver = driver
	tabs.add_child(character)
	survey_tab = SURVEY_TAB.instantiate() as SurveyTab
	survey_tab.survey = survey
	tabs.add_child(survey_tab)
	# The tabs later slices add, like the Quests tab and the codex book (#1174, #1614): game/ hands
	# them over as the menu's own children in the main scene, so the menu never names a slice after
	# it. Each is titled by its tab_title() (#1677).
	for more: Node in more_tabs:
		remove_child(more)
		tabs.add_child(more)
	# The gameplay tabs first, then the system tabs (owner, #465).
	settings = (load(SETTINGS_TAB) as PackedScene).instantiate() as SettingsTab
	settings.graphics = graphics
	var _followed: int = settings.changed.connect(_follow)
	tabs.add_child(settings)
	tabs.add_child(CONTROLS_TAB.instantiate())
	tabs.add_child(CREDITS_TAB.instantiate())
	# Each tab names its title with a literal tr() (#1677), which the translation template sees; a
	# tab without one keeps its node's name.
	for tab: Node in tabs.get_children():
		if tab.has_method(&"tab_title"):
			tabs.set_tab_title(tab.get_index(), str(tab.call(&"tab_title")))
	row.add_child(tabs)
	var close: Button = MenuWidgets.icon_button(
		ResourcePacks.texture(CLOSE_ICON),
		tr("Close the menu"),
		toggle,
	)
	close.name = CLOSE_NAME
	var _glyph: ActionGlyph = ActionGlyph.badge(close, &"ui_cancel")
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(close)
	_sheet.add_child(row)
	add_child(_sheet)


## Raises the names `named` (a tab or a panel with NameLinks) selects and shows as the menu's own.
func _relay_names(named: Control) -> void:
	var _selected: int = named.connect(&"name_selected", name_selected.emit)
	var _met: int = named.connect(&"name_shown", name_shown.emit)


## The world's settings, which the host chooses (#1309), in the Settings tab: the difficulty in its
## Difficulty submenu (#1315) and the world settings in its World submenu (#1316).
func _add_host_settings() -> void:
	if driver == null:
		return
	var difficulties: Array[String] = [tr("Easy"), tr("Standard"), tr("Hard")]
	_add_host_row(SettingsTab.DIFFICULTY, HostSettings.DIFFICULTY, tr("Difficulty"), difficulties)
	var rates: Array[String] = [tr("50%"), tr("Standard (100%)"), tr("150%"), tr("200%")]
	_add_host_row(SettingsTab.WORLD, HostSettings.DROP_RATE, tr("Drop rate"), rates)
	var delays: Array[String] = [
		tr("15 min"),
		tr("30 min"),
		tr("Standard (1 hour)"),
		tr("2 hours"),
		tr("4 hours"),
	]
	_add_host_row(SettingsTab.WORLD, HostSettings.RESET_DELAY, tr("Instance reset delay"), delays)
	var off_on: Array[String] = [tr("Off"), tr("On")]
	_add_host_row(
		SettingsTab.WORLD,
		HostSettings.REVIVE_ON_WAYSTONES,
		tr("Revive beasts at waystones"),
		off_on,
	)


## A row in the Settings tab's `submenu` for the host's `setting` (HostChoice), named `title`, its
## choices called `names`. The choice is a child of the menu, so the row's callables stay bound to
## it.
func _add_host_row(submenu: String, setting: String, title: String, names: Array[String]) -> void:
	var choice: HostChoice = HostChoice.new(driver, setting, names)
	choice.name = setting.to_pascal_case()
	add_child(choice)
	var _row: HBoxContainer = settings.add_row(submenu, setting, title, choice.label, choice.step)


## The pause setting, an index into pause_choices(); Auto while there's no Graphics to keep it.
func _pause() -> SettingChoice:
	var kept_in: Settings = null
	if graphics != null:
		kept_in = graphics.settings
	return SettingChoice.new(kept_in, PAUSE_SETTING, PAUSE_COUNT, AUTO_PAUSE)


## The Controls tab, found under the sheet rather than kept in a field of its own.
func controls_tab() -> ControlsTab:
	return _sheet.find_child("Controls", true, false) as ControlsTab


## Whether a monster the player carries has a knot to take (#1443).
func knot_waits() -> bool:
	if character == null:
		return false
	for short_id: String in character.monsters.carried_ids():
		if KnotMark.waits(character.monsters.monster_by(short_id)):
			return true
	return false


## Marks the open button while a knot `waits` (#1443): it shows then on every device, in words and
## with the knot's shape.
func show_knot(waits: bool) -> void:
	_open_button.text = knot_text() if waits else open_text()
	_open_button.icon = ResourcePacks.texture(KnotMark.ICON if waits else OPEN_ICON)
	_open_button.visible = waits or DisplayServer.is_touchscreen_available()


## What the open button says.
func open_text() -> String:
	return tr("Menu")


## What the open button says while a knot waits (#1443), with the knot's mark in its words.
func knot_text() -> String:
	return tr("Menu: %s") % KnotMark.text()


## The button at the top that opens the menu on touch screens, and on every device while a knot
## waits.
func open_button() -> Button:
	return _open_button


## The button at the top right that closes the menu, found like the Controls tab.
func close_button() -> Button:
	return _sheet.find_child(CLOSE_NAME, true, false) as Button


## Gives every button under `node` a finger-sized smallest side for the font in use.
func _size_buttons(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Button:
			(child as Button).custom_minimum_size = Vector2.ONE * _font_size * BUTTON_FONTS
		_size_buttons(child)
