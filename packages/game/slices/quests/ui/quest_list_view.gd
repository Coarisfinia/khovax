class_name QuestListView
extends Control
## The quest followed at the side of the screen (#340, #1298): a card for the open quest this
## machine's player follows (QuestTracker.focused), with its name (and its path mark in words, #471)
## and what its current step asks, and the count where the step counts up ("1/3"), with the
## instance the step counts in as a pill under its name (QuestPill, #794). The other open quests
## are in the menu's Quests tab. A quest that finishes says so and fades out, and one the player
## stops following fades out at once, while the card of the one followed next fades in under it
## and glides up into its place; nothing snaps.
## It keeps to the side of the screen the Survey's corner isn't on (#301), below the roster on
## the left (#540). Quests are told apart by their words, never by color (#68), and the text grows
## with the screen, so it stays readable on a phone. It only reads the quests.
## Its layout lives in scenes (#437): the list's node in main.tscn, each card in quest_card.tscn
## (QuestCard); this script keeps only what it does.
## The people and places its step and its pill name are links to their codex pages (NameLinks,
## #1446): a mouse click or a long press on touch selects one, raising `name_selected`. A
## controller never focuses them here (NameLinks.focusable), so the HUD stays out of its way while
## playing: it reaches them in the menu's Quests tab.
## A name shown here isn't met (CodexKeeper): the player meets it where they come across it, in the
## dialog that gave the quest or by entering the place (#1209), so a new player's book stays empty.

## A name on a card was selected (NameLinks): the kind of its tag and its id.
signal name_selected(kind: String, id: String)

## A quest's card: its name above its step, both wrapping, the pill between them, starting faded
## out.
const QUEST_CARD: PackedScene = preload("res://slices/quests/ui/quest_card.tscn")
## How quickly a card glides to its place: the share of the way left it closes per second.
const GLIDE: float = 8.0
## How long a card takes to fade in, or out once its quest is finished.
const FADE_SECONDS: float = 0.6
## How long a finished quest's card says so before it fades.
const DONE_SECONDS: float = 1.2
## The gap to the screen's edges, as the Survey keeps it, and between cards.
const MARGIN: float = SurveyChoice.MARGIN
const GAP: float = 8.0
## The text's size as a share of the screen's shorter side, and never smaller than this.
const FONT_SHARE: float = 0.028
const MIN_FONT: int = 16
## How wide a card is, in font sizes, and never more than this share of the screen's width.
const WIDTH_FONTS: float = 15.0
const MAX_WIDTH_SHARE: float = 0.42
const DONE_TEXT: String = "Done"

## Whose quests are listed: this machine's player's.
@export var keeper: QuestKeeper
## The running session, which says the instance this machine's player is in, for the pills.
@export var driver: Session
## Where the Survey shows, so the list keeps out of its corner.
@export var survey: SurveyChoice
## The roster in the top left corner (#540), which the list starts below when it's on that side.
@export var roster: RosterHud

## What each listed quest's card says under its name, by quest id: the step, or that it's done.
## Kept here so tests can read what is shown.
var shown: Dictionary[String, String] = {}
## Each listed quest's card, by quest id, while it's listed or fading out.
var cards: Dictionary[String, QuestCard] = {}
## The cards' order from the top, finished ones included until they're gone.
var order: Array[String] = []
## The quests whose cards fade out, by quest id: finished, or no longer followed. Each with the
## tween fading it, which stops when the player follows the quest again before it's gone.
var leaving: Dictionary[String, Tween] = {}
var _font_size: int = 0


func _process(delta: float) -> void:
	show_quests()
	_lay_out(1.0 - exp(-GLIDE * delta))


## Matches the card to the quest followed. Called every frame; tests call it directly.
func show_quests() -> void:
	var open: Dictionary[String, QuestStep] = {}
	var steps: Dictionary[String, QuestStep] = {}
	var quests: QuestTracker = keeper.quests() if keeper != null else null
	if quests != null:
		open = quests.open_steps()
		var followed: String = quests.focused()
		if not followed.is_empty():
			steps[followed] = open[followed]
	var here: String = driver.local_instance_name() if driver != null else ""
	for id: String in order:
		if not leaving.has(id) and not open.has(id):
			_finish(id)
		elif not leaving.has(id) and not steps.has(id):
			_fade_out(id, 0.0)
	for id: String in steps:
		if leaving.has(id):
			_come_back(id)
		var progress: QuestProgress = quests.progress.get(id)
		var line: String = step_tagged(steps[id], progress.count if progress != null else 0)
		if not cards.has(id):
			_add_card(id, quests.book[id].shown_name())
		shown[id] = TextTags.shown(line)
		cards[id].show_line(line)
		var where: String = steps[id].counts_in()
		pill(id).show_instance(where, where == here)


## What `step` asks, worded for the player, with `count` of its count where it counts up, as the
## player reads it (step_tagged).
static func step_line(step: QuestStep, count: int) -> String:
	return TextTags.shown(step_tagged(step, count))


## What `step` asks with `count`, a text with text tags (#733): the people and the places it names
## are tags, so a NameLinks shows them as links to their codex pages (#1446). A step with choices
## (#573) offers each of them, joined by "or". A new condition gets its own wording here; one
## without any shows only the count.
static func step_tagged(step: QuestStep, count: int) -> String:
	if not step.choices.is_empty():
		var ways: Array[String] = []
		for choice: QuestStep in step.choices:
			var way: String = step_tagged(choice, 0)
			ways.append(way if ways.is_empty() else way.left(1).to_lower() + way.substr(1))
		return " or ".join(ways)
	var asks: String = ""
	match step.condition:
		QuestStep.DOMINATED:
			var what: String = "a monster"
			if step.quarry.species != null:
				what = _with_article(step.quarry.species.name)
			elif not step.quarry.target.is_empty():
				what = "the " + _words(step.quarry.target)
			asks = "Dominate " + what
		QuestStep.OPENED:
			asks = "Open a chest"
		QuestStep.REACHED:
			asks = "Go to the " + _words(step.place)
		QuestStep.ENTERED:
			if step.enters_instance():
				asks = "Enter " + QuestPill.place_tagged(step.instance)
			else:
				asks = "Enter the " + _words(step.piece)
		QuestStep.ANSWERED:
			asks = _answer_line(step)
		QuestStep.OBTAINED:
			asks = "Collect " + _words(step.item)
	if step.count > 1:
		asks += ("  " if not asks.is_empty() else "") + "%d/%d" % [count, step.count]
	return asks


## What an answered `step` asks (#636): the answer's text to its dialog's speaker, by the person's
## tag (#1005) without an article (#977), or the answer's id in words when the dialogs weren't
## read with it.
static func _answer_line(step: QuestStep) -> String:
	if step.answer.text.is_empty():
		return "Answer " + _words(step.answer.id)
	var speaker: String = TextTags.tag(TextTags.PERSON, step.answer.speaker)
	return "Tell %s: \"%s\"" % [speaker, step.answer.text]


## An id (a place, a region piece, an item or a quest target) as words: they have no
## player-facing names yet.
static func _words(id: String) -> String:
	return id.replace("_", " ")


## A species' player-facing name (#351), after "a" or "an" by its first letter.
static func _with_article(species_name: String) -> String:
	return ("an " if "aeiou".contains(species_name.left(1).to_lower()) else "a ") + species_name


## A new card for quest `id`, named `quest_name`, fading in under the others.
func _add_card(id: String, quest_name: String) -> void:
	var card: QuestCard = QUEST_CARD.instantiate() as QuestCard
	card.name_label().text = quest_name
	add_child(card)
	card.links_on(false)
	var _selected: int = card.name_selected.connect(name_selected.emit)
	card.fit(maxi(MIN_FONT, _font_size))
	card.position = Vector2(0.0, _bottom())
	cards[id] = card
	order.append(id)
	_fade_in(card)


## Says quest `id` is done, fades its card out after a while, then lets the card below move up.
func _finish(id: String) -> void:
	shown[id] = DONE_TEXT
	cards[id].show_line(DONE_TEXT)
	_fade_out(id, DONE_SECONDS)


## Fades quest `id`'s card out after `wait` seconds, then forgets it.
func _fade_out(id: String, wait: float) -> void:
	var card: QuestCard = cards[id]
	var tween: Tween = card.create_tween()
	leaving[id] = tween
	var _waited: IntervalTweener = tween.tween_interval(wait)
	var _faded: PropertyTweener = tween.tween_property(card, "modulate:a", 0.0, FADE_SECONDS)
	var _gone: CallbackTweener = tween.tween_callback(_drop.bind(id))


## Fades quest `id`'s card, fading out as it's no longer followed, back in: the player follows it
## again.
func _come_back(id: String) -> void:
	leaving[id].kill()
	var _stays: bool = leaving.erase(id)
	_fade_in(cards[id])


## Fades `card` in.
static func _fade_in(card: QuestCard) -> void:
	var _faded_in: PropertyTweener = card.create_tween().tween_property(
		card,
		"modulate:a",
		1.0,
		FADE_SECONDS,
	)


## Forgets quest `id`'s card, once it has faded out.
func _drop(id: String) -> void:
	cards[id].queue_free()
	var _forgotten: bool = cards.erase(id)
	var _unshown: bool = shown.erase(id)
	var _left: bool = leaving.erase(id)
	order.erase(id)


## The pill under quest `id`'s name, saying where its step counts.
func pill(id: String) -> QuestPill:
	return cards[id].pill()


## Puts the list on the Survey's other side and glides each card the share `glide` of the way to
## its place, the text sized to the screen.
func _lay_out(glide: float) -> void:
	var screen: Vector2 = get_viewport_rect().size
	var font: int = maxi(MIN_FONT, roundi(minf(screen.x, screen.y) * FONT_SHARE))
	var width: float = minf(font * WIDTH_FONTS, screen.x * MAX_WIDTH_SHARE)
	var font_changed: bool = font != _font_size
	_font_size = font
	var place: SurveyChoice.Place = SurveyChoice.AUTO_PLACE
	if survey != null:
		place = survey.place_shown()
	var survey_left: bool = (place == SurveyChoice.Place.TOP_LEFT
			or place == SurveyChoice.Place.BOTTOM_LEFT)
	position = Vector2(
		screen.x - width - MARGIN if survey_left else MARGIN,
		MARGIN if survey_left or roster == null else roster.bottom(),
	)
	var y: float = 0.0
	for id: String in order:
		var card: QuestCard = cards[id]
		if font_changed:
			card.fit(font)
		card.lay_out(width)
		card.position = card.position.lerp(Vector2(0.0, y), glide)
		y += card.size.y + GAP


## How far down the screen the cards reach, or 0 while there are none (#1465).
func bottom() -> float:
	return position.y + _bottom() - GAP if not order.is_empty() else 0.0


## Where a new card starts: under the last one.
func _bottom() -> float:
	var y: float = 0.0
	for id: String in order:
		y += cards[id].size.y + GAP
	return y
