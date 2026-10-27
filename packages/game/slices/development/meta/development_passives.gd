class_name DevelopmentPassives
extends RefCounted
## Whether the passives the development webs grant hold together with the abilities (#1404): each
## is a passive in the ability data, none is a passive a species already has (#222) or a special,
## and no two nodes grant the same one, so each is one web's own. Checked by the content flow, like
## SpeciesKit.


## Why the passives `webs` grant don't hold together against `all_species` and `all_abilities`
## (each by id), or "".
static func problem(
	webs: Dictionary[String, DevelopmentWeb],
	all_species: Dictionary[String, Species],
	all_abilities: Dictionary[String, Ability],
) -> String:
	var kits: Array[String] = []
	for entry: Species in all_species.values():
		kits.append_array([entry.player_passive, entry.self_passive])
	var granted_by: Dictionary[String, String] = {}
	for web: DevelopmentWeb in webs.values():
		for node: String in web.passives:
			var passive: String = web.passives[node]
			var where: String = "%s's %s" % [web.species, node]
			var ability: Ability = all_abilities.get(passive)
			if ability == null or ability.kind == Ability.SPECIAL:
				return "%s grants %s, which isn't a passive" % [where, passive]
			if kits.has(passive):
				return "%s grants %s, a passive a species already has" % [where, passive]
			if granted_by.has(passive):
				return "%s and %s both grant %s" % [granted_by[passive], where, passive]
			granted_by[passive] = where
	return ""
