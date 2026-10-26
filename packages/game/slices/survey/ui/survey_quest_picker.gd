class_name SurveyQuestPicker
extends Node
## Picks a quest to follow on the Survey (#1298): a tap or a click on a small grey arrow, a quest
## not followed (SurveyView.quest_at), makes this machine's player follow that quest
## (QuestKeeper.follow), and the pointer resting on one shows its quest card (SurveyQuestHover).
## It works on the Survey wherever it shows, and while the menu is open (GameMenu, #362) only on
## its Survey tab's (#392), which SurveyPinch knows. A tap on an arrow is taken, so the touch stick
## never starts from it; every other touch goes on as before. Godot hands `_input` to later nodes
## first, so this node comes after the stick in the Hud and sees a touch before it does. A
## controller picks in the Quests tab instead (QuestsTab).

## Where the Survey shows.
@export var survey: SurveyChoice
## Which Survey takes touches while the menu is open.
@export var pinch: SurveyPinch


func _input(event: InputEvent) -> void:
	var moved: InputEventMouseMotion = event as InputEventMouseMotion
	if moved != null:
		_hover(moved.position)
		return
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	var click: InputEventMouseButton = event as InputEventMouseButton
	var tapped: bool = touch != null and touch.pressed and not touch.canceled
	var clicked: bool = click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT
	if tapped or clicked:
		var at: Vector2 = touch.position if tapped else click.position
		if pick(at):
			get_viewport().set_input_as_handled()


## Follows the quest whose grey arrow is at `at` on the screen, on the Survey that takes it; returns
## whether there was one.
func pick(at: Vector2) -> bool:
	var view: SurveyView = _view_at(at)
	var key: String = view.quest_at(_on(view, at)) if view != null else ""
	if key.is_empty() or view.quest_keeper == null:
		return false
	view.quest_keeper.follow(key.get_slice("/", 0))
	return true


## Shows the card of the quest whose grey arrow the pointer at `at` on the screen rests on, on the
## Survey that takes it, and none on the others.
func _hover(at: Vector2) -> void:
	var view: SurveyView = _view_at(at)
	for each: SurveyView in _views():
		each.quest_hover().pointer = _on(each, at) if each == view else Vector2.INF


## The Surveys the pointer can rest on: the one in the menu's Survey tab while the menu is open,
## and the one on the screen.
func _views() -> Array[SurveyView]:
	var views: Array[SurveyView] = []
	if pinch != null and pinch.in_menu != null:
		views.append(pinch.in_menu)
	if survey != null and survey.view != null:
		views.append(survey.view)
	return views


## The Survey at `at` on the screen that takes it: the menu's while the menu is open, else the
## screen's while it shows; null when `at` isn't on it.
func _view_at(at: Vector2) -> SurveyView:
	var views: Array[SurveyView] = _views()
	if views.is_empty():
		return null
	var view: SurveyView = views[0]
	var shows: bool = view.is_visible_in_tree() and view.get_global_rect().has_point(at)
	return view if shows else null


## `at` on the screen in `view`'s own pixels.
static func _on(view: SurveyView, at: Vector2) -> Vector2:
	return view.get_global_transform().affine_inverse() * at
