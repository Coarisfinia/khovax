extends RefCounted
## Fog flow (#65): what each player sees is simulation state. Hex lines step tile by tile, rock
## blocks sight and is seen itself, water doesn't block it, sight ends at the radius, it follows a
## player who walks, it's in the state hash, and a player who leaves loses it.

const START: Vector2i = Vector2i(1, -1)
const WEST: int = 3


func run(_tree: SceneTree) -> String:
	var result: String = _check_hex_lines()
	if result.is_empty():
		result = _check_sight()
	if result.is_empty():
		result = _check_fog_follows()
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
	var rock: Region = Region.parse("origin 0 0
1 . ^ . .")
	var seen: Array[Vector2i] = FogFeature.sight(rock, Vector2i.ZERO, FogFeature.SIGHT_RADIUS)
	if not seen.has(Vector2i(2, 0)) or seen.has(Vector2i(3, 0)) or seen.has(Vector2i(4, 0)):
		return "rock didn't block sight, or wasn't seen itself: %s" % [seen]
	var water: Region = Region.parse("origin 0 0
1 . ~ . .")
	if not FogFeature.sight(water, Vector2i.ZERO, FogFeature.SIGHT_RADIUS).has(Vector2i(4, 0)):
		return "water blocked sight"
	var wide: Region = Region.disc(FogFeature.SIGHT_RADIUS + 1)
	var far: Array[Vector2i] = FogFeature.sight(wide, Vector2i.ZERO, FogFeature.SIGHT_RADIUS)
	if far.size() != Hex.disc(FogFeature.SIGHT_RADIUS).size():
		return "an open region showed %d tiles within the sight radius" % far.size()
	return ""


## In a run, each player's sight follows them as they walk, and it's in the state hash.
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


## Walks player 0 `moves` tiles west, waiting for each move to arrive.
func _walk_west(state: GameState, moves: int) -> void:
	var movement: MovementFeature = state.feature(Features.MOVEMENT) as MovementFeature
	for _move: int in moves:
		Simulation.step(state, _commands(WEST))
		while movement.walk(state.player(0).id).is_moving():
			Simulation.step(state, _commands(Command.NO_MOVE))


func _commands(move: int) -> Array[Command]:
	var commands: Array[Command] = [Command.new(move)]
	return commands


func _tile(state: GameState) -> Vector2i:
	return state.player(0).tile
