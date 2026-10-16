extends RefCounted
## Fog flow (#65): what each player sees is simulation state. Hex lines step tile by tile, rock
## blocks sight and is seen itself, water doesn't block it, sight ends at the radius, it follows a
## player who walks, it's in the state hash, and a player who leaves loses it. An event reveals an
## area to every player (#177): only tiles of the region, each once, in the state hash. The glade's
## lookout (#181) reveals the area around it the first time a player steps onto it, once.

const START: Vector2i = Vector2i(1, -1)
const WEST: int = 3


func run(_tree: SceneTree) -> String:
	var result: String = _check_hex_lines()
	if result.is_empty():
		result = _check_sight()
	if result.is_empty():
		result = _check_fog_follows()
	if result.is_empty():
		result = _check_reveal()
	if result.is_empty():
		result = _check_lookout()
	return result


## Hex.line: from one end to the other in single steps, one tile per step, the same both ways round
## for a straight line along a direction.
func _check_hex_lines() -> String:
	for tile: Vector2i in Hex.disc(4):
		var path: Array[Vector2i] = Hex.line(Vector2i.ZERO, tile)
		if path.size() != Hex.distance(Vector2i.ZERO, tile) + 1 or path[-1] != tile:
			return "the line to %s is %s" % [tile, path]
		for i: int in range(1, path.size()):
			if Hex.distance(path[i - 1], path[i]) != 1:
				return "the line to %s jumps: %s" % [tile, path]
	var straight: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, -1), Vector2i(2, -2)]
	if Hex.line(Vector2i.ZERO, Vector2i(2, -2)) != straight:
		return "a line along a direction left it: %s" % [Hex.line(Vector2i.ZERO, Vector2i(2, -2))]
	return ""


## Sight (#65): rock blocks it and is seen itself, water doesn't, and it ends at the radius.
func _check_sight() -> String:
	var rock: Region = RegionFormat.parse("origin 0 0
1 . ^ . .")
	var seen: Array[Vector2i] = FogFeature.sight(rock, Vector2i.ZERO, FogFeature.SIGHT_RADIUS)
	if not seen.has(Vector2i(2, 0)) or seen.has(Vector2i(3, 0)) or seen.has(Vector2i(4, 0)):
		return "rock didn't block sight, or wasn't seen itself: %s" % [seen]
	var water: Region = RegionFormat.parse("origin 0 0
1 . ~ . .")
	if not FogFeature.sight(water, Vector2i.ZERO, FogFeature.SIGHT_RADIUS).has(Vector2i(4, 0)):
		return "water blocked sight"
	var wide: Region = Region.disc(FogFeature.SIGHT_RADIUS + 1)
	var far: Array[Vector2i] = FogFeature.sight(wide, Vector2i.ZERO, FogFeature.SIGHT_RADIUS)
	if far.size() != Hex.disc(FogFeature.SIGHT_RADIUS).size():
		return "an open region showed %d tiles within the sight radius" % far.size()
	return ""


## In a session, each player's sight follows them as they walk, and it's in the state hash.
func _check_fog_follows() -> String:
	var ordered: Array[Feature] = [MovementFeature.new(), FogFeature.new()]
	var region: Region = Region.disc(2 * FogFeature.SIGHT_RADIUS)
	var state: GameState = GameState.new(region, 1, ordered)
	var _player: Entity = state.add_entity(0, START)
	var fog: FogFeature = state.feature(Features.FOG) as FogFeature
	# Just out of sight to the west, until the player walks two tiles towards it.
	var west: Vector2i = START + Hex.DIRECTIONS[WEST] * (FogFeature.SIGHT_RADIUS + 2)
	if not fog.sees(0, START) or fog.sees(1, START) or fog.sees(0, west):
		return "the player doesn't see where they stand, sees too far, or a missing player sees"
	var before: Array = fog.visible[0].duplicate()
	_walk_west(state, 2)
	if not fog.sees(0, west) or not fog.sees(0, _tile(state)):
		return "the player's sight didn't follow them"
	var hashed: int = state.state_hash()
	fog.visible[0] = before
	if state.state_hash() == hashed:
		return "the state hash doesn't see a change in sight"
	state.remove_entity(state.player(0).id)
	if fog.visible.has(0):
		return "a player who left kept their sight"
	return ""


## An event reveals an area to every player: tiles of the region only, each once, sorted, in the
## state hash; nothing revealed leaves the hash as it was.
func _check_reveal() -> String:
	var ordered: Array[Feature] = [MovementFeature.new(), FogFeature.new()]
	var state: GameState = GameState.new(Region.disc(2), 2, ordered)
	var _player: Entity = state.add_entity(0, START)
	var fog: FogFeature = state.feature(Features.FOG) as FogFeature
	var before: int = state.state_hash()
	var area: Array[Vector2i] = [Vector2i(2, 0), Vector2i(0, 0), Vector2i(9, 9), Vector2i(2, 0)]
	fog.reveal(state, area)
	var expected: Array[Vector2i] = [Vector2i(0, 0), Vector2i(2, 0)]
	if fog.revealed != expected:
		return "the reveal kept %s, not the region's tiles once each" % [fog.revealed]
	if state.state_hash() == before:
		return "the state hash doesn't see a reveal"
	fog.revealed.clear()
	if state.state_hash() != before:
		return "nothing revealed changed the state hash"
	return ""


## A player stepping onto the glade's lookout reveals the region within its radius, in a tick, once.
func _check_lookout() -> String:
	var state: GameState = InstanceBlueprints.create(InstanceBlueprints.GLADE, 7, 1)
	if state.region.triggers.is_empty() or state.feature(Features.TRIGGERS) == null:
		return "the glade has no lookout"
	var lookout: TileTrigger = state.region.triggers[0]
	var fog: FogFeature = state.feature(Features.FOG) as FogFeature
	state.player(0).tile = lookout.tile
	Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
	var far: Vector2i = lookout.tile + Hex.DIRECTIONS[WEST] * lookout.amount
	var near_edge: bool = not state.region.has_tile(far) or fog.revealed.has(far)
	if fog.revealed.is_empty() or not near_edge:
		return "stepping onto the lookout didn't reveal the area around it"
	var hashed: int = state.state_hash()
	fog.revealed.clear()
	Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
	if not fog.revealed.is_empty() or state.state_hash() == hashed:
		return "a lookout revealed twice"
	return ""


## Walks player 0 `moves` tiles west, waiting for each move to arrive.
func _walk_west(state: GameState, moves: int) -> void:
	var movement: MovementFeature = state.feature(Features.MOVEMENT) as MovementFeature
	for _move: int in moves:
		Simulation.step(state, FlowSteps.command(WEST))
		while movement.walk(state.player(0).id).is_moving():
			Simulation.step(state, FlowSteps.command(Command.NO_MOVE))


func _tile(state: GameState) -> Vector2i:
	return state.player(0).tile
