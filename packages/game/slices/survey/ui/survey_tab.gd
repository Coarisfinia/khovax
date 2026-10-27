class_name SurveyTab
extends VBoxContainer
## The menu's Survey tab (#392): the Survey (#301) over the whole tab, so the player can look over
## what they explored while the menu is open. It's one more SurveyView reading what the Survey on
## the screen reads, so it shows the same ground (what's still in the fog stays hidden), players and
## quest targets; only its place is the tab's. Its zoom is the Survey's one zoom setting
## (SurveyChoice): while the tab shows, the zoom keys, a controller's triggers (#779) and a pinch on
## it (SurveyPinch) step it, and so do its buttons below it, which say what they do in words, never
## by color alone (#68). One more cycles where the Survey shows. Above them, a line says which
## faction holds the instance the player is in, by its symbol and name (#637), or that none does;
## the name is a link to its codex page (NameLinks, #1447), whose `name_selected` and `name_shown`
## the tab raises as its own.
## The buttons always show here, with no cogwheel (#438): this tab is where a controller reaches
## them, since the cogwheel on the screen hides with a controller. Each shows the glyph of the key
## or controller button that presses it too (ActionGlyph, #1192): - or the left trigger, = or the
## right one, and Tab or Back, and on touch the zoom buttons the pinch (#1221); they share the
## row's width, so their words leave the glyph room.
## Its layout lives in its scene, survey_tab.tscn (#437): this script keeps only what it does.

## The faction's name in the line saying who holds the instance was selected (NameLinks).
signal name_selected(kind: String, id: String)
## The line showed a faction's name: the player met it (#1174).
signal name_shown(kind: String, id: String)

## The Survey's choices, whose zoom the tab follows and steps, and whose Survey it reads from.
var survey: SurveyChoice
## Who holds the instance the player is in, as the line shows it now: a text with text tags.
var held: String = ""

## The Survey drawn in the tab.
@onready var view: SurveyView = $View
## What the zoom is on now, in words.
@onready var zoom_text: Label = $Row/ZoomText
## Who holds the instance the player is in, in words, the holder's name a link.
@onready var held_text: NameLinks = $Held
## The button cycling where the Survey shows, which says where it shows now.
@onready var place_button: Button = $Row/Place


func _ready() -> void:
	# The view is ready before the tab, which is fine: it reads these first when it draws.
	view.bordered = true
	if survey != null and survey.view != null:
		var shown: SurveyView = survey.view
		view.driver = shown.driver
		view.keeper = shown.keeper
		view.quest_keeper = shown.quest_keeper
		view.input = shown.input
		view.neighbours = shown.neighbours
	var farther: Button = $Row/ZoomOut as Button
	var closer: Button = $Row/ZoomIn as Button
	var _farther: int = farther.pressed.connect(zoom_by.bind(-1))
	var _closer: int = closer.pressed.connect(zoom_by.bind(1))
	var _cycled: int = place_button.pressed.connect(cycle)
	var _out_glyph: ActionGlyph = ActionGlyph.badge(farther, &"survey_zoom_out")
	var _in_glyph: ActionGlyph = ActionGlyph.badge(closer, &"survey_zoom_in")
	var _place_glyph: ActionGlyph = ActionGlyph.badge(place_button, &"survey")
	_relay_held_names()


func _process(_delta: float) -> void:
	if survey != null and is_visible_in_tree():
		view.across = SurveyChoice.ZOOMS[survey.zoom_step()]
		zoom_text.text = survey.zoom_label()
		# Shown anew only when it changes: showing resets the controller's chosen name.
		var now_held: String = view.held_marks().here_text()
		if now_held != held:
			held = now_held
			held_text.show_tagged(held)
		place_button.text = "Shows: " + survey.place_label()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	# The menu takes every other key while it's open; the zoom's come here first.
	if _pressed(event, &"survey_zoom_in"):
		zoom_by(1)
		get_viewport().set_input_as_handled()
	elif _pressed(event, &"survey_zoom_out"):
		zoom_by(-1)
		get_viewport().set_input_as_handled()


## Raises the names the holder's line selects and shows as the tab's own.
func _relay_held_names() -> void:
	var _selected: int = held_text.name_selected.connect(name_selected.emit)
	var _met: int = held_text.name_shown.connect(name_shown.emit)


## Whether `event` newly presses `action`. A controller's trigger (#779) sends motion events all the
## while it's held, each pressing the action again: only the one that pulled it past the dead zone
## counts, so a pull zooms one step.
static func _pressed(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action):
		return false
	return not event is InputEventJoypadMotion or Input.is_action_just_pressed_by_event(
		action,
		event,
	)


## Steps the Survey's zoom `steps` closer (fewer is farther), as its buttons do, and keeps it.
func zoom_by(steps: int) -> void:
	if survey == null:
		return
	var problem: String = survey.zoom_by(steps)
	if not problem.is_empty():
		push_warning("the Survey's setting can't be saved: " + problem)


## Shows the Survey on the screen in its next place, as its button there does, and keeps it.
func cycle() -> void:
	if survey == null:
		return
	var problem: String = survey.cycle()
	if not problem.is_empty():
		push_warning("the Survey's setting can't be saved: " + problem)
