class_name SettingsTab
extends ScrollContainer
## The menu's Settings tab (#362, once #355's settings menu): the player's settings (#161), in
## submenus (#1314). It opens on a list of them; each shows its own rows, one per setting with its
## name and what it's on now, "Auto (…)" while Auto picks it, and buttons to step to the previous
## or next choice or to hand it back to Auto, and a Back button (or `ui_cancel`, a controller's B)
## back to the list. The settings' owners (Graphics, and those of the slices after this one, which
## add their own rows with `add_auto_row`, #1614) know each setting's choices and keep the player's;
## the tab only shows them and passes the player's picks on. It says everything in words, never by
## color alone (#68). It scrolls when the
## screen is too short for every row. Its layout lives in its scene, settings_tab.tscn (#437): the
## rows sit in the middle of the tab, as wide as `fit` makes them. Below the list of submenus, a
## button opens the README (#1312), with its download links.

## After a pick changed a setting, so what follows it (the menu's pause) follows at once.
signal changed

## The buttons that step a setting back and on: their icons (#584); add_row gives their words on
## hover.
const PREVIOUS_ICON: String = "icon_plain_arrow_left"
const NEXT_ICON: String = "icon_plain_arrow_right"
## The submenus, in the order the list shows them, by their English names, which their nodes keep
## too; _ready names them in the player's language. The difficulty's and the world's rows, the
## world's own settings (#1315, #1316), come from the menu (`add_row`).
const DIFFICULTY: String = "Difficulty"
const WORLD: String = "World"
const GRAPHICS: String = "Graphics"
const INTERFACE: String = "Interface"
const GAME: String = "Game"
## The list of submenus, as `open_submenu` names it while none is open.
const LIST: String = ""
## The README's downloads, where every build can be fetched (#1312).
const README_URL: String = "https://github.com/Coarisfinia/khovax#download"

## Whose settings the graphics rows show; it keeps every setting's choice (Settings' one owner).
var graphics: Graphics
## What each setting's row says it's on, by the setting's name. Kept here so tests can read it.
var shown: Dictionary[String, String] = {}
## What opens a link in the system's browser (a new tab on the web); tests swap it so none opens.
var open_link: Callable = OS.shell_open
## The button in the list that opens the README.
var readme_button: Button
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
	var titles: Dictionary[String, String] = submenu_titles()
	for submenu: String in titles:
		_add_submenu(submenu, titles[submenu])
	readme_button = MenuWidgets.button(readme_text(), open_readme)
	_list.add_child(readme_button)
	if graphics != null:
		add_auto_row(
			GRAPHICS,
			Graphics.ANTI_ALIASING,
			tr("Anti-aliasing"),
			graphics.anti_aliasing_label,
			graphics.step_anti_aliasing,
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


## The menu's title for this tab (#1677): a literal tr(), so the translation template has it; the
## node keeps its English name, which the tests find it by.
func tab_title() -> String:
	return tr("Settings")


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


## Each submenu's title in the player's language, by its name, in the order the list shows them.
func submenu_titles() -> Dictionary[String, String]:
	return {
		DIFFICULTY: tr("Difficulty"),
		WORLD: tr("World"),
		GRAPHICS: tr("Graphics"),
		INTERFACE: tr("Interface"),
		GAME: tr("Game"),
	}


## What the button that opens the README says.
func readme_text() -> String:
	return tr("Downloads and guide (README)")


## Opens the README's downloads, as its button does.
func open_readme() -> void:
	var problem: int = open_link.call(README_URL)
	if problem != OK:
		push_warning("the README can't be opened: " + error_string(problem))


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


## A submenu named `submenu`, hidden until it's opened: a Back button and its `title` at its top,
## and a button in the list, saying its title, that opens it.
func _add_submenu(submenu: String, title_text: String) -> void:
	var opens: Button = MenuWidgets.button(title_text, open.bind(submenu))
	opens.name = submenu
	_list.add_child(opens)
	_openers[submenu] = opens
	var box: VBoxContainer = VBoxContainer.new()
	box.name = submenu
	box.visible = false
	box.add_theme_constant_override("separation", _rows.get_theme_constant("separation"))
	var top: HBoxContainer = HBoxContainer.new()
	var leave: Button = MenuWidgets.button(tr("Back"), back)
	leave.icon = ResourcePacks.texture(PREVIOUS_ICON)
	# A controller's B goes back too (_unhandled_input), and the button shows it.
	var _glyph: ActionGlyph = ActionGlyph.badge(leave, &"ui_cancel")
	top.add_child(_named(leave, "Back"))
	var title: Label = MenuWidgets.label(title_text)
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
## `stepper` steps it with (back and on) and one back to Auto. The menu and the slices after this
## one add theirs this way once the tab is ready (#1614).
func add_auto_row(
		submenu: String,
		setting: String,
		title: String,
		label: Callable,
		stepper: Callable,
) -> void:
	var row: HBoxContainer = add_row(submenu, setting, title, label, stepper)
	row.add_child(_named(MenuWidgets.button(tr("Auto"), choose_auto.bind(setting)), "Auto"))


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
	rows.add_child(MenuWidgets.label(title))
	var row: HBoxContainer = HBoxContainer.new()
	var value: Label = MenuWidgets.label("")
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value)
	_values[setting] = value
	var previous: Button = MenuWidgets.icon_button(
		ResourcePacks.texture(PREVIOUS_ICON),
		tr("Previous choice"),
		step.bind(setting, -1),
	)
	row.add_child(_named(previous, "Previous"))
	var next: Button = MenuWidgets.icon_button(
		ResourcePacks.texture(NEXT_ICON),
		tr("Next choice"),
		step.bind(setting, 1),
	)
	row.add_child(_named(next, "Next"))
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
