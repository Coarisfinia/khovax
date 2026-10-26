class_name GameMenu
extends Control
## The game's one menu (#362): fullscreen and opaque, with a tab for each part of it, gameplay
## first, then system (_build_sheet). The `menu` action (Escape, a controller's Start, #779) opens
## and closes it, and on touch screens a small button does, showing the glyph of that key or button
## while a keyboard or a controller is in use there (#1192); the close button at its top right and
## `ui_cancel` (a controller's B) close it (#554). It eases in and out, never snaps.
## While it's open the game hears no input: the player stands, the touch stick rests, and the
## Survey's keys and pinch zoom only the Survey tab's Survey. By default it pauses single player
## (#302), a setting the player can change; co-op never pauses (GameDriver.pause). Its text grows
## with the screen, so it stays readable on a phone.

## The pause setting and its choices, saved by number: never reorder.
const PAUSE_SETTING: String = "pause_in_menu"
const PAUSE_CHOICES: Array[String] = ["Off", "On"]
const PAUSE_ON: int = 1
const AUTO_PAUSE: int = PAUSE_ON
const FADE_SECONDS: float = 0.25
## The Character tab, laid out in its scene (#437). This tab and the Quests and Settings tabs are
## loaded when the menu is built, not preloaded: their scripts name `GameMenu` (directly or through
## a panel), so a preload here makes a load cycle that Godot's script check reports as a scene
## referencing a non-existent script (#964).
const CHARACTER_TAB: String = "res://slices/menu/ui/character_tab.tscn"
## The Credits tab, laid out in its scene (#437).
const CREDITS_TAB: PackedScene = preload("res://slices/credits/ui/credits_tab.tscn")
## The Quests tab, laid out in its scene (#437).
const QUESTS_TAB: String = "res://slices/quests/ui/quests_tab.tscn"
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
const OPEN_TEXT: String = "Menu"
## The open and close buttons' icons (#459): white shapes, drawn in ink by the UI's theme.
const OPEN_ICON: Texture2D = preload("res://assets/game-icons/hamburger-menu.svg")
const CLOSE_ICON: Texture2D = preload("res://assets/game-icons/cancel.svg")
## How wide the menu's icons are, in font sizes: a little larger than the text, so they read as
## clearly.
const ICON_FONTS: float = 1.3
## The close button's words on hover: it shows only its icon, and its glyph the key (#583).
const CLOSE_TIP: String = "Close the menu"
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
## Who keeps the quests the Quests tab shows. The Character tab shows the profile the driver
## holds.
@export var quest_keeper: QuestKeeper

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
	# A copy of the UI's theme: the menu scales its own font with the screen.
	theme = UiTheme.theme().duplicate()
	var more_tabs: Array[Node] = get_children()
	_open_button = _with_icon(button(OPEN_TEXT, toggle), OPEN_ICON)
	_open_button.visible = DisplayServer.is_touchscreen_available()
	var _glyph: ActionGlyph = ActionGlyph.badge(_open_button, &"menu")
	add_child(_open_button)
	_build_sheet(more_tabs)


func _process(_delta: float) -> void:
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


## A label with `text` on one line, cut short with an ellipsis rather than wrapped: a wrapped
## label's height depends on a width its container only gives it later, so the menu's size would
## lag.
static func label(text: String) -> Label:
	var made: Label = Label.new()
	made.text = text
	made.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	made.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return made


## Replaces what `box` shows with one label per line of `lines`. The old labels leave it at once,
## so it never shows both.
static func show_lines(box: Container, lines: Array[String]) -> void:
	for old: Node in box.get_children():
		box.remove_child(old)
		old.queue_free()
	for line: String in lines:
		box.add_child(label(line))


## A button saying `text` that calls `pressed`.
static func button(text: String, pressed: Callable) -> Button:
	var made: Button = Button.new()
	made.text = text
	var _connected: int = made.pressed.connect(pressed)
	return made


## A button showing only the icon `shown` (#459), with `tip` as its words on hover, that calls
## `pressed`.
static func icon_button(shown: Texture2D, tip: String, pressed: Callable) -> Button:
	var made: Button = _with_icon(button("", pressed), shown)
	made.tooltip_text = tip
	return made


## Gives `made` the icon `shown`, beside its text, if any; lay_out sizes it with the font.
static func _with_icon(made: Button, shown: Texture2D) -> Button:
	made.icon = shown
	return made


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
	return pause.label(PAUSE_CHOICES[pause.value()])


## Steps the pause setting `steps` choices on, round after the last, and keeps it; returns why it
## couldn't be saved, or "".
func step_pause(steps: int) -> String:
	_pause().step(steps)
	return graphics.save_settings()


## Sizes the text to a screen of `screen` pixels, the open button at the top's middle (tests lay
## it out for other screens than their own this way).
func lay_out(screen: Vector2) -> void:
	var font: int = maxi(MIN_FONT, roundi(minf(screen.x, screen.y) * FONT_SHARE))
	if font != _font_size:
		_font_size = font
		theme.default_font_size = font
		_size_buttons(self)
		# Every button's icon in the menu, those of rows it builds later too (#584).
		theme.set_constant("icon_max_width", "Button", roundi(font * ICON_FONTS))
		character.fit(font)
	# The close button stands beside the tabs, so they have its width less.
	var room: float = screen.x - 4.0 * MARGIN - font * BUTTON_FONTS
	var width: float = minf(font * WIDTH_FONTS, room)
	settings.fit(width)
	# Beside the detail pane, the monsters' lines need the same width again, as far as it fits.
	var beside: bool = screen.x > screen.y
	character.fit_width(minf(2.0 * width, room) if beside else width)
	character.place_details(beside)
	quests_tab().fit(width)
	_open_button.size = Vector2.ZERO
	_open_button.position = Vector2((screen.x - _open_button.size.x) / 2.0, MARGIN)


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
		var hover: SurveyQuestHover = survey_tab.view.quest_hover()
		hover.pointer = Vector2.INF
		hover.show_state()


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
	character.holder = driver.holder
	tabs.add_child(character)
	survey_tab = SURVEY_TAB.instantiate() as SurveyTab
	survey_tab.survey = survey
	tabs.add_child(survey_tab)
	var quests_tab_shown: QuestsTab = (load(QUESTS_TAB) as PackedScene).instantiate() as QuestsTab
	quests_tab_shown.keeper = quest_keeper
	quests_tab_shown.driver = driver
	tabs.add_child(quests_tab_shown)
	# The tabs later slices add, like the codex book (#1174): game/ hands them over as the menu's
	# own children in the main scene, so the menu never names a slice after it. Each is named by its
	# node's name.
	for more: Node in more_tabs:
		remove_child(more)
		tabs.add_child(more)
	# The gameplay tabs first, then the system tabs (owner, #465).
	settings = (load(SETTINGS_TAB) as PackedScene).instantiate() as SettingsTab
	settings.graphics = graphics
	settings.survey = survey
	settings.menu = self
	var _followed: int = settings.changed.connect(_follow)
	tabs.add_child(settings)
	tabs.add_child(CREDITS_TAB.instantiate())
	row.add_child(tabs)
	var close: Button = icon_button(CLOSE_ICON, CLOSE_TIP, toggle)
	close.name = CLOSE_NAME
	var _glyph: ActionGlyph = ActionGlyph.badge(close, &"ui_cancel")
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(close)
	_sheet.add_child(row)
	add_child(_sheet)


## The pause setting, an index into PAUSE_CHOICES; Auto while there's no Graphics to keep it.
func _pause() -> SettingChoice:
	var kept_in: Settings = null
	if graphics != null:
		kept_in = graphics.settings
	return SettingChoice.new(kept_in, PAUSE_SETTING, PAUSE_CHOICES.size(), AUTO_PAUSE)


## The Quests tab, found under the sheet rather than kept in a field of its own.
func quests_tab() -> QuestsTab:
	return _sheet.find_child("Quests", true, false) as QuestsTab


## The button at the top that opens the menu on touch screens.
func open_button() -> Button:
	return _open_button


## The button at the top right that closes the menu, found like the Quests tab.
func close_button() -> Button:
	return _sheet.find_child(CLOSE_NAME, true, false) as Button


## Gives every button under `node` a finger-sized smallest side for the font in use.
func _size_buttons(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Button:
			(child as Button).custom_minimum_size = Vector2.ONE * _font_size * BUTTON_FONTS
		_size_buttons(child)
