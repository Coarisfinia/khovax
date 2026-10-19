class_name RequestApplied
extends RefCounted
## Event: the world took the request `request` from the outbox of the player in `slot` this tick
## (#771): applied now, or already before (OutboxReceipts). That player's profile drops it from its
## outbox then.

var slot: int
## The request's short id (ShortId, the one Command.request carries the code of).
var request: String


func _init(player_slot: int, request_id: String) -> void:
	slot = player_slot
	request = request_id
