class_name WildAttackFactory
extends RefCounted
## Builds an instance's wild attacks feature (#422, #823) with every passive's guard (#616) and
## dodge (#1499), from the ability data.


static func build(_setup: FeatureSetup) -> WildAttackFeature:
	var dodges: Dictionary[String, int] = {}
	var abilities: Dictionary[String, Ability] = AbilityContent.cached().abilities
	for ability_id: String in abilities:
		if abilities[ability_id].dodge > 0:
			dodges[ability_id] = abilities[ability_id].dodge
	return WildAttackFeature.new(guards(), dodges)


## Every passive's guard (Ability.guard), in thousandths, by its id, for the passives that have one:
## what a wild monster's hit lands less of (WildHit). A boss's specials take them too (#2458).
static func guards() -> Dictionary[String, int]:
	var found: Dictionary[String, int] = {}
	var abilities: Dictionary[String, Ability] = AbilityContent.cached().abilities
	for ability_id: String in abilities:
		if abilities[ability_id].guard > 0:
			found[ability_id] = abilities[ability_id].guard
	return found
