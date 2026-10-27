class_name QuestPill
extends PanelContainer
## The instance a quest's current step counts in (#769), as a small pill under the quest's name
## (owner, #794), in the list at the side of the screen and on the Quests tab alike: its name, a
## size smaller than the step. While this machine's player is in that instance it's filled, as
## "here"; elsewhere it's only outlined, with an arrow pointing on, as "there": fill and shape tell
## the two apart, never color alone (#68). Hidden while the step counts anywhere. Once `links_on`, a
## place a realm draws is a link to its codex page (NameLinks, #1446), raising `name_selected`; a
## controller reaches it only in the menu (`links_on`), never on the HUD, where it stays out of the
## way while playing. Its layout lives in quest_pill.tscn (#437); this
## script keeps only what it does.

## The place in it was selected (NameLinks): TextTags.PLACE and its id.
signal name_selected(kind: String, id: String)

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
@onready var _name: NameLinks = $Row/Name


func _ready() -> void:
	_name.add_theme_color_override("default_color", Toon.INK)
	# One line as wide as the name: wrapping, it would shrink to a letter's width in its row.
	_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	# Inert until links_on: the Survey's pills take no focus either.
	_name.focusable = false
	var _drawn: int = _arrow.draw.connect(_draw_arrow)
	var _selected: int = _name.name_selected.connect(name_selected.emit)


## Shows the instance `id`, filled when `is_here`, or hides the pill when `id` is "".
func show_instance(id: String, is_here: bool) -> void:
	visible = not id.is_empty()
	if id == instance_id and is_here == here and not _name.text.is_empty():
		return
	instance_id = id
	here = is_here
	_name.show_tagged(place_tagged(id) if visible else "")
	_arrow.visible = not is_here
	add_theme_stylebox_override("panel", UiTheme.pill(is_here))


## Makes the place in it a link a mouse or a touch selects, and a controller too when
## `by_controller` (NameLinks.focusable); until then it takes no clicks and no focus.
func links_on(by_controller: bool) -> void:
	_name.mouse_filter = Control.MOUSE_FILTER_STOP
	_name.focusable = by_controller
	_name.show_tagged(place_tagged(instance_id) if visible else "")


## The place's name as the player reads it, "" while hidden. Kept so tests can read it.
func shown_name() -> String:
	return _name.get_parsed_text()


## The text naming the place, its link in it. Kept so tests can select it.
func place_links() -> NameLinks:
	return _name


## Sizes its text to a size smaller than `step_font`, the font size of the step under it.
func fit(step_font: int) -> void:
	var font: int = roundi(step_font * FONT_SCALE)
	for sized: StringName in [&"normal_font_size", &"bold_font_size"]:
		_name.add_theme_font_size_override(sized, font)
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


## The instance `id` as a text with text tags: a place's tag where a realm draws it, which has a
## codex page (TextTags.PLACE, #1175), else its player-facing name (#909, #975) in plain words, a
## proper noun needing no article ("Lumwen Hoal"). Here, not in QuestListView, whose card scene
## holds this pill: the pill naming the list would load in a cycle.
static func place_tagged(id: String) -> String:
	return TextTags.tag(TextTags.PLACE, id) if Realms.holding(id) != null else Realms.name_of(id)
