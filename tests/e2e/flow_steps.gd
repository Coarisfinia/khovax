class_name FlowSteps
extends RefCounted
## Helpers several e2e flows use (#246, AGENTS.md: shared, never copied): one tick's commands, a
## whole step on the grid, and a shortest walk. Not a flow itself: the runner runs only the
## `test_*.gd` files.


## One tick's commands with only the player in slot 0: `move`.
static func command(move: int) -> Array[Command]:
	var one: Array[Command] = [Command.new(move)]
	return one


## One tick's commands, one per slot, from each slot's move.
static func commands(moves: Array[int]) -> Array[Command]:
	var made: Array[Command] = []
	made.assign(moves.map(func(move: int) -> Command: return Command.new(move)))
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


## The directions of a shortest walk in `state` from `from` to `goal` over walkable tiles nobody
## but players stands on; empty when there's none.
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


## Whether a player can walk onto `tile`: walkable, and nothing but players stands there.
static func walkable_for_players(state: GameState, tile: Vector2i) -> bool:
	if not state.region.is_walkable(tile):
		return false
	for other: Entity in state.entities:
		if other.slot == Entity.NO_SLOT and other.tile == tile:
			return false
	return true
