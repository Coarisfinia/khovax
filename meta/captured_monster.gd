class_name CapturedMonster
extends RefCounted
## A monster the player caught and owns (a `captured_monster`, #45), kept in the profile between
## sessions. Its species is an id into the content data (#72).

## Unique in the profile and never reused.
var id: int = 0
var species: String = ""
var level: int = 1


func _init(monster_id: int = 0, species_id: String = "", start_level: int = 1) -> void:
	id = monster_id
	species = species_id
	level = start_level


func to_data() -> Dictionary[String, Variant]:
	var data: Dictionary[String, Variant] = { "id": id, "species": species, "level": level }
	return data
