extends RefCounted
## Survey flow (#301): the player looks at the Survey, the overview of the ground they explored, in
## the glade. It starts at Auto, in a corner; it shows exactly the tiles explored, each in its
## kind's color with its kind's symbol (#68), while ground still in the fog stays hidden; next
## door it shows exactly what was explored there, at its place in the world, and the exits on the
## tiles it shows, one chevron per exit in its middle (#790), loading nothing; it marks each
## instance shown that a faction holds with its holder's symbol, and its menu tab says who holds the
## glade (#637); it marks every player by slot
## and every open quest's target;
## its action cycles it through the corners, over the game, opaque and off, its zoom steps within
## their range, and both choices are kept. In every place, on desktop screens and phones held
## either way, it sits against its own corner or covers the whole screen; every zoom step is
## followed, and zooming stops at both ends. Its buttons hide behind a cogwheel on its top right
## corner, which hides while a controller is used (#438); a tap or a click on the cogwheel turns it
## and shows them beside it, on every screen, and a press or a click on each presses its action and
## moves the Survey like the key, without starting the touch stick (#352). A pinch on a corner
## Survey zooms it a step at a time, spreading the fingers closer and pinching them farther, and
## never starts the touch stick, which still starts anywhere else (#358). In the menu's Survey tab
## (#392) it shows the same ground,
## players and quest targets over the tab, and its zoom key, its buttons there and a pinch on it
## step the one zoom, which it follows; its place button there cycles where the Survey shows.

## Desktop screens and phones held either way.
const SCREENS: Array[Vector2] = [
	Vector2(1152, 648),
	Vector2(1920, 1080),
	Vector2(720, 1600),
	Vector2(2400, 1080),
]


func run(tree: SceneTree) -> String:
	# The glade: big enough that some of it is still in the fog at the start, for the Survey to
	# hide. The runner's own starting instance comes back after.
	var given: String = GameDriver.start_instance
	GameDriver.start_instance = InstanceBlueprints.GLADE
	var main: Node = (load(Boot.GAME) as PackedScene).instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame
	var result: String = await _check_survey(main)
	main.queue_free()
	GameDriver.start_instance = given
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
	if result.is_empty():
		result = await _survey_buttons(main, choice, survey)
	if result.is_empty():
		result = _survey_pinches(main, choice, survey)
	if result.is_empty():
		result = await _survey_in_menu(main, choice, survey)
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
		if known and survey.tiles[tile].color != look.color:
			return "the Survey colors %s unlike its kind" % tile
		if known and survey.tiles[tile].symbol != look.symbol:
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
	var there: Dictionary[Vector2i, bool] = _explore_next_door(
		driver,
		survey.keeper,
		region,
		target,
	)
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
		if there.has(tile) and survey.tiles[at].color != TileLooks.of(region.terrain[tile]).color:
			return "the Survey colors %s next door unlike its kind" % tile
	var exits: String = _survey_exits(driver.state.region, region, shift, survey)
	return exits if not exits.is_empty() else _survey_held(driver, survey)


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
## `there` next door, shifted by `shift`, and of the other instances next door (#689), or "".
func _survey_exits(here: Region, there: Region, shift: Vector2i, survey: SurveyView) -> String:
	var everywhere: Array[Vector3i] = []
	everywhere.append_array(here.exits)
	for exit: Vector3i in there.exits:
		everywhere.append(exit + Vector3i(shift.x, shift.y, 0))
	for other: String in survey.neighbours.shifts:
		var moved: Vector2i = survey.neighbours.shifts[other]
		for exit: Vector3i in survey.neighbours.region_of(other).exits:
			var placed: Vector3i = exit + Vector3i(moved.x, moved.y, 0)
			if moved != shift and not everywhere.has(placed):
				everywhere.append(placed)
	var shown: Array[Vector3i] = []
	for exit: Vector3i in everywhere:
		if survey.tiles.has(Vector2i(exit.x, exit.y)):
			shown.append(exit)
	var drawn: Array[Vector3i] = []
	drawn.assign(survey.exits.keys())
	drawn.sort()
	shown.sort()
	if shown.size() <= here.exits.size() or drawn != shown:
		return "the Survey doesn't show the exits here and next door on the tiles it shows: %s" % [
			survey.exits,
		]
	return _survey_exit_arrows(here, survey)


## Why an exit here, three tiles wide (#689), doesn't show exactly one chevron, on its middle tile
## (#790), or "".
func _survey_exit_arrows(here: Region, survey: SurveyView) -> String:
	for i: int in here.exits.size():
		var side: int = here.exits[i].z
		var tiles: Array[Vector2i] = []
		for j: int in here.exits.size():
			var same: bool = here.exit_blueprints[j] == here.exit_blueprints[i]
			if same and here.exits[j].z == side:
				tiles.append(Vector2i(here.exits[j].x, here.exits[j].y))
		var middle: Array[Vector2i] = []
		for tile: Vector2i in tiles:
			if tiles.all(func(other: Vector2i) -> bool: return Hex.distance(tile, other) <= 1):
				middle.append(tile)
		if tiles.size() != 3 or middle.size() != 1:
			return "the exit to %s here isn't three tiles in a row: %s" % [
				here.exit_blueprints[i],
				tiles,
			]
		var on: Array[Vector2] = []
		for arrow: SurveyExitArrow in survey.exit_arrows():
			if arrow.side == side and _near_any(arrow.at, tiles):
				on.append(arrow.at)
		if on.size() != 1 or not on[0].is_equal_approx(SurveyView.ground_of(middle[0])):
			return "the exit to %s shows chevrons at %s, not one on its middle tile %s" % [
				here.exit_blueprints[i],
				on,
				middle[0],
			]
	return ""


## Whether `ground` lies on one of `tiles` or between two of them.
func _near_any(ground: Vector2, tiles: Array[Vector2i]) -> bool:
	for tile: Vector2i in tiles:
		if ground.distance_to(SurveyView.ground_of(tile)) < HexLayout.SIZE * sqrt(3.0):
			return true
	return false


## Why the Survey's held marks (#637) don't follow the holder flags, or "". With every holder flag
## cleared, nothing is marked and it says nobody holds the instance the player is in. Once a flag
## says the Cartographer's Guild holds it, it's marked and said in words, by symbol and name. Once
## the guild holds the first instance next door too, if there is one, that one is marked in the
## middle of what shows of it. The world's holder flags are put back after, whichever start it had.
func _survey_held(driver: GameDriver, survey: SurveyView) -> String:
	var kept: Array[String] = _holder_flags(driver.world)
	for flag: String in kept:
		driver.world.set_flag(flag, false)
	var why: String = _held_marks_follow(driver, survey, survey.held_marks())
	for flag: String in _holder_flags(driver.world):
		driver.world.set_flag(flag, false)
	for flag: String in kept:
		driver.world.set_flag(flag)
	# Drawn again from the world as it was, so the later steps see what the menu's Survey sees.
	survey.show_state()
	survey.held_marks().show_state()
	return why


## Every holder flag (#637) `world` has.
func _holder_flags(world: World) -> Array[String]:
	var held: Array[String] = []
	for flag: String in world.flags:
		if flag.begins_with(Territory.FLAG_START):
			held.append(flag)
	return held


## Why the marks don't follow the flags `_survey_held` sets, or "".
func _held_marks_follow(driver: GameDriver, survey: SurveyView, marks: SurveyHeldMarks) -> String:
	var guild: String = "cartographers_guild"
	var here: String = driver.local_instance_name()
	survey.show_state()
	marks.show_state()
	if not marks.held_by.is_empty() or marks.here_text() != TerritoryText.NOT_HELD_TEXT:
		return "with no holder flags, the Survey still marks %s" % [marks.held_by]
	driver.world.set_flag(Territory.flag(here, guild))
	marks.show_state()
	if marks.held_by.get(here, "") != guild:
		return "the Survey doesn't mark the instance here once the guild holds it"
	if marks.here_text() != TerritoryText.HELD_TEXT % ["+", "Cartographer's Guild"]:
		return "the Survey says %s about the instance the guild holds" % marks.here_text()
	var next_door: Array[String] = []
	next_door.assign(survey.neighbours.shifts.keys())
	next_door.sort()
	if next_door.is_empty():
		return ""
	driver.world.set_flag(Territory.flag(next_door[0], guild))
	survey.show_state()
	marks.show_state()
	var shift: Vector2i = survey.neighbours.shifts[next_door[0]]
	var middle: Vector2 = Vector2.ZERO
	var shown: int = 0
	for tile: Vector2i in survey.tiles:
		if survey.neighbours.region_of(next_door[0]).has_tile(tile - shift):
			middle += survey.to_view(tile)
			shown += 1
	if marks.held_by.get(next_door[0], "") != guild:
		return "the Survey doesn't mark %s next door once the guild holds it" % next_door[0]
	if shown == 0 or not marks.held_at[next_door[0]].is_equal_approx(middle / shown):
		return "the Survey's mark of %s isn't in the middle of what shows of it" % next_door[0]
	return ""


## Why the Survey doesn't mark every player and the open quests' targets, or "".
func _survey_marks(driver: GameDriver, survey: SurveyView, profile: Profile) -> String:
	var text: String = "{\"id\": \"survey_any\", \"name\": \"Any\", "
	text += "\"steps\": [{\"condition\": \"dominated\", \"ends\": \"survey_any\"}]}"
	profile.quest_book["survey_any"] = QuestDefinition.parse("survey_any", text, {})
	survey.show_state()
	var targets: Dictionary[String, Vector2i] = QuestMarkerView.targets_of(driver.state, profile, 0)
	var marked: Dictionary[String, Vector2i] = survey.quest_targets.duplicate()
	var _dropped: bool = profile.quest_book.erase("survey_any")
	if not marked.has("survey_any") or marked != targets:
		return "the Survey doesn't mark the open quests' targets: %s" % [marked]
	var own: Entity = driver.state.player(0)
	var on_tile: bool = survey.circles.has(0) and survey.on_view(survey.circles[0]).is_equal_approx(
		survey.to_view(own.tile)
	)
	if survey.circles.keys() != [0] or not on_tile:
		return "the Survey doesn't mark the player on their tile: %s" % [survey.circles]
	return _survey_mark_glides(driver, survey)


## Why the player's mark, a tick into a step, doesn't sit on the way between the tile they walk
## from and the one they walk to, short of both, or "" (#354).
func _survey_mark_glides(driver: GameDriver, survey: SurveyView) -> String:
	var state: GameState = driver.state
	var from: Vector2i = state.player(0).tile
	var direction: int = -1
	for side: int in Hex.DIRECTIONS.size():
		if direction < 0 and FlowSteps.walkable_for_players(state, from + Hex.DIRECTIONS[side]):
			direction = side
	# Stepped by hand, so the driver's own ticks don't finish the step first.
	driver.set_process(false)
	Simulation.step(state, FlowSteps.command(direction))
	Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
	survey.show_state()
	var start: Vector2 = survey.to_view(from)
	var way: Vector2 = survey.to_view(state.player(0).tile) - start
	var mark: Vector2 = survey.on_view(survey.circles[0]) - start
	var share: float = mark.dot(way) / way.length_squared()
	driver.set_process(true)
	if share <= 0.0 or share >= 1.0 or not mark.is_equal_approx(way * share):
		return "the Survey's mark of a walking player isn't between their tiles: %s of the way" % [
			share,
		]
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
	for screen: Vector2 in SCREENS:
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


## Why the Survey's cogwheel (#438) doesn't hide exactly while a controller is used, or isn't
## placed right on every screen, or its buttons show before a tap on it, or a tap on it doesn't
## turn it and show them without starting the touch stick or a pinch, or a press on each doesn't
## press its action and move the Survey like its key, or a click doesn't press it too, or a click
## on the cogwheel doesn't hide them again, or "". The zoom is at its closest step here, so
## zooming out comes first.
func _survey_buttons(main: Node, choice: SurveyChoice, survey: SurveyView) -> String:
	var buttons: SurveyButtons = main.get_node("Hud/SurveyButtons") as SurveyButtons
	var stick: TouchStick = main.get_node("Hud/TouchStick") as TouchStick
	var viewport: Viewport = buttons.get_viewport()
	# A click lands only on the screen, and the headless one is tiny: a desktop screen's size.
	var window: Window = main.get_tree().root
	var kept_size: Vector2i = window.size
	window.size = Vector2i(SCREENS[0])
	await main.get_tree().process_frame
	var problem: String = _survey_cog_with_controller(buttons)
	if problem.is_empty():
		problem = _survey_buttons_placed(choice, survey, buttons)
	if problem.is_empty() and (buttons.open or buttons.buttons[&"survey"].visible):
		problem = "the Survey's buttons show before the cogwheel is tapped"
	var cog: Vector2 = buttons.cog_rect().get_center()
	_touch(viewport, cog, true)
	var held: bool = stick.is_held() or _pinching(main)
	_touch(viewport, cog, false)
	await main.get_tree().create_timer(SurveyButtons.TURN_SECONDS * 2.0).timeout
	buttons.lay_out()
	var turned: bool = is_equal_approx(buttons.cog_angle(), SurveyButtons.COG_TURN)
	if problem.is_empty() and (not buttons.open or held or not turned):
		problem = "a tap on the Survey's cogwheel didn't turn it and show its buttons alone"
	var actions: Array[StringName] = [&"survey_zoom_out", &"survey_zoom_in", &"survey"]
	for action: StringName in actions:
		if problem.is_empty():
			problem = _survey_button_pressed(buttons, stick, choice, action)
	if problem.is_empty():
		problem = _survey_button_clicked(buttons, choice)
	_click(viewport, buttons.cog_rect().get_center(), true)
	_click(viewport, buttons.cog_rect().get_center(), false)
	buttons.lay_out()
	if problem.is_empty() and (buttons.open or buttons.buttons[&"survey"].visible):
		problem = "a click on the Survey's cogwheel didn't hide its buttons"
	window.size = kept_size
	return problem


## Why the Survey's cogwheel shows while a controller is used, or doesn't show again on a touch,
## or "".
func _survey_cog_with_controller(buttons: SurveyButtons) -> String:
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.pressed = true
	buttons.get_viewport().push_input(pad)
	buttons.lay_out()
	var problem: String = "the Survey's cogwheel shows with a controller" if buttons.visible else ""
	_touch(buttons.get_viewport(), Vector2.ONE, true)
	_touch(buttons.get_viewport(), Vector2.ONE, false)
	buttons.lay_out()
	if problem.is_empty() and not buttons.visible:
		problem = "the Survey's cogwheel doesn't show again on a touch"
	return problem


## Whether the Survey's pinch holds a finger.
func _pinching(main: Node) -> bool:
	var pinch: SurveyPinch = main.get_node("Hud/SurveyPinch") as SurveyPinch
	var fingers: Dictionary = pinch.get("_fingers")
	return not fingers.is_empty()


## Why a touch on `action`'s button doesn't press its action alone, without the touch stick, and
## move the Survey's place or zoom like the key, or "".
func _survey_button_pressed(
		buttons: SurveyButtons,
		stick: TouchStick,
		choice: SurveyChoice,
		action: StringName,
) -> String:
	var place: int = choice.place_shown()
	var zoom: int = choice.zoom_step()
	buttons.lay_out()
	var at: Vector2 = buttons.rect_of(action).get_center()
	_touch(buttons.get_viewport(), at, true)
	var pressed: bool = Input.is_action_pressed(action) and not stick.is_held()
	_touch(buttons.get_viewport(), at, false)
	var expected: Vector2i = Vector2i(posmod(place + 1, SurveyChoice.Place.size()), zoom)
	if action != &"survey":
		expected = Vector2i(place, zoom + (1 if action == &"survey_zoom_in" else -1))
	var moved: bool = Vector2i(choice.place_shown(), choice.zoom_step()) == expected
	if not pressed or Input.is_action_pressed(action) or not moved:
		return "the Survey's %s button didn't press its action alone, or move it like its key" % [
			action,
		]
	return ""


## Why a mouse click on the button cycling where the Survey shows doesn't press its action until
## it's let go and cycle the Survey, or "".
func _survey_button_clicked(buttons: SurveyButtons, choice: SurveyChoice) -> String:
	var place: int = choice.place_shown()
	buttons.lay_out()
	var at: Vector2 = buttons.rect_of(&"survey").get_center()
	_click(buttons.get_viewport(), at, true)
	var pressed: bool = Input.is_action_pressed(&"survey")
	_click(buttons.get_viewport(), at, false)
	if not pressed or Input.is_action_pressed(&"survey"):
		return "a click on the Survey's button didn't press its action until let go"
	if choice.place_shown() != posmod(place + 1, SurveyChoice.Place.size()):
		return "a click on the Survey's button didn't cycle where it shows"
	return ""


## Why the Survey's cogwheel and buttons aren't wholly on every screen, in each place, with the
## cogwheel on a corner Survey that shows and the buttons clear of the cogwheel, or "".
func _survey_buttons_placed(
		choice: SurveyChoice,
		survey: SurveyView,
		buttons: SurveyButtons,
) -> String:
	var problem: String = ""
	for screen: Vector2 in SCREENS:
		for _place: int in SurveyChoice.Place.size():
			problem += choice.cycle()
			choice.place_in(screen)
			buttons.lay_out_in(screen)
			if problem.is_empty():
				problem = _survey_buttons_beside(survey, buttons, screen)
	choice.place()
	buttons.lay_out()
	return problem


## Why the Survey's cogwheel and buttons, laid out for a `screen`, aren't wholly on it, with the
## cogwheel on a corner Survey that shows and the buttons clear of the cogwheel, or "".
func _survey_buttons_beside(survey: SurveyView, buttons: SurveyButtons, screen: Vector2) -> String:
	var whole: Rect2 = Rect2(Vector2.ZERO, screen)
	var cog: Rect2 = buttons.cog_rect()
	var in_corner: bool = survey.visible and survey.bordered
	if not whole.encloses(cog) or (in_corner and not survey.get_rect().encloses(cog)):
		return "the Survey's cogwheel on a %s screen is at %s" % [screen, cog]
	for action: StringName in SurveyButtons.ACTIONS:
		var rect: Rect2 = buttons.rect_of(action)
		if not whole.encloses(rect) or rect.intersects(cog):
			return "the Survey's %s button on a %s screen is at %s" % [action, screen, rect]
	return ""


## Why a pinch on a corner Survey doesn't zoom it a step at a time, out on pinching the fingers
## together and in on spreading them, or starts the touch stick, or the stick doesn't start
## anywhere else, or "". The zoom is at its closest step here, so pinching in comes first.
func _survey_pinches(main: Node, choice: SurveyChoice, survey: SurveyView) -> String:
	var stick: TouchStick = main.get_node("Hud/TouchStick") as TouchStick
	var problem: String = ""
	while problem.is_empty() and not (survey.visible and survey.bordered):
		problem = choice.cycle()
	var zoom: int = choice.zoom_step()
	# Each pinch moves one finger a little first, too little for a step, then the other one far
	# enough for exactly one.
	var pinches: Array[PackedFloat32Array] = [
		PackedFloat32Array([0.22, 0.15, 0.12, -1.0]),
		PackedFloat32Array([0.15, 0.25, 0.22, 1.0]),
	]
	for pinch: PackedFloat32Array in pinches:
		if problem.is_empty():
			zoom += int(pinch[3])
			problem = _survey_pinched(survey, stick, pinch)
		if problem.is_empty() and choice.zoom_step() != zoom:
			problem = "a pinch on the Survey went to zoom step %d, not %d" % [
				choice.zoom_step(),
				zoom,
			]
	# The screen's corner across from the Survey's: the headless screen is small, so its middle
	# can be on the Survey.
	var screen: Vector2 = survey.get_viewport_rect().size
	var across: Vector2 = screen - survey.get_global_rect().get_center()
	var off: Vector2 = Vector2(
		1.0 if across.x < screen.x / 2.0 else screen.x - 1.0,
		1.0 if across.y < screen.y / 2.0 else screen.y - 1.0,
	)
	_touch(survey.get_viewport(), off, true)
	if problem.is_empty() and not stick.is_held():
		problem = "the touch stick didn't start off the Survey"
	_touch(survey.get_viewport(), off, false)
	return problem


## Why two fingers on the Survey, `pinch[0]` of its side from its middle each, moved to `pinch[1]`
## and `pinch[2]` and lifted, started the touch stick or left a zoom action pressed, or "".
func _survey_pinched(survey: SurveyView, stick: TouchStick, pinch: PackedFloat32Array) -> String:
	var viewport: Viewport = survey.get_viewport()
	var middle: Vector2 = survey.get_global_rect().get_center()
	var side: float = survey.size.x
	var apart: Vector2 = Vector2(pinch[0] * side, 0.0)
	var fingers: Array[Vector2] = [middle - apart, middle + apart]
	for finger: int in fingers.size():
		_touch(viewport, fingers[finger], true, finger)
	_drag(viewport, middle + Vector2(pinch[1] * side, 0.0), 1)
	_drag(viewport, middle - Vector2(pinch[2] * side, 0.0), 0)
	var held: bool = stick.is_held()
	for finger: int in fingers.size():
		_touch(viewport, fingers[finger], false, finger)
	var zooming: bool = Input.is_action_pressed(&"survey_zoom_in")
	if held or zooming or Input.is_action_pressed(&"survey_zoom_out"):
		return "a pinch on the Survey started the touch stick, or left a zoom action pressed"
	return ""


## Why the menu's Survey tab (#392) doesn't show what the Survey shows, over the tab, with a line
## saying the Cartographer's Guild holds the glade, where the player starts (#637, #712), or its
## zoom key, its buttons or a pinch on it don't step the one zoom it follows, or "".
func _survey_in_menu(main: Node, choice: SurveyChoice, survey: SurveyView) -> String:
	var menu: GameMenu = main.get_node("Hud/GameMenu") as GameMenu
	var tab: SurveyTab = menu.survey_tab
	# Laid out in its scene (#437): the Survey over the tab, its buttons centred in a row below it.
	if (tab.get_child(0) != tab.view
			or (tab.get_node("Row") as HBoxContainer).alignment != BoxContainer.ALIGNMENT_CENTER):
		return "the Survey tab's scene doesn't put its Survey above its centred row of buttons"
	menu.toggle()
	(tab.get_parent() as TabContainer).current_tab = tab.get_index()
	var problem: String = choice.zoom_by(SurveyChoice.AUTO_ZOOM - choice.zoom_step())
	# The headless window is too small for the tab to lay its Survey out: a desktop screen's size.
	var window: Window = main.get_tree().root
	var kept_size: Vector2i = window.size
	window.size = Vector2i(SCREENS[0])
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	survey.show_state()
	tab.view.show_state()
	var same: bool = (tab.view.tiles.keys() == survey.tiles.keys()
			and tab.view.circles.keys() == survey.circles.keys()
			and tab.view.quest_targets == survey.quest_targets
			and tab.held_text.text == TerritoryText.HELD_TEXT % ["+", "Cartographer's Guild"])
	if problem.is_empty() and (not same or tab.view.size.y < tab.size.y / 2.0):
		problem = "the menu's Survey doesn't show what the Survey shows, over the tab"
	var key: InputEventAction = InputEventAction.new()
	key.action = &"survey_zoom_in"
	key.pressed = true
	tab.get_viewport().push_input(key)
	problem += _survey_zoomed_to(choice, "key", SurveyChoice.AUTO_ZOOM + 1)
	(tab.find_child("ZoomIn", true, false) as Button).pressed.emit()
	problem += _survey_zoomed_to(choice, "Zoom in button", SurveyChoice.AUTO_ZOOM + 2)
	(tab.find_child("ZoomOut", true, false) as Button).pressed.emit()
	problem += _survey_zoomed_to(choice, "Zoom out button", SurveyChoice.AUTO_ZOOM + 1)
	var place: int = choice.place_shown()
	tab.place_button.pressed.emit()
	if problem.is_empty() and choice.place_shown() != posmod(place + 1, SurveyChoice.Place.size()):
		problem = "the menu's Survey place button didn't cycle where the Survey shows"
	if problem.is_empty():
		# Spread far enough for exactly one step closer, as on the corner Survey.
		var spread: PackedFloat32Array = PackedFloat32Array([0.15, 0.25, 0.22])
		var stick: TouchStick = main.get_node("Hud/TouchStick") as TouchStick
		problem = _survey_pinched(tab.view, stick, spread)
	problem += _survey_zoomed_to(choice, "pinch", SurveyChoice.AUTO_ZOOM + 2)
	await main.get_tree().process_frame
	if problem.is_empty() and tab.view.across != SurveyChoice.ZOOMS[choice.zoom_step()]:
		problem = "the menu's Survey doesn't follow the zoom"
	menu.toggle()
	window.size = kept_size
	return problem


## Why the menu's Survey `how` didn't step the zoom to `step`, or "".
func _survey_zoomed_to(choice: SurveyChoice, how: String, step: int) -> String:
	if choice.zoom_step() == step:
		return ""
	return "the menu's Survey %s went to zoom step %d, not %d. " % [how, choice.zoom_step(), step]


## Touches `at` with `finger` (the first one unless named), or lifts it there.
func _touch(viewport: Viewport, at: Vector2, down: bool, finger: int = 0) -> void:
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.index = finger
	touch.position = at
	touch.pressed = down
	viewport.push_input(touch)


## Presses the mouse's left button at `at` (`down`), or lets it go there.
func _click(viewport: Viewport, at: Vector2, down: bool) -> void:
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = at
	click.pressed = down
	viewport.push_input(click)


## Drags `finger` to `at`.
func _drag(viewport: Viewport, at: Vector2, finger: int) -> void:
	var drag: InputEventScreenDrag = InputEventScreenDrag.new()
	drag.index = finger
	drag.position = at
	viewport.push_input(drag)
