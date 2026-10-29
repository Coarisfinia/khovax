class_name SurveyQuestPicker
extends Node
## Picks a quest to follow on the Survey (#1298): a tap or a click on a small grey arrow, a quest
## not followed (SurveyView.quest_at), makes this machine's player follow that quest
## (SurveyQuests.follow), and the pointer resting on one shows its quest card
## (SurveyQuestHover).
## It works on the Survey wherever it shows, and while the menu is open (GameMenu, #362) only on
## its Survey tab's (#392), which SurveyPinch knows. A click picks as it's pressed. A tap picks as
## its finger lifts, alone and where it went down, so a pinch that starts on an arrow still zooms
## (SurveyPinch); it lets every touch through, so a corner Survey still keeps the touch stick from
## starting under it. Like a menu's button, it's a choice kept in the profile, not a command to the
## game, so it goes to the quests' keeper rather than the controls. Godot hands `_input` to later
## nodes first, so this node comes after the stick and the pinch in the Hud and sees a touch first.
## A controller picks in the Quests tab instead (QuestsTab).

## How far a finger may move between going down and lifting for a tap, in pixels.
const TAP_SLOP: float = 12.0

## Where the Survey shows.
@export var survey: SurveyChoice
## Which Survey takes touches while the menu is open.
@export var pinch: SurveyPinch

## The fingers down, by index, each where it went down.
var _fingers: Dictionary[int, Vector2] = {}
## Whether the finger down is still a tap: alone, and near where it went down.
var _tapping: bool = false


func _input(event: InputEvent) -> void:
	var moved: InputEventMouseMotion = event as InputEventMouseMotion
	if moved != null:
		_hover(moved.position)
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	# Godot also reports a touch as a click (emulate_mouse_from_touch): the touch picks on its own.
	var own: bool = click != null and click.device != InputEvent.DEVICE_ID_EMULATION
	if own and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		if pick(click.position):
			get_viewport().set_input_as_handled()
		return
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag != null and _fingers.has(drag.index):
		_tapping = _tapping and drag.position.distance_to(_fingers[drag.index]) <= TAP_SLOP
		return
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		_on_touch(touch)


## Keeps track of the fingers, and picks on a tap's finger lifting.
func _on_touch(touch: InputEventScreenTouch) -> void:
	if touch.pressed and not touch.canceled:
		_fingers[touch.index] = touch.position
		_tapping = _fingers.size() == 1
		return
	var tap: bool = _tapping and not touch.canceled and _fingers.has(touch.index)
	tap = tap and touch.position.distance_to(_fingers[touch.index]) <= TAP_SLOP
	var _lifted: bool = _fingers.erase(touch.index)
	_tapping = false
	if tap:
		var _picked: bool = pick(touch.position)


## Follows the quest whose grey arrow is at `at` on the screen, on the Survey that takes it; returns
## whether there was one.
func pick(at: Vector2) -> bool:
	var view: SurveyView = _view_at(at)
	var key: String = view.quest_at(_on(view, at)) if view != null else ""
	if key.is_empty():
		return false
	view.quests.follow(key.get_slice("/", 0))
	return true


## Shows the card of the quest whose grey arrow the pointer at `at` on the screen rests on, on the
## Survey that takes it, and none on the others.
func _hover(at: Vector2) -> void:
	var view: SurveyView = _view_at(at)
	for each: SurveyView in _views():
		for layer: SurveyLayer in each.layers():
			layer.point(_on(each, at) if each == view else Vector2.INF)


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
