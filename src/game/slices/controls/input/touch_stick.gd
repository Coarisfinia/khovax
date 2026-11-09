class_name TouchStick
extends Control
## A floating virtual stick for touch screens: it appears where a finger touches down, and
## dragging away from that point steers. It presses the same movement actions as the keyboard, with
## the drag's strength, so the mover can't tell the two apart. Lifting the finger releases them.
## Only the first finger steers; the stick is drawn only while it is held, and nothing on screen
## moves with it, which keeps it calm for motion sickness.

## Drag distance, in pixels, for full strength.
const RADIUS: float = 80.0
const BASE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.18)
const KNOB_COLOR: Color = Color(1.0, 1.0, 1.0, 0.45)

## The finger that steers, or -1 when none does.
var _finger: int = -1
var _origin: Vector2 = Vector2.ZERO
## Screen-space steering, x right and y up, at most length 1.
var _steer: Vector2 = Vector2.ZERO
## The movement actions the stick itself is pressing.
var _own: Array[String] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		_on_touch(touch)
		return
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag != null and drag.index == _finger:
		_steer_toward(drag.position)


func _draw() -> void:
	if not is_held():
		return
	draw_circle(_origin, RADIUS, BASE_COLOR)
	draw_circle(_origin + Vector2(_steer.x, -_steer.y) * RADIUS, RADIUS * 0.4, KNOB_COLOR)


func is_held() -> bool:
	return _finger >= 0


func steering() -> Vector2:
	return _steer


## Lets go of the steering finger as if it was lifted, e.g. when a menu opens over the stick
## (GameMenu, #362).
func let_go() -> void:
	if is_held():
		_finger = -1
		_steer_toward(_origin)


func _on_touch(touch: InputEventScreenTouch) -> void:
	# A touch the system cancels (e.g. for a gesture) ends like a lifted finger.
	var down: bool = touch.pressed and not touch.canceled
	if down and not is_held():
		_finger = touch.index
		_origin = touch.position
		_steer_toward(touch.position)
	elif not down and touch.index == _finger:
		let_go()


func _steer_toward(point: Vector2) -> void:
	var offset: Vector2 = (point - _origin) / RADIUS
	# Screen y grows downwards; steering y points up, like the movement actions.
	_steer = Vector2(offset.x, -offset.y).limit_length(1.0)
	_press("move_right", "move_left", _steer.x)
	_press("move_up", "move_down", _steer.y)
	queue_redraw()


## Presses one of two opposite actions with the axis value's strength. Only actions the stick
## pressed itself are released, so a key held at the same time stays held.
func _press(positive: String, negative: String, value: float) -> void:
	_release_own(positive)
	_release_own(negative)
	if value > 0.0:
		_press_own(positive, value)
	elif value < 0.0:
		_press_own(negative, -value)


func _press_own(action: String, strength: float) -> void:
	Input.action_press(action, strength)
	if not _own.has(action):
		_own.append(action)


func _release_own(action: String) -> void:
	if _own.has(action):
		Input.action_release(action)
		_own.erase(action)
