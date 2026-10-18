class_name Command
extends RefCounted
## One player's input for one tick: the only thing that enters the simulation from outside. A
## tick's commands are indexed by player slot. Recording the commands of every tick, together with
## the starting state, is a replay.

const NO_MOVE: int = -1
## Whether the player places their totem this tick (#423): integers, like every value here.
const NO_TOTEM: int = 0
const PLACE_TOTEM: int = 1
## No wild monster focused (#436).
const NO_FOCUS: int = 0
## How many integers a command is in a replay (to_values).
const VALUE_COUNT: int = 4

## An index into Hex.DIRECTIONS, or NO_MOVE.
var move: int = NO_MOVE
## Whether the player fires their companion's special attack this tick (#410). A press, not a held
## state: it's given for the one tick the player presses it.
var special: bool = false
## NO_TOTEM or PLACE_TOTEM.
var totem: int = NO_TOTEM
## The entity id of the wild monster the player focuses (#436), or NO_FOCUS. The special attack
## strikes it; the simulation checks it's a wild monster it can strike.
var focus: int = NO_FOCUS


func _init(
	direction: int = NO_MOVE,
	fires: bool = false,
	place: int = NO_TOTEM,
	focused: int = NO_FOCUS,
) -> void:
	move = direction
	special = fires
	totem = place
	focus = focused


## The command as integers, for replays: from_values turns them back into the same command.
func to_values() -> Array[int]:
	var values: Array[int] = [move, 1 if special else 0, totem, focus]
	return values


## The command from to_values' integers; is_valid_values says whether they make one.
static func from_values(values: Array[int]) -> Command:
	return Command.new(values[0], values[1] == 1, values[2], values[3])


## Whether the command is one a player can give: no move or one of the six directions, a totem
## placed or not, and a focus that is an entity id or none.
func is_valid() -> bool:
	var moves: bool = move == NO_MOVE or (move >= 0 and move < Hex.DIRECTIONS.size())
	return moves and (totem == NO_TOTEM or totem == PLACE_TOTEM) and focus >= NO_FOCUS


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
