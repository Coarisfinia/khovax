class_name SurveyButtons
extends Control
## The Survey's buttons (#352): one cycles where the Survey shows, two zoom it in and out. They hide
## behind a small cogwheel over the Survey's top right corner (#438): a tap or a click on it turns
## it, eased, and shows them in a column beside it, and another one hides them again. Each is one
## of Godot's TouchScreenButtons, which presses the same InputMap action as its key (`survey`,
## `survey_zoom_in`, `survey_zoom_out`), so SurveyChoice can't tell the two apart; a mouse click
## presses the same action here. A touch or click that lands on the cogwheel or a shown button is
## taken, so neither the touch stick nor a pinch starts under it. With a controller the cogwheel
## is hidden entirely, since it can't be pointed at: controller players use the menu's Survey tab.
## Each button carries a symbol, never color alone (#68): a screen with a block in its corner, a
## lens with a plus or a minus, and the cogwheel.

## A button's side as a share of the screen's shorter side, and never smaller than this, so it
## stays big enough to hit with a thumb on a phone. The cogwheel is smaller, as a share of that.
const SIDE_SHARE: float = 0.1
const MIN_SIDE: float = 64.0
const COG_SHARE: float = 0.7
const MIN_COG: float = 48.0
## The cogwheel's gap to the Survey's edges, and the buttons' gaps to it and to each other.
const INSET: float = 4.0
const GAP: float = 12.0
const BACKDROP_ALPHA: float = 0.7
const PRESSED_ALPHA: float = 0.95
const INK_PIXELS: float = 3.0
## The actions, in their buttons' order from the cogwheel.
const ACTIONS: Array[StringName] = [&"survey", &"survey_zoom_in", &"survey_zoom_out"]
## How far the cogwheel turns on each tap, and how long that takes.
const COG_TURN: float = TAU / 4.0
const TURN_SECONDS: float = 0.35
const COG_TEETH: int = 8
## How far a controller's stick has to move to count as using the controller, past any drift.
const STICK_USED: float = 0.5

## Where the Survey shows, so the cogwheel sits on its corner.
@export var survey: SurveyChoice

## Whether the buttons show beside the cogwheel.
var open: bool = false
## Whether the player is using a controller, which hides the cogwheel; the last input decides.
var controller: bool = false
## Each action's button.
var buttons: Dictionary[StringName, TouchScreenButton] = {}
## The cogwheel's button.
var cog: TouchScreenButton
var _side: float = 0.0
var _cog_side: float = 0.0
## How far the cogwheel has turned, in taps; eased toward the number of taps.
var _turn: float = 0.0
var _turning: Tween
## The action a mouse click is pressing, or "".
var _clicked: StringName = &""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for action: StringName in ACTIONS:
		var button: TouchScreenButton = _button(action)
		add_child(button)
		buttons[action] = button
	cog = _button(&"")
	var _toggled: int = cog.pressed.connect(toggle)
	add_child(cog)


func _process(_delta: float) -> void:
	lay_out()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (
			event is InputEventJoypadMotion
			and absf((event as InputEventJoypadMotion).axis_value) >= STICK_USED
	):
		controller = true
		open = false
		return
	if event is InputEventScreenTouch:
		controller = false
	# A click is let go here, wherever it's let go, so its action never stays pressed.
	var click: InputEventMouseButton = _click_of(event)
	if click != null:
		controller = false
		if not click.pressed and not _clicked.is_empty():
			_send(_clicked, false)
			_clicked = &""
			_take_touch()


## A click lands here only when no control took it first, so the open menu over the Survey keeps
## its clicks.
func _unhandled_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = _click_of(event)
	if click != null and click.pressed and visible:
		_on_click(click)


func _draw() -> void:
	_draw_cog(cog_rect())
	if not open:
		return
	for action: StringName in ACTIONS:
		var rect: Rect2 = rect_of(action)
		var pressed: bool = buttons[action].is_pressed() or _clicked == action
		_draw_backdrop(rect, pressed)
		if action == &"survey":
			_draw_screen(rect)
		else:
			_draw_lens(rect, action == &"survey_zoom_in")


## Shows the buttons if they're hidden and hides them if they show, turning the cogwheel.
func toggle() -> void:
	open = not open
	if _turning != null:
		_turning.kill()
	_turning = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var _tweened: PropertyTweener = _turning.tween_property(
		self,
		^"_turn",
		roundf(_turn) + 1.0,
		TURN_SECONDS,
	)
	_take_touch()


## How far the cogwheel has turned, as an angle.
func cog_angle() -> float:
	return _turn * COG_TURN


## Lays the buttons out on the screen.
func lay_out() -> void:
	lay_out_in(get_viewport_rect().size)


## Lays the buttons out for a screen of `screen` pixels (tests lay them out for other screens than
## their own this way): the cogwheel over the top right of the Survey's corner, and the buttons in
## a column beside it, down from a top corner and up from a bottom one. Over the whole screen, or
## off, they stay where they are for Auto's corner.
func lay_out_in(screen: Vector2) -> void:
	visible = not controller
	var shorter: float = minf(screen.x, screen.y)
	_side = maxf(MIN_SIDE, shorter * SIDE_SHARE)
	_cog_side = maxf(MIN_COG, _side * COG_SHARE)
	var place: SurveyChoice.Place = SurveyChoice.AUTO_PLACE
	if survey != null:
		place = survey.place_shown()
	if place in [SurveyChoice.Place.OFF, SurveyChoice.Place.OVER_GAME, SurveyChoice.Place.OPAQUE]:
		place = SurveyChoice.AUTO_PLACE
	var middle: Vector2 = _cog_middle(screen, place)
	_place(cog, middle, _cog_side)
	var column: float = _side * ACTIONS.size() + GAP * (ACTIONS.size() - 1)
	# Down from the cogwheel, or up from it, but never off the screen's right edge.
	var x: float = minf(middle.x, screen.x - SurveyChoice.MARGIN - _side / 2.0)
	var first: float = middle.y + _cog_side / 2.0 + GAP
	if place == SurveyChoice.Place.BOTTOM_LEFT or place == SurveyChoice.Place.BOTTOM_RIGHT:
		first = middle.y - _cog_side / 2.0 - GAP - column
	for i: int in ACTIONS.size():
		var button: TouchScreenButton = buttons[ACTIONS[i]]
		_place(button, Vector2(x, first + (_side + GAP) * i + _side / 2.0), _side)
		# A hidden TouchScreenButton takes no touches, so the Survey under it can be pinched.
		button.visible = open
	queue_redraw()


## The cogwheel's middle on a screen of `screen` pixels: just inside the top right of the Survey
## in its corner `place`.
func _cog_middle(screen: Vector2, place: SurveyChoice.Place) -> Vector2:
	var corner: float = minf(screen.x, screen.y) * SurveyChoice.CORNER_SHARE
	var left: bool = place == SurveyChoice.Place.TOP_LEFT or place == SurveyChoice.Place.BOTTOM_LEFT
	var top: bool = place == SurveyChoice.Place.TOP_LEFT or place == SurveyChoice.Place.TOP_RIGHT
	var right: float = SurveyChoice.MARGIN + corner if left else screen.x - SurveyChoice.MARGIN
	var upper: float = SurveyChoice.MARGIN if top else screen.y - SurveyChoice.MARGIN - corner
	return Vector2(right - INSET - _cog_side / 2.0, upper + INSET + _cog_side / 2.0)


## Where `action`'s button is on the screen.
func rect_of(action: StringName) -> Rect2:
	return Rect2(buttons[action].position - Vector2(_side, _side) / 2.0, Vector2(_side, _side))


## Where the cogwheel is on the screen.
func cog_rect() -> Rect2:
	return Rect2(cog.position - Vector2(_cog_side, _cog_side) / 2.0, Vector2(_cog_side, _cog_side))


## A new button pressing `action` (none for the cogwheel), sized and placed by `lay_out_in`.
func _button(action: StringName) -> TouchScreenButton:
	var button: TouchScreenButton = TouchScreenButton.new()
	button.action = action
	button.shape = RectangleShape2D.new()
	# The buttons are hidden with this node while a controller is used.
	button.visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
	var _taken: int = button.pressed.connect(_take_touch)
	var _redrawn: int = button.released.connect(queue_redraw)
	return button


func _place(button: TouchScreenButton, middle: Vector2, side: float) -> void:
	button.position = middle
	(button.shape as RectangleShape2D).size = Vector2(side, side)


## `event` as a left click of a real mouse, or null. A touch reaches the buttons as itself, so the
## click Godot makes up from it is skipped.
func _click_of(event: InputEvent) -> InputEventMouseButton:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or click.device == InputEvent.DEVICE_ID_EMULATION:
		return null
	return click if click.button_index == MOUSE_BUTTON_LEFT else null


## A left click on the cogwheel turns it; on a shown button it presses the button's action until
## it's let go, as a touch does. Either is taken, so nothing under it sees it.
func _on_click(click: InputEventMouseButton) -> void:
	if cog_rect().has_point(click.position):
		toggle()
		return
	for action: StringName in ACTIONS:
		if open and rect_of(action).has_point(click.position):
			_clicked = action
			_send(action, true)
			_take_touch()
			return


## Presses or releases `action`, as its button would.
func _send(action: StringName, pressed: bool) -> void:
	var press: InputEventAction = InputEventAction.new()
	press.action = action
	press.pressed = pressed
	Input.parse_input_event(press)


## Keeps the touch that pressed a button from reaching the touch stick or the pinch. Godot hands
## `_input` to later nodes first, so this node comes after both in the Hud and sees the touch
## before they do.
func _take_touch() -> void:
	get_viewport().set_input_as_handled()
	queue_redraw()


func _draw_backdrop(rect: Rect2, pressed: bool) -> void:
	draw_rect(rect, Color(Boot.FOG, PRESSED_ALPHA if pressed else BACKDROP_ALPHA))
	draw_rect(rect, Toon.INK, false, INK_PIXELS)


## The cogwheel, turned as far as it has: a wheel with teeth and a hole in its middle.
func _draw_cog(rect: Rect2) -> void:
	_draw_backdrop(rect, cog.is_pressed())
	var wheel: float = rect.size.x * 0.24
	var tooth: Vector2 = Vector2(wheel * 0.5, wheel * 0.45)
	for i: int in COG_TEETH:
		draw_set_transform(rect.get_center(), cog_angle() + TAU * i / COG_TEETH)
		draw_rect(Rect2(-tooth.x / 2.0, -wheel - tooth.y, tooth.x, tooth.y + wheel), Toon.INK)
	draw_set_transform(Vector2.ZERO)
	draw_circle(rect.get_center(), wheel, Toon.INK)
	draw_circle(rect.get_center(), wheel * 0.4, Boot.FOG)


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
