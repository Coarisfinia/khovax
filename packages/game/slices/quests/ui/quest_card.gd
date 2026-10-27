class_name QuestCard
extends PanelContainer
## A quest's card (#340): its name (and its path mark in words, #471) above what its step asks,
## both wrapping, with the instance the step counts in as a pill between them (QuestPill, #794), in
## ink on a card. The quest list at the side of the screen shows the followed quest's, and the
## Survey one quest's while the pointer rests on its arrow (#1298). The people and places its step
## and its pill name are links to their codex pages once `links_on` (NameLinks, #1446): the list's
## card raises `name_selected` and `name_shown` for them; the Survey's shows them as plain words.
## Its layout lives in quest_card.tscn (#437); this script keeps only what it does.

## A name in its step or its pill was selected (NameLinks): the kind of its tag and its id.
signal name_selected(kind: String, id: String)
## A name with a codex page was shown in its step or its pill: the player met it (#1174).
signal name_shown(kind: String, id: String)

## How much bigger a quest's name is than its step.
const NAME_SCALE: float = 1.15

## The step's text shown, its tags as written: it's shown anew only when it changes.
var _line: String = ""


func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.card())
	name_label().add_theme_color_override("font_color", Toon.INK)
	step_label().add_theme_color_override("default_color", Toon.INK)
	# Inert until links_on: the Survey's card takes no focus either.
	step_label().focusable = false
	var _selected: int = step_label().name_selected.connect(name_selected.emit)
	var _shown: int = step_label().name_shown.connect(name_shown.emit)
	var _picked: int = pill().name_selected.connect(name_selected.emit)
	var _met: int = pill().name_shown.connect(name_shown.emit)


## Shows `line` under its name, what the step asks, a text with text tags (#733), or nothing when
## it's "".
func show_line(line: String) -> void:
	step_label().visible = not line.is_empty()
	if line == _line:
		return
	_line = line
	step_label().show_tagged(line)


## Makes the names in its step and its pill links a mouse or a touch selects, and a controller too
## when `by_controller` (NameLinks.focusable); until then they take no clicks and no focus.
func links_on(by_controller: bool) -> void:
	step_label().mouse_filter = Control.MOUSE_FILTER_STOP
	step_label().focusable = by_controller
	step_label().show_tagged(_line)
	pill().links_on(by_controller)


## Sizes its text to `font`: its name a little bigger than its step, its pill a little smaller.
func fit(font: int) -> void:
	name_label().add_theme_font_size_override("font_size", roundi(font * NAME_SCALE))
	for sized: StringName in [&"normal_font_size", &"bold_font_size"]:
		step_label().add_theme_font_size_override(sized, font)
	pill().fit(font)


## Lays it out `width` pixels wide at once: its wrapping lines take their height from their width,
## which the container would only hand them on the next frame, so a card shown at once (the
## Survey's, SurveyQuestHover) would be as tall as one letter per line until then.
func lay_out(width: float) -> void:
	custom_minimum_size.x = width
	var inner: float = width - get_theme_stylebox("panel").get_minimum_size().x
	for line: Control in [name_label(), step_label()]:
		line.size.x = inner
		line.update_minimum_size()
	# Each one keeps its minimum size until it's told to measure again, from the lines up.
	($Lines as Control).update_minimum_size()
	update_minimum_size()
	reset_size()


## The label with the quest's name.
func name_label() -> Label:
	return $Lines/Name as Label


## The text under its name, saying what its step asks.
func step_label() -> NameLinks:
	return $Lines/Step as NameLinks


## The pill under its name, saying where its step counts.
func pill() -> QuestPill:
	return $Lines/Where as QuestPill
