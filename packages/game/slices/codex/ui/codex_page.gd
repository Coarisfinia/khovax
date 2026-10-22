class_name CodexPage
extends Control
## A codex page (#959): what selecting an invented name in a text opens (NameLinks), over the whole
## screen. A faction's is its lexicon entry: its name, the line saying what its name means ("Amvrel
## Velmarai: *the guild of those who chart*"), its entry, and this machine's player's standing
## with it, its current rank only (#484). The close button at its top right, `ui_cancel` (Escape,
## or a controller's B) and the `menu` action close it, and the focus goes back to where it was.
## While it's open the game hears no input, as under the menu, but it doesn't pause: reading a
## dialog's line doesn't either. It eases in and out, never snaps, and its text grows with the
## screen. Monsters' bestiary entries and the other named kinds' pages follow (#959).

## The page's heading over a faction's name.
const LEXICON_TEXT: String = "Lexicon"
## The standing line: neutral, or the standing with its sign and the rank the faction names it.
const NEUTRAL_TEXT: String = "Your standing: neutral"
const STANDING_TEXT: String = "Your standing: %+d, %s"
## The meaning line: the name, then what it means in italics.
const GLOSS_TEXT: String = "%s: [i]%s[/i]"
const CLOSE_TIP: String = "Close the page (Escape, or B on a controller)"
const FADE_SECONDS: float = GameMenu.FADE_SECONDS
## The text's size as a share of the screen's shorter side, and never smaller than the menu's.
const FONT_SHARE: float = GameMenu.FONT_SHARE
## How much bigger the name is than the text.
const TITLE_SCALE: float = 1.6
## How wide the page's text is, in font sizes, at most the screen's width less the margins.
const WIDTH_FONTS: float = 30.0
const MARGIN: float = GameMenu.MARGIN

## This machine's player's input, which hears nothing while the page is open.
@export var input: LocalInput
## The session, whose holder keeps this machine's player's standings.
@export var driver: Session

## What the page shows, kept here so tests can read them: the heading, the name, the meaning line
## (as the player reads it), the entry and the standing line.
var heading: Label
var title: Label
var gloss: RichTextLabel
var entry: Label
var standing: Label
var close_button: Button
var _sheet: PanelContainer
var _column: VBoxContainer
var _open: bool = false
var _fade: Tween
var _font_size: int = 0
## What had the focus before the page opened, which gets it back when it closes.
var _focused_before: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme().duplicate()
	_sheet = PanelContainer.new()
	_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sheet.add_theme_stylebox_override("panel", UiTheme.sheet(MARGIN))
	_sheet.visible = false
	_sheet.modulate.a = 0.0
	var row: HBoxContainer = HBoxContainer.new()
	var middle: CenterContainer = CenterContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column = VBoxContainer.new()
	heading = GameMenu.label(LEXICON_TEXT)
	title = GameMenu.label("")
	gloss = RichTextLabel.new()
	gloss.bbcode_enabled = true
	gloss.fit_content = true
	entry = Label.new()
	entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	standing = GameMenu.label("")
	for shown: Control in [heading, title, gloss, entry, standing]:
		_column.add_child(shown)
	# Only the sheet takes clicks, and only while open: fading out, the page lets them through.
	for passive: Control in [row, middle, _column, gloss]:
		passive.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(_column)
	row.add_child(middle)
	close_button = GameMenu.button("", close)
	close_button.icon = GameMenu.CLOSE_ICON
	close_button.tooltip_text = CLOSE_TIP
	close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(close_button)
	_sheet.add_child(row)
	add_child(_sheet)


func _process(_delta: float) -> void:
	lay_out(get_viewport_rect().size)


## `ui_cancel` and `menu` close an open page before the dialog or the menu hear them.
func _input(event: InputEvent) -> void:
	if _open and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu")):
		close()
		get_viewport().set_input_as_handled()


## Opens the page of the thing of the kind `kind` (TextTags.FACTION) with the id `id`; whether it
## has one.
func open(kind: String, id: String) -> bool:
	if kind != TextTags.FACTION:
		push_warning("%s %s has no codex page" % [kind, id])
		return false
	var faction: Faction = FactionContent.cached().factions.get(id)
	if faction == null:
		push_warning("no faction %s for a codex page" % id)
		return false
	var faction_name: String = TextTags.shown(faction.name)
	heading.text = LEXICON_TEXT
	title.text = faction_name
	gloss.text = GLOSS_TEXT % [
		NameLinks.escaped(faction_name),
		NameLinks.escaped(faction.codex_gloss),
	]
	entry.text = faction.codex_entry
	standing.text = _standing_line(faction)
	if not _open:
		_focused_before = get_viewport().gui_get_focus_owner()
	_ease(true)
	close_button.grab_focus()
	return true


## Closes the page, easing out; the focus goes back to where it was.
func close() -> void:
	if not _open:
		return
	_ease(false)
	if is_instance_valid(_focused_before) and _focused_before.is_visible_in_tree():
		_focused_before.grab_focus()
	else:
		close_button.release_focus()
	_focused_before = null


func is_open() -> bool:
	return _open


## Sizes the text to a screen of `screen` pixels (tests lay it out for other screens this way).
func lay_out(screen: Vector2) -> void:
	var font: int = maxi(GameMenu.MIN_FONT, roundi(minf(screen.x, screen.y) * FONT_SHARE))
	if font != _font_size:
		_font_size = font
		theme.default_font_size = font
		title.add_theme_font_size_override("font_size", roundi(font * TITLE_SCALE))
		gloss.add_theme_font_size_override("normal_font_size", font)
		gloss.add_theme_font_size_override("italics_font_size", font)
		# Half a line between the page's parts, so the name, its meaning, the entry and the standing
		# read apart.
		_column.add_theme_constant_override("separation", roundi(font * 0.5))
		var side: float = font * GameMenu.BUTTON_FONTS
		close_button.custom_minimum_size = Vector2(side, side)
		close_button.add_theme_constant_override(
			"icon_max_width",
			roundi(font * GameMenu.ICON_FONTS),
		)
	var room: float = screen.x - 4.0 * MARGIN - font * GameMenu.BUTTON_FONTS
	_column.custom_minimum_size.x = minf(font * WIDTH_FONTS, room)


## The standing line for `faction`: this machine's player's current rank with it, never the others.
func _standing_line(faction: Faction) -> String:
	var holder: ProfileHolder = driver.holder if driver != null else null
	if holder == null or holder.keeper == null:
		return NEUTRAL_TEXT
	var value: int = holder.keeper.profile.standings.of(faction.id)
	if value == 0:
		return NEUTRAL_TEXT
	return STANDING_TEXT % [value, TextTags.shown(faction.rank_name(value))]


## Eases the page in or out; the game hears no input while it's in.
func _ease(opening: bool) -> void:
	_open = opening
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP if opening else Control.MOUSE_FILTER_IGNORE
	if input != null:
		input.blocked = opening
	if _fade != null:
		_fade.kill()
	_sheet.visible = true
	_fade = _sheet.create_tween()
	var _eased: PropertyTweener = _fade.tween_property(
		_sheet,
		"modulate:a",
		1.0 if opening else 0.0,
		FADE_SECONDS,
	)
	if not opening:
		var _hidden: CallbackTweener = _fade.tween_callback(_sheet.hide)
