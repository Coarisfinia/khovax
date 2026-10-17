class_name SurveyButtons
extends Control
## The Survey's buttons on touch screens (#352): one cycles where the Survey shows, two zoom it in
## and out. Each is one of Godot's TouchScreenButtons, which presses the same InputMap action as
## its key (`survey`, `survey_zoom_in`, `survey_zoom_out`), so SurveyChoice can't tell the two
## apart. They show only where touch input exists, in a column at the screen's edge next to the
## Survey's corner, clear of it and of the quest list at the top of the other side. A touch that
## lands on one is taken, so the touch stick doesn't start under it. Each button carries a symbol,
## never color alone (#68): a screen with a block in its corner, and a lens with a plus or a minus.

## A button's side as a share of the screen's shorter side, and never smaller than this, so it
## stays big enough to hit with a thumb on a phone.
const SIDE_SHARE: float = 0.1
const MIN_SIDE: float = 64.0
const GAP: float = 12.0
const BACKDROP_ALPHA: float = 0.7
const PRESSED_ALPHA: float = 0.95
const INK_PIXELS: float = 3.0
## The actions, in their buttons' order from the top.
const ACTIONS: Array[StringName] = [&"survey", &"survey_zoom_in", &"survey_zoom_out"]

## Where the Survey shows, so the buttons keep to its side.
@export var survey: SurveyChoice

## Whether this device has touch input; tests switch it on.
var touch: bool = DisplayServer.is_touchscreen_available()
## Each action's button.
var buttons: Dictionary[StringName, TouchScreenButton] = {}
var _side: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for action: StringName in ACTIONS:
		var button: TouchScreenButton = _button(action)
		add_child(button)
		buttons[action] = button


func _process(_delta: float) -> void:
	lay_out()


func _draw() -> void:
	for action: StringName in ACTIONS:
		var rect: Rect2 = rect_of(action)
		var alpha: float = PRESSED_ALPHA if buttons[action].is_pressed() else BACKDROP_ALPHA
		draw_rect(rect, Color(Boot.FOG, alpha))
		draw_rect(rect, Toon.INK, false, INK_PIXELS)
		if action == &"survey":
			_draw_screen(rect)
		else:
			_draw_lens(rect, action == &"survey_zoom_in")


## Lays the buttons out on the screen.
func lay_out() -> void:
	lay_out_in(get_viewport_rect().size)


## Lays the buttons out for a screen of `screen` pixels (tests lay them out for other screens than
## their own this way): a column at the edge on the Survey's side, next to its corner and a gap
## from it, below a top corner and above a bottom one. Over the whole screen, or off, they stay
## where they are for Auto's corner.
func lay_out_in(screen: Vector2) -> void:
	visible = touch
	_side = maxf(MIN_SIDE, minf(screen.x, screen.y) * SIDE_SHARE)
	var place: SurveyChoice.Place = SurveyChoice.AUTO_PLACE
	if survey != null:
		place = survey.place_shown()
	if place in [SurveyChoice.Place.OFF, SurveyChoice.Place.OVER_GAME, SurveyChoice.Place.OPAQUE]:
		place = SurveyChoice.AUTO_PLACE
	var left: bool = place == SurveyChoice.Place.TOP_LEFT or place == SurveyChoice.Place.BOTTOM_LEFT
	var x: float = SurveyChoice.MARGIN + _side / 2.0
	if not left:
		x = screen.x - x
	var beside: float = SurveyChoice.MARGIN + minf(screen.x, screen.y) * SurveyChoice.CORNER_SHARE
	var column: float = _side * ACTIONS.size() + GAP * (ACTIONS.size() - 1)
	var top: float = beside + GAP
	if place == SurveyChoice.Place.BOTTOM_LEFT or place == SurveyChoice.Place.BOTTOM_RIGHT:
		top = screen.y - beside - GAP - column
	for i: int in ACTIONS.size():
		var button: TouchScreenButton = buttons[ACTIONS[i]]
		button.position = Vector2(x, top + (_side + GAP) * i + _side / 2.0)
		(button.shape as RectangleShape2D).size = Vector2(_side, _side)
	queue_redraw()


## A new button pressing `action`, sized and placed by `lay_out_in`.
func _button(action: StringName) -> TouchScreenButton:
	var button: TouchScreenButton = TouchScreenButton.new()
	button.action = action
	button.shape = RectangleShape2D.new()
	# The buttons are hidden with this node where there is no touch input.
	button.visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
	var _taken: int = button.pressed.connect(_take_touch)
	var _redrawn: int = button.released.connect(queue_redraw)
	return button


## Where `action`'s button is on the screen.
func rect_of(action: StringName) -> Rect2:
	return Rect2(buttons[action].position - Vector2(_side, _side) / 2.0, Vector2(_side, _side))


## Keeps the touch that pressed a button from reaching the touch stick. Godot hands `_input` to
## later
## nodes first, so this node comes after the stick in the Hud and sees the touch before it does.
func _take_touch() -> void:
	get_viewport().set_input_as_handled()
	queue_redraw()


## A screen's outline with a block in its corner: where the Survey shows.
func _draw_screen(rect: Rect2) -> void:
	var frame: Rect2 = rect.grow(-rect.size.x * 0.22)
	draw_rect(frame, Toon.INK, false, INK_PIXELS)
	var block: float = frame.size.x * 0.4
	draw_rect(Rect2(frame.end.x - block, frame.position.y, block, block), Toon.INK)


## A lens with a handle and a plus (`closer`) or a minus in it: zooming in or out.
func _draw_lens(rect: Rect2, closer: bool) -> void:
	var radius: float = rect.size.x * 0.24
	var middle: Vector2 = rect.get_center() - Vector2(radius, radius) * 0.25
	draw_arc(middle, radius, 0.0, TAU, 32, Toon.INK, INK_PIXELS)
	var handle: Vector2 = Vector2.ONE.normalized()
	draw_line(middle + handle * radius, middle + handle * radius * 1.9, Toon.INK, INK_PIXELS * 2.0)
	var bar: float = radius * 0.55
	draw_line(middle - Vector2(bar, 0.0), middle + Vector2(bar, 0.0), Toon.INK, INK_PIXELS)
	if closer:
		draw_line(middle - Vector2(0.0, bar), middle + Vector2(0.0, bar), Toon.INK, INK_PIXELS)
