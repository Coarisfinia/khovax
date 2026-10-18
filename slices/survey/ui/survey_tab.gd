class_name SurveyTab
extends VBoxContainer
## The menu's Survey tab (#392): the Survey (#301) over the whole tab, so the player can look over
## what they explored while the menu is open. It's one more SurveyView reading what the Survey on
## the screen reads, so it shows the same ground (what's still in the fog stays hidden), players
## and quest targets; only its place is the tab's. Its zoom is the Survey's one zoom setting
## (SurveyChoice): while the tab shows, the zoom keys and a pinch on it (SurveyPinch) step it, and
## so do its buttons below it, which say what they do in words, never by color alone (#68). One
## more cycles where the Survey shows. The buttons always show here, with no cogwheel (#438): this
## tab is where a controller reaches them, since the cogwheel on the screen hides with a controller.
## Its layout lives in its scene, survey_tab.tscn (#437): this script keeps only what it does.

## The Survey's choices, whose zoom the tab follows and steps, and whose Survey it reads from.
var survey: SurveyChoice

## The Survey drawn in the tab.
@onready var view: SurveyView = $View
## What the zoom is on now, in words.
@onready var zoom_text: Label = $Row/ZoomText
## The button cycling where the Survey shows, which says where it shows now.
@onready var place_button: Button = $Row/Place


func _ready() -> void:
	# The view is ready before the tab, which is fine: it reads these first when it draws.
	view.bordered = true
	if survey != null and survey.view != null:
		var shown: SurveyView = survey.view
		view.driver = shown.driver
		view.keeper = shown.keeper
		view.holder = shown.holder
		view.input = shown.input
		view.neighbours = shown.neighbours
	var _farther: int = ($Row/ZoomOut as Button).pressed.connect(zoom_by.bind(-1))
	var _closer: int = ($Row/ZoomIn as Button).pressed.connect(zoom_by.bind(1))
	var _cycled: int = place_button.pressed.connect(cycle)


func _process(_delta: float) -> void:
	if survey != null and is_visible_in_tree():
		view.across = SurveyChoice.ZOOMS[survey.zoom_step()]
		zoom_text.text = survey.zoom_label()
		place_button.text = "Shows: " + survey.place_label()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	# The menu takes every other key while it's open; the zoom's come here first.
	if event.is_action_pressed("survey_zoom_in"):
		zoom_by(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("survey_zoom_out"):
		zoom_by(-1)
		get_viewport().set_input_as_handled()


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
