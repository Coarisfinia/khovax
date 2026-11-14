class_name SpeciesKit
extends RefCounted
## Whether the species' abilities hold together (#222): each species names a special attack and two
## passives that exist in the ability data and are of their kind, and no two species share a special
## attack, which is one species' own (owner, #228). A species' core list (#2409,
## SpeciesContent.cores)
## names abilities of kind core, each once and each that species' own. Checked by the content flow,
## beside the schemas.


## Why `all_species`' abilities don't hold together against `all_abilities` (both by id), with
## their core lists `cores` (by species id), or "".
static func problem(
	all_species: Dictionary[String, Species],
	all_abilities: Dictionary[String, Ability],
	cores: Dictionary[String, Array] = {},
) -> String:
	var special_of: Dictionary[String, String] = {}
	var core_of: Dictionary[String, String] = {}
	for entry: Species in all_species.values():
		var wrong: String = _kind_problem(entry, all_abilities)
		var listed: Array = cores.get(entry.id, [])
		if wrong.is_empty():
			wrong = _core_problem(entry.id, listed, all_abilities, core_of)
		if not wrong.is_empty():
			return wrong
		if special_of.has(entry.special):
			return "%s and %s share the special %s" % [
				special_of[entry.special],
				entry.id,
				entry.special,
			]
		special_of[entry.special] = entry.id
	return ""


## Why one of `entry`'s abilities isn't one of its kind, or "".
static func _kind_problem(entry: Species, all_abilities: Dictionary[String, Ability]) -> String:
	# In pairs, not keyed by id: the same id named twice must still be checked for each kind.
	var ids: Array[String] = [entry.special, entry.player_passive, entry.self_passive]
	var kinds: Array[String] = [Ability.SPECIAL, Ability.PLAYER_PASSIVE, Ability.SELF_PASSIVE]
	for i: int in ids.size():
		var ability: Ability = all_abilities.get(ids[i])
		if ability == null or ability.kind != kinds[i]:
			return "%s's %s isn't an ability of that kind: %s" % [entry.id, kinds[i], ids[i]]
	return ""


## Why `species_id`'s core list `listed` doesn't hold together, or "": each is an ability of kind
## core, named once, that no species before it (in `core_of`, each core ability's species) lists.
static func _core_problem(
	species_id: String,
	listed: Array,
	all_abilities: Dictionary[String, Ability],
	core_of: Dictionary[String, String],
) -> String:
	for raw: Variant in listed:
		var id: String = str(raw)
		var ability: Ability = all_abilities.get(id)
		if ability == null or ability.kind != Ability.CORE:
			return "%s's core skill %s isn't an ability of kind core" % [species_id, id]
		if core_of.get(id, "") == species_id:
			return "%s names the core skill %s twice" % [species_id, id]
		if core_of.has(id):
			return "%s and %s share the core skill %s" % [core_of[id], species_id, id]
		core_of[id] = species_id
	return ""
