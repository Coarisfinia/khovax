class_name ControlsTab
extends ScrollContainer
## The menu's Controls tab (#1414): every action the player can take, one row each, with the glyphs
## of what presses it on the device in use (InputGlyphs): keys, a controller's buttons and sticks,
## or on touch the gesture that does it (a drag walks, a pinch zooms) and else a tap on its button
## or on what it acts on. It follows a change of device at once. Every row takes the focus, so a
## controller's left stick or d-pad moves among them, the focused one framed in ink like a focused
## button, and the tab scrolls to it. Its layout lives in its scene, controls_tab.tscn (#437): this
## script keeps only what it does.

## The rows, in order: what each says in English (its key, which names its node; words_of() gives
## what it shows), then the actions it covers, whose glyphs it shows in that order, each glyph once.
const ROWS: Dictionary[String, Array] = {
	"Walk": [&"move_up", &"move_left", &"move_down", &"move_right"],
	"Special attack": [&"special_attack"],
	"Focus another wild monster": [&"focus_previous", &"focus_next"],
	"Place a totem": [&"place_totem"],
	"Swap to monster 1, 2 or 3": [&"swap_1", &"swap_2", &"swap_3"],
	"Revive a fainted monster": [&"revive_monster"],
	"Respawn when knocked down": [&"respawn"],
	"Harvest a tile by hand": [&"interact"],
	"Move the Survey": [&"survey"],
	"Zoom the Survey in or out": [&"survey_zoom_in", &"survey_zoom_out"],
	"Open or close the menu": [&"menu"],
	"Confirm": [&"ui_accept"],
	"Back": [&"ui_cancel"],
}
## The space inside a row, around its words and glyphs, in pixels: room for the focus frame.
const PADDING: int = 8

## The glyphs each row shows now, by its words. Kept here so tests can read them.
var shown: Dictionary[String, Array] = {}
## Each row, by its words, so tests can focus them.
var rows: Dictionary[String, PanelContainer] = {}
## The device the glyphs were picked for, or -1 before the first.
var _device: int = -1
## Each row's glyph box, by its words.
var _glyph_boxes: Dictionary[String, HBoxContainer] = {}
## A row's frame while it rests and while it has the focus.
var _resting: StyleBoxEmpty
var _focused: StyleBox

@onready var _rows: VBoxContainer = $Middle/Rows


func _ready() -> void:
	_resting = StyleBoxEmpty.new()
	_resting.set_content_margin_all(PADDING)
	_focused = get_theme_stylebox("focus", "Button").duplicate() as StyleBox
	_focused.set_content_margin_all(PADDING)
	for words: String in ROWS:
		_rows.add_child(_row(words))
	refresh()


func _process(_delta: float) -> void:
	# Only while the tab is shown: the menu is open on it.
	if is_visible_in_tree():
		refresh()


## The menu's title for this tab (#1677): a literal tr(), so the translation template has it; the
## node keeps its English name, which the tests find it by.
func tab_title() -> String:
	return tr("Controls")


## Makes the rows `width` pixels wide, as wide as the Settings tab's, in the tab's middle.
func fit(width: float) -> void:
	_rows.custom_minimum_size.x = width


## Shows the glyphs of the device in use; picks them anew only when it changed.
func refresh() -> void:
	if DeviceInUse.device == _device:
		return
	_device = DeviceInUse.device
	for words: String in ROWS:
		var glyphs: Array[Texture2D] = glyphs_of(ROWS[words], DeviceInUse.device)
		shown[words] = glyphs
		var box: HBoxContainer = _glyph_boxes[words]
		for old: Node in box.get_children():
			box.remove_child(old)
			old.queue_free()
		for glyph: Texture2D in glyphs:
			box.add_child(_glyph(glyph))


## The glyphs that press `actions` on `device`, each once, in order: on touch, a tap where no
## gesture presses one, since every action there has its button or its target on the screen.
static func glyphs_of(actions: Array, device: DeviceInUse.Device) -> Array[Texture2D]:
	var glyphs: Array[Texture2D] = []
	for action: StringName in actions:
		var glyph: Texture2D = InputGlyphs.of(action, device)
		if glyph == null:
			glyph = InputGlyphs.pointing(device)
		if glyph != null and glyph not in glyphs:
			glyphs.append(glyph)
	return glyphs


## A row saying `words`, with a box for its glyphs at its right end, that takes the focus and is
## framed while it has it.
func _row(words: String) -> PanelContainer:
	var row: PanelContainer = PanelContainer.new()
	row.name = words.to_pascal_case()
	row.focus_mode = Control.FOCUS_ALL
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_stylebox_override("panel", _resting)
	var _entered: int = row.focus_entered.connect(_frame.bind(row, true))
	var _exited: int = row.focus_exited.connect(_frame.bind(row, false))
	# A drag on a row still scrolls the tab on touch: nothing in it takes the pointer.
	var line: HBoxContainer = HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label: Label = Label.new()
	label.text = words_of(words)
	# Cut short rather than wrapped, so a phone's narrow screen keeps the glyphs in view.
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(label)
	var box: HBoxContainer = HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(box)
	row.add_child(line)
	rows[words] = row
	_glyph_boxes[words] = box
	return row


## What the row `words` (a key of ROWS) says, translated: a literal tr() each, so the translation
## template has them.
func words_of(words: String) -> String:
	match words:
		"Walk":
			return tr("Walk")
		"Special attack":
			return tr("Special attack")
		"Focus another wild monster":
			return tr("Focus another wild monster")
		"Place a totem":
			return tr("Place a totem")
		"Swap to monster 1, 2 or 3":
			return tr("Swap to monster 1, 2 or 3")
		"Revive a fainted monster":
			return tr("Revive a fainted monster")
		"Respawn when knocked down":
			return tr("Respawn when knocked down")
		"Harvest a tile by hand":
			return tr("Harvest a tile by hand")
		"Move the Survey":
			return tr("Move the Survey")
		"Zoom the Survey in or out":
			return tr("Zoom the Survey in or out")
		"Open or close the menu":
			return tr("Open or close the menu")
		"Confirm":
			return tr("Confirm")
		"Back":
			return tr("Back")
	# Every key of ROWS has its words above (the settings flow checks it).
	push_warning("the Controls tab has no words for the row " + words)
	return ""


## Frames `row` in ink while `focused`, and not otherwise.
func _frame(row: PanelContainer, focused: bool) -> void:
	row.add_theme_stylebox_override("panel", _focused if focused else _resting)


## `glyph` as tall as its row's words, in ink like the UI's icons (the sheet under it is the fog
## a hint's backdrop shows elsewhere, ActionGlyph.draw_on).
static func _glyph(glyph: Texture2D) -> TextureRect:
	var shape: TextureRect = TextureRect.new()
	shape.texture = glyph
	shape.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	shape.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	shape.self_modulate = Toon.INK
	shape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return shape
