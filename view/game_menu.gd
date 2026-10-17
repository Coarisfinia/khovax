class_name GameMenu
extends Control
## The game's one menu (#362): fullscreen and opaque, with a tab for each part of it (Settings so
## far; the other tabs are their own issues). The `menu` action (Escape) opens and closes it, and
## on touch screens a small button does; it eases in and out, never snaps. While it's open the game
## hears no input: the player stands, and the touch stick and the Survey's pinch and keys rest. By
## default it pauses single player (#302), a setting the player can change; co-op never pauses
## (GameDriver.pause). Its text grows with the screen, so it stays readable on a phone.

## The pause setting and its choices, saved by number: never reorder.
const PAUSE_SETTING: String = "pause_in_menu"
const PAUSE_CHOICES: Array[String] = ["Off", "On"]
const PAUSE_ON: int = 1
const AUTO_PAUSE: int = PAUSE_ON
const FADE_SECONDS: float = 0.25
## The text's size as a share of the screen's shorter side, and never smaller than this.
const FONT_SHARE: float = 0.03
const MIN_FONT: int = 16
## How wide the settings' rows are, in font sizes, at most the screen's width less the margins.
const WIDTH_FONTS: float = 24.0
const MARGIN: float = SurveyChoice.MARGIN
## A button's smallest side, in font sizes, so a finger can hit it.
const BUTTON_FONTS: float = 2.2
const OPEN_TEXT: String = "Menu"

## The driver, which holds its ticks while the menu pauses the game.
@export var driver: GameDriver
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

## The Settings tab.
var settings: SettingsTab
## Everything the menu shows when open: the opaque sheet over the whole screen.
var _sheet: PanelContainer
var _open_button: Button
var _open: bool = false
var _fade: Tween
var _font_size: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = Theme.new()
	theme.set_color("font_color", "Label", Toon.INK)
	_open_button = button(OPEN_TEXT, toggle)
	_open_button.visible = DisplayServer.is_touchscreen_available()
	add_child(_open_button)
	_build_sheet()


func _process(_delta: float) -> void:
	lay_out(get_viewport_rect().size)
	if _sheet.visible:
		settings.refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		toggle()
		get_viewport().set_input_as_handled()
	elif _open:
		# The game's own keys (the Survey's) rest while the menu is open.
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


## A button saying `text` that calls `pressed`.
static func button(text: String, pressed: Callable) -> Button:
	var made: Button = Button.new()
	made.text = text
	var _connected: int = made.pressed.connect(pressed)
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
	return _pause_choice() == PAUSE_ON


## The pause setting as the Settings tab shows it: "On", or "Auto (On)" while Auto picks it.
func pause_label() -> String:
	var shown: String = PAUSE_CHOICES[_pause_choice()]
	if _pause_chosen() >= 0:
		return shown
	return "Auto (%s)" % shown


## Steps the pause setting `steps` choices on, round after the last, and keeps it; returns why it
## couldn't be saved, or "".
func step_pause(steps: int) -> String:
	graphics.settings.chosen[PAUSE_SETTING] = posmod(_pause_choice() + steps, PAUSE_CHOICES.size())
	return graphics.settings.save(graphics.settings_path)


## Sizes the text to a screen of `screen` pixels, the open button at the top's middle (tests lay
## it out for other screens than their own this way).
func lay_out(screen: Vector2) -> void:
	var font: int = maxi(MIN_FONT, roundi(minf(screen.x, screen.y) * FONT_SHARE))
	if font != _font_size:
		_font_size = font
		theme.default_font_size = font
		_size_buttons(self)
	settings.fit(minf(font * WIDTH_FONTS, screen.x - 4.0 * MARGIN))
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
		pinch.set_process_input(not _open)


## The sheet: the tabs over the whole screen, and a button that closes the menu below them.
func _build_sheet() -> void:
	_sheet = PanelContainer.new()
	_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Boot.FOG
	style.set_content_margin_all(MARGIN)
	_sheet.add_theme_stylebox_override("panel", style)
	_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.visible = false
	_sheet.modulate.a = 0.0
	var column: VBoxContainer = VBoxContainer.new()
	var tabs: TabContainer = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# No panel of its own: the tabs' pages lie on the sheet, so the ink text stays on the fog.
	tabs.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	settings = SettingsTab.new()
	settings.name = "Settings"
	settings.graphics = graphics
	settings.survey = survey
	settings.menu = self
	var _followed: int = settings.changed.connect(_follow)
	tabs.add_child(settings)
	column.add_child(tabs)
	var close: Button = button("Close", toggle)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(close)
	_sheet.add_child(column)
	add_child(_sheet)


## The pause setting's choice in use, as an index into PAUSE_CHOICES.
func _pause_choice() -> int:
	var chosen: int = _pause_chosen()
	return chosen if chosen >= 0 else AUTO_PAUSE


## The player's choice of the pause setting, or -1 for Auto (also for a value that isn't a choice).
func _pause_chosen() -> int:
	if graphics == null:
		return -1
	var chosen: int = graphics.settings.chosen.get(PAUSE_SETTING, -1)
	return chosen if chosen >= 0 and chosen < PAUSE_CHOICES.size() else -1


## Gives every button under `node` a finger-sized smallest side for the font in use.
func _size_buttons(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Button:
			(child as Button).custom_minimum_size = Vector2.ONE * _font_size * BUTTON_FONTS
		_size_buttons(child)
