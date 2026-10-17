class_name SurveyChoice
extends Node
## Where the Survey (#301) shows and how close, as this machine's player chooses: off, in one of
## the screen's corners, see-through over the whole game, or opaque over it; and one of the zoom
## steps. The `survey` action cycles where it shows, `survey_zoom_in` and `survey_zoom_out` step
## the zoom. Both start at Auto (#161) and a choice is kept in the player's Settings, the ones
## Graphics loads and saves, so the file has one owner.

## Where the Survey shows. Saved by number: append new ones, never reorder.
enum Place {
	OFF,
	TOP_LEFT,
	TOP_RIGHT,
	BOTTOM_LEFT,
	BOTTOM_RIGHT,
	OVER_GAME,
	OPAQUE,
}

const PLACE_SETTING: String = "survey_place"
const ZOOM_SETTING: String = "survey_zoom"
const AUTO_PLACE: Place = Place.TOP_RIGHT
## The zoom steps, as how many tiles fit across the Survey's shorter side, from far to close.
const ZOOMS: Array[float] = [48.0, 32.0, 20.0, 12.0, 8.0]
const AUTO_ZOOM: int = 2
## How much of the screen's shorter side a corner Survey takes, and its gap to the edges.
const CORNER_SHARE: float = 0.32
const MARGIN: float = 16.0
## The backdrop's opacity: in a corner, see-through over the game, and opaque.
const CORNER_ALPHA: float = 0.85
const OVER_GAME_ALPHA: float = 0.4

@export var view: SurveyView
## Whose Settings the choice is kept in.
@export var graphics: Graphics


func _process(_delta: float) -> void:
	place()


func _unhandled_input(event: InputEvent) -> void:
	var problem: String = ""
	if event.is_action_pressed("survey"):
		problem = cycle()
	elif event.is_action_pressed("survey_zoom_in"):
		problem = zoom_by(1)
	elif event.is_action_pressed("survey_zoom_out"):
		problem = zoom_by(-1)
	if not problem.is_empty():
		push_warning("the Survey's setting can't be saved: " + problem)


## Where the Survey shows: the player's choice, or Auto's. A saved value that isn't a place counts
## as Auto.
func place_shown() -> Place:
	var chosen: int = _chosen(PLACE_SETTING)
	if chosen >= 0 and chosen < Place.size():
		return chosen as Place
	return AUTO_PLACE


## The zoom step in use: the player's choice, or Auto's.
func zoom_step() -> int:
	var chosen: int = _chosen(ZOOM_SETTING)
	if chosen >= 0 and chosen < ZOOMS.size():
		return chosen
	return AUTO_ZOOM


## Shows the Survey in the next place, after the last one off again, and keeps that; returns why it
## couldn't be saved, or "".
func cycle() -> String:
	return _choose(PLACE_SETTING, posmod(place_shown() + 1, Place.size()))


## Steps the zoom `steps` closer (fewer is farther), within the steps there are, and keeps it;
## returns why it couldn't be saved, or "".
func zoom_by(steps: int) -> String:
	return _choose(ZOOM_SETTING, clampi(zoom_step() + steps, 0, ZOOMS.size() - 1))


## Puts the Survey where it shows, at its zoom, sized to the screen.
func place() -> void:
	if view == null:
		return
	var shown: Place = place_shown()
	view.visible = shown != Place.OFF
	view.across = ZOOMS[zoom_step()]
	var screen: Vector2 = view.get_viewport_rect().size
	var alpha: float = 1.0
	if shown == Place.OVER_GAME:
		alpha = OVER_GAME_ALPHA
	elif shown != Place.OPAQUE:
		alpha = CORNER_ALPHA
	view.backdrop = Color(Boot.FOG, alpha)
	view.bordered = shown != Place.OVER_GAME and shown != Place.OPAQUE
	if not view.bordered:
		view.position = Vector2.ZERO
		view.size = screen
		return
	var side: float = minf(screen.x, screen.y) * CORNER_SHARE
	var left: bool = shown == Place.TOP_LEFT or shown == Place.BOTTOM_LEFT
	var top: bool = shown == Place.TOP_LEFT or shown == Place.TOP_RIGHT
	view.size = Vector2(side, side)
	view.position = Vector2(
		MARGIN if left else screen.x - side - MARGIN,
		MARGIN if top else screen.y - side - MARGIN,
	)


func _chosen(setting: String) -> int:
	if graphics == null:
		return -1
	return graphics.settings.chosen.get(setting, -1)


func _choose(setting: String, value: int) -> String:
	if graphics == null:
		return ""
	graphics.settings.chosen[setting] = value
	place()
	return graphics.settings.save(graphics.settings_path)
