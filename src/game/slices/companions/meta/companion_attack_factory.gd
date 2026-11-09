class_name CompanionAttackFactory
extends RefCounted
## Builds an instance's companion attacks feature (#221, #823) with every passive's haste when hurt
## and heal at rest (#1500), from the ability data.


static func build(_setup: FeatureSetup) -> CompanionAttackFeature:
	var hastes: Dictionary[String, int] = {}
	var rest_heals: Dictionary[String, int] = {}
	var abilities: Dictionary[String, Ability] = AbilityContent.cached().abilities
	for ability_id: String in abilities:
		if abilities[ability_id].hurt_haste > 0:
			hastes[ability_id] = abilities[ability_id].hurt_haste
		if abilities[ability_id].rest_heal > 0:
			rest_heals[ability_id] = abilities[ability_id].rest_heal
	return CompanionAttackFeature.new(hastes, rest_heals)
