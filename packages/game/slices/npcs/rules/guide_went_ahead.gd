class_name GuideWentAhead
extends RefCounted
## Event: a guide's player left the instance before their seal was open (#1588), so the guide goes
## there on their own. It's raised in the instance the player leaves, in the tick they leave, for
## that player to be told (#1589).

## The guide's id, as the region's legend names them, and their entity.
var npc: String
var guide_id: int
## The slot of the player who left.
var slot: int


func _init(npc_id: String, guide_entity: int, player_slot: int) -> void:
	npc = npc_id
	guide_id = guide_entity
	slot = player_slot
