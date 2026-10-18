class_name FlowSteps
extends RefCounted
## Helpers several e2e flows use (#246, AGENTS.md: shared, never copied): one tick's commands, a
## whole step on the grid, and a shortest walk. Not a flow itself: the runner runs only the
## `test_*.gd` files.

## The six tiles around the basic instance's wild monster, walked in a ring from the player's start
## at (1, -1).
const BASIC_RING: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(-1, -1),
	Vector2i(-2, -1),
	Vector2i(-3, 0),
	Vector2i(-3, 1),
	Vector2i(-2, 1),
	Vector2i(-1, 0),
]
## Where the basic instance's wounded moss toad waits on the beach (#448).
const BEACH_TOAD: Vector2i = Vector2i(-3, 2)


## Takes the beach's wounded toad out of `state`, for flows whose walks cross the beach and aren't
## about it: it stands in their way and steps about.
static func drop_beach_toad(state: GameState) -> void:
	var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	for entity_id: int in wild.monsters.duplicate():
		if state.entity(entity_id).tile == BEACH_TOAD:
			state.remove_entity(entity_id)


## The tiles player 0 sees in `state`.
static func sight_of(state: GameState) -> Array[Vector2i]:
	var seen: Array[Vector2i] = []
	seen.assign((state.feature(Features.FOG) as FogFeature).visible[0])
	return seen


## One tick's commands with only the player in slot 0: `move`.
static func command(move: int) -> Array[Command]:
	var one: Array[Command] = [Command.new(move)]
	return one


## One tick's commands, one per slot, from each slot's move.
static func commands(moves: Array[int]) -> Array[Command]:
	var made: Array[Command] = []
	made.assign(moves.map(func(move: int) -> Command: return Command.new(move)))
	return made


## One tick's commands for `slots` players standing still, the one in `slot` placing their totem
## (#423).
static func totem(slot: int = 0, slots: int = 1) -> Array[Command]:
	var placing: Command = Command.new(Command.NO_MOVE, false, Command.PLACE_TOTEM)
	var standing: Command = Command.new()
	var made: Array[Command] = []
	for each: int in slots:
		made.append(placing if each == slot else standing)
	return made


## Walks the player in slot 0 one whole step in `direction` while the other `slots` - 1 players
## stand still; returns every event raised on the way.
static func step(state: GameState, direction: int, slots: int = 1) -> Array[RefCounted]:
	var events: Array[RefCounted] = []
	for tick: int in MovementFeature.MOVE_TICKS:
		var moves: Array[int] = [direction if tick == 0 else Command.NO_MOVE]
		for _other: int in slots - 1:
			moves.append(Command.NO_MOVE)
		Simulation.step(state, commands(moves))
		events.append_array(state.events)
	return events


## Walks the player in slot 0 along `path`, one tile after another, each a neighbour of the one
## before; returns every event raised on the way.
static func walk(state: GameState, path: Array[Vector2i]) -> Array[RefCounted]:
	var events: Array[RefCounted] = []
	for next: Vector2i in path:
		events.append_array(step(state, Hex.DIRECTIONS.find(next - state.player(0).tile)))
	return events


## The directions of a shortest walk in `state` from `from` to `goal` over walkable tiles nothing
## that doesn't walk stands on; empty when there's none.
static func shortest_path(state: GameState, from: Vector2i, goal: Vector2i) -> Array[int]:
	var came: Dictionary[Vector2i, int] = { from: -1 }
	var open: Array[Vector2i] = [from]
	while not open.is_empty() and not came.has(goal):
		var current: Vector2i = open.pop_front()
		for direction: int in Hex.DIRECTIONS.size():
			var next: Vector2i = current + Hex.DIRECTIONS[direction]
			if not came.has(next) and walkable_for_players(state, next):
				came[next] = direction
				open.append(next)
	var directions: Array[int] = []
	var tile: Vector2i = goal
	while came.has(goal) and tile != from:
		directions.push_front(came[tile])
		tile -= Hex.DIRECTIONS[came[tile]]
	return directions


## Whether a player can walk onto `tile`: walkable, and nothing that doesn't walk stands there.
static func walkable_for_players(state: GameState, tile: Vector2i) -> bool:
	var movement: MovementFeature = state.feature(Features.MOVEMENT) as MovementFeature
	return state.region.is_walkable(tile) and not movement.is_occupied(state, tile)
