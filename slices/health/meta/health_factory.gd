class_name HealthFactory
extends RefCounted
## Builds an instance's health feature (#455, #823) with every species' HP, for companions and
## wild monsters (#835).


static func build(setup: FeatureSetup) -> HealthFeature:
	var content: SpeciesContent = SpeciesContent.species_for(setup)
	var max_hps: Dictionary[String, int] = {}
	for species_id: String in content.species:
		max_hps[species_id] = content.species[species_id].hp
	return HealthFeature.new(max_hps)
