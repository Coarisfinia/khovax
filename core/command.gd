class_name Command
extends RefCounted
## One player's input for one tick: the only thing that enters the simulation from outside. A
## tick's commands are indexed by player slot. Recording the commands of every tick, together with
## the starting state, is a replay.

const NO_MOVE: int = -1
## No companion's lethal strikes toggled this tick.
const NO_TOGGLE: int = -1
## How many integers a command is in a replay (to_values).
const VALUE_COUNT: int = 2

## An index into Hex.DIRECTIONS, or NO_MOVE.
var move: int = NO_MOVE
## Which of the player's companions, by its place among them in id order, switches between
## non-lethal and lethal strikes this tick (#221), or NO_TOGGLE. A press, not a held state: it's
## given for the one tick the player presses it.
var toggle_lethal: int = NO_TOGGLE


func _init(direction: int = NO_MOVE, toggled: int = NO_TOGGLE) -> void:
	move = direction
	toggle_lethal = toggled


## The command as integers, for replays: from_values turns them back into the same command.
func to_values() -> Array[int]:
	var values: Array[int] = [move, toggle_lethal]
	return values


static func from_values(values: Array[int]) -> Command:
	return Command.new(values[0], values[1])


## Whether the command is one a player can give: no move or one of the six directions, and no
## toggle or a companion's place. A place the player has no companion at toggles nothing.
func is_valid() -> bool:
	var moved: bool = move == NO_MOVE or (move >= 0 and move < Hex.DIRECTIONS.size())
	return moved and toggle_lethal >= NO_TOGGLE


## The command of the player in `slot` this tick, or null: a slot without a command (no player
## there, or none received) does nothing.
static func of(commands: Array[Command], slot: int) -> Command:
	if slot < 0 or slot >= commands.size():
		return null
	return commands[slot]
