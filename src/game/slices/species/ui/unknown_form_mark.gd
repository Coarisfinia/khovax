class_name UnknownFormMark
extends Control
## A form that's still unknown (#1796): a question mark in a dark circle, edged like a type's
## badge (TypeBadge) so it shows on any ground. EvolutionGraphic puts it at its arrow's end.

## The circle's fill and the question mark's color.
const FILL: Color = Color("2b2833")
const MARK_COLOR: Color = Color.WHITE
## The question mark's size, as a share of the circle's side.
const MARK_SHARE: float = 0.6

## Its side, in the menu's font size, the same as the form it stands beside.
var fonts: float = TypeBadge.FONTS


func _init() -> void:
	tooltip_text = tr("Its next form is still unknown")


func _notification(what: int) -> void:
	# The menu scales its font with the screen; the mark follows it, as the labels beside it do.
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_ENTER_TREE:
		custom_minimum_size = Vector2.ONE * get_theme_default_font_size() * fonts


func _draw() -> void:
	var side: float = minf(size.x, size.y)
	var center: Vector2 = size / 2.0
	var edge: float = maxf(1.0, side * TypeBadge.EDGE_SHARE)
	var ring: float = maxf(1.0, side * TypeBadge.RING_SHARE)
	var inner: float = side / 2.0 - edge - ring
	# Before layout gives it a size, there is no room for the ring and the circle.
	if inner <= 0.0:
		return
	draw_circle(center, side / 2.0, Toon.INK, true, -1.0, true)
	draw_circle(center, side / 2.0 - edge, TypeBadge.RING_COLOR, true, -1.0, true)
	draw_circle(center, inner, FILL, true, -1.0, true)
	_draw_mark(center, side)


## Draws the question mark in the middle, at `center`, sized to the circle's `side`.
func _draw_mark(center: Vector2, side: float) -> void:
	var font: Font = get_theme_default_font()
	var font_size: int = maxi(1, roundi(side * MARK_SHARE))
	var mark: String = tr("?")
	var ascent: float = font.get_ascent(font_size)
	var height: float = ascent + font.get_descent(font_size)
	var baseline: Vector2 = Vector2(center.x - side / 2.0, center.y - height / 2.0 + ascent)
	draw_string(font, baseline, mark, HORIZONTAL_ALIGNMENT_CENTER, side, font_size, MARK_COLOR)
