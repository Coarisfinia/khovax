class_name ActionButton
extends Control
## A touch button for an action a key presses too (#429): one of Godot's TouchScreenButtons, which
## presses the same InputMap action, so the game can't tell the two apart. Every action button
## follows the owner's ground rule (#429): it always shows its item's or attack's icon, with its
## charges or its cooldown, and never vanishes when empty or cooling down; it shows 0, or a
## cooldown circle with the seconds left. One it can't be used on right now is drawn faded, never
## hidden. It shows only where touch input exists, and a touch that lands on it is taken, so the
## touch stick doesn't start under it. Subclasses draw the icon and say the numbers.

## A button's side as a share of the screen's shorter side, never smaller than MIN_SIDE.
## How far the icon sits in from the button's edges, as a share of its side.
const ICON_INSET: float = 0.2
const SIDE_SHARE: float = 0.12
const MIN_SIDE: float = 72.0
const MARGIN: float = 16.0
const GAP: float = 12.0
const BACKDROP_ALPHA: float = 0.7
const PRESSED_ALPHA: float = 0.95
## How a button that can't be used right now is drawn: faded, never hidden.
const UNUSABLE_ALPHA: float = 0.45
const INK_PIXELS: float = 3.0

## The InputMap action the button presses.
@export var action: StringName = &""
## Its place in the column at the bottom right, counted from the bottom.
@export var column_index: int = 0

## Whether this device has touch input; tests switch it on.
## The item's or attack's icon (#459): a white shape, drawn in ink.
var icon: Texture2D
var touch: bool = DisplayServer.is_touchscreen_available()
## The button Godot presses the action with.
var button: TouchScreenButton
var _side: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	button = TouchScreenButton.new()
	button.action = action
	button.shape = RectangleShape2D.new()
	# Hidden with this node where there is no touch input.
	button.visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
	var _taken: int = button.pressed.connect(_take_touch)
	var _redrawn: int = button.released.connect(queue_redraw)
	add_child(button)


func _process(_delta: float) -> void:
	lay_out_in(get_viewport_rect().size)


func _draw() -> void:
	# Not laid out yet: nothing to draw, and a font size of 0 would fail.
	if _side <= 0.0:
		return
	var area: Rect2 = rect()
	var faded: float = 1.0 if usable() else UNUSABLE_ALPHA
	var alpha: float = PRESSED_ALPHA if button.is_pressed() else BACKDROP_ALPHA
	draw_rect(area, Color(Boot.FOG, alpha * faded))
	var ink: Color = Color(Toon.INK, faded)
	draw_rect(area, ink, false, INK_PIXELS)
	_draw_icon(area, ink)
	_draw_numbers(area, ink)


## The cooldown circle, while one runs, and the number in the corner.
func _draw_numbers(area: Rect2, ink: Color) -> void:
	var left: float = cooldown_share()
	if left > 0.0:
		var radius: float = area.size.x * 0.42
		var turned: float = -PI / 2.0 + TAU * left
		draw_arc(area.get_center(), radius, -PI / 2.0, turned, 32, ink, INK_PIXELS * 2.0)
	var label: String = corner_text()
	if not label.is_empty():
		var at: Vector2 = area.end - Vector2(area.size.x * 0.32, area.size.y * 0.1)
		var font_size: int = int(area.size.x * 0.3)
		draw_string(ThemeDB.fallback_font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)


## Lays the button out for a screen of `screen` pixels: in a column at the bottom right corner.
func lay_out_in(screen: Vector2) -> void:
	visible = touch
	_side = maxf(MIN_SIDE, minf(screen.x, screen.y) * SIDE_SHARE)
	var from_bottom: float = MARGIN + _side / 2.0 + (_side + GAP) * column_index
	button.position = Vector2(screen.x - MARGIN - _side / 2.0, screen.y - from_bottom)
	(button.shape as RectangleShape2D).size = Vector2(_side, _side)
	queue_redraw()


## Where the button is on the screen.
func rect() -> Rect2:
	return Rect2(button.position - Vector2(_side, _side) / 2.0, Vector2(_side, _side))


## Draws `icon` in `area`, tinted with `ink` (its shape is white), or a dot while it has none.
func _draw_icon(area: Rect2, ink: Color) -> void:
	if icon == null:
		draw_circle(area.get_center(), area.size.x * 0.1, ink)
		return
	draw_texture_rect(icon, area.grow(-area.size.x * ICON_INSET), false, ink)


## The number in the button's corner: charges left, or the cooldown's seconds; "" for none.
func corner_text() -> String:
	return ""


## How much of the cooldown is left, from 0 (ready) to 1, drawn as a circle.
func cooldown_share() -> float:
	return 0.0


## Whether the action would do anything right now; the button is drawn faded when not.
func usable() -> bool:
	return true


## Keeps the touch that pressed the button from reaching the touch stick. Godot hands `_input` to
## later nodes first, so this node comes after the stick in the Hud and sees the touch before it
## does.
func _take_touch() -> void:
	get_viewport().set_input_as_handled()
	queue_redraw()
