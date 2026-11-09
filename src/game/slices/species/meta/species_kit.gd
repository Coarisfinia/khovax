class_name SpeciesKit
extends RefCounted
## Whether the species' abilities hold together (#222): each species names a special attack and two
## passives that exist in the ability data and are of their kind, and no two species share a special
## attack, which is one species' own (owner, #228). Checked by the content flow, beside the schemas.


## Why `all_species`' abilities don't hold together against `all_abilities` (both by id), or "".
static func problem(
	all_species: Dictionary[String, Species],
	all_abilities: Dictionary[String, Ability],
) -> String:
	var special_of: Dictionary[String, String] = {}
	for entry: Species in all_species.values():
		var wrong: String = _kind_problem(entry, all_abilities)
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
