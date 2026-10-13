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
