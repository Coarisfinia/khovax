class_name QuestMarkerLabel
extends PanelContainer
## A quest marker's label on the Survey (#1278): the quest's name on a small card, with the pill
## under it naming the instance its step counts in (QuestPill, #794), as the quest list shows them,
## so both look alike. Its layout lives in quest_marker_label.tscn (#437); this script keeps only
## what it does.

## How much room the card leaves round its lines.
const MARGIN: float = 4.0

## The quest's name it shows. Kept so tests can read it.
var quest_name: String = ""

@onready var _name: Label = $Lines/Name


func _ready() -> void:
	var style: StyleBoxFlat = UiTheme.card()
	style.set_content_margin_all(MARGIN)
	add_theme_stylebox_override("panel", style)
	_name.add_theme_color_override("font_color", Toon.INK)


## Shows the quest named `shown_name`, its step counting in the instance `where` ("" for anywhere),
## filled when `here`.
func show_quest(shown_name: String, where: String, here: bool) -> void:
	if shown_name != quest_name:
		quest_name = shown_name
		_name.text = shown_name
	pill().show_instance(where, here)


## Sizes its name to `font`, and its pill a size smaller.
func fit(font: int) -> void:
	_name.add_theme_font_size_override("font_size", font)
	pill().fit(font)


## The pill under its name.
func pill() -> QuestPill:
	return $Lines/Where as QuestPill
