class_name SurveyHeldMarks
extends SurveyLayer
## The Survey's marks of faction territory (#637), drawn over the SurveyView it's a child of: every
## instance the Survey shows that a faction holds (Territory) carries its holder's symbol
## (TerritoryText) in ink on a light disc ringed in ink, so only the symbol tells the factions
## apart, never a color (#68). The instance this machine's player is in has its mark in the middle
## of the Survey's top edge, clear of the players' circles and of what sits in the screen's top
## corners over a full Survey (the quest list, the cogwheel); each one next door has its mark in the
## middle of what shows of it. It only reads the world's flags and what the Survey shows, after the
## Survey worked it out each frame.

## A mark next door, in tile radii, never smaller than the pixels below; the one at the top edge is
## always EDGE_PIXELS, a margin below it.
const SHARE: float = 1.3
const MIN_PIXELS: float = 10.0
const EDGE_PIXELS: float = 14.0
const MARGIN: float = 6.0

## The holder of each instance shown that a faction holds, by instance name: its faction's id.
var held_by: Dictionary[String, String] = {}
## Where each held instance next door has its mark, by instance name, in the Survey's pixels.
var held_at: Dictionary[String, Vector2] = {}


func _draw() -> void:
	var survey: SurveyView = get_parent() as SurveyView
	if survey == null:
		return
	var here: String = _here(survey)
	var radius: float = maxf(survey.zoom() * SHARE, MIN_PIXELS)
	for instance_name: String in held_by:
		var symbol: String = TerritoryText.symbol_of(held_by[instance_name])
		if instance_name == here:
			var top: float = MARGIN + EDGE_PIXELS + SurveyView.INK_PIXELS
			_draw_mark(Vector2(size.x / 2.0, top), EDGE_PIXELS, symbol)
		elif held_at.has(instance_name):
			_draw_mark(held_at[instance_name], radius, symbol)


## Works out the marks from the world's flags and what the Survey shows. Called every frame while
## it shows; tests call it directly, after the Survey's own.
func show_state() -> void:
	held_by.clear()
	held_at.clear()
	var survey: SurveyView = get_parent() as SurveyView
	if survey == null or survey.driver == null or survey.driver.world == null:
		return
	var flags: Array[String] = survey.driver.world.flags
	var here: String = _here(survey)
	var here_holder: String = Territory.holder(flags, here)
	if not here_holder.is_empty() and not survey.tiles.is_empty():
		held_by[here] = here_holder
	if survey.driver.state == null or survey.neighbours == null:
		return
	for target: String in survey.driver.state.region.exit_blueprints:
		var holder: String = Territory.holder(flags, target)
		var middle: Vector2 = _middle_shown(survey, target)
		if not holder.is_empty() and middle.is_finite():
			held_by[target] = holder
			held_at[target] = middle


## Who holds the instance this machine's player is in, in words with text tags (TerritoryText),
## shown or not.
func here_text() -> String:
	var survey: SurveyView = get_parent() as SurveyView
	if survey == null or survey.driver == null or survey.driver.world == null:
		return TerritoryText.held_text("")
	return TerritoryText.held_text(Territory.holder(survey.driver.world.flags, _here(survey)))


## The middle of what the Survey shows of the instance `target` next door, in its pixels, or
## Vector2.INF when none of it shows.
static func _middle_shown(survey: SurveyView, target: String) -> Vector2:
	var region: Region = survey.neighbours.region_of(target)
	if region == null:
		return Vector2.INF
	var shift: Vector2i = survey.neighbours.shifts[target]
	var total: Vector2 = Vector2.ZERO
	var shown: int = 0
	for tile: Vector2i in region.sorted_tiles():
		if survey.tiles.has(tile + shift):
			total += survey.to_view(tile + shift)
			shown += 1
	return total / shown if shown > 0 else Vector2.INF


## The instance this machine's player is in.
static func _here(survey: SurveyView) -> String:
	return survey.driver.local_instance_name() if survey.driver != null else ""


## A mark at `at`, `radius` pixels round: a light disc ringed in ink with `symbol` in ink.
func _draw_mark(at: Vector2, radius: float, symbol: String) -> void:
	draw_circle(at, radius + SurveyView.INK_PIXELS, Toon.INK)
	draw_circle(at, radius, SurveyView.EXIT_COLOR)
	var font: Font = get_theme_default_font()
	var font_size: int = roundi(radius * 1.4)
	var middle: float = (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	var baseline: Vector2 = at + Vector2(-radius, middle)
	var center: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER
	draw_string(font, baseline, symbol, center, radius * 2.0, font_size, Toon.INK)
