class_name CarriedMonsters
extends RefCounted
## The monsters one player brings into a session (#53, #700), in their carried order: each one's
## short id (ShortId), which tells two of one species apart, its species and its level (#1255),
## from 1.

var short_ids: PackedStringArray = PackedStringArray()
var species: PackedStringArray = PackedStringArray()
var levels: PackedInt64Array = PackedInt64Array()


## Adds the monster `short_id` of `species_id` at `level` (up to CarryRequest.MOST_LEVEL) at the
## end; returns these, to add the next.
func add(short_id: String, species_id: String, level: int = 1) -> CarriedMonsters:
	var _added: bool = short_ids.append(short_id)
	_added = species.append(species_id)
	_added = levels.append(clampi(level, 1, CarryRequest.MOST_LEVEL))
	return self


func size() -> int:
	return short_ids.size()


## Whether `other` carries the same monsters in the same order; null carries none.
func same_as(other: CarriedMonsters) -> bool:
	if other == null:
		return short_ids.is_empty()
	return short_ids == other.short_ids and species == other.species and levels == other.levels


## As save data: each one's short id and species, in carried order, and its level above 1 (one at
## level 1 leaves it out, as before levels, #1255).
func to_data() -> Array[Dictionary]:
	var data: Array[Dictionary] = []
	for place: int in size():
		var monster: Dictionary = { "short_id": short_ids[place], "species": species[place] }
		if levels[place] > 1:
			monster["level"] = levels[place]
		data.append(monster)
	return data


## The monsters `to_data` gave (its numbers whole), or null when `data` isn't a list of a short id
## and a species each, with a level from 1 or none (level 1).
static func of_data(data: Variant) -> CarriedMonsters:
	if not data is Array:
		return null
	var carried: CarriedMonsters = CarriedMonsters.new()
	var entries: Array = data
	for entry: Variant in entries:
		var fields: Dictionary = entry if entry is Dictionary else {}
		var short_id: Variant = fields.get("short_id")
		var species_id: Variant = fields.get("species")
		var saved_level: Variant = fields.get("level", 1)
		var level: int = saved_level if saved_level is int else 0
		if not short_id is String or not species_id is String or level < 1:
			return null
		var id_text: String = short_id
		var species_text: String = species_id
		var _carried: CarriedMonsters = carried.add(id_text, species_text, level)
	return carried
