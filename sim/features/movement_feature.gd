class_name MovementFeature
extends Feature
## Walking tile by tile: a move command starts a step to the neighboring tile, which takes
## MOVE_TICKS ticks to arrive. A move that arrives is followed by the next one in the same tick, so
## a held direction walks without pauses. The grid's edge stops the player. Each started step
## raises a PlayerMoved event.

## Ticks to walk from one tile to the next.
const MOVE_TICKS: int = 6

## The tile the current move started from.
var move_from: Vector2i = Vector2i.ZERO
## Ticks until the current move arrives; 0 when standing on the state's player tile.
var move_ticks_left: int = 0


func id() -> int:
	return Features.MOVEMENT


func start(state: GameState) -> void:
	move_from = state.player_tile


func step(state: GameState, commands: Array[Command]) -> void:
	if move_ticks_left > 0:
		move_ticks_left -= 1
	if commands.is_empty() or is_moving():
		return
	_start_move(state, commands[0])


func is_moving() -> bool:
	return move_ticks_left > 0


func hash_values() -> Array[int]:
	var values: Array[int] = [move_from.x, move_from.y, move_ticks_left]
	return values


func _start_move(state: GameState, command: Command) -> void:
	if command.move < 0 or command.move >= Hex.DIRECTIONS.size():
		return
	var next: Vector2i = state.player_tile + Hex.DIRECTIONS[command.move]
	if not state.has_tile(next):
		return
	move_from = state.player_tile
	state.player_tile = next
	move_ticks_left = MOVE_TICKS
	state.events.append(PlayerMoved.new(move_from, next))
