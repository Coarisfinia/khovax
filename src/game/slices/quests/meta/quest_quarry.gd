class_name QuestQuarry
extends RefCounted
## The wild monster a `dominated` quest step asks for: one of a species (#184), any when it names
## none, or the one quest target a region's legend marks (#625, WildSpot.target).

## The species, its name as the player reads it (#351) included, or null for any.
var species: Species = null
## The quest target's id, as region legends name it, or "" when the step asks for a species or any
## monster.
var target: String = ""


## Whether a wild monster of `species_id` that is the quest target `target_id` ("" for none) is
## what's asked for.
func fits(species_id: String, target_id: String) -> bool:
	if not target.is_empty():
		return target == target_id
	return species == null or species.id == species_id
