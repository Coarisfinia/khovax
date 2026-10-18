class_name RosterHud
extends Control
## The roster at the top left of the screen (#540): one square per monster this machine's player
## carries, in their carried order (#53), with its species' initials and its place's number, the key
## that swaps to it (1 to 3; the d-pad's left, up and right on a controller). The companion's square
## is drawn bold, with a pointer under it, and the reserve's thin and faded, so which is which shows
## by a shape too, never by color alone (#68). Which carried monster fainted isn't tracked yet
## (#54).
## A tap or a click on a square swaps to that monster for the next tick (LocalInput.choose_swap,
## #55). It moves below the Survey when that shows in the top left corner. It only reads the state.

## A square's side as a share of the screen's shorter side, never smaller than MIN_SIDE, so a
## thumb can hit it on a phone.
const SIDE_SHARE: float = 0.09
const MIN_SIDE: float = 56.0
const MARGIN: float = SurveyChoice.MARGIN
const GAP: float = 10.0
## The pointer under the companion's square, as a share of the square's side.
const POINTER_SHARE: float = 0.18
const BACKDROP_ALPHA: float = 0.7
## How a reserve's square is drawn next to the companion's: faded and thin.
const RESERVE_ALPHA: float = 0.55
const INK_PIXELS: float = 2.0
const COMPANION_INK_PIXELS: float = 6.0

@export var driver: GameDriver
## Where the Survey shows, so the roster keeps out of its corner.
@export var survey: SurveyChoice

## The species of every square, in carried order. Kept here so tests can read what is shown.
var shown: PackedStringArray = PackedStringArray()
## The companion's place among `shown`, from 0, or -1 when none of them is the companion.
var companion_place: int = -1
## The initials shown for each species, by id; a species missing from the data shows its id's.
var _initials: Dictionary[String, String] = {}
var _side: float = 0.0
var _top: float = MARGIN


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var species: SpeciesData = SpeciesContent.load_species()
	for id: String in species.species:
		_initials[id] = initials_of(species.species[id].name)


func _process(_delta: float) -> void:
	show_state()
	lay_out_in(get_viewport_rect().size)


## A tap or a left click on a square swaps to its monster and is taken, so the touch stick doesn't
## start under it. Godot hands `_input` to later nodes first, so this node comes after the stick in
## the Hud. While the game hears no input (the menu is open) it takes nothing.
func _input(event: InputEvent) -> void:
	if driver == null or driver.input == null or driver.input.blocked:
		return
	var at: Vector2 = Vector2(-1.0, -1.0)
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	var click: InputEventMouseButton = event as InputEventMouseButton
	if touch != null and touch.pressed:
		at = touch.position
	# A touch reaches here as itself, so the click Godot makes up from it is skipped.
	elif click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		at = click.position if click.device != InputEvent.DEVICE_ID_EMULATION else at
	for place: int in shown.size():
		if rect_of(place).has_point(at):
			driver.input.choose_swap(place + 1)
			get_viewport().set_input_as_handled()
			return


func _draw() -> void:
	# Not laid out yet: nothing to draw, and a font size of 0 would fail.
	if _side <= 0.0:
		return
	for place: int in shown.size():
		_draw_square(place)


## Matches the squares to the state. Called every frame; tests call it after stepping.
func show_state() -> void:
	var party: PackedStringArray = PackedStringArray()
	var companion: String = ""
	if driver != null and driver.state != null and driver.input != null:
		var slot: int = driver.input.slot
		party = driver.state.carried[slot]
		companion = driver.state.companions[slot]
	if party != shown or party.find(companion) != companion_place:
		shown = party
		companion_place = party.find(companion)
		queue_redraw()


## Lays the squares out for a screen of `screen` pixels: in a row from the top left corner, below
## the Survey when it shows there.
func lay_out_in(screen: Vector2) -> void:
	_side = maxf(MIN_SIDE, minf(screen.x, screen.y) * SIDE_SHARE)
	_top = MARGIN
	if survey != null and survey.place_shown() == SurveyChoice.Place.TOP_LEFT:
		_top += minf(screen.x, screen.y) * SurveyChoice.CORNER_SHARE + GAP
	queue_redraw()


## Where the square of the monster at `place` (from 0) in the carried order is on the screen.
func rect_of(place: int) -> Rect2:
	return Rect2(MARGIN + (_side + GAP) * place, _top, _side, _side)


## The height on the screen below the roster and its pointer, where whatever stands under it starts.
func bottom() -> float:
	if shown.is_empty():
		return _top
	return _top + _side * (1.0 + POINTER_SHARE) + GAP * 2.0


## A species' initials: the first letter of each word of its name, as "SF" for "Storm Finch".
static func initials_of(species_name: String) -> String:
	var letters: String = ""
	for word: String in species_name.split(" ", false):
		letters += word.left(1).to_upper()
	return letters


## The square of the monster at `place`: its initials, its place's number in the corner, and for
## the companion a bold frame and a pointer under it.
func _draw_square(place: int) -> void:
	var area: Rect2 = rect_of(place)
	var chosen: bool = place == companion_place
	var faded: float = 1.0 if chosen else RESERVE_ALPHA
	draw_rect(area, Color(Boot.FOG, BACKDROP_ALPHA * faded))
	var ink: Color = Color(Toon.INK, faded)
	draw_rect(area, ink, false, COMPANION_INK_PIXELS if chosen else INK_PIXELS)
	var font: Font = ThemeDB.fallback_font
	var big: int = int(area.size.x * 0.36)
	var baseline: Vector2 = Vector2(area.position.x, area.get_center().y + big * 0.45)
	var initials: String = _initials.get(shown[place], shown[place].left(2).to_upper())
	draw_string(font, baseline, initials, HORIZONTAL_ALIGNMENT_CENTER, area.size.x, big, ink)
	var small: int = int(area.size.x * 0.22)
	var corner: Vector2 = area.position + Vector2(area.size.x * 0.1, area.size.y * 0.1 + small)
	draw_string(font, corner, str(place + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, small, ink)
	if chosen:
		_draw_pointer(area, ink)


## The pointer under the companion's square: a triangle pointing up at it.
func _draw_pointer(area: Rect2, ink: Color) -> void:
	var half: float = area.size.x * POINTER_SHARE
	var tip: Vector2 = Vector2(area.get_center().x, area.end.y + GAP * 0.5)
	var points: PackedVector2Array = [tip, tip + Vector2(half, half), tip + Vector2(-half, half)]
	draw_colored_polygon(points, ink)
