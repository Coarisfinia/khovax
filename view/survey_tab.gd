class_name SurveyTab
extends VBoxContainer
## The menu's Survey tab (#392): the Survey (#301) over the whole tab, so the player can look over
## what they explored while the menu is open. It's one more SurveyView reading what the Survey on
## the screen reads, so it shows the same ground (what's still in the fog stays hidden), players
## and quest targets; only its place is the tab's. Its zoom is the Survey's one zoom setting
## (SurveyChoice): while the tab shows, the zoom keys and a pinch on it (SurveyPinch) step it, and
## so do its buttons below it, which say what they do in words, never by color alone (#68).

## The Survey's choices, whose zoom the tab follows and steps, and whose Survey it reads from.
var survey: SurveyChoice
## The Survey drawn in the tab.
var view: SurveyView
## What the zoom is on now, in words.
var zoom_text: Label


func _ready() -> void:
	view = SurveyView.new()
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.bordered = true
	if survey != null and survey.view != null:
		var shown: SurveyView = survey.view
		view.driver = shown.driver
		view.keeper = shown.keeper
		view.holder = shown.holder
		view.input = shown.input
		view.neighbours = shown.neighbours
	add_child(view)
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var farther: Button = GameMenu.button("Zoom out", zoom_by.bind(-1))
	farther.name = "ZoomOut"
	row.add_child(farther)
	zoom_text = Label.new()
	zoom_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(zoom_text)
	var closer: Button = GameMenu.button("Zoom in", zoom_by.bind(1))
	closer.name = "ZoomIn"
	row.add_child(closer)
	add_child(row)


func _process(_delta: float) -> void:
	if survey != null and is_visible_in_tree():
		view.across = SurveyChoice.ZOOMS[survey.zoom_step()]
		zoom_text.text = survey.zoom_label()


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
