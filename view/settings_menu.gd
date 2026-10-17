class_name SettingsMenu
extends Control
## The settings menu (#355): the player's settings (#161), one row per setting with its name and
## what it's on now, "Auto (…)" while Auto picks it, and buttons to step to the previous or next
## choice or to hand it back to Auto. The `menu` action (Escape) opens and closes it, and on touch
## screens a small button does; it eases in and out, never snaps. The settings' owners (Graphics,
## SurveyChoice) know each setting's choices and keep the player's; the menu only shows them and
## passes the player's picks on. It says everything in words, never by color alone (#68), and its
## text grows with the screen, so it stays readable on a phone. Pausing while it's open is #302.

const FADE_SECONDS: float = 0.25
## The text's size as a share of the screen's shorter side, and never smaller than this.
const FONT_SHARE: float = 0.03
const MIN_FONT: int = 16
## How wide the menu is, in font sizes, at most the screen's width less a margin on both sides.
const WIDTH_FONTS: float = 24.0
const MARGIN: float = SurveyChoice.MARGIN
const GAP: float = 8.0
## A button's smallest side, in font sizes, so a finger can hit it.
const BUTTON_FONTS: float = 2.2
const BACKDROP_ALPHA: float = 0.95
const BORDER_PIXELS: int = 2
const TITLE: String = "Settings"

## Whose settings the graphics rows show; it keeps every setting's choice (Settings' one owner).
@export var graphics: Graphics
## The Survey's place and zoom.
@export var survey: SurveyChoice
## The touch stick, which stops steering while the menu is open.
@export var stick: TouchStick

## What each setting's row says it's on, by the setting's name. Kept here so tests can read it.
var shown: Dictionary[String, String] = {}
var _panel: PanelContainer
var _rows: VBoxContainer
var _open_button: Button
## How to word each setting's value and how to step it, by the setting's name.
var _labels: Dictionary[String, Callable] = {}
var _steps: Dictionary[String, Callable] = {}
var _values: Dictionary[String, Label] = {}
var _open: bool = false
var _fade: Tween
var _font_size: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = Theme.new()
	theme.set_color("font_color", "Label", Toon.INK)
	_open_button = _button(TITLE, toggle)
	_open_button.visible = DisplayServer.is_touchscreen_available()
	add_child(_open_button)
	_build_panel()
	if graphics != null:
		_add_row(
			Graphics.ANTI_ALIASING,
			"Anti-aliasing",
			graphics.anti_aliasing_label,
			graphics.step_anti_aliasing,
		)
	if survey != null:
		_add_row(SurveyChoice.PLACE_SETTING, "Survey", survey.place_label, survey.cycle)
		_add_row(SurveyChoice.ZOOM_SETTING, "Survey zoom", survey.zoom_label, survey.zoom_by)
	_rows.add_child(_button("Close", toggle))


func _process(_delta: float) -> void:
	lay_out(get_viewport_rect().size)
	if _panel.visible:
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		toggle()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _open


## Opens the menu if it's closed and closes it if it's open, easing either way.
func toggle() -> void:
	_open = not _open
	if stick != null:
		stick.let_go()
		stick.set_process_input(not _open)
	if _fade != null:
		_fade.kill()
	refresh()
	_panel.visible = true
	_fade = _panel.create_tween()
	var _eased: PropertyTweener = _fade.tween_property(
		_panel,
		"modulate:a",
		1.0 if _open else 0.0,
		FADE_SECONDS,
	)
	if not _open:
		var _hidden: CallbackTweener = _fade.tween_callback(_panel.hide)


## Steps `setting` `steps` choices on (back for fewer), as the row's buttons do.
func step(setting: String, steps: int) -> void:
	var problem: String = _steps[setting].call(steps)
	_report(problem)


## Hands `setting` back to Auto, as the row's Auto button does.
func choose_auto(setting: String) -> void:
	_report(graphics.choose_auto(setting))


## Shows what every setting is on now.
func refresh() -> void:
	for setting: String in _labels:
		var label: String = _labels[setting].call()
		shown[setting] = label
		_values[setting].text = shown[setting]


## Sizes the text to a screen of `screen` pixels and centres the menu on it, the open button at the
## top's middle (tests lay it out for other screens than their own this way).
func lay_out(screen: Vector2) -> void:
	var font: int = maxi(MIN_FONT, roundi(minf(screen.x, screen.y) * FONT_SHARE))
	if font != _font_size:
		_font_size = font
		theme.default_font_size = font
		_size_buttons(self)
	var width: float = minf(font * WIDTH_FONTS, screen.x - 2.0 * MARGIN)
	_panel.custom_minimum_size.x = width
	_panel.size = Vector2(width, 0.0)
	_panel.position = ((screen - _panel.size) / 2.0).max(Vector2.ZERO)
	_open_button.size = Vector2.ZERO
	_open_button.position = Vector2((screen.x - _open_button.size.x) / 2.0, MARGIN)


## The menu's panel: where it is on screen, for tests.
func panel_rect() -> Rect2:
	return _panel.get_rect()


## How far the menu has faded in: 0 while hidden, 1 when fully shown.
func opacity() -> float:
	return _panel.modulate.a if _panel.visible else 0.0


## The button `which` ("Previous", "Next" or "Auto") in `setting`'s row.
func button(setting: String, which: String) -> Button:
	return _values[setting].get_parent().get_node(which) as Button


func _build_panel() -> void:
	_panel = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(Boot.FOG, BACKDROP_ALPHA)
	style.border_color = Toon.INK
	style.set_border_width_all(BORDER_PIXELS)
	style.set_content_margin_all(MARGIN)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.visible = false
	_panel.modulate.a = 0.0
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", roundi(GAP))
	var title: Label = _label(TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rows.add_child(title)
	_panel.add_child(_rows)
	add_child(_panel)


## A row for `setting`, named `title`: what `label` says it's on, and buttons that `stepper` steps
## it with (back and on) and one back to Auto.
func _add_row(setting: String, title: String, label: Callable, stepper: Callable) -> void:
	_labels[setting] = label
	_steps[setting] = stepper
	_rows.add_child(_label(title))
	var row: HBoxContainer = HBoxContainer.new()
	var value: Label = _label("")
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value)
	_values[setting] = value
	row.add_child(_named(_button("<", step.bind(setting, -1)), "Previous"))
	row.add_child(_named(_button(">", step.bind(setting, 1)), "Next"))
	row.add_child(_named(_button("Auto", choose_auto.bind(setting)), "Auto"))
	_rows.add_child(row)


func _label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	# One line each, cut short with an ellipsis rather than wrapped: a wrapped label's height
	# depends on a width its container only gives it later, so the menu's size would lag.
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _button(text: String, pressed: Callable) -> Button:
	var made: Button = Button.new()
	made.text = text
	var _connected: int = made.pressed.connect(pressed)
	return made


func _named(node: Node, node_name: String) -> Node:
	node.name = node_name
	return node


## Gives every button under `node` a finger-sized smallest side for the font in use.
func _size_buttons(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Button:
			(child as Button).custom_minimum_size = Vector2.ONE * _font_size * BUTTON_FONTS
		_size_buttons(child)


func _report(problem: String) -> void:
	refresh()
	if not problem.is_empty():
		push_warning("the setting can't be saved: " + problem)
