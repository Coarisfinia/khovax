class_name RosterHud
extends Control
## The roster at the top left of the screen (#540): one square per monster this machine's player
## carries, in their carried order (#53), with its species' picture (SpeciesStage, #722), the
## first two letters of its name in the bottom right corner, since species may share a stand-in
## model, and its place's number in the top left corner; while a keyboard or a controller is in use
## (DeviceInUse), the glyph
## of the key or button
## that swaps to it stands there instead (1 to 3; the d-pad's left, up and right, #1192). The
## companion's square
## is drawn bold, with a pointer under it, and the reserve's thin and faded, so which is which shows
## by a shape too, never by color alone (#68). One that fainted here (#597) is crossed out and
## faded further, and can't be swapped to. The fainted one being picked for a revive item (#780,
## RevivePick) gets a second frame around its square.
## A tap or a click on a square swaps to that monster for the next tick (LocalInput.choose_swap,
## #55), and on a fainted one uses a revive item on it (LocalInput.choose_revive, #780): the glyph
## of a click with the mouse and keyboard, or of a tap on touch, stands right of the row to say so
## (#1221), and none with a controller, which can't point. It moves
## below the Survey when that shows in the top left corner. It only reads the state.
## It runs before the rest of the Hud (process_priority in main.tscn), so the quest list below it
## lays out under where it is this frame.

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
## How a fainted one's square is drawn: faded further, and crossed out.
const FAINTED_ALPHA: float = 0.35
const INK_PIXELS: float = 2.0
const COMPANION_INK_PIXELS: float = 6.0
## The swap's glyph in a square's top left corner, its side as a share of the square's, and its gap
## to the square's edges, as a share of the square's.
const GLYPH_SHARE: float = 0.42
const GLYPH_INSET: float = 0.03
## The name's letters in a square's bottom right corner, their size as a share of the square's.
const NAME_SHARE: float = 0.3
## The fog around those letters, in pixels, so they read over the picture.
const NAME_OUTLINE_PIXELS: int = 4
## The letters of a species missing from the data, which has no name to take them from.
const UNKNOWN_LETTERS: String = "?"
## The click's or tap's glyph right of the row, its side as a share of a square's.
const POINTING_SHARE: float = 0.85

@export var driver: Session
## Where the Survey shows, so the roster keeps out of its corner.
@export var survey: SurveyChoice

## The species of every square, in carried order. Kept here so tests can read what is shown.
var shown: PackedStringArray = PackedStringArray()
## The companion's place among `shown`, from 0, or -1 when none of them is the companion.
var companion_place: int = -1
## Whether each square's monster fainted here (#597), in carried order.
var fainted: Array[bool] = []
## The place among `shown`, from 0, of the fainted monster picked for a revive item (#780), or -1.
var picked_place: int = -1
## The short ids of the squares' monsters, in carried order.
var _short_ids: PackedStringArray = PackedStringArray()
## The picture of each species shown, by id: rendered once, a still in a square, since a HUD
## that fidgets draws the eye and every frame costs on a phone.
var _pictures: Dictionary[String, SpeciesStage] = {}
## The letters shown for each species, by id, from its translated name (#1657); a species missing
## from the data shows UNKNOWN_LETTERS.
var _letters: Dictionary[String, String] = {}
var _side: float = 0.0
var _top: float = MARGIN


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var species: SpeciesContent = SpeciesContent.cached()
	for id: String in species.species:
		_letters[id] = letters_of(tr(species.species[id].name))


func _process(_delta: float) -> void:
	show_state()
	lay_out_in(get_viewport_rect().size)


## A tap or a left click on a square swaps to its monster, or revives a fainted one, and is taken,
## so the touch stick doesn't start under it. Godot hands `_input` to later nodes first, so this
## node comes after the stick in the Hud. While the game hears no input (the menu is open) it takes
## nothing.
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
	var input: LocalInput = driver.input as LocalInput
	for place: int in shown.size():
		if rect_of(place).has_point(at):
			if has_fainted(place):
				input.choose_revive(_short_ids[place])
			else:
				# Swapping ends a pick for a revive item.
				input.revive_pick.drop()
				input.choose_swap(place + 1)
			get_viewport().set_input_as_handled()
			return


func _draw() -> void:
	# Not laid out yet: nothing to draw, and a font size of 0 would fail.
	if _side <= 0.0:
		return
	for place: int in shown.size():
		_draw_square(place)
	var pointed_with: Texture2D = pointing_glyph()
	if pointed_with != null and not shown.is_empty():
		ActionGlyph.draw_on(self, pointed_with, pointing_rect())


## Matches the squares to the state. Called every frame; tests call it after stepping.
func show_state() -> void:
	var party: PackedStringArray = PackedStringArray()
	var party_species: PackedStringArray = PackedStringArray()
	var companion: String = ""
	var down: Array[bool] = []
	var picked: String = ""
	if driver != null and driver.state != null and driver.input != null:
		var slot: int = driver.input.slot
		party = CompanionParty.carried(driver.state, slot)
		party_species = CompanionParty.carried_species(driver.state, slot)
		companion = CompanionParty.companion(driver.state, slot)
		down = _fainted_in(driver.state, slot, party)
		picked = (driver.input as LocalInput).revive_pick.picked
	var changed: bool = party != _short_ids or party_species != shown or down != fainted
	if changed or party.find(companion) != companion_place or party.find(picked) != picked_place:
		_short_ids = party
		shown = party_species
		companion_place = party.find(companion)
		fainted = down
		picked_place = party.find(picked)
		_keep_pictures()
		queue_redraw()


## A picture for every species shown, and none for one no longer shown.
func _keep_pictures() -> void:
	for id: String in _pictures.keys():
		if not shown.has(id):
			_pictures[id].queue_free()
			var _dropped: bool = _pictures.erase(id)
	for id: String in shown:
		if not _pictures.has(id):
			_add_picture(id)


## Adds the picture of `species_id` and renders it.
func _add_picture(species_id: String) -> void:
	var picture: SpeciesStage = SpeciesStage.new(species_id)
	_pictures[species_id] = picture
	add_child(picture)
	_render(picture)


## Renders `picture` once more, at the squares' side.
func _render(picture: SpeciesStage) -> void:
	picture.size = Vector2i(roundi(maxf(_side, MIN_SIDE)), roundi(maxf(_side, MIN_SIDE)))
	picture.render_target_update_mode = SubViewport.UPDATE_ONCE


## The picture shown for `species_id`, or null when none is shown.
func picture_of(species_id: String) -> SpeciesStage:
	return _pictures.get(species_id)


## Whether each of `party`, the short ids of the monsters the player in `slot` carries, fainted in
## `state` (#597).
static func _fainted_in(state: GameState, slot: int, party: PackedStringArray) -> Array[bool]:
	var down: Array[bool] = []
	for short_id: String in party:
		down.append(CompanionParty.has_fainted(state, slot, short_id))
	return down


## Lays the squares out for a screen of `screen` pixels: in a row from the top left corner, below
## the Survey when it shows there.
func lay_out_in(screen: Vector2) -> void:
	var side: float = maxf(MIN_SIDE, minf(screen.x, screen.y) * SIDE_SHARE)
	if side != _side:
		_side = side
		for picture: SpeciesStage in _pictures.values():
			_render(picture)
	_top = MARGIN
	if survey != null and survey.place_shown() == SurveyChoice.Place.TOP_LEFT:
		_top += minf(screen.x, screen.y) * SurveyChoice.CORNER_SHARE + GAP
	queue_redraw()


## Where the square of the monster at `place` (from 0) in the carried order is on the screen.
func rect_of(place: int) -> Rect2:
	return Rect2(MARGIN + (_side + GAP) * place, _top, _side, _side)


## Where the click's or tap's glyph stands on the screen: right of the last square, in the middle
## of its height.
func pointing_rect() -> Rect2:
	var side: float = _side * POINTING_SHARE
	var last: Rect2 = rect_of(maxi(shown.size() - 1, 0))
	return Rect2(last.end.x + GAP, last.get_center().y - side / 2.0, side, side)


## The glyph of pointing at a square on the device in use, a click or a tap, or null with a
## controller.
static func pointing_glyph() -> Texture2D:
	return InputGlyphs.pointing(DeviceInUse.device)


## The height on the screen below the roster and its pointer, where whatever stands under it starts.
func bottom() -> float:
	if shown.is_empty():
		return _top
	return _top + _side * (1.0 + POINTER_SHARE) + GAP * 2.0


## A species' letters in its square: the first two of its one-word name (#717), as "Ti" for
## "Tikazzir".
static func letters_of(species_name: String) -> String:
	return species_name.left(2)


## The square of the monster at `place`: its species' picture and letters, its place's number in the
## corner, for
## the
## companion a bold frame and a pointer under it, for a fainted one a cross over it, and for the one
## picked for a revive item a second frame around it.
func _draw_square(place: int) -> void:
	var area: Rect2 = rect_of(place)
	var chosen: bool = place == companion_place
	var faded: float = FAINTED_ALPHA if has_fainted(place) else (1.0 if chosen else RESERVE_ALPHA)
	draw_rect(area, Color(FogView.FOG, BACKDROP_ALPHA * faded))
	var picture: SpeciesStage = picture_of(shown[place])
	if picture != null:
		draw_texture_rect(picture.get_texture(), area, false, Color(Color.WHITE, faded))
	var ink: Color = Color(Toon.INK, faded)
	var letters: String = _letters.get(shown[place], UNKNOWN_LETTERS)
	_draw_letters(area, letters, ink)
	draw_rect(area, ink, false, COMPANION_INK_PIXELS if chosen else INK_PIXELS)
	_draw_corner(area, place, faded)
	if chosen:
		_draw_pointer(area, ink)
	if has_fainted(place):
		_draw_cross(area, ink)
	if place == picked_place:
		draw_rect(area.grow(GAP * 0.5), Color(Toon.INK), false, COMPANION_INK_PIXELS)


## `letters` in the bottom right corner of `area`, in `ink` on a fog outline.
func _draw_letters(area: Rect2, letters: String, ink: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	var font_size: int = int(area.size.x * NAME_SHARE)
	var inset: float = area.size.x * 0.1
	var baseline: Vector2 = Vector2(area.position.x, area.end.y - inset)
	var width: float = area.size.x - inset
	var fog: Color = Color(FogView.FOG, ink.a)
	var right: HorizontalAlignment = HORIZONTAL_ALIGNMENT_RIGHT
	draw_string_outline(font, baseline, letters, right, width, font_size, NAME_OUTLINE_PIXELS, fog)
	draw_string(font, baseline, letters, right, width, font_size, ink)


## The top left corner of the square of the monster at `place`, faded to `faded`: the glyph of what
## swaps to it on the device in use, or on touch its place's number.
func _draw_corner(area: Rect2, place: int, faded: float) -> void:
	var swapped_by: Texture2D = glyph_of(place)
	if swapped_by != null:
		var at: Vector2 = area.position + area.size * GLYPH_INSET
		ActionGlyph.draw_on(self, swapped_by, Rect2(at, area.size * GLYPH_SHARE), faded)
		return
	var small: int = int(area.size.x * 0.22)
	var corner: Vector2 = area.position + Vector2(area.size.x * 0.1, area.size.y * 0.1 + small)
	var ink: Color = Color(Toon.INK, faded)
	draw_string(
		ThemeDB.fallback_font,
		corner,
		str(place + 1),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		small,
		ink,
	)


## The glyph of the key or button that swaps to the monster at `place` (from 0) on the device in
## use, or null on touch, where the square itself is tapped, and past the swap keys.
static func glyph_of(place: int) -> Texture2D:
	if place >= LocalInput.SWAP_ACTIONS.size():
		return null
	return InputGlyphs.of(LocalInput.SWAP_ACTIONS[place], DeviceInUse.device)


## Whether the monster at `place` (from 0) fainted here (#597).
func has_fainted(place: int) -> bool:
	return place < fainted.size() and fainted[place]


## A bold cross over a fainted monster's square, corner to corner.
func _draw_cross(area: Rect2, ink: Color) -> void:
	var top_right: Vector2 = Vector2(area.end.x, area.position.y)
	var bottom_left: Vector2 = Vector2(area.position.x, area.end.y)
	draw_line(area.position, area.end, ink, COMPANION_INK_PIXELS)
	draw_line(top_right, bottom_left, ink, COMPANION_INK_PIXELS)


## The pointer under the companion's square: a triangle pointing up at it.
func _draw_pointer(area: Rect2, ink: Color) -> void:
	var half: float = area.size.x * POINTER_SHARE
	var tip: Vector2 = Vector2(area.get_center().x, area.end.y + GAP * 0.5)
	var points: PackedVector2Array = [tip, tip + Vector2(half, half), tip + Vector2(-half, half)]
	draw_colored_polygon(points, ink)
