class_name HushFactory
extends RefCounted
## Builds an instance's hush feature (#1563, #823) with every passive's hush, from the ability data.


static func build(_setup: FeatureSetup) -> HushFeature:
	var hushes: Dictionary[String, int] = {}
	var abilities: Dictionary[String, Ability] = AbilityContent.cached().abilities
	for ability_id: String in abilities:
		if abilities[ability_id].hush > 0:
			hushes[ability_id] = abilities[ability_id].hush
	return HushFeature.new(hushes)
