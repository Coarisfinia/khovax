class_name MonsterRevived
extends RefCounted
## Event: a player used a revive item this tick (#656) and brought back their fainted carried
## monster `short_id` (ShortId, #700), of `species`; their profile spends the item.

## The player's slot.
var slot: int
var short_id: String
var species: String


func _init(by_slot: int, revived_id: String, revived_species: String) -> void:
	slot = by_slot
	short_id = revived_id
	species = revived_species
