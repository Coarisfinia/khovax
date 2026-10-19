class_name NpcTalkedTo
extends RefCounted
## Event: a player talked to a person this tick (#557), by walking into them. The dialog screen
## opens the person's dialog for that player, and quests can count it (#624), like PlaceReached.

## The person's id and the dialog they open ("" for none), as the region piece's legend names them.
var npc: String
var dialog: String
## The player's entity and slot.
var entity_id: int
var slot: int


func _init(npc_id: String, dialog_id: String, talking_id: int, player_slot: int) -> void:
	npc = npc_id
	dialog = dialog_id
	entity_id = talking_id
	slot = player_slot
