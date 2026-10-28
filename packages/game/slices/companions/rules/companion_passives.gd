class_name CompanionPassives
extends RefCounted
## Which passives work now (#616): a monster's passives (#222) work only while it is out, as its
## player's companion here (CompanionFeature). The monsters a player carries in reserve give none.
## What a passive does is read where it acts (e.g. a guard, WildAttackFeature).


## The passives that help the player in `slot` now: their companion's, while it is out here; none
## while it isn't, whatever they carry in reserve.
static func of_player(companions: CompanionFeature, slot: int) -> Array[String]:
	return _passives(companions, companions.player_passives, companions.companion_of(slot))


## The passives that help the companion `companion_id` itself: its species' own; none for an entity
## that's no companion here.
static func of_companion(companions: CompanionFeature, companion_id: int) -> Array[String]:
	return _passives(companions, companions.self_passives, companion_id)


## The passive `by_species` names for the species of the companion `companion_id`, if any.
static func _passives(
	companions: CompanionFeature,
	by_species: Dictionary[String, String],
	companion_id: int,
) -> Array[String]:
	var working: Array[String] = []
	var passive: String = by_species.get(companions.species_of(companion_id), "")
	if not passive.is_empty():
		working.append(passive)
	return working
