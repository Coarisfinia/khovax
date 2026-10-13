class_name Instances
extends RefCounted
## Instance definitions: a map, the players' starts and the features an instance has, in their
## step order. An instance switches game rules on and off by listing them, and they can change
## during a run.

const BASIC: String = "basic"
## Where the basic instance's players start, by slot.
const BASIC_STARTS: Array[Vector2i] = [
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
]


## Whether an instance of this name exists.
static func exists(instance_name: String) -> bool:
	return instance_name == BASIC


## A new state for the named instance with `players` players in slots 0 and up, or null (with an
## error) for an unknown name, a player count out of range or an invalid feature order.
static func create(instance_name: String, seed_value: int, players: int = 1) -> GameState:
	if not exists(instance_name):
		push_error("unknown instance: " + instance_name)
		return null
	var state: GameState = basic(seed_value, players)
	if state == null:
		return null
	if not state.problem.is_empty():
		push_error("instance %s has an invalid feature order: %s" % [instance_name, state.problem])
		return null
	return state


## The current playground: a disc of radius 3, walking, and a trail per player. Null (with an
## error) for a player count out of range.
static func basic(seed_value: int, players: int = 1) -> GameState:
	if players < 1 or players > GameState.MAX_PLAYERS:
		push_error("an instance takes 1 to %d players, not %d" % [GameState.MAX_PLAYERS, players])
		return null
	var ordered: Array[Feature] = [MovementFeature.new(), TrailFeature.new()]
	var state: GameState = GameState.new(3, seed_value, ordered)
	for slot: int in players:
		# Can't be refused: the count is checked above and every slot is new.
		var _player: Entity = state.add_entity(slot, BASIC_STARTS[slot])
	return state
