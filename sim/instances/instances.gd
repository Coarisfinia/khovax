class_name Instances
extends RefCounted
## Instance definitions: a map (a map file or a generator with its parameters), and the features
## an instance has, in their step order. The players start on the map's starts. An instance
## switches game rules on and off by listing them, and they can change during a run.

## The playground: the hand-made map maps/basic.map, walking, and a trail per player.
const BASIC: String = "basic"
## A generated island, different for every seed (#36).
const WILDS: String = "wilds"
const NAMES: Array[String] = [BASIC, WILDS]
const MAPS: String = "res://maps/"
## The wilds' island: tiles, and rocks scattered over it.
const WILDS_SIZE: int = 60
const WILDS_ROCKS: int = 10


## Whether an instance of this name exists.
static func exists(instance_name: String) -> bool:
	return NAMES.has(instance_name)


## A new state for the named instance with `players` players in slots 0 and up, or null (with an
## error) for an unknown name, an unreadable map, more players than the map has starts, or an
## invalid feature order.
static func create(instance_name: String, seed_value: int, players: int = 1) -> GameState:
	if not exists(instance_name):
		push_error("unknown instance: " + instance_name)
		return null
	var map: HexMap = _map(instance_name, seed_value)
	if not map.problem.is_empty():
		push_error("instance %s has a broken map: %s" % [instance_name, map.problem])
		return null
	if players < 1 or players > map.starts.size():
		push_error("instance %s takes 1 to %d players, not %d" % [instance_name, map.starts.size(), players])
		return null
	var ordered: Array[Feature] = [MovementFeature.new(), TrailFeature.new()]
	var state: GameState = GameState.new(map, seed_value, ordered)
	if not state.problem.is_empty():
		push_error("instance %s has an invalid feature order: %s" % [instance_name, state.problem])
		return null
	for slot: int in players:
		# Can't be refused: the count is checked above and every slot is new.
		var _player: Entity = state.add_entity(slot, map.starts[slot])
	return state


## The basic instance, as `create` makes it.
static func basic(seed_value: int, players: int = 1) -> GameState:
	return create(BASIC, seed_value, players)


## The instance's map: read from its map file, or generated from the seed.
static func _map(instance_name: String, seed_value: int) -> HexMap:
	if instance_name == WILDS:
		return MapGenerator.island(seed_value, WILDS_SIZE, WILDS_ROCKS)
	return HexMap.parse(FileAccess.get_file_as_string(MAPS + instance_name + ".map"))
