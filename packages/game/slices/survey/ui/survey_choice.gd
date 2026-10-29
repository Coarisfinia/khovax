class_name SurveyChoice
extends Node
## Where the Survey (#301) shows and how close, as this machine's player chooses: off, in one of
## the screen's corners, see-through over the whole game, or opaque over it; and one of the zoom
## steps. The `survey` action (Tab, a controller's Back, #779) cycles where it shows,
## `survey_zoom_in` and `survey_zoom_out` step the zoom; the controller's triggers zoom only the
## menu's Survey (SurveyTab), since in the game the right one fires the special attack. Both start
## at Auto (#161) and a choice is kept in the player's Settings, the ones Graphics loads and saves,
## so the file has one owner.

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
	if event is InputEventJoypadMotion:
		return
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
	return _place().value() as Place


## The zoom step in use: the player's choice, or Auto's.
func zoom_step() -> int:
	return _zoom().value()


## Where the Survey shows, as a menu (#355) shows it: "Top right", or "Auto (Top right)" while
## Auto picks it.
func place_label() -> String:
	return _place().label(place_words(place_shown()))


## The place `shown` in words, as the menu shows it.
func place_words(shown: Place) -> String:
	match shown:
		Place.OFF:
			return tr("Off")
		Place.TOP_LEFT:
			return tr("Top left")
		Place.TOP_RIGHT:
			return tr("Top right")
		Place.BOTTOM_LEFT:
			return tr("Bottom left")
		Place.BOTTOM_RIGHT:
			return tr("Bottom right")
		Place.OVER_GAME:
			return tr("Over game")
	return tr("Opaque")


## The zoom as a menu shows it: "20 tiles across", or "Auto (20 tiles across)" while Auto picks it.
func zoom_label() -> String:
	var across: int = roundi(ZOOMS[zoom_step()])
	# Through tr_n(), so a language picks its plural form by the count (#1709); English reads alike.
	var words: String = tr_n("{across} tiles across", "{across} tiles across", across)
	return _zoom().label(words.format({ "across": across }))


## Shows the Survey `steps` places on (back for fewer), after the last one off again, and keeps
## that; returns why it couldn't be saved, or "".
func cycle(steps: int = 1) -> String:
	_place().step(steps)
	return _keep()


## Steps the zoom `steps` closer (fewer is farther), within the steps there are, and keeps it;
## returns why it couldn't be saved, or "".
func zoom_by(steps: int) -> String:
	_zoom().step_within(steps)
	return _keep()


## Adds its rows, where the Survey shows and how close, to the Settings tab's Interface submenu
## (#1614): the tab comes before the Survey's slice, so it doesn't name them.
func add_rows(tab: SettingsTab) -> void:
	tab.add_auto_row(SettingsTab.INTERFACE, PLACE_SETTING, tr("Survey"), place_label, cycle)
	tab.add_auto_row(SettingsTab.INTERFACE, ZOOM_SETTING, tr("Survey zoom"), zoom_label, zoom_by)


## Puts the Survey where it shows, at its zoom, sized to the screen.
func place() -> void:
	if view != null:
		place_in(view.get_viewport_rect().size)


## Puts the Survey where it shows, at its zoom, sized to a screen of `screen` pixels (tests lay it
## out for other screens than their own this way).
func place_in(screen: Vector2) -> void:
	if view == null:
		return
	var shown: Place = place_shown()
	view.visible = shown != Place.OFF
	view.across = ZOOMS[zoom_step()]
	var alpha: float = 1.0
	if shown == Place.OVER_GAME:
		alpha = OVER_GAME_ALPHA
	elif shown != Place.OPAQUE:
		alpha = CORNER_ALPHA
	view.backdrop = Color(FogView.FOG, alpha)
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


## Where the Survey shows, by the place's number; Auto while there's no Graphics to keep it.
func _place() -> SettingChoice:
	return SettingChoice.new(_settings(), PLACE_SETTING, Place.size(), AUTO_PLACE)


## The zoom, an index into ZOOMS; Auto while there's no Graphics to keep it.
func _zoom() -> SettingChoice:
	return SettingChoice.new(_settings(), ZOOM_SETTING, ZOOMS.size(), AUTO_ZOOM)


func _settings() -> Settings:
	if graphics == null:
		return null
	return graphics.settings


## Puts the Survey where the choices say and keeps them; returns why they couldn't be saved, or "".
func _keep() -> String:
	if graphics == null:
		return ""
	place()
	return graphics.save_settings()
