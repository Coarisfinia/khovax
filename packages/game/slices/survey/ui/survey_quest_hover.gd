class_name SurveyQuestHover
extends SurveyLayer
## The card of the quest whose small grey arrow the pointer rests on, on the SurveyView it's a
## child of (#1298): the quest card the list on the side shows (QuestCard), its name, the pill
## naming where its step counts and what the step asks, next to the arrow's target wherever
## there's room on the Survey: right of it, else left, below or above, else pushed inside. A tap or
## a click on the arrow follows the quest (SurveyQuestPicker). It only reads what the Survey worked
## out and this machine's player's quests, after the Survey each frame.

## A quest's card.
const CARD: PackedScene = preload("res://slices/quests/ui/quest_card.tscn")
## The card's font size and width, in pixels and in font sizes, never wider than the Survey.
const FONT: int = 16
const WIDTH_FONTS: float = 15.0
## The room between the card and the arrow, in pixels.
const GAP: float = 4.0

## The key in SurveyView.quest_targets of the grey arrow the pointer rests on, or "".
var hovered: String = ""
## The card shown, or null while none is.
var card: QuestCard = null


## Shows the card of the arrow `hovered`, or none when it's no grey arrow the Survey shows.
func show_state() -> void:
	var survey: SurveyView = get_parent() as SurveyView
	var quests: QuestTracker = null
	if survey != null and survey.quest_keeper != null:
		quests = survey.quest_keeper.quests()
	var shown: bool = quests != null and survey.quest_targets.has(hovered)
	shown = shown and not survey.focused_quest().arrows.has(hovered)
	var step: QuestStep = null
	if shown:
		step = SurveyFocusedQuest.step_of(quests.open_steps(), hovered)
	if step == null:
		if card != null:
			card.queue_free()
			card = null
		return
	if card == null:
		card = CARD.instantiate() as QuestCard
		card.modulate.a = 1.0
		add_child(card)
		card.fit(FONT)
	card.custom_minimum_size.x = minf(FONT * WIDTH_FONTS, survey.size.x)
	var id: String = hovered.get_slice("/", 0)
	card.name_label().text = quests.book[id].shown_name()
	card.show_line(QuestListView.step_line(step, quests.progress_of(id).count))
	var where: String = step.counts_in()
	card.pill().show_instance(where, where == survey.driver.local_instance_name())
	card.reset_size()
	card.position = spot(card.size, survey.grey_arrow_box(hovered), survey.size)


## Where a card `box` big goes next to an arrow's box `arrow` on a Survey `area` big, its top left
## corner: right of it, else left of it, below or above it, the first one wholly on the Survey;
## else the first pushed inside.
static func spot(box: Vector2, arrow: Rect2, area: Vector2) -> Vector2:
	var middle: Vector2 = arrow.get_center() - box / 2.0
	var tries: Array[Vector2] = [
		Vector2(arrow.end.x + GAP, middle.y),
		Vector2(arrow.position.x - GAP - box.x, middle.y),
		Vector2(middle.x, arrow.end.y + GAP),
		Vector2(middle.x, arrow.position.y - GAP - box.y),
	]
	var view: Rect2 = Rect2(Vector2.ZERO, area)
	for corner: Vector2 in tries:
		if view.encloses(Rect2(corner, box)):
			return corner
	return tries[0].clamp(Vector2.ZERO, (area - box).max(Vector2.ZERO))
