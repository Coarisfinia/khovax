class_name DialogScreen
extends Control
## A dialog on screen (#635): a card at the bottom with the speaker's name and the line they say.
## A line without answers reads on with one button; a line with answers lists them as buttons, and
## the chosen one leads on (Dialog.after) or ends the dialog. The card follows the simulation's
## state (#890, #898): after every tick it reads this machine's player's open dialog and line
## (DialogFeature), which talking to a person opens (NpcTalkedTo, #557) and answers move on or
## close, whatever sent them (the buttons, a replay or a co-op peer's commands), so it's right
## after a resume too. An answer button only sends the answer in this machine's player's next
## command (LocalInput.choose_answer). Reading on changes nothing in the game, so it stays on the
## card, from the line the state holds. Controller, touch and keyboard all work: the buttons take
## the focus, so the d-pad or the stick moves it and A (or Enter) confirms. While a dialog is open
## the player stands. A dialog that doesn't hold its player (#970) can be left: the leave button
## at the card's top right (a click or a tap), or `ui_cancel` (Escape, or a controller's B) closes
## the card and lets the player walk; walking away or acting then closes the dialog in the state too
## (DialogFeature). One that holds them shows no leave button, and Escape opens the menu as ever.
## Its text tags show the names they stand for (#733), and the names that have a codex page can be
## selected in its line and the speaker's name (NameLinks, #959, #1005), which raises
## `name_selected`: a click, a long press on touch, or a controller's d-pad up from the buttons to
## the line (and on up to the speaker), left and right to the name and A. The focused button and the
## leave button show the key or controller button that presses them, for the device in use (#583,
## ActionGlyph). Each such name the line or the speaker shows raises `name_shown`: the player met
## it (the codex book, #1174).
## It eases in and out, never snaps, and its text grows with the screen. Its layout lives in
## dialog_screen.tscn (#437).

## A name in the line or the speaker's was selected (NameLinks): the kind of its tag and its id,
## whose codex page opens.
signal name_selected(kind: String, id: String)
## The line or the speaker showed a name that has a codex page: the kind of its tag and its id.
signal name_shown(kind: String, id: String)

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
## The leave button's words on hover: it shows only the menu's close icon, and its glyph the key.
const LEAVE_TIP: String = "Leave"

## This machine's player's input: it stands while a dialog is open, and takes the answers.
@export var input: LocalInput
## The session, whose state holds this machine's player's open dialog, read after every tick.
@export var driver: Session

## The dialog open now, or null.
var dialog: Dialog
## The index of the line shown in `dialog`.
var line_index: int = -1
## The open dialog and line the card last took from the state.
var _followed_dialog: String = ""
var _followed_line: int = DialogFeature.NO_LINE
var _fade: Tween
var _font_size: int = 0

@onready var _card: PanelContainer = $Card
@onready var _speaker: NameLinks = $Card/Rows/Header/Speaker
@onready var _leave: Button = $Card/Rows/Header/Leave
@onready var _line: NameLinks = $Card/Rows/Line
@onready var _choices: VBoxContainer = $Card/Rows/Choices


func _ready() -> void:
	# A copy of the UI's theme: the screen scales its own font with the screen.
	theme = UiTheme.theme().duplicate()
	_card.add_theme_stylebox_override("panel", UiTheme.card())
	_leave.icon = GameMenu.CLOSE_ICON
	_leave.tooltip_text = LEAVE_TIP
	var _glyph: ActionGlyph = ActionGlyph.badge(_leave, &"ui_cancel")
	var _left: int = _leave.pressed.connect(leave)
	var _selected: int = _line.name_selected.connect(name_selected.emit)
	var _named: int = _speaker.name_selected.connect(name_selected.emit)
	var _met: int = _line.name_shown.connect(name_shown.emit)
	var _met_speaker: int = _speaker.name_shown.connect(name_shown.emit)
	if driver != null:
		var _connected: int = driver.ticked.connect(_on_ticked)


func _process(_delta: float) -> void:
	lay_out(get_viewport_rect().size)
	_follow_menu()


## Escape or a controller's B leaves a dialog that doesn't hold the player, before the menu hears
## Escape; under the menu, or for a dialog that holds them, the menu keeps it.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and can_leave():
		leave()
		get_viewport().set_input_as_handled()


## Whether the open dialog can be left now: it doesn't hold this machine's player (#970), and the
## menu isn't open over it.
func can_leave() -> bool:
	var resting: bool = input != null and input.blocked
	return is_open() and not resting and not _holds()


## Closes the card of a dialog that doesn't hold the player, who can walk again; the state keeps it
## open until they walk away or act (DialogFeature), and talking to the person again opens it anew.
func leave() -> void:
	if can_leave():
		_go_to(DialogFeature.NO_LINE)


## Opens the dialog with the id `dialog_id` at the line `index`, its first by default, or moves the
## open one there; whether there is one to open.
func open(dialog_id: String, index: int = 0) -> bool:
	if is_open() and dialog.id == dialog_id:
		_show_line(index)
		return true
	var content: DialogContent = DialogContent.cached()
	dialog = content.dialogs.get(dialog_id)
	if dialog == null:
		push_warning("no dialog %s to open: %s" % [dialog_id, content.problem])
		return false
	_show_line(index)
	_ease(true)
	return true


## Shows this machine's player's open dialog at the line the state holds, or closes the card when
## none is open, if that changed since the card last looked, or always with `refresh`. Reading on
## or closing on the card leaves the state as it is, so the card stays where it read to.
func follow_state(refresh: bool = false) -> void:
	var slot: int = _slot()
	var feature: DialogFeature = _dialogs()
	var dialog_id: String = feature.dialog_of(slot) if feature != null else ""
	var index: int = feature.line_of(slot) if feature != null else DialogFeature.NO_LINE
	if not refresh and dialog_id == _followed_dialog and index == _followed_line:
		return
	_followed_dialog = dialog_id
	_followed_line = index
	if dialog_id.is_empty():
		if is_open():
			_go_to(DialogFeature.NO_LINE)
		return
	var _opened: bool = open(dialog_id, index)


## The slot of this machine's player.
func _slot() -> int:
	return input.slot if input != null else 0


## The dialogs of the state the session plays, or null.
func _dialogs() -> DialogFeature:
	if driver == null or driver.state == null:
		return null
	return driver.state.feature(DialogFeature.ID) as DialogFeature


## Whether this machine's player's open dialog holds them (#912): it can't be left then.
func _holds() -> bool:
	var feature: DialogFeature = _dialogs()
	return feature != null and feature.holds(_slot())


## Follows the state after every tick; this machine's player talking to a person or answering
## refreshes it even when it looks the same: talking again shows the dialog's first line again, and
## an answer that leads back to the line the state held moves the card there from where it read to.
func _on_ticked(_tick: int, events: Array[RefCounted]) -> void:
	var refresh: bool = false
	for event: RefCounted in events:
		var talk: NpcTalkedTo = event as NpcTalkedTo
		var answer: DialogAnswered = event as DialogAnswered
		var slot: int = talk.slot if talk != null else (answer.slot if answer != null else -1)
		if input != null and slot == input.slot:
			refresh = true
	follow_state(refresh)


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
	return _speaker.get_parsed_text()


func shown_line() -> String:
	return _line.get_parsed_text()


## The line's names that have a codex page, each as its link's meta ("FACTION:amvrel_velmarai").
func line_links() -> Array[String]:
	return _line.links


## Sizes the text to a screen of `screen` pixels and keeps the card at its bottom's middle (tests
## lay it out for other screens than their own this way).
func lay_out(screen: Vector2) -> void:
	var font: int = maxi(MIN_FONT, roundi(minf(screen.x, screen.y) * FONT_SHARE))
	if font != _font_size:
		_font_size = font
		theme.default_font_size = font
		for sized: String in ["normal_font_size", "bold_font_size"]:
			_speaker.add_theme_font_size_override(sized, roundi(font * SPEAKER_SCALE))
		_size_buttons()
	var width: float = minf(font * WIDTH_FONTS, screen.x - 2.0 * MARGIN)
	_card.custom_minimum_size.x = width
	_card.size = Vector2(width, 0.0)
	_card.position = Vector2((screen.x - width) / 2.0, screen.y - MARGIN - _card.size.y)


## Shows the line at `index`: its words, and its answers or the read-on button, the first focused.
func _show_line(index: int) -> void:
	line_index = index
	var line: DialogLine = dialog.lines[index]
	_speaker.show_tagged(TextTags.tag(TextTags.PERSON, dialog.speaker))
	_line.show_tagged(line.text)
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
	# A confirm presses the focused button only.
	var _glyph: ActionGlyph = ActionGlyph.badge(made, &"ui_accept", true)
	_choices.add_child(made)


## Reads on from a line without answers, to the next line or the dialog's end.
func _read_on() -> void:
	_go_to(dialog.after(line_index))


## Sends the answer `answer_id` of the line shown to the simulation; the card moves on once the
## simulation's state moves on (_on_ticked, follow_state).
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
## behind it; once it closes, the first button takes the focus back if neither they, the line nor
## the speaker's name have it.
func _follow_menu() -> void:
	if dialog == null or input == null:
		return
	var live: Array[Button] = _buttons()
	for button: Button in live:
		button.disabled = input.blocked
	_leave.visible = not _holds()
	_leave.disabled = input.blocked
	var focused: Control = get_viewport().gui_get_focus_owner()
	var on_names: bool = focused == _line or focused == _speaker
	var on_card: bool = on_names or (focused is Button and live.has(focused as Button))
	if not input.blocked and not live.is_empty() and not on_card:
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
	var side: float = _font_size * BUTTON_FONTS
	_leave.custom_minimum_size = Vector2(side, side)
	_leave.add_theme_constant_override(
		"icon_max_width",
		roundi(_font_size * MenuWidgets.ICON_FONTS),
	)
