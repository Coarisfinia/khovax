class_name CarriedMonsters
extends RefCounted
## The monsters one player brings into a session (#53, #700), in their carried order: each one's
## short id (ShortId), which tells two of one species apart, and its species.

var short_ids: PackedStringArray = PackedStringArray()
var species: PackedStringArray = PackedStringArray()


## Adds the monster `short_id` of `species_id` at the end; returns these, to add the next.
func add(short_id: String, species_id: String) -> CarriedMonsters:
	var _added: bool = short_ids.append(short_id)
	_added = species.append(species_id)
	return self


func size() -> int:
	return short_ids.size()


## Whether `other` carries the same monsters in the same order; null carries none.
func same_as(other: CarriedMonsters) -> bool:
	if other == null:
		return short_ids.is_empty()
	return short_ids == other.short_ids and species == other.species


## As save data: each one's short id and species, in carried order.
func to_data() -> Array[Dictionary]:
	var data: Array[Dictionary] = []
	for place: int in size():
		data.append({ "short_id": short_ids[place], "species": species[place] })
	return data


## The monsters `to_data` gave, or null when `data` isn't a list of a short id and a species each.
static func of_data(data: Variant) -> CarriedMonsters:
	if not data is Array:
		return null
	var carried: CarriedMonsters = CarriedMonsters.new()
	var entries: Array = data
	for entry: Variant in entries:
		var fields: Dictionary = entry if entry is Dictionary else {}
		var short_id: Variant = fields.get("short_id")
		var species_id: Variant = fields.get("species")
		if not short_id is String or not species_id is String:
			return null
		var id_text: String = short_id
		var species_text: String = species_id
		var _carried: CarriedMonsters = carried.add(id_text, species_text)
	return carried
