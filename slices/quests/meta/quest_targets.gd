class_name QuestTargets
extends RefCounted
## Where a player's open quests point (#300): the nearest wild monster of the species a domination
## step names (any, when it names none), or the one quest target it names (#625), the nearest
## closed treasure chest, the nearest tile of the place a reached step names (#339) or of the
## region piece an entered step names (#350), or the nearest exit leading to the instance it names
## (#370), or that the step counts in while the player is elsewhere (#769). A wild monster still
## hiding in its tile (#202) isn't pointed at, since that would give it away. The quest markers
## and the Survey both show these; it only reads the state and the profile.


## The tile each of `profile`'s open quests points at in `state`, by quest id, measured from the
## player in `slot`; a quest with nothing to point at here isn't listed. A step with choices (#573)
## points at each of them that's here, by the quest's id, a slash and the choice's index. `here` is
## the blueprint name of the instance `state` is (#769), or "" when it isn't known: a step that
## counts in another instance, or in one when it isn't known which this is, points at the exits
## leading there.
static func of(
	state: GameState,
	profile: Profile,
	slot: int,
	here: String = "",
) -> Dictionary[String, Vector2i]:
	var targets: Dictionary[String, Vector2i] = {}
	var player: Entity = state.player(slot)
	if player == null:
		return targets
	var steps: Dictionary[String, QuestStep] = profile.open_steps()
	for id: String in steps:
		var triggers: Array[QuestStep] = steps[id].triggers()
		for index: int in triggers.size():
			var candidates: Array[Vector2i] = _candidates(state, triggers[index], here)
			var key: String = id if steps[id].choices.is_empty() else "%s/%d" % [id, index]
			if not candidates.is_empty():
				targets[key] = _nearest(candidates, player.tile)
	return targets


## The tiles `step` could be met at in `state`: wild monsters of its species, or its quest target
## (#625), that aren't hiding, in id order, the closed chests, the tiles of its place, in the
## legend's order, the tiles of
## its piece, or the exits leading to its instance, also when it counts there and `state` is
## another instance, `here`.
static func _candidates(state: GameState, step: QuestStep, here: String) -> Array[Vector2i]:
	var elsewhere: bool = not step.instance.is_empty() and step.instance != here
	if step.enters_instance() or elsewhere:
		return _exits_to(state, step.instance)
	if step.condition == QuestStep.ENTERED:
		return _piece_tiles(state, step.piece)
	var tiles: Array[Vector2i] = []
	if step.condition == QuestStep.REACHED:
		for trigger: TileTrigger in state.region.triggers:
			if trigger.action == TileTrigger.REACH and trigger.place == step.place:
				tiles.append(trigger.tile)
		return tiles
	if step.condition == QuestStep.OPENED:
		var chests: ChestFeature = state.feature(ChestFeature.ID) as ChestFeature
		if chests != null:
			tiles.assign(chests.chests)
		return tiles
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	if wild == null or step.condition != QuestStep.DOMINATED:
		return tiles
	var hiding: HidingFeature = state.feature(HidingFeature.ID) as HidingFeature
	var ids: Array[int] = wild.monsters.duplicate()
	ids.sort()
	for entity_id: int in ids:
		var entity: Entity = state.entity(entity_id)
		var hidden: bool = hiding != null and hiding.is_hidden(entity_id)
		var target: String = WildSpot.target_in(wild.marks, entity_id)
		var fits: bool = step.quarry.fits(wild.species_of(entity_id), target)
		if entity != null and fits and not hidden:
			tiles.append(entity.tile)
	return tiles


## The tiles of the exits in `state` leading to the instance `instance_name`.
static func _exits_to(state: GameState, instance_name: String) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for i: int in state.region.exits.size():
		if state.region.exit_blueprints[i] == instance_name:
			tiles.append(Vector2i(state.region.exits[i].x, state.region.exits[i].y))
	return tiles


## The tiles of the region piece `piece` in `state`.
static func _piece_tiles(state: GameState, piece: String) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for tile: Vector2i in state.region.piece_of:
		if state.region.piece_of[tile] == piece:
			tiles.append(tile)
	return tiles


## The tile of `tiles` nearest to `from`; the first one on a tie.
static func _nearest(tiles: Array[Vector2i], from: Vector2i) -> Vector2i:
	var best: Vector2i = tiles[0]
	for tile: Vector2i in tiles:
		if Hex.distance(tile, from) < Hex.distance(best, from):
			best = tile
	return best
