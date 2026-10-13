class_name Simulation
extends RefCounted
## The game's rules: advances a GameState by one tick from that tick's commands. Deterministic: the
## same state and commands always give the same next state, on every platform. Integers only; no
## nodes, input, time or engine state (CI checks `sim/` for them).

const TICKS_PER_SECOND: int = 20
## Ticks to walk from one tile to the next.
const MOVE_TICKS: int = 6


## Advances `state` by one tick. `commands` holds one command per player; there is one player.
static func step(state: GameState, commands: Array[Command]) -> void:
	state.tick += 1
	if state.move_ticks_left > 0:
		state.move_ticks_left -= 1
	if commands.is_empty():
		return
	# A move that just arrived is followed by the next one in the same tick, so a held direction
	# walks without pauses.
	if not state.is_moving():
		_start_move(state, commands[0])


static func _start_move(state: GameState, command: Command) -> void:
	if command.move < 0 or command.move >= Hex.DIRECTIONS.size():
		return
	var next: Vector2i = state.player_tile + Hex.DIRECTIONS[command.move]
	if not state.has_tile(next):
		return
	state.move_from = state.player_tile
	state.player_tile = next
	state.move_ticks_left = MOVE_TICKS
	state.trail[next] = true
