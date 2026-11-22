class_name MonsterAbsorbed
extends RefCounted
## Event: a wild absorber (#2412, AbsorptionFeature) absorbed a fainted wild monster next to it
## this tick. The fainted monster has already left the region, and the absorber's catalogue now
## holds a snapshot of its form.

## The absorbing wild monster's entity id.
var absorber_id: int
## The absorbed wild monster's stable short id (ShortId, #700).
var short_id: String
## The absorbed wild monster's species id.
var species: String


func _init(absorber: int, absorbed_short_id: String, absorbed_species: String) -> void:
	absorber_id = absorber
	short_id = absorbed_short_id
	species = absorbed_species
