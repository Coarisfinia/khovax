class_name CompanionReturned
extends RefCounted
## Event: a companion at 0 HP went back to its player (#456): it left the instance and stays in its
## player's keeping until they leave through an exit. The look shrinks it into its player.

var companion_id: int
var slot: int


func _init(returned_id: int, player_slot: int) -> void:
	companion_id = returned_id
	slot = player_slot
