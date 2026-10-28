class_name NoticeScreen
extends Control
## A short notice on screen (#1589): a card at the top's middle with a title and a line, which eases
## in, stays a few seconds and eases out on its own. It takes no input, so it never holds the player
## or keeps them from walking, and it can tell them of something that happened out of their sight,
## like a guide who went ahead without them (GuideNoticeTie). A notice shown while another is up
## takes its place. Its text tags show the names they stand for (#733), and its text grows with the
## screen. Its layout lives in notice_screen.tscn.

## How long the card takes to ease in and out, and how long it stays in between.
const FADE_SECONDS: float = 0.4
const SHOW_SECONDS: float = 4.0
## The text's size as a share of the screen's shorter side, and never smaller than this.
const FONT_SHARE: float = 0.026
const MIN_FONT: int = 14
## How much bigger the title is than the line.
const TITLE_SCALE: float = 1.15
## How wide the card is at most, in font sizes, and at most the screen's width less the margins.
const WIDTH_FONTS: float = 22.0
const MARGIN: float = SurveyChoice.MARGIN

var _shown: Tween
var _font_size: int = 0

@onready var _card: PanelContainer = $Card
@onready var _title: Label = $Card/Rows/Title
@onready var _text: Label = $Card/Rows/Text


func _ready() -> void:
	# A copy of the UI's theme: the notice scales its own font with the screen.
	theme = UiTheme.theme().duplicate()
	_card.add_theme_stylebox_override("panel", UiTheme.card())


func _process(_delta: float) -> void:
	_fit(get_viewport_rect().size)


## Shows `text` under `title` (none when ""), both with text tags, easing in, staying SHOW_SECONDS
## and easing out; it takes the place of a notice shown now.
func notify(title: String, text: String) -> void:
	_title.text = TextTags.shown(title)
	_title.visible = not title.is_empty()
	_text.text = TextTags.shown(text)
	if _shown != null:
		_shown.kill()
	_card.visible = true
	_shown = _card.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var _in: PropertyTweener = _shown.tween_property(_card, "modulate:a", 1.0, FADE_SECONDS)
	var _stay: IntervalTweener = _shown.tween_interval(SHOW_SECONDS)
	var _out: PropertyTweener = _shown.tween_property(_card, "modulate:a", 0.0, FADE_SECONDS)
	var _hidden: CallbackTweener = _shown.tween_callback(_card.hide)


## Whether a notice is on screen, easing in or out included.
func is_showing() -> bool:
	return _card.visible


## The title and the line of the notice shown last.
func shown_title() -> String:
	return _title.text


func shown_text() -> String:
	return _text.text


## Sizes the text to a screen of `screen` pixels and keeps the card at its top's middle.
func _fit(screen: Vector2) -> void:
	var font: int = maxi(MIN_FONT, roundi(minf(screen.x, screen.y) * FONT_SHARE))
	if font != _font_size:
		_font_size = font
		theme.default_font_size = font
		_title.add_theme_font_size_override("font_size", roundi(font * TITLE_SCALE))
	var width: float = minf(font * WIDTH_FONTS, screen.x - 2.0 * MARGIN)
	_card.custom_minimum_size.x = width
	_card.size = Vector2(width, 0.0)
	_card.position = Vector2((screen.x - width) / 2.0, MARGIN)
