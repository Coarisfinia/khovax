class_name QuestPill
extends PanelContainer
## The instance a quest's current step counts in (#769), as a small pill under the quest's name
## (owner, #794), in the list at the side of the screen and on the Quests tab alike: its name, a
## size smaller than the step. While this machine's player is in that instance it's filled, as
## "here"; elsewhere it's only outlined, with an arrow pointing on, as "there": fill and shape tell
## the two apart, never color alone (#68). Hidden while the step counts anywhere. Its layout lives
## in quest_pill.tscn (#437); this script keeps only what it does.

## How big its text is next to the step's.
const FONT_SCALE: float = 0.85
## How tall the arrow is, as a share of its text's size, and how wide next to its height.
const ARROW_HEIGHT: float = 0.6
const ARROW_WIDTH: float = 0.7

## The instance it shows, by blueprint name, or "" while it's hidden. Kept so tests can read it.
var instance_id: String = ""
## Whether this machine's player is in that instance.
var here: bool = false

@onready var _arrow: Control = $Row/Arrow
@onready var _name: Label = $Row/Name


func _ready() -> void:
	_name.add_theme_color_override("font_color", Toon.INK)
	var _drawn: int = _arrow.draw.connect(_draw_arrow)


## Shows the instance `id`, filled when `is_here`, or hides the pill when `id` is "".
func show_instance(id: String, is_here: bool) -> void:
	visible = not id.is_empty()
	if id == instance_id and is_here == here and _name.text != "":
		return
	instance_id = id
	here = is_here
	_name.text = TextTags.shown(TextTags.tag(TextTags.PLACE, id)) if visible else ""
	_arrow.visible = not is_here
	add_theme_stylebox_override("panel", UiTheme.pill(is_here))


## Sizes its text to a size smaller than `step_font`, the font size of the step under it.
func fit(step_font: int) -> void:
	var font: int = roundi(step_font * FONT_SCALE)
	_name.add_theme_font_size_override("font_size", font)
	_arrow.custom_minimum_size = Vector2(font * ARROW_HEIGHT * ARROW_WIDTH, font * ARROW_HEIGHT)


## Draws the arrow pointing on, in ink: a triangle filling the arrow's box.
func _draw_arrow() -> void:
	var box: Vector2 = _arrow.size
	var top: float = (box.y - _arrow.custom_minimum_size.y) / 2.0
	var bottom: float = top + _arrow.custom_minimum_size.y
	var corners: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, top),
		Vector2(box.x, (top + bottom) / 2.0),
		Vector2(0.0, bottom),
	])
	_arrow.draw_colored_polygon(corners, Toon.INK)
