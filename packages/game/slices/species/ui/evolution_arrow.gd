class_name EvolutionArrow
extends Control
## The long arrow pointing from a monster's form to the one it ascends into (EvolutionGraphic,
## #1796): an ink shaft with a head at its right end, as long as the item above it is wide.

## Its height, and its shaft's thickness, in the menu's font size.
const HEIGHT_FONTS: float = 0.8
const SHAFT_FONTS: float = 0.18


func _notification(what: int) -> void:
	# The menu scales its font with the screen; the arrow follows it, as the labels beside it do.
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_ENTER_TREE:
		custom_minimum_size.y = get_theme_default_font_size() * HEIGHT_FONTS


func _draw() -> void:
	var font_size: float = get_theme_default_font_size()
	var middle: float = size.y / 2.0
	var head: float = size.y
	# Before layout gives it a size, there is no room for the shaft beside the head.
	if size.x <= head:
		return
	var shaft: float = maxf(1.0, font_size * SHAFT_FONTS)
	draw_line(Vector2(0.0, middle), Vector2(size.x - head, middle), Toon.INK, shaft, true)
	var tip: PackedVector2Array = [
		Vector2(size.x - head, 0.0),
		Vector2(size.x, middle),
		Vector2(size.x - head, size.y),
	]
	draw_colored_polygon(tip, Toon.INK)
