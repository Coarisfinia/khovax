class_name CarriedMonsters
extends RefCounted
## The monsters one player brings into a session (#53, #700), in their carried order: each one's
## short id (ShortId), which tells two of one species apart, its species and its leaning (#1358,
## what the stat nodes it took add up to).

var short_ids: PackedStringArray = PackedStringArray()
var species: PackedStringArray = PackedStringArray()
var leanings: Array[CompanionLeaning] = []


## Adds the monster `short_id` of `species_id`, leaning by `leaning` (none when null), at the end;
## returns these, to add the next.
func add(short_id: String, species_id: String, leaning: CompanionLeaning = null) -> CarriedMonsters:
	var _added: bool = short_ids.append(short_id)
	_added = species.append(species_id)
	leanings.append(leaning if leaning != null else CompanionLeaning.new())
	return self


func size() -> int:
	return short_ids.size()


## Whether `other` carries the same monsters in the same order, leaning the same; null carries
## none.
func same_as(other: CarriedMonsters) -> bool:
	if other == null:
		return short_ids.is_empty()
	if short_ids != other.short_ids or species != other.species:
		return false
	for place: int in size():
		if not leanings[place].same_as(other.leanings[place]):
			return false
	return true


## As save data: each one's short id and species, in carried order, and its leaning when it has
## one (one without leaves it out, as before leanings, #1358).
func to_data() -> Array[Dictionary]:
	var data: Array[Dictionary] = []
	for place: int in size():
		var monster: Dictionary = { "short_id": short_ids[place], "species": species[place] }
		if not leanings[place].is_none():
			monster["leaning"] = leanings[place].to_data()
		data.append(monster)
	return data


## The monsters `to_data` gave (its numbers whole), or null when `data` isn't a list of a short id
## and a species each, with a leaning (CompanionLeaning.of_data) or none.
static func of_data(data: Variant) -> CarriedMonsters:
	if not data is Array:
		return null
	var carried: CarriedMonsters = CarriedMonsters.new()
	var entries: Array = data
	for entry: Variant in entries:
		var fields: Dictionary = entry if entry is Dictionary else {}
		var short_id: Variant = fields.get("short_id")
		var species_id: Variant = fields.get("species")
		var leaning: CompanionLeaning = CompanionLeaning.of_data(fields.get("leaning", [0, 0, 0]))
		if not short_id is String or not species_id is String or leaning == null:
			return null
		var id_text: String = short_id
		var species_text: String = species_id
		var _carried: CarriedMonsters = carried.add(id_text, species_text, leaning)
	return carried
