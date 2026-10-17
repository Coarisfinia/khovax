class_name QuestListView
extends Control
## The open quests at the side of the screen (#340): one card per quest of this machine's player
## that isn't finished (Profile.open_steps), with its name and what its current step asks, and the
## count where the step counts up ("1/3"). A quest that finishes says so and fades out, and the
## cards below glide up into its place; nothing snaps. It keeps to the side of the screen the
## Survey's corner isn't on (#301). Quests are told apart by their words, never by color (#68), and
## the text grows with the screen, so it stays readable on a phone. It only reads the profile.

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
## How much bigger a quest's name is than its step.
const NAME_SCALE: float = 1.15
## How wide a card is, in font sizes, and never more than this share of the screen's width.
const WIDTH_FONTS: float = 15.0
const MAX_WIDTH_SHARE: float = 0.42
const BACKDROP_ALPHA: float = 0.85
const BORDER_PIXELS: int = 2
const DONE_TEXT: String = "Done"

## Whose quests are listed: this machine's player's profile.
@export var holder: ProfileHolder
## Where the Survey shows, so the list keeps out of its corner.
@export var survey: SurveyChoice

## What each listed quest's card says under its name, by quest id: the step, or that it's done.
## Kept here so tests can read what is shown.
var shown: Dictionary[String, String] = {}
## Each listed quest's card, by quest id, while it's listed or fading out.
var cards: Dictionary[String, PanelContainer] = {}
## The cards' order from the top, finished ones included until they're gone.
var order: Array[String] = []
var _font_size: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	show_quests()
	_lay_out(1.0 - exp(-GLIDE * delta))


## Matches the cards to the open quests. Called every frame; tests call it directly.
func show_quests() -> void:
	var steps: Dictionary[String, QuestStep] = {}
	var profile: Profile = null
	if holder != null and holder.keeper != null:
		profile = holder.keeper.profile
		steps = profile.open_steps()
	for id: String in order:
		if not steps.has(id) and shown[id] != DONE_TEXT:
			_finish(id)
	for id: String in steps:
		var progress: QuestProgress = profile.quest_progress.get(id)
		var line: String = step_line(steps[id], progress.count if progress != null else 0)
		if not cards.has(id):
			_add_card(id, profile.quest_book[id].name)
		shown[id] = line
		_line_label(id).text = line
		_line_label(id).visible = not line.is_empty()


## What `step` asks, worded for the player, with `count` of its count where it counts up. A new
## condition gets its own wording here; one without any shows only the count.
static func step_line(step: QuestStep, count: int) -> String:
	var asks: String = ""
	match step.condition:
		"dominated":
			var what: String = "a monster"
			if not step.species.is_empty():
				what = _with_article(step.species)
			asks = "Dominate " + what
		"opened":
			asks = "Open a chest"
	if step.count > 1:
		asks += ("  " if not asks.is_empty() else "") + "%d/%d" % [count, step.count]
	return asks


## `species` named for the player, after "a" or "an". Species have no player-facing names yet, so
## the id is read out, its words apart.
static func _with_article(species: String) -> String:
	var words: String = species.replace("_", " ")
	return ("an " if "aeiou".contains(words.left(1)) else "a ") + words


## A new card for quest `id`, named `quest_name`, fading in under the others.
func _add_card(id: String, quest_name: String) -> void:
	var card: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(Boot.FOG, BACKDROP_ALPHA)
	style.border_color = Toon.INK
	style.set_border_width_all(BORDER_PIXELS)
	style.set_content_margin_all(GAP)
	card.add_theme_stylebox_override("panel", style)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lines: VBoxContainer = VBoxContainer.new()
	lines.add_child(_label(quest_name))
	lines.add_child(_label(""))
	card.add_child(lines)
	card.modulate.a = 0.0
	add_child(card)
	_size_text(card)
	card.position = Vector2(0.0, _bottom())
	cards[id] = card
	order.append(id)
	var _faded_in: PropertyTweener = card.create_tween().tween_property(
		card,
		"modulate:a",
		1.0,
		FADE_SECONDS,
	)


## A line of a card's text, in ink, wrapped to the card's width.
func _label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Toon.INK)
	return label


## Says quest `id` is done, fades its card out after a while, then lets the cards below move up.
func _finish(id: String) -> void:
	shown[id] = DONE_TEXT
	_line_label(id).text = DONE_TEXT
	_line_label(id).visible = true
	var card: PanelContainer = cards[id]
	var tween: Tween = card.create_tween()
	var _waited: IntervalTweener = tween.tween_interval(DONE_SECONDS)
	var _faded: PropertyTweener = tween.tween_property(card, "modulate:a", 0.0, FADE_SECONDS)
	var _gone: CallbackTweener = tween.tween_callback(_drop.bind(id))


## Forgets finished quest `id`'s card, once it has faded out.
func _drop(id: String) -> void:
	cards[id].queue_free()
	var _forgotten: bool = cards.erase(id)
	var _unshown: bool = shown.erase(id)
	order.erase(id)


## The label under quest `id`'s name.
func _line_label(id: String) -> Label:
	return cards[id].get_child(0).get_child(1) as Label


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
	position = Vector2(screen.x - width - MARGIN if survey_left else MARGIN, MARGIN)
	var y: float = 0.0
	for id: String in order:
		var card: PanelContainer = cards[id]
		if font_changed:
			_size_text(card)
		card.custom_minimum_size.x = width
		card.size = Vector2(width, 0.0)
		card.position = card.position.lerp(Vector2(0.0, y), glide)
		y += card.size.y + GAP


## Sizes `card`'s text to the font size in use: its name a little bigger than its step.
func _size_text(card: PanelContainer) -> void:
	var font: int = maxi(MIN_FONT, _font_size)
	var lines: Node = card.get_child(0)
	var name_label: Label = lines.get_child(0) as Label
	name_label.add_theme_font_size_override("font_size", roundi(font * NAME_SCALE))
	(lines.get_child(1) as Label).add_theme_font_size_override("font_size", font)


## Where a new card starts: under the last one.
func _bottom() -> float:
	var y: float = 0.0
	for id: String in order:
		y += cards[id].size.y + GAP
	return y
