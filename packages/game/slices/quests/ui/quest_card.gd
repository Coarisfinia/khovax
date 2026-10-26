class_name QuestCard
extends PanelContainer
## A quest's card (#340): its name (and its path mark in words, #471) above what its step asks,
## both wrapping, with the instance the step counts in as a pill between them (QuestPill, #794), in
## ink on a card. The quest list at the side of the screen shows the followed quest's, and the
## Survey one quest's while the pointer rests on its arrow (#1298). Its layout lives in
## quest_card.tscn (#437); this script keeps only what it does.

## How much bigger a quest's name is than its step.
const NAME_SCALE: float = 1.15


func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.card())
	name_label().add_theme_color_override("font_color", Toon.INK)
	step_label().add_theme_color_override("font_color", Toon.INK)


## Shows `line` under its name, what the step asks, or nothing when it's "".
func show_line(line: String) -> void:
	step_label().text = line
	step_label().visible = not line.is_empty()


## Sizes its text to `font`: its name a little bigger than its step, its pill a little smaller.
func fit(font: int) -> void:
	name_label().add_theme_font_size_override("font_size", roundi(font * NAME_SCALE))
	step_label().add_theme_font_size_override("font_size", font)
	pill().fit(font)


## The label with the quest's name.
func name_label() -> Label:
	return $Lines/Name as Label


## The label under its name, saying what its step asks.
func step_label() -> Label:
	return $Lines/Step as Label


## The pill under its name, saying where its step counts.
func pill() -> QuestPill:
	return $Lines/Where as QuestPill
