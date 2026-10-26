class_name SettingsTab
extends ScrollContainer
## The menu's Settings tab (#362, once #355's settings menu): the player's settings (#161), in
## submenus (#1314). It opens on a list of them; each shows its own rows, one per setting with its
## name and what it's on now, "Auto (…)" while Auto picks it, and buttons to step to the previous
## or next choice or to hand it back to Auto, and a Back button (or `ui_cancel`, a controller's B)
## back to the list. The settings' owners (Graphics, SurveyChoice, DamageNumbersChoice, the menu's
## pause) know each setting's choices and keep the player's; the tab only shows them and passes the
## player's picks on. It says everything in words, never by color alone (#68). It scrolls when the
## screen is too short for every row. Its layout lives in its scene, settings_tab.tscn (#437): the
## rows sit in the middle of the tab, as wide as `fit` makes them.

## After a pick changed a setting, so what follows it (the menu's pause) follows at once.
signal changed

## The buttons that step a setting back and on: their icons (#584) and their words on hover.
const PREVIOUS_ICON: Texture2D = preload("res://assets/game-icons/plain-arrow-left.svg")
const NEXT_ICON: Texture2D = preload("res://assets/game-icons/plain-arrow-right.svg")
const PREVIOUS_TIP: String = "Previous choice"
const NEXT_TIP: String = "Next choice"
## The submenus, in the order the list shows them. The difficulty's rows, the world's own (#1315),
## come from the menu (`add_row`).
const DIFFICULTY: String = "Difficulty"
const GRAPHICS: String = "Graphics"
const INTERFACE: String = "Interface"
const GAME: String = "Game"
## The list of submenus, as `open_submenu` names it while none is open.
const LIST: String = ""

## Whose settings the graphics rows show; it keeps every setting's choice (Settings' one owner).
var graphics: Graphics
## The Survey's place and zoom.
var survey: SurveyChoice
## The menu, whose pause is a setting.
var menu: GameMenu
## Whether the damage numbers show and how large, kept in `graphics`' Settings; held here so the
## rows' callables stay bound to it.
var damage_numbers: DamageNumbersChoice
## What each setting's row says it's on, by the setting's name. Kept here so tests can read it.
var shown: Dictionary[String, String] = {}
## How to word each setting's value and how to step it, by the setting's name.
var _labels: Dictionary[String, Callable] = {}
var _steps: Dictionary[String, Callable] = {}
var _values: Dictionary[String, Label] = {}
## Each submenu's rows, and the button in the list that opens it, by the submenu's name.
var _submenus: Dictionary[String, VBoxContainer] = {}
var _openers: Dictionary[String, Button] = {}
var _open: String = LIST

@onready var _rows: VBoxContainer = $Middle/Rows
@onready var _list: VBoxContainer = $Middle/Rows/List


func _ready() -> void:
	for submenu: String in [DIFFICULTY, GRAPHICS, INTERFACE, GAME]:
		_add_submenu(submenu)
	if graphics != null:
		_auto_row(
			GRAPHICS,
			Graphics.ANTI_ALIASING,
			"Anti-aliasing",
			graphics.anti_aliasing_label,
			graphics.step_anti_aliasing,
		)
	if survey != null:
		_auto_row(INTERFACE, SurveyChoice.PLACE_SETTING, "Survey", survey.place_label, survey.cycle)
		_auto_row(
			INTERFACE,
			SurveyChoice.ZOOM_SETTING,
			"Survey zoom",
			survey.zoom_label,
			survey.zoom_by,
		)
	if graphics != null:
		damage_numbers = DamageNumbersChoice.new(graphics)
		_auto_row(
			INTERFACE,
			DamageNumbersChoice.SHOWN_SETTING,
			"Damage numbers",
			damage_numbers.shown_label,
			damage_numbers.step_shown,
		)
		_auto_row(
			INTERFACE,
			DamageNumbersChoice.SIZE_SETTING,
			"Damage number size",
			damage_numbers.size_label,
			damage_numbers.step_size,
		)
	if menu != null and graphics != null:
		_auto_row(
			GAME,
			GameMenu.PAUSE_SETTING,
			"Pause in single player",
			menu.pause_label,
			menu.step_pause,
		)


## Hidden (another tab chosen, or the menu closed), it's back on the list the next time it shows.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready() and not is_visible_in_tree():
		_open = LIST
		_show_open()


## A controller's B in a submenu goes back to the list, before the menu hears it and closes.
func _unhandled_input(event: InputEvent) -> void:
	if _open != LIST and is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		back()
		get_viewport().set_input_as_handled()


## Shows the rows of `submenu` in place of the list; a controller's focus moves onto them if it
## was on the tab.
func open(submenu: String) -> void:
	var focused: bool = _has_focus()
	_open = submenu
	_show_open()
	if focused:
		back_button(submenu).grab_focus()


## Goes back from a submenu to the list; a controller's focus moves onto the submenu's button.
func back() -> void:
	var left: String = _open
	var focused: bool = _has_focus()
	_open = LIST
	_show_open()
	if focused and _openers.has(left):
		_openers[left].grab_focus()


## The submenu open now, or LIST while the list shows.
func open_submenu() -> String:
	return _open


## The button in the list that opens `submenu`.
func opener(submenu: String) -> Button:
	return _openers[submenu]


## The Back button at the top of `submenu`.
func back_button(submenu: String) -> Button:
	return _submenus[submenu].get_child(0).get_child(0) as Button


## The submenu `setting`'s row is in.
func submenu_of(setting: String) -> String:
	for submenu: String in _submenus:
		if _values[setting].get_parent().get_parent() == _submenus[submenu]:
			return submenu
	return LIST


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


## A submenu named `submenu`, hidden until it's opened: a Back button and its name at its top,
## and a button in the list that opens it.
func _add_submenu(submenu: String) -> void:
	var opens: Button = GameMenu.button(submenu, open.bind(submenu))
	opens.name = submenu
	_list.add_child(opens)
	_openers[submenu] = opens
	var box: VBoxContainer = VBoxContainer.new()
	box.name = submenu
	box.visible = false
	box.add_theme_constant_override("separation", _rows.get_theme_constant("separation"))
	var top: HBoxContainer = HBoxContainer.new()
	var leave: Button = GameMenu.button("Back", back)
	leave.icon = PREVIOUS_ICON
	# A controller's B goes back too (_unhandled_input), and the button shows it.
	var _glyph: ActionGlyph = ActionGlyph.badge(leave, &"ui_cancel")
	top.add_child(_named(leave, "Back"))
	var title: Label = GameMenu.label(submenu)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(title)
	box.add_child(top)
	_rows.add_child(box)
	_submenus[submenu] = box


## Shows the list or the open submenu, and hides the rest.
func _show_open() -> void:
	_list.visible = _open == LIST
	for submenu: String in _submenus:
		_submenus[submenu].visible = submenu == _open


## Whether a controller's focus is on something in the tab.
func _has_focus() -> bool:
	var focused: Control = get_viewport().gui_get_focus_owner()
	return focused != null and is_ancestor_of(focused)


## A row in `submenu` for `setting`, named `title`: what `label` says it's on, and buttons that
## `stepper` steps it with (back and on) and one back to Auto.
func _auto_row(
		submenu: String,
		setting: String,
		title: String,
		label: Callable,
		stepper: Callable,
) -> void:
	var row: HBoxContainer = add_row(submenu, setting, title, label, stepper)
	row.add_child(_named(GameMenu.button("Auto", choose_auto.bind(setting)), "Auto"))


## A row in `submenu` for `setting`, named `title`: what `label` says it's on, and buttons that
## `stepper` steps it with (back and on), for a setting without Auto, like the difficulty the menu
## adds; returns the row.
func add_row(
		submenu: String,
		setting: String,
		title: String,
		label: Callable,
		stepper: Callable,
) -> HBoxContainer:
	_labels[setting] = label
	_steps[setting] = stepper
	var rows: VBoxContainer = _submenus[submenu]
	rows.add_child(GameMenu.label(title))
	var row: HBoxContainer = HBoxContainer.new()
	var value: Label = GameMenu.label("")
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value)
	_values[setting] = value
	var previous: Button = GameMenu.icon_button(PREVIOUS_ICON, PREVIOUS_TIP, step.bind(setting, -1))
	row.add_child(_named(previous, "Previous"))
	row.add_child(_named(GameMenu.icon_button(NEXT_ICON, NEXT_TIP, step.bind(setting, 1)), "Next"))
	rows.add_child(row)
	return row


func _named(node: Node, node_name: String) -> Node:
	node.name = node_name
	return node


func _report(problem: String) -> void:
	refresh()
	changed.emit()
	if not problem.is_empty():
		push_warning("the setting can't be saved: " + problem)
