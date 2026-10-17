extends RefCounted
## Survey flow (#301): the player looks at the Survey, the overview of the ground they explored, in
## the glade. It starts at Auto, in a corner; it shows exactly the tiles explored, each in its
## kind's color with its kind's symbol (#68), while ground still in the fog stays hidden; next
## door it shows exactly what was explored there, at its place in the world, and the exits on the
## tiles it shows, loading nothing; it marks every player by slot and every open quest's target;
## its action cycles it through the corners, over the game, opaque and off, its zoom steps within
## their range, and both choices are kept. In every place, on desktop screens and phones held
## either way, it sits against its own corner or covers the whole screen; every zoom step is
## followed, and zooming stops at both ends.


func run(tree: SceneTree) -> String:
	# The glade: big enough that some of it is still in the fog at the start, for the Survey to
	# hide.
	GameDriver.start_instance = InstanceBlueprints.GLADE
	var main: Node = (load(Boot.GAME) as PackedScene).instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame
	var result: String = _check_survey(main)
	main.queue_free()
	GameDriver.start_instance = ""
	await tree.process_frame
	return result


## The Survey (#301) starts at Auto, in a corner; it shows exactly the tiles explored, seen now or
## revealed, each in its kind's color with its kind's symbol, while ground still in the fog stays
## hidden; it marks every player by slot and every open quest's target; its action cycles it
## through the corners, over the game, opaque and off, its zoom steps within their range, and both
## choices are kept.
func _check_survey(main: Node) -> String:
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var fog: FogView = main.get_node("FogView") as FogView
	var survey: SurveyView = main.get_node("Hud/Survey") as SurveyView
	var choice: SurveyChoice = main.get_node("SurveyChoice") as SurveyChoice
	var graphics: Graphics = main.get_node("Graphics") as Graphics
	var path: String = "user://test_survey_settings.json"
	var kept_path: String = graphics.settings_path
	var kept: Dictionary[String, int] = graphics.settings.chosen.duplicate()
	graphics.settings_path = path
	graphics.settings.chosen.clear()
	fog.show_state(10.0)
	var result: String = _survey_ground(driver, survey)
	if result.is_empty():
		result = _survey_next_door(driver, survey)
	if result.is_empty():
		result = _survey_marks(driver, survey, FlowGame.holder(main).keeper.profile)
	if result.is_empty():
		result = _survey_choice(choice, survey, path)
	if result.is_empty():
		result = _survey_screens(choice, survey)
	if result.is_empty():
		result = _survey_zooms(choice, survey)
	SaveStore.remove(path)
	graphics.settings_path = kept_path
	graphics.settings.chosen = kept
	return result


## Why the Survey's tiles aren't exactly the explored ones in their kinds' colors and symbols
## (#68), or its closest zoom draws no symbols, or "".
func _survey_ground(driver: GameDriver, survey: SurveyView) -> String:
	var state: GameState = driver.state
	var keeper: WorldKeeper = survey.keeper
	var instance_name: String = driver.local_instance_name()
	var seen: Dictionary = keeper.explored_in(driver.world).seen(
		instance_name,
		driver.world.generation(instance_name),
	)
	var fog: FogFeature = state.feature(Features.FOG) as FogFeature
	survey.show_state()
	var hidden: int = 0
	for tile: Vector2i in state.region.sorted_tiles():
		var known: bool = seen.has(tile) or fog.revealed.has(tile) or FogView.ally_sees(state, tile)
		if survey.tiles.has(tile) != known:
			return "the Survey shows %s although it's %s" % [tile, "known" if known else "fogged"]
		var look: TileBlueprint = TileLooks.of(state.region.terrain[tile])
		if known and survey.tiles[tile] != look.color:
			return "the Survey colors %s unlike its kind" % tile
		if known and survey.symbols[tile] != look.symbol:
			return "the Survey doesn't mark %s with its kind's symbol" % tile
		if known and survey.blocking.has(tile) == state.region.is_walkable(tile):
			return "the Survey doesn't ring %s in ink exactly when it blocks the way" % tile
		hidden += 0 if known else 1
	if hidden == 0:
		return "nothing of the instance was still in the fog to hide on the Survey"
	return "" if _survey_symbols_drawn(survey) else (
		"the Survey draws no tile symbols even at its closest zoom"
	)


## Whether the Survey draws tile symbols at its closest zoom, at the corner size of a desktop
## screen, whatever size the test's own window is.
func _survey_symbols_drawn(survey: SurveyView) -> bool:
	var across: float = survey.across
	var shown: Vector2 = survey.size
	survey.across = SurveyChoice.ZOOMS[-1]
	survey.size = Vector2.ONE * 648.0 * SurveyChoice.CORNER_SHARE
	var drawn: bool = survey.symbol_size() > 0
	survey.across = across
	survey.size = shown
	return drawn


## Why the Survey doesn't show exactly the explored ground of the instance next door at its place
## in the world, or the exits on the tiles it shows, or loads an instance to draw them, or ""
## (#353).
func _survey_next_door(driver: GameDriver, survey: SurveyView) -> String:
	var world: World = driver.world
	var target: String = driver.state.region.exit_blueprints[0]
	var region: Region = survey.neighbours.region_of(target)
	if world.instances.has(target) or region == null:
		return "the glade's neighbour %s is loaded already, or not drawn next door" % target
	var keeper: WorldKeeper = survey.keeper
	var there: Dictionary[Vector2i, bool] = _explore_next_door(driver, keeper, region, target)
	var loaded: Array[String] = world.sorted_names()
	var before: int = world.state_hash()
	survey.show_state()
	if world.sorted_names() != loaded or world.state_hash() != before:
		return "drawing the Survey loaded or changed an instance"
	var shift: Vector2i = survey.neighbours.shifts[target]
	for tile: Vector2i in region.sorted_tiles():
		var at: Vector2i = tile + shift
		if survey.tiles.has(at) != there.has(tile):
			var how: String = "shows the fogged" if survey.tiles.has(at) else "hides the explored"
			return "the Survey %s tile %s next door" % [how, tile]
		if there.has(tile) and survey.tiles[at] != TileLooks.of(region.terrain[tile]).color:
			return "the Survey colors %s next door unlike its kind" % tile
	return _survey_exits(driver.state.region, region, shift, survey)


## Marks every other tile of `region`, the instance `target` next door, explored, and the exits'
## own tiles here and there, for their chevrons; returns what is explored there.
func _explore_next_door(
		driver: GameDriver,
		keeper: WorldKeeper,
		region: Region,
		target: String,
) -> Dictionary[Vector2i, bool]:
	var world: World = driver.world
	var explored: ExploredGround = keeper.explored_in(world)
	var there: Dictionary[Vector2i, bool] = explored.tiles_of(target, world.generation(target))
	var ground: Array[Vector2i] = region.sorted_tiles()
	for i: int in range(0, ground.size(), 2):
		there[ground[i]] = true
	for exit: Vector3i in region.exits:
		there[Vector2i(exit.x, exit.y)] = true
	var here_name: String = driver.local_instance_name()
	var here: Dictionary[Vector2i, bool] = explored.tiles_of(here_name, world.generation(here_name))
	for exit: Vector3i in driver.state.region.exits:
		here[Vector2i(exit.x, exit.y)] = true
	return there


## Why the Survey doesn't show exactly the exits on the tiles it shows, those of `here` and those of
## `there` next door, shifted by `shift`, or "".
func _survey_exits(here: Region, there: Region, shift: Vector2i, survey: SurveyView) -> String:
	var everywhere: Array[Vector3i] = []
	everywhere.append_array(here.exits)
	for exit: Vector3i in there.exits:
		everywhere.append(exit + Vector3i(shift.x, shift.y, 0))
	var shown: Array[Vector3i] = []
	for exit: Vector3i in everywhere:
		if survey.tiles.has(Vector2i(exit.x, exit.y)):
			shown.append(exit)
	if shown.size() <= here.exits.size() or survey.exits != shown:
		return "the Survey doesn't show the exits here and next door on the tiles it shows: %s" % [
			survey.exits,
		]
	return ""


## Why the Survey doesn't mark every player and the open quests' targets, or "".
func _survey_marks(driver: GameDriver, survey: SurveyView, profile: Profile) -> String:
	var text: String = "{\"id\": \"survey_any\", \"name\": \"Any\", "
	text += "\"steps\": [{\"condition\": \"dominated\"}]}"
	profile.quest_book["survey_any"] = QuestDefinition.parse("survey_any", text, {})
	survey.show_state()
	var targets: Dictionary[String, Vector2i] = QuestMarkerView.targets_of(driver.state, profile, 0)
	var marked: Dictionary[String, Vector2i] = survey.quest_targets.duplicate()
	var _dropped: bool = profile.quest_book.erase("survey_any")
	if not marked.has("survey_any") or marked != targets:
		return "the Survey doesn't mark the open quests' targets: %s" % [marked]
	var own: Entity = driver.state.player(0)
	if survey.players.keys() != [0] or survey.players[0] != own.tile:
		return "the Survey doesn't mark the player on their tile: %s" % [survey.players]
	return ""


## Why cycling the Survey doesn't lead through every place in turn, each followed, or zooming it
## isn't followed within its steps, or either isn't kept, or "".
func _survey_choice(choice: SurveyChoice, survey: SurveyView, path: String) -> String:
	choice.place()
	if choice.place_shown() != SurveyChoice.AUTO_PLACE:
		return "the Survey doesn't start at Auto"
	var problem: String = _survey_placed(choice, survey)
	var places: int = SurveyChoice.Place.size()
	var pressed: InputEventAction = InputEventAction.new()
	pressed.action = &"survey"
	pressed.pressed = true
	for step: int in places:
		# The first press goes through the input map's action, the rest straight to the choice.
		var cycled: String = choice.cycle() if step > 0 else ""
		if step == 0:
			survey.get_viewport().push_input(pressed)
		if problem.is_empty() and not cycled.is_empty():
			problem = "the Survey's place couldn't be saved: " + cycled
		if (problem.is_empty()
				and choice.place_shown() != posmod(SurveyChoice.AUTO_PLACE + step + 1, places)):
			problem = "cycling the Survey skipped a place"
		if problem.is_empty():
			problem = _survey_placed(choice, survey)
	for _step: int in SurveyChoice.ZOOMS.size():
		problem += choice.zoom_by(-1)
	var farthest: bool = survey.across == SurveyChoice.ZOOMS[0]
	problem += choice.zoom_by(1)
	var kept: Settings = Settings.load_from(path)
	if (problem.is_empty()
			and kept.chosen.get(SurveyChoice.PLACE_SETTING) != SurveyChoice.AUTO_PLACE):
		problem = "the Survey's place wasn't kept: %s" % [kept.chosen]
	var zoomed: bool = farthest and survey.across == SurveyChoice.ZOOMS[1]
	if problem.is_empty() and (kept.chosen.get(SurveyChoice.ZOOM_SETTING) != 1 or not zoomed):
		problem = "the Survey's zoom wasn't followed within its steps, or not kept"
	return problem


## Why the Survey isn't where its place says, or "": hidden when off, in its corner, or over the
## whole screen, see-through over the game and opaque otherwise.
func _survey_placed(choice: SurveyChoice, survey: SurveyView) -> String:
	return _survey_placed_in(choice, survey, survey.get_viewport_rect().size)


## Why the Survey, laid out for a screen of `screen` pixels, isn't where its place says, or "": a
## corner one sits against its own corner, a margin from both edges and wholly on the screen; a
## full one covers the screen exactly, opaque or see-through as its place says.
func _survey_placed_in(choice: SurveyChoice, survey: SurveyView, screen: Vector2) -> String:
	var place: SurveyChoice.Place = choice.place_shown()
	if place == SurveyChoice.Place.OFF:
		return "the Survey shows while off" if survey.visible else ""
	var rect: Rect2 = survey.get_rect()
	if not survey.visible or not Rect2(Vector2.ZERO, screen).encloses(rect):
		return "the Survey in place %d isn't wholly on a %s screen: %s" % [place, screen, rect]
	var full: bool = place in [SurveyChoice.Place.OVER_GAME, SurveyChoice.Place.OPAQUE]
	if survey.bordered == full:
		return "the Survey in place %d is laid out as the other kind of place" % place
	if full:
		var opaque: bool = place == SurveyChoice.Place.OPAQUE
		if rect != Rect2(Vector2.ZERO, screen) or (survey.backdrop.a == 1.0) != opaque:
			return "the full Survey on a %s screen isn't so, or not as see-through as its place" % [
				screen,
			]
		return ""
	return _survey_cornered(place, rect, screen)


## Why a corner Survey at `rect` isn't against its own corner of a `screen`, a margin from both of
## its edges, or "".
func _survey_cornered(place: SurveyChoice.Place, rect: Rect2, screen: Vector2) -> String:
	var left: bool = place in [SurveyChoice.Place.TOP_LEFT, SurveyChoice.Place.BOTTOM_LEFT]
	var top: bool = place in [SurveyChoice.Place.TOP_LEFT, SurveyChoice.Place.TOP_RIGHT]
	var gap: Vector2 = Vector2(
		rect.position.x if left else screen.x - rect.end.x,
		rect.position.y if top else screen.y - rect.end.y,
	)
	if not gap.is_equal_approx(Vector2.ONE * SurveyChoice.MARGIN):
		return "the Survey isn't against its corner %d on a %s screen: %s" % [place, screen, rect]
	return ""


## Why the Survey isn't placed right in every place on every kind of screen, desktop and phones
## held either way, or "".
func _survey_screens(choice: SurveyChoice, survey: SurveyView) -> String:
	var screens: Array[Vector2] = [
		Vector2(1152, 648),
		Vector2(1920, 1080),
		Vector2(720, 1600),
		Vector2(2400, 1080),
	]
	for screen: Vector2 in screens:
		for _place: int in SurveyChoice.Place.size():
			var _kept: String = choice.cycle()
			choice.place_in(screen)
			var problem: String = _survey_placed_in(choice, survey, screen)
			if not problem.is_empty():
				return problem
	choice.place()
	return ""


## Why the Survey doesn't follow every zoom step from far to close, or doesn't stop at either end,
## or "".
func _survey_zooms(choice: SurveyChoice, survey: SurveyView) -> String:
	var problem: String = ""
	for _step: int in SurveyChoice.ZOOMS.size() + 1:
		problem += choice.zoom_by(-1)
	choice.place()
	if problem.is_empty() and survey.across != SurveyChoice.ZOOMS.front():
		problem = "zooming out past the farthest step didn't stop there"
	for step: int in SurveyChoice.ZOOMS.size():
		choice.place()
		if problem.is_empty() and survey.across != SurveyChoice.ZOOMS[step]:
			problem = "the Survey's zoom step %d shows %s tiles across" % [step, survey.across]
		problem += choice.zoom_by(1)
	choice.place()
	if problem.is_empty() and survey.across != SurveyChoice.ZOOMS.back():
		problem = "zooming in past the closest step didn't stop there"
	return problem
