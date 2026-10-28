class_name OutboxEntry
extends RefCounted
## One request in a profile's outbox (Outbox, #771): something the profile asks the world to do,
## with its kind, its data and its id. It rides in one of the player's commands: its id in
## Command.request, its kind and data in Command.request_kind and Command.request_data, the same
## fields for every kind (#818).

## Hand a territory over to a faction (#638): its data is the territory's code (Territory.code).
const TERRITORY: int = 1
## Use a revive item on a fainted carried monster (#656, #818): its data is the monster's short
## id's code (ShortId.code).
const REVIVE: int = 2
## Put gear into the trap slot, or empty it (#692, #818): its data is the gear's code
## (SpikesFeature.code_of), or CommandCodes.NONE for an empty slot.
const TRAP: int = 3
## Bring monsters into the player's party (#53, #818): a run of these, its data a place in the run,
## how many monsters it brings and one value of them (CarryRequest).
const CARRY: int = 4
## Set one of the world's settings, from its host (#1309, HostSettings): its data is the
## setting's code and its choice (HostSettings.request_data).
const HOST_SETTING: int = 5
## Raise an event a quest emitted in the world (#755, QuestEventFeature): its data is the event's
## code (CommandCodes.of).
const QUEST_EVENT: int = 6
## Keep the player's carried monsters' passives on while they aren't out, or stop (#617): its data
## is 1 while gear that keeps them (GearItem.keeps_passives) is in the ward slot, 0 otherwise
## (CompanionPassives.keep).
const PASSIVES_KEPT: int = 7
## Every kind there is.
const KINDS: Array[int] = [TERRITORY, REVIVE, TRAP, CARRY, HOST_SETTING, QUEST_EVENT, PASSIVES_KEPT]

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


## Puts this request into `command`: its id, as its code (ShortId.code), its kind and its data.
func fill(command: Command) -> void:
	command.request = ShortId.code(id)
	command.request_kind = kind
	command.request_data = data


## The request as save data.
func to_data() -> Dictionary:
	return { "id": id, "kind": kind, "data": data }
