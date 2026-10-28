class_name CarriedMonsters
extends RefCounted
## The monsters one player brings into a session (#53, #700), in their carried order: each one's
## short id (ShortId), which tells two of one species apart, its species, its leaning (#1358,
## what the stat nodes it took add up to) and the passive a passive node it took grants (#1472), ""
## for none: a web grants one passive at most (DevelopmentPassives), so a monster has one at most.

var short_ids: PackedStringArray = PackedStringArray()
var species: PackedStringArray = PackedStringArray()
var leanings: Array[CompanionLeaning] = []
var passives: PackedStringArray = PackedStringArray()


## Adds the monster `short_id` of `species_id`, leaning by `leaning` (none when null), with the
## passive `passive` its web grants it ("" for none), at the end; returns these, to add the next.
func add(
	short_id: String,
	species_id: String,
	leaning: CompanionLeaning = null,
	passive: String = "",
) -> CarriedMonsters:
	var _added: bool = short_ids.append(short_id)
	_added = species.append(species_id)
	leanings.append(leaning if leaning != null else CompanionLeaning.new())
	_added = passives.append(passive)
	return self


func size() -> int:
	return short_ids.size()


## Whether `other` carries the same monsters in the same order, leaning the same, with the same
## passives; null carries none.
func same_as(other: CarriedMonsters) -> bool:
	if other == null:
		return short_ids.is_empty()
	if short_ids != other.short_ids or species != other.species or passives != other.passives:
		return false
	for place: int in size():
		if not leanings[place].same_as(other.leanings[place]):
			return false
	return true


## As save data: each one's short id and species, in carried order, its leaning when it has one
## (one without leaves it out, as before leanings, #1358) and its passive when it has one (#1472).
func to_data() -> Array[Dictionary]:
	var data: Array[Dictionary] = []
	for place: int in size():
		var monster: Dictionary = { "short_id": short_ids[place], "species": species[place] }
		if not leanings[place].is_none():
			monster["leaning"] = leanings[place].to_data()
		if not passives[place].is_empty():
			monster["passive"] = passives[place]
		data.append(monster)
	return data


## The monsters `to_data` gave (its numbers whole), or null when `data` isn't a list of a short id
## and a species each, with a leaning (CompanionLeaning.of_data) or none, and a passive's id or
## none.
static func of_data(data: Variant) -> CarriedMonsters:
	if not data is Array:
		return null
	var carried: CarriedMonsters = CarriedMonsters.new()
	var entries: Array = data
	for entry: Variant in entries:
		if not carried._add_data(entry):
			return null
	return carried


## Adds the monster one entry of `to_data` gave, `entry`; false, adding none, when it isn't a short
## id and a species, with a leaning or none and a passive's id or none.
func _add_data(entry: Variant) -> bool:
	var fields: Dictionary = entry if entry is Dictionary else {}
	var short_id: Variant = fields.get("short_id")
	var species_id: Variant = fields.get("species")
	var leaning: CompanionLeaning = CompanionLeaning.of_data(fields.get("leaning", [0, 0, 0]))
	var passive: Variant = fields.get("passive", "")
	if not short_id is String or not species_id is String or not passive is String:
		return false
	if leaning == null:
		return false
	var _carried: CarriedMonsters = add(str(short_id), str(species_id), leaning, str(passive))
	return true
