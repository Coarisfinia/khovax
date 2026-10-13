class_name Command
extends RefCounted
## One player's input for one tick: the only thing that enters the simulation from outside.
## Recording the commands of every tick, together with the starting state, is a replay.

const NO_MOVE: int = -1

## An index into Hex.DIRECTIONS, or NO_MOVE.
var move: int = NO_MOVE


func _init(direction: int = NO_MOVE) -> void:
	move = direction
