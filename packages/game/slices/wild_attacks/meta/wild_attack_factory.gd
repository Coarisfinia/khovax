class_name WildAttackFactory
extends RefCounted
## Builds an instance's wild attacks feature (#422, #823) with every passive's guard (#616) and
## dodge (#1499), from the ability data.


static func build(_setup: FeatureSetup) -> WildAttackFeature:
	var guards: Dictionary[String, int] = {}
	var dodges: Dictionary[String, int] = {}
	var abilities: Dictionary[String, Ability] = AbilityContent.cached().abilities
	for ability_id: String in abilities:
		if abilities[ability_id].guard > 0:
			guards[ability_id] = abilities[ability_id].guard
		if abilities[ability_id].dodge > 0:
			dodges[ability_id] = abilities[ability_id].dodge
	return WildAttackFeature.new(guards, dodges)
