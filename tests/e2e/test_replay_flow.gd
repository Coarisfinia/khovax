extends RefCounted
## Replay flow: the simulation alone, without scenes, input or frames. The same start and the same
## commands must always give the same state, tick for tick; that is what makes replays and
## lockstep co-op possible. Also checks the movement rules in whole ticks.

const START: Vector2i = Vector2i(1, -1)
const RADIUS: int = 3
const EAST: int = 0
## Long enough for the scripted commands to walk around the grid several times.
const REPLAY_TICKS: int = 600


func run(_tree: SceneTree) -> String:
	var steps: Array[Callable] = [
		_check_move_timing,
		_check_invalid_commands,
		_check_same_commands_same_state,
		_check_hash_sees_changes,
		_check_hash_covers_fields,
		_check_trail,
	]
	for step: Callable in steps:
		var result: String = step.call()
		if not result.is_empty():
			return result
	return ""


## Holding east: the first move starts at once, the next one exactly MOVE_TICKS later, and the
## grid's edge stops the player.
func _check_move_timing() -> String:
	var state: GameState = GameState.new(RADIUS, START, 1)
	var arrivals: Array[Vector2i] = []
	for _tick: int in 3 * Simulation.MOVE_TICKS + 1:
		Simulation.step(state, _commands(EAST))
		arrivals.append(state.player_tile)
	var expected_second: Vector2i = START + 2 * Hex.DIRECTIONS[EAST]
	if arrivals[0] != START + Hex.DIRECTIONS[EAST]:
		return "the first move didn't start on the first tick"
	if arrivals[Simulation.MOVE_TICKS - 1] != arrivals[0]:
		return "the second move started before the first one arrived"
	if arrivals[Simulation.MOVE_TICKS] != expected_second:
		return "the second move didn't start right as the first one arrived"
	if state.player_tile != expected_second or state.is_moving():
		return "the player didn't stop at the grid's edge, at %s" % state.player_tile
	return ""


func _check_invalid_commands() -> String:
	var state: GameState = GameState.new(RADIUS, START, 1)
	var invalid: Array[int] = [-5, Command.NO_MOVE, Hex.DIRECTIONS.size(), 99]
	for direction: int in invalid:
		Simulation.step(state, _commands(direction))
	if state.player_tile != START or state.is_moving():
		return "an invalid or empty command moved the player"
	return ""


func _check_same_commands_same_state() -> String:
	var first: Array[int] = _replay(_moves(), 42)
	var second: Array[int] = _replay(_moves(), 42)
	if first != second:
		return "the same seed and commands gave different states"
	var last: GameState = GameState.new(RADIUS, START, 42)
	for direction: int in _moves():
		Simulation.step(last, _commands(direction))
	if last.player_tile == START and not last.is_moving():
		return "the scripted commands never moved the player, so the replay proves little"
	return ""


## Changing one command, or the seed, must change the hashes.
func _check_hash_sees_changes() -> String:
	var moves: Array[int] = _moves()
	var baseline: Array[int] = _replay(moves, 42)
	var changed: Array[int] = []
	changed.assign(moves)
	# The first command: the player stands still then, so it is never ignored like a command
	# that arrives mid-move.
	changed[0] = (changed[0] + 1) % Hex.DIRECTIONS.size()
	var last: int = baseline.size() - 1
	if _replay(changed, 42)[last] == baseline[last]:
		return "changing one command didn't change the final state hash"
	if _replay(moves, 43)[0] == baseline[0]:
		return "a different seed didn't change the state hash"
	return ""


## Changing any single field changes the hash, including bits above the lowest 32.
func _check_hash_covers_fields() -> String:
	var base: int = GameState.new(RADIUS, START, 42).state_hash()
	var changes: Dictionary[String, Callable] = {
		"tick": func(state: GameState) -> void: state.tick += 1,
		"rng_seed": func(state: GameState) -> void: state.rng_seed += 1,
		"rng_seed above bit 31": func(state: GameState) -> void: state.rng_seed += 1 << 40,
		"grid_radius": func(state: GameState) -> void: state.grid_radius += 1,
		"player_tile.x": func(state: GameState) -> void: state.player_tile.x += 1,
		"player_tile.y": func(state: GameState) -> void: state.player_tile.y += 1,
		"move_from.x": func(state: GameState) -> void: state.move_from.x += 1,
		"move_from.y": func(state: GameState) -> void: state.move_from.y += 1,
		"move_ticks_left": func(state: GameState) -> void: state.move_ticks_left += 1,
		"trail": func(state: GameState) -> void: state.trail[Vector2i.ZERO] = true,
		# Same size, other tile: the hash must see the coordinates, not only how many there are.
		"trail tile": func(state: GameState) -> void: state.trail = { Vector2i.ZERO: true },
	}
	for field: String in changes:
		var state: GameState = _fresh_state()
		changes[field].call(state)
		if state.state_hash() == base:
			return "changing %s didn't change the state hash" % field
	return ""


## The trail starts with the start tile, gains every tile moved onto, and walking back over it
## changes nothing. Its hash doesn't depend on the order it was walked in.
func _check_trail() -> String:
	var state: GameState = _fresh_state()
	var only_start: Array[Vector2i] = [START]
	if state.trail_tiles() != only_start:
		return "a new state's trail is %s, not just the start tile" % [state.trail_tiles()]
	var east: Vector2i = Hex.DIRECTIONS[EAST]
	_walk(state, EAST, 2)
	var after_two: Array[Vector2i] = [START, START + east, START + 2 * east]
	after_two.sort()
	if state.trail_tiles() != after_two:
		return "after two moves the trail is %s, expected %s" % [state.trail_tiles(), after_two]
	_walk(state, (EAST + 3) % Hex.DIRECTIONS.size(), 1)
	if state.trail_tiles() != after_two:
		return "walking back over the trail changed it to %s" % [state.trail_tiles()]
	var reordered: GameState = _fresh_state()
	reordered.trail = {}
	var shuffled: Array[Vector2i] = [START + 2 * east, START, START + east]
	for tile: Vector2i in shuffled:
		reordered.trail[tile] = true
	var ordered: GameState = _fresh_state()
	ordered.trail = {}
	for tile: Vector2i in after_two:
		ordered.trail[tile] = true
	if reordered.state_hash() != ordered.state_hash():
		return "the same trail walked in a different order hashes differently"
	return ""


## Moves `moves` tiles in one direction, waiting for each move to arrive.
func _walk(state: GameState, direction: int, moves: int) -> void:
	for _move: int in moves:
		Simulation.step(state, _commands(direction))
		while state.is_moving():
			Simulation.step(state, _commands(Command.NO_MOVE))


func _fresh_state() -> GameState:
	return GameState.new(RADIUS, START, 42)


## The state hash after every tick.
func _replay(moves: Array[int], seed_value: int) -> Array[int]:
	var state: GameState = GameState.new(RADIUS, START, seed_value)
	var hashes: Array[int] = []
	for direction: int in moves:
		Simulation.step(state, _commands(direction))
		hashes.append(state.state_hash())
	return hashes


## A fixed mix of moves and pauses in every direction.
func _moves() -> Array[int]:
	var moves: Array[int] = []
	for tick: int in REPLAY_TICKS:
		moves.append(posmod(tick * 3 + tick % 11, Hex.DIRECTIONS.size() + 1) - 1)
	return moves


func _commands(direction: int) -> Array[Command]:
	var commands: Array[Command] = [Command.new(direction)]
	return commands
