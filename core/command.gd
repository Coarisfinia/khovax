class_name Command
extends RefCounted
## One player's input for one tick: the only thing that enters the simulation from outside. A
## tick's commands are indexed by player slot. Recording the commands of every tick, together with
## the starting state, is a replay.

const NO_MOVE: int = -1
## How many integers a command is in a replay (to_values).
const VALUE_COUNT: int = 2

## An index into Hex.DIRECTIONS, or NO_MOVE.
var move: int = NO_MOVE
## Whether the player fires their companion's special attack this tick (#410). A press, not a held
## state: it's given for the one tick the player presses it.
var special: bool = false


func _init(direction: int = NO_MOVE, fires: bool = false) -> void:
	move = direction
	special = fires


## The command as integers, for replays: from_values turns them back into the same command.
func to_values() -> Array[int]:
	var values: Array[int] = [move, 1 if special else 0]
	return values


## The command from to_values' integers; is_valid_values says whether they make one.
static func from_values(values: Array[int]) -> Command:
	return Command.new(values[0], values[1] == 1)


## Whether the command is one a player can give: no move, or one of the six directions.
func is_valid() -> bool:
	return move == NO_MOVE or (move >= 0 and move < Hex.DIRECTIONS.size())


## Whether `values` are a command's, as to_values gives them, of one a player can give.
static func is_valid_values(values: Array[int]) -> bool:
	if values.size() != VALUE_COUNT or (values[1] != 0 and values[1] != 1):
		return false
	return from_values(values).is_valid()


## The command of the player in `slot` this tick, or null: a slot without a command (no player
## there, or none received) does nothing.
static func of(commands: Array[Command], slot: int) -> Command:
	if slot < 0 or slot >= commands.size():
		return null
	return commands[slot]
