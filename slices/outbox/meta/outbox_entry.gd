class_name OutboxEntry
extends RefCounted
## One request in a profile's outbox (Outbox, #771): something the profile asks the world to do,
## with its kind, its data and its id. It rides in one of the player's commands: its id in
## Command.request, and its data in its kind's own field of the command.

## Hand a territory over to a faction (#638): its data is the territory's code (Territory.code),
## and it rides in Command.hand_over.
const TERRITORY: int = 1
## Every kind there is.
const KINDS: Array[int] = [TERRITORY]
## The stream the profile's outbox draws ids from (Outbox).
const ID_STREAM: int = 771

## The profile's id for it, a short id (ShortId, #791) no other request in the outbox has: the
## world records the ids it applied.
var id: String = ""
## One of KINDS.
var kind: int = TERRITORY
## What it asks for, as its kind reads it: a whole number from 0 to DataReader.MOST.
var data: int = 0


func _init(entry_id: String = "", entry_kind: int = TERRITORY, entry_data: int = 0) -> void:
	id = entry_id
	kind = entry_kind
	data = entry_data


## Puts this request into `command`: its id, as its code (ShortId.code), and its data into the field
## its kind rides in.
func fill(command: Command) -> void:
	command.request = ShortId.code(id)
	match kind:
		TERRITORY:
			command.hand_over = data


## The request as save data.
func to_data() -> Dictionary:
	return { "id": id, "kind": kind, "data": data }
