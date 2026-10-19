class_name SettingsTab
extends ScrollContainer
## The menu's Settings tab (#362, once #355's settings menu): the player's settings (#161), one row
## per setting with its name and what it's on now, "Auto (…)" while Auto picks it, and buttons to
## step to the previous or next choice or to hand it back to Auto. The settings' owners (Graphics,
## SurveyChoice, DamageNumbersChoice, the menu's pause) know each setting's choices and keep the
## player's; the tab only shows them and passes the player's picks on. It says everything in words,
## never by color alone
## (#68). It scrolls when the screen is too short for every row. Its layout lives in its scene,
## settings_tab.tscn (#437): the rows sit in the middle of the tab, as wide as `fit` makes them.

## After a pick changed a setting, so what follows it (the menu's pause) follows at once.
signal changed

## Whose settings the graphics rows show; it keeps every setting's choice (Settings' one owner).
var graphics: Graphics
## The Survey's place and zoom.
var survey: SurveyChoice
## The menu, whose pause is a setting.
var menu: GameMenu
## What each setting's row says it's on, by the setting's name. Kept here so tests can read it.
var shown: Dictionary[String, String] = {}
## How to word each setting's value and how to step it, by the setting's name.
var _labels: Dictionary[String, Callable] = {}
var _steps: Dictionary[String, Callable] = {}
var _values: Dictionary[String, Label] = {}

@onready var _rows: VBoxContainer = $Middle/Rows


func _ready() -> void:
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
	if graphics != null:
		var damage_numbers: DamageNumbersChoice = DamageNumbersChoice.new(graphics)
		_add_row(
			DamageNumbersChoice.SHOWN_SETTING,
			"Damage numbers",
			damage_numbers.shown_label,
			damage_numbers.step_shown,
		)
		_add_row(
			DamageNumbersChoice.SIZE_SETTING,
			"Damage number size",
			damage_numbers.size_label,
			damage_numbers.step_size,
		)
	if menu != null and graphics != null:
		_add_row(
			GameMenu.PAUSE_SETTING,
			"Pause in single player",
			menu.pause_label,
			menu.step_pause,
		)


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


## Makes the rows `width` pixels wide.
func fit(width: float) -> void:
	_rows.custom_minimum_size.x = width


## How wide the rows are: for tests.
func rows_width() -> float:
	return _rows.custom_minimum_size.x


## The button `which` ("Previous", "Next" or "Auto") in `setting`'s row.
func button(setting: String, which: String) -> Button:
	return _values[setting].get_parent().get_node(which) as Button


## A row for `setting`, named `title`: what `label` says it's on, and buttons that `stepper` steps
## it with (back and on) and one back to Auto.
func _add_row(setting: String, title: String, label: Callable, stepper: Callable) -> void:
	_labels[setting] = label
	_steps[setting] = stepper
	_rows.add_child(GameMenu.label(title))
	var row: HBoxContainer = HBoxContainer.new()
	var value: Label = GameMenu.label("")
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value)
	_values[setting] = value
	row.add_child(_named(GameMenu.button("<", step.bind(setting, -1)), "Previous"))
	row.add_child(_named(GameMenu.button(">", step.bind(setting, 1)), "Next"))
	row.add_child(_named(GameMenu.button("Auto", choose_auto.bind(setting)), "Auto"))
	_rows.add_child(row)


func _named(node: Node, node_name: String) -> Node:
	node.name = node_name
	return node


func _report(problem: String) -> void:
	refresh()
	changed.emit()
	if not problem.is_empty():
		push_warning("the setting can't be saved: " + problem)
