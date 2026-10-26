class_name SurveyFocusedQuest
extends SurveyLayer
## The quest this machine's player follows on the Survey (QuestTracker.focused, #1298), over the
## SurveyView it's a child of: its arrows bright yellow, drawn above everything else the Survey
## shows (tiles, exits, the players' circles, the held marks), and above each a small card naming
## the quest, with the pill under its name naming the instance its step counts in, as the quest
## list shows it (QuestMarkerLabel, QuestPill, #1278, #794): filled while this machine's player is
## there, outlined with an arrow while elsewhere, and none while the step counts anywhere. A step
## with choices has an arrow and a label for each choice, with that choice's instance. Labels keep
## inside the Survey and clear of the players' circles (#1289) and of each other: one that would
## cover another moves up above it, one whose spot above its arrow is on a circle hangs below the
## arrow's tip instead, and one that still can't fit is left out. A Survey too small for labels,
## like one in a corner, which the quest list sits beside anyway, shows the arrows bare, and an
## arrow off the Survey has no label. The other open quests' arrows are the Survey's own, small and
## grey. It only reads what the Survey worked out and this machine's player's quests, after the
## Survey each frame.

## A quest marker's label: the quest's name and its pill.
const LABEL: PackedScene = preload("res://slices/quests/ui/quest_marker_label.tscn")
## The Survey's shorter side, in pixels, below which it shows no labels.
const MIN_SIDE: float = 400.0
## The labels' font size, as a share of the Survey's shorter side, within the sizes below.
const FONT_SHARE: float = 0.03
const MIN_FONT: int = 14
const MAX_FONT: int = 20
## The room between labels, in pixels.
const GAP: float = 2.0

## The followed quest's arrows on the Survey, by their keys in SurveyView.quest_targets: the tile
## each points at. Kept so tests can read what is drawn.
var arrows: Dictionary[String, Vector2i] = {}
## Each label shown, by the key its arrow has in SurveyView.quest_targets. Kept so tests can read
## them.
var labels: Dictionary[String, QuestMarkerLabel] = {}


func _draw() -> void:
	var survey: SurveyView = get_parent() as SurveyView
	for key: String in arrows:
		survey.draw_quest_arrow(self, survey.to_view(arrows[key]), true)


## Picks the followed quest's arrows out of those the Survey shows and labels them. Called every
## frame while it shows; tests call it directly, after the Survey's own.
func show_state() -> void:
	var survey: SurveyView = get_parent() as SurveyView
	arrows.clear()
	var targets: Dictionary[String, Vector2i] = {}
	if survey != null and survey.quest_keeper != null and survey.quest_keeper.quests() != null:
		var followed: String = survey.quest_keeper.quests().focused()
		for key: String in survey.quest_targets:
			# Its id, or its id and a choice's index after a slash.
			if key.get_slice("/", 0) == followed:
				arrows[key] = survey.quest_targets[key]
		if minf(survey.size.x, survey.size.y) >= MIN_SIDE:
			targets = _on_view(survey, arrows)
	for key: String in labels.keys():
		if not targets.has(key):
			labels[key].queue_free()
			var _dropped: bool = labels.erase(key)
	if not targets.is_empty():
		_show(survey, targets)


## The arrows of `shown` whose tips are on `survey`, by key.
static func _on_view(
	survey: SurveyView,
	shown: Dictionary[String, Vector2i],
) -> Dictionary[String, Vector2i]:
	var on_view: Dictionary[String, Vector2i] = {}
	var view: Rect2 = Rect2(Vector2.ZERO, survey.size)
	for key: String in shown:
		if view.has_point(survey.to_view(shown[key])):
			on_view[key] = shown[key]
	return on_view


## Shows a label over each arrow of `targets`, the arrows `survey` shows, by key.
func _show(survey: SurveyView, targets: Dictionary[String, Vector2i]) -> void:
	var quests: QuestTracker = survey.quest_keeper.quests()
	var steps: Dictionary[String, QuestStep] = quests.open_steps()
	var font: int = clampi(
		roundi(minf(survey.size.x, survey.size.y) * FONT_SHARE),
		MIN_FONT,
		MAX_FONT,
	)
	# The players' circles go first, so labels keep clear of them as they do of each other.
	var circles: Array[Rect2] = survey.circle_boxes()
	var placed: Array[Rect2] = []
	placed.append_array(circles)
	for key: String in targets:
		var step: QuestStep = step_of(steps, key)
		if step == null:
			continue
		var label: QuestMarkerLabel = _label(key)
		var shown_name: String = quests.book[key.get_slice("/", 0)].shown_name()
		var where: String = step.counts_in()
		label.show_quest(shown_name, where, where == survey.driver.local_instance_name())
		label.fit(font)
		label.reset_size()
		label.position = _place(label.size, survey, targets[key], circles, placed)
		label.visible = _fits(label.get_rect(), survey.size, placed)
		if label.visible:
			placed.append(label.get_rect())


## Where the label `box` big of the arrow pointing at `tile` goes on `survey`, its top left corner:
## above the arrow, or, when that's on one of the players' `circles`, below its tip if that's clear
## of what's already `placed`, or else above whatever it would cover.
static func _place(
	box: Vector2,
	survey: SurveyView,
	tile: Vector2i,
	circles: Array[Rect2],
	placed: Array[Rect2],
) -> Vector2:
	var top: Vector2 = survey.arrow_top(tile)
	if not _fits(Rect2(_above(box, top, survey.size), box), survey.size, circles):
		var below: Vector2 = survey.arrow_tip(tile) + Vector2(-box.x / 2.0, GAP)
		below = below.clamp(Vector2.ZERO, survey.size - box)
		if _fits(Rect2(below, box), survey.size, placed):
			return below
	return _spot(box, top, survey.size, placed)


## Where a label `box` big goes, its top left corner: its bottom's middle on `top`, the top of its
## arrow, moved inside a Survey `area` big, and up above each of the labels and circles already
## `placed` it would cover, as long as it stays inside.
static func _spot(box: Vector2, top: Vector2, area: Vector2, placed: Array[Rect2]) -> Vector2:
	var corner: Vector2 = _above(box, top, area)
	var moved: bool = true
	while moved:
		moved = false
		for other: Rect2 in placed:
			if other.intersects(Rect2(corner, box)) and other.position.y - GAP - box.y >= 0.0:
				corner.y = other.position.y - GAP - box.y
				moved = true
	return corner


## Where a label `box` big goes before anything moves it, its top left corner: its bottom's middle
## on `top`, the top of its arrow, moved inside a Survey `area` big.
static func _above(box: Vector2, top: Vector2, area: Vector2) -> Vector2:
	return (top - Vector2(box.x / 2.0, box.y)).clamp(Vector2.ZERO, area - box)


## Whether `box` lies inside a Survey `area` big, clear of the labels and circles already `placed`:
## a label that can't, as one too wide or crowded against the top edge, isn't shown.
static func _fits(box: Rect2, area: Vector2, placed: Array[Rect2]) -> bool:
	if not Rect2(Vector2.ZERO, area).encloses(box):
		return false
	for other: Rect2 in placed:
		if other.intersects(box):
			return false
	return true


## The step the arrow `key` points for, of the open `steps`: the quest's current step, or the
## choice its key names after a slash (QuestTargets.of); null when its quest isn't open.
static func step_of(steps: Dictionary[String, QuestStep], key: String) -> QuestStep:
	var id: String = key.get_slice("/", 0)
	if not steps.has(id):
		return null
	if key.get_slice_count("/") < 2:
		return steps[id]
	return steps[id].triggers()[key.get_slice("/", 1).to_int()]


## The label of the arrow `key`, made the first time it's asked for.
func _label(key: String) -> QuestMarkerLabel:
	if not labels.has(key):
		var label: QuestMarkerLabel = LABEL.instantiate() as QuestMarkerLabel
		add_child(label)
		labels[key] = label
	return labels[key]
