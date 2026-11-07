class_name SurveyChanges
extends RefCounted
## What a SurveyView last worked out its ground from and last drew (#2096), so it works its ground
## out anew and is drawn again only when that changed, never on every frame: the ground it shows
## grows with what was explored here and next door, and going through it all each frame was the
## frame's largest share. Also how often it did either, which tests count across frames where
## nothing it shows changes.

var rebuilds: int = 0
var redraws: int = 0
## The region it showed last: in another one the middle starts on this machine's player.
var region: Region
## What its ground was last worked out from, and what it last drew.
var _ground: Array = []
var _drawn: Array = []


## Whether what `survey`'s ground (its tiles, which block the way, its exits) is worked out from
## changed since it was last: notes it as worked out.
func ground_changed(survey: SurveyView) -> bool:
	var now: Array = ground_of(survey)
	if now == _ground:
		return false
	_ground = now
	rebuilds += 1
	return true


## Whether `drawn`, everything a Survey draws from, differs from what it drew last: notes it as
## drawn.
func drawn_changed(drawn: Array) -> bool:
	if drawn == _drawn:
		return false
	_drawn = drawn
	redraws += 1
	return true


## Everything `survey`'s ground is worked out from, to compare: the instance and its region, which
## tiles each player sees (FogFeature hands a new array whenever a player's sight changes), which
## are revealed and which changed in place, the ground next door and its neighbours, and how much
## this machine's player explored here and next door, which only grows within a generation.
static func ground_of(survey: SurveyView) -> Array:
	var driver: Session = survey.driver
	if driver == null or driver.state == null:
		return [null]
	var state: GameState = driver.state
	var here: String = driver.local_instance_name()
	var key: Array = [state, state.region, driver.world, here, state.next_door_version]
	var fog: FogFeature = state.feature(FogFeature.ID) as FogFeature
	if fog != null:
		key.append_array([fog.enabled, fog.visible.duplicate(), fog.revealed.duplicate()])
	for tile: Vector2i in state.changed_tiles:
		key.append_array([tile, state.region.terrain.get(tile, "")])
	if survey.neighbours != null:
		survey.neighbours.show_state()
		key.append(survey.neighbours.rebuilds)
	if survey.keeper != null and driver.world != null:
		var explored: ExploredGround = survey.keeper.explored_in(driver.world)
		key.append(explored)
		var names: Array[String] = [here]
		names.append_array(state.region.exit_blueprints)
		for instance_name: String in names:
			var generation: int = driver.world.generation(instance_name)
			key.append_array([generation, explored.seen(instance_name, generation).size()])
	return key
