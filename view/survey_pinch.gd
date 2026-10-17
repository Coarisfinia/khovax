class_name SurveyPinch
extends Node
## A pinch on the Survey zooms it in steps (#358): spreading two fingers on it presses
## `survey_zoom_in`, pinching them together `survey_zoom_out`, the same actions as the keys and
## the Survey's buttons, so SurveyChoice can't tell them apart. Godot reports a pinch as a gesture
## only on some platforms (not the web), so this follows the two fingers itself. Every touch that
## lands on a corner Survey is taken, so the touch stick never starts under it; over the whole
## screen the Survey leaves touches to the stick, and its buttons zoom it. Godot hands `_input` to
## later nodes first, so this node comes after the stick in the Hud and sees a touch before it does.

## How far apart the fingers have to move, as a share of their distance at the last step, for one
## more step: about the zoom steps' own ratio, so the Survey follows the fingers.
const STEP_RATIO: float = 1.5

## Where the Survey shows.
@export var survey: SurveyChoice

## Where each finger on the Survey is, by its index.
var _fingers: Dictionary[int, Vector2] = {}
## The two fingers' distance at the last step, or 0 while fewer than two are down.
var _spread: float = 0.0


func _input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		_on_touch(touch)
		return
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag != null and _fingers.has(drag.index):
		_fingers[drag.index] = drag.position
		_step()
		get_viewport().set_input_as_handled()


func _on_touch(touch: InputEventScreenTouch) -> void:
	# A touch the system cancels (e.g. for a gesture) ends like a lifted finger.
	var down: bool = touch.pressed and not touch.canceled
	if down and _on_survey(touch.position):
		_fingers[touch.index] = touch.position
	elif not down and _fingers.has(touch.index):
		var _lifted: bool = _fingers.erase(touch.index)
	else:
		return
	# Every finger change starts the measuring anew from the fingers down now.
	_spread = _distance()
	get_viewport().set_input_as_handled()


## Steps the zoom once the fingers have moved far enough apart or together since the last step.
func _step() -> void:
	var distance: float = _distance()
	if _spread <= 0.0 or distance <= 0.0:
		_spread = distance
		return
	if distance >= _spread * STEP_RATIO:
		_press(&"survey_zoom_in")
		_spread = distance
	elif distance * STEP_RATIO <= _spread:
		_press(&"survey_zoom_out")
		_spread = distance


## The first two fingers' distance on the Survey, or 0 while fewer than two are down.
func _distance() -> float:
	if _fingers.size() < 2:
		return 0.0
	var at: Array[Vector2] = []
	for index: int in _fingers:
		at.append(_fingers[index])
	return at[0].distance_to(at[1])


## Whether `at` is on a corner Survey that shows.
func _on_survey(at: Vector2) -> bool:
	if survey == null or survey.view == null:
		return false
	var view: SurveyView = survey.view
	return view.is_visible_in_tree() and view.bordered and view.get_global_rect().has_point(at)


## Presses and releases `action` once, as a TouchScreenButton does: its event, so SurveyChoice
## steps once, and its state, unless a key or a button holds it already, which keeps it held.
func _press(action: StringName) -> void:
	var held: bool = Input.is_action_pressed(action)
	for pressed: bool in [true, false]:
		if not held and pressed:
			Input.action_press(action)
		elif not held:
			Input.action_release(action)
		var event: InputEventAction = InputEventAction.new()
		event.action = action
		event.pressed = pressed
		get_viewport().push_input(event, true)
