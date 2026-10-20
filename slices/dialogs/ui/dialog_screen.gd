class_name DialogScreen
extends Control
## A dialog on screen (#635): a card at the bottom with the speaker's name and the line they say.
## A line without answers reads on with one button; a line with answers lists them as buttons, and
## the chosen one leads on (Dialog.after) or ends the dialog. The card follows the simulation
## (#890): an answer button only sends the answer in this machine's player's next command
## (LocalInput.choose_answer), and the card moves on or closes once the simulation raises it as
## DialogAnswered for this player, whatever sent it (the buttons, a replay or a co-op peer's
## commands). Reading on changes nothing in the game, so it stays on the card. Controller, touch
## and keyboard all work: the buttons take the focus, so the d-pad or the stick moves it and A (or
## Enter) confirms. While a dialog is open the player stands. Talking to a person (NpcTalkedTo,
## #557) opens their dialog for the player who talked. Its text tags show the names they stand for
## (#733).
## It eases in and out, never snaps, and its text grows with the screen. Its layout lives in
## dialog_screen.tscn (#437).

## The read-on button's words: on to the next line, or the end of the dialog.
const READ_ON_TEXT: String = "Continue"
const END_TEXT: String = "Farewell"
const FADE_SECONDS: float = 0.2
## The text's size as a share of the screen's shorter side, and never smaller than this.
const FONT_SHARE: float = 0.03
const MIN_FONT: int = 16
## How much bigger the speaker's name is than the line.
const SPEAKER_SCALE: float = 1.15
## How wide the card is, in font sizes, at most the screen's width less the margins.
const WIDTH_FONTS: float = 26.0
const MARGIN: float = SurveyChoice.MARGIN
## A button's smallest height, in font sizes, so a finger can hit it.
const BUTTON_FONTS: float = GameMenu.BUTTON_FONTS

## This machine's player's input: it stands while a dialog is open, and takes the answers.
@export var input: LocalInput
## The world's events, which say when this machine's player talks to a person or answers.
@export var bus: EventBus

## The dialog open now, or null.
var dialog: Dialog
## The index of the line shown in `dialog`.
var line_index: int = -1
## The dialogs, read when the first one opens.
var _content: DialogContent
var _fade: Tween
var _font_size: int = 0

@onready var _card: PanelContainer = $Card
@onready var _speaker: Label = $Card/Rows/Speaker
@onready var _line: Label = $Card/Rows/Line
@onready var _choices: VBoxContainer = $Card/Rows/Choices


func _ready() -> void:
	# A copy of the UI's theme: the screen scales its own font with the screen.
	theme = UiTheme.theme().duplicate()
	_card.add_theme_stylebox_override("panel", UiTheme.card())
	if bus != null:
		bus.subscribe(NpcTalkedTo, _on_talked)
		bus.subscribe(DialogAnswered, _on_answered)


func _process(_delta: float) -> void:
	lay_out(get_viewport_rect().size)
	_follow_menu()


## Opens the dialog with the id `dialog_id` at its first line; whether there is one to open.
func open(dialog_id: String) -> bool:
	if _content == null:
		_content = DialogContent.load_dialogs()
	dialog = _content.dialogs.get(dialog_id)
	if dialog == null:
		push_warning("no dialog %s to open: %s" % [dialog_id, _content.problem])
		return false
	_show_line(0)
	_ease(true)
	return true


## Opens the dialog of the person this machine's player talked to, unless one is open already.
func _on_talked(event: NpcTalkedTo) -> void:
	if input != null and event.slot == input.slot and not event.dialog.is_empty() and not is_open():
		var _opened: bool = open(event.dialog)


## Moves the open dialog on to where the answer this machine's player chose leads, or closes it,
## once the simulation has it: the line shown may be an earlier one, which the answer skips.
func _on_answered(event: DialogAnswered) -> void:
	if input == null or event.slot != input.slot or dialog == null or event.dialog != dialog.id:
		return
	var chosen: DialogAnswer = dialog.answer_of(event.answer)
	if chosen != null:
		_go_to(dialog.line_index(chosen.next))


## Whether a dialog is open.
func is_open() -> bool:
	return dialog != null


## What each button on the card says now, in order: the read-on button's words, or the answers'.
func choices() -> Array[String]:
	var texts: Array[String] = []
	for button: Button in _buttons():
		texts.append(button.text)
	return texts


## The text of the speaker's name and of the line on the card now.
func shown_speaker() -> String:
	return _speaker.text


func shown_line() -> String:
	return _line.text


## Sizes the text to a screen of `screen` pixels and keeps the card at its bottom's middle (tests
## lay it out for other screens than their own this way).
func lay_out(screen: Vector2) -> void:
	var font: int = maxi(MIN_FONT, roundi(minf(screen.x, screen.y) * FONT_SHARE))
	if font != _font_size:
		_font_size = font
		theme.default_font_size = font
		_speaker.add_theme_font_size_override("font_size", roundi(font * SPEAKER_SCALE))
		_size_buttons()
	var width: float = minf(font * WIDTH_FONTS, screen.x - 2.0 * MARGIN)
	_card.custom_minimum_size.x = width
	_card.size = Vector2(width, 0.0)
	_card.position = Vector2((screen.x - width) / 2.0, screen.y - MARGIN - _card.size.y)


## Shows the line at `index`: its words, and its answers or the read-on button, the first focused.
func _show_line(index: int) -> void:
	line_index = index
	var line: DialogLine = dialog.lines[index]
	_speaker.text = TextTags.shown(dialog.speaker)
	_line.text = TextTags.shown(line.text)
	# The old buttons leave at once, so the card never shows both lines' buttons.
	for old: Button in _buttons():
		_choices.remove_child(old)
		old.queue_free()
	if line.answers.is_empty():
		var last: bool = dialog.after(index) < 0
		_add_button(END_TEXT if last else READ_ON_TEXT, _read_on)
	for answer: DialogAnswer in line.answers:
		_add_button(TextTags.shown(answer.text), _answer.bind(answer.id))
	_size_buttons()
	_buttons()[0].grab_focus()


func _add_button(text: String, pressed: Callable) -> void:
	var made: Button = Button.new()
	made.text = text
	made.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var _connected: int = made.pressed.connect(pressed)
	_choices.add_child(made)


## Reads on from a line without answers, to the next line or the dialog's end.
func _read_on() -> void:
	_go_to(dialog.after(line_index))


## Sends the answer `answer_id` of the line shown to the simulation; the card moves on once the
## simulation raises it (_on_answered).
func _answer(answer_id: String) -> void:
	if input != null:
		input.choose_answer(DialogFeature.code(dialog.id, answer_id))


## Shows the line at `index`, or closes the dialog for -1.
func _go_to(index: int) -> void:
	if index >= 0:
		_show_line(index)
		return
	dialog = null
	line_index = -1
	# The card fades out with its last buttons, which nothing presses any more.
	for button: Button in _buttons():
		button.disabled = true
		button.release_focus()
	_ease(false)


## Eases the card in or out; the player stands while it's in.
func _ease(opening: bool) -> void:
	if input != null:
		input.in_dialog = opening
	if _fade != null:
		_fade.kill()
	_card.visible = true
	_fade = _card.create_tween()
	var _eased: PropertyTweener = _fade.tween_property(
		_card,
		"modulate:a",
		1.0 if opening else 0.0,
		FADE_SECONDS,
	)
	if not opening:
		var _hidden: CallbackTweener = _fade.tween_callback(_card.hide)


## While the menu is open over the dialog its buttons rest, so A or Enter in the menu can't answer
## behind it; once it closes, the first button takes the focus back if none of them has it.
func _follow_menu() -> void:
	if dialog == null or input == null:
		return
	var live: Array[Button] = _buttons()
	for button: Button in live:
		button.disabled = input.blocked
	var focused: Control = get_viewport().gui_get_focus_owner()
	if not input.blocked and not live.is_empty() and not live.has(focused):
		live[0].grab_focus()


## The card's buttons now: the old line's leave the card at once (_show_line).
func _buttons() -> Array[Button]:
	var live: Array[Button] = []
	for child: Node in _choices.get_children():
		live.append(child as Button)
	return live


## Gives every button a finger-sized height for the font in use.
func _size_buttons() -> void:
	for button: Button in _buttons():
		button.custom_minimum_size.y = _font_size * BUTTON_FONTS
