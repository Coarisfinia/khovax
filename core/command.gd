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
## No swap of the companion this tick (#55).
const NO_SWAP: int = 0
## No answer chosen in a dialog this tick (#635).
const NO_ANSWER: int = CommandCodes.NONE
## No request from the player's profile's outbox this tick (#771).
const NO_REQUEST: int = 0
## No kind of request this tick (#818): a command without a request.
const NO_REQUEST_KIND: int = 0
## How many integers a command is in a replay (to_values).
const VALUE_COUNT: int = 11

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
## Whether the player, knocked down, chooses to go back to the world's spawn now (#495). A press,
## like the special: given for the one tick it's pressed.
var respawn: bool = false
## Which of their carried monsters the player makes their companion this tick (#55), counted from 1
## in the carried order, or NO_SWAP. A press, like the special; the simulation checks they carry it.
var swap: int = NO_SWAP
## The answer the player chose in a dialog this tick (#635), as the code of its dialog's and its
## own id (a whole number, never NO_ANSWER), or NO_ANSWER. A press, like the special; the
## simulation checks a dialog has that answer.
var answer: int = NO_ANSWER
## The id of the request from the player's profile's outbox (#771, Outbox) this command carries, as
## its short id's code (ShortId.code, #791), or NO_REQUEST. The world records the ids it applied, so
## a request sent again (at every session's start, until the world acknowledges it) is never
## applied twice.
var request: int = NO_REQUEST
## What the request asks for (#818), a kind the outbox knows (OutboxEntry.KINDS: handing a
## territory over, using a revive item, changing the gear in the trap slot), or NO_REQUEST_KIND.
## Every kind rides in these same two fields, so a new kind of request never grows the command; the
## feature carrying out a kind checks its data.
var request_kind: int = NO_REQUEST_KIND
## The request's data, as its kind reads it (OutboxEntry): a whole number from 0.
var request_data: int = 0
## The code of the newest request id up to which the player's profile saw every request of the
## kind this command carries acknowledged (#942, #968, Outbox.confirmed), or NO_REQUEST: the
## feature carrying out that kind forgets its receipts of those and refuses any of them sent again,
## so it forgets as it records. Per kind, a request of another kind stuck in the outbox doesn't
## hold it back.
var acknowledged: int = NO_REQUEST


func _init(
	direction: int = NO_MOVE,
	fires: bool = false,
	place: int = NO_TOTEM,
	focused: int = NO_FOCUS,
	gives_up: bool = false,
) -> void:
	move = direction
	special = fires
	totem = place
	focus = focused
	respawn = gives_up


## The command as integers, for replays: from_values turns them back into the same command.
func to_values() -> Array[int]:
	var values: Array[int] = [
		move, 1 if special else 0, totem, focus, 1 if respawn else 0, swap, answer, request,
		request_kind, request_data, acknowledged,
	]
	return values


## The command from to_values' integers; is_valid_values says whether they make one.
static func from_values(values: Array[int]) -> Command:
	var command: Command = Command.new(
		values[0],
		values[1] == 1,
		values[2],
		values[3],
		values[4] == 1,
	)
	command.swap = values[5]
	command.answer = values[6]
	command.request = values[7]
	command.request_kind = values[8]
	command.request_data = values[9]
	command.acknowledged = values[10]
	return command


## Whether the command is one a player can give: no move or one of the six directions, a totem
## placed or not, a focus that is an entity id or none, a swap to a place in the carried order or
## none, an answer's code or none, a request with both its id and its kind, or none at all, and
## an acknowledged mark of a request's code or none.
func is_valid() -> bool:
	var moves: bool = move == NO_MOVE or (move >= 0 and move < Hex.DIRECTIONS.size())
	var placed: bool = totem == NO_TOTEM or totem == PLACE_TOTEM
	var chosen: bool = swap >= NO_SWAP and answer >= NO_ANSWER
	var requests: bool = request > NO_REQUEST and request_kind > NO_REQUEST_KIND
	var none: bool = request == NO_REQUEST and request_kind == NO_REQUEST_KIND and request_data == 0
	chosen = chosen and (none or (requests and request_data >= 0))
	return moves and placed and focus >= NO_FOCUS and chosen and acknowledged >= NO_REQUEST


## Whether `values` are a command's, as to_values gives them, of one a player can give.
static func is_valid_values(values: Array[int]) -> bool:
	if values.size() != VALUE_COUNT:
		return false
	# The presses: the special and going back to the spawn.
	var presses: Array[int] = [values[1], values[4]]
	for press: int in presses:
		if press != 0 and press != 1:
			return false
	return from_values(values).is_valid()


## The command of the player in `slot` this tick, or null: a slot without a command (no player
## there, or none received) does nothing.
static func of(commands: Array[Command], slot: int) -> Command:
	if slot < 0 or slot >= commands.size():
		return null
	return commands[slot]
