extends RefCounted
## Survey flow (#301): the player looks at the Survey, the overview of the ground they explored. It
## starts at Auto, in a corner; it shows exactly the tiles explored, each in its kind's color, while
## ground still in the fog stays hidden; it marks every player by slot and every open quest's
## target; its action cycles it through the corners, over the game, opaque and off, its zoom steps
## within their range, and both choices are kept.


func run(tree: SceneTree) -> String:
	var main: Node = (load(Boot.GAME) as PackedScene).instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame
	var result: String = _check_survey(main)
	main.queue_free()
	await tree.process_frame
	return result


## The Survey (#301) starts at Auto, in a corner; it shows exactly the tiles explored, seen now or
## revealed, each in its kind's color, while ground still in the fog stays hidden; it marks every
## player by slot and every open quest's target; its action cycles it through the corners, over the
## game, opaque and off, its zoom steps within their range, and both choices are kept.
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
		result = _survey_marks(driver, survey, FlowGame.holder(main).keeper.profile)
	if result.is_empty():
		result = _survey_choice(choice, survey, path)
	SaveStore.remove(path)
	graphics.settings_path = kept_path
	graphics.settings.chosen = kept
	return result


## Why the Survey's tiles aren't exactly the explored ones in their kinds' colors, or "".
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
		var color: Color = TileLooks.of(state.region.terrain[tile]).color
		if known and survey.tiles[tile] != color:
			return "the Survey colors %s unlike its kind" % tile
		if known and survey.blocking.has(tile) == state.region.is_walkable(tile):
			return "the Survey doesn't ring %s in ink exactly when it blocks the way" % tile
		hidden += 0 if known else 1
	if hidden == 0:
		return "nothing of the instance was still in the fog to hide on the Survey"
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
	var place: SurveyChoice.Place = choice.place_shown()
	var screen: Vector2 = survey.get_viewport_rect().size
	if place == SurveyChoice.Place.OFF:
		return "the Survey shows while off" if survey.visible else ""
	var corners: Dictionary[SurveyChoice.Place, Vector2] = {
		SurveyChoice.Place.TOP_LEFT: Vector2.ZERO,
		SurveyChoice.Place.TOP_RIGHT: Vector2(screen.x, 0.0),
		SurveyChoice.Place.BOTTOM_LEFT: Vector2(0.0, screen.y),
		SurveyChoice.Place.BOTTOM_RIGHT: screen,
	}
	var middle: Vector2 = survey.position + survey.size / 2.0
	if corners.has(place):
		var half: Vector2 = screen / 2.0
		var nearest: bool = (middle - half).sign() == (corners[place] - half).sign()
		if not survey.visible or not survey.bordered or not nearest:
			return "the Survey isn't in its corner %d: %s" % [place, survey.get_rect()]
		return ""
	var opaque: bool = place == SurveyChoice.Place.OPAQUE
	if survey.get_rect() != Rect2(Vector2.ZERO, screen) or (survey.backdrop.a == 1.0) != opaque:
		return "the Survey over the whole screen isn't so, or not as see-through as its place"
	return ""
