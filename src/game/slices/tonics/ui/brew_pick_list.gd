class_name BrewPickList
extends Control
## The list of the tonics and draughts to pick from (#2313), shown while this machine's player picks
## one to drink (LocalInput's drink_pick): left of the drink button (DrinkButton), level with its
## top,
## or in its place where it's hidden (no touch),
## one row per brew they hold, with how many, in the order their tonic lists them. The
## picked one is marked with an arrow, never by color alone (#68); the arrows or the d-pad move
## the mark and Enter or A drinks it, and a tap or a click on a row drinks that one at once. Hidden
## while nothing is picked, and so while the menu or a dialog shows, which ends the pick.

## The mark in front of the picked row.
const MARK: String = "▶ "

## Where the pick is.
@export var input: LocalInput
## Whose tonics and draughts are listed: this machine's player's profile.
@export var holder: ProfileHolder
## The drink button the list stands beside.
@export var button: DrinkButton

## The ids of the brews listed now, in order, and the picked one, "" while hidden. Kept here so
## tests can read them.
var shown: PackedStringArray = PackedStringArray()
var picked: String = ""
## The rows' words as they show now, in order.
var lines: Array[String] = []
var _card: PanelContainer
var _rows: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.theme()
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UiTheme.card())
	_card.visible = false
	_rows = VBoxContainer.new()
	_card.add_child(_rows)
	add_child(_card)


func _process(_delta: float) -> void:
	refresh()


## Shows the pick as it is now; builds the rows anew only when it changed.
func refresh() -> void:
	var now_picked: String = input.drink_pick.picked if input != null else ""
	var brews: PackedStringArray = PackedStringArray()
	if not now_picked.is_empty():
		brews = DrinkTie.held(holder)
	var words: Array[String] = _words_of(brews, now_picked)
	if now_picked != picked or brews != shown or words != lines:
		picked = now_picked
		shown = brews
		lines = words
		_build()
	_card.visible = not picked.is_empty()
	if _card.visible and button != null:
		_card.reset_size()
		# Its top level with the button's, growing down over the play area rather than up into the
		# Survey at the top right, and never past the screen's bottom.
		# Without touch the button is hidden, so the list takes its place at the right edge.
		var beside: Rect2 = button.rect()
		var screen: Vector2 = get_viewport_rect().size
		var right: float = beside.position.x - ActionButton.GAP
		if not button.visible:
			right = screen.x - ActionButton.MARGIN
		var lowest: float = screen.y - ActionButton.MARGIN - _card.size.y
		_card.position = Vector2(right - _card.size.x, minf(beside.position.y, lowest))


## Where the list is on the screen, for tests and taps.
func card_rect() -> Rect2:
	return _card.get_global_rect()


## The row of the brew `brew_id`, or null when it isn't listed.
func row_of(brew_id: String) -> Button:
	var place: int = shown.find(brew_id)
	return _rows.get_child(place) as Button if place >= 0 else null


## Each row's words for `brews`, the one `marked` with the mark.
func _words_of(brews: PackedStringArray, marked: String) -> Array[String]:
	var words: Array[String] = []
	var content: TonicContent = TonicContent.cached()
	for brew_id: String in brews:
		var brew: TonicBrew = content.brews.get(brew_id)
		var named: String = tr(brew.name) if brew != null else brew_id
		var count: int = holder.keeper.profile.materials.get(brew_id, 0)
		var line: String = tr("{brew} ×{count}").format({ "brew": named, "count": count })
		words.append((MARK if brew_id == marked else "") + line)
	return words


func _build() -> void:
	for row: Node in _rows.get_children():
		_rows.remove_child(row)
		row.queue_free()
	for place: int in shown.size():
		var row: Button = MenuWidgets.button(lines[place], input.choose_drink.bind(shown[place]))
		# The controller and the keys move the pick, never the GUI's focus.
		row.focus_mode = Control.FOCUS_NONE
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_rows.add_child(row)
