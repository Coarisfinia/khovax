class_name WildMonsterFactory
extends RefCounted
## Builds an instance's wild monster feature (#823) from its blueprint's species weights and every
## species' strength (#219); when the species don't load, its monsters push on nothing.


static func build(setup: FeatureSetup) -> WildMonsterFeature:
	var roster: Array[String] = []
	roster.assign(setup.wild_species.keys())
	var weights: Array[int] = []
	weights.assign(setup.wild_species.values())
	var content: SpeciesData = SpeciesContent.species_for(setup)
	var strengths: Dictionary[String, int] = {}
	for species_id: String in content.species:
		strengths[species_id] = content.species[species_id].strength
	return WildMonsterFeature.new(roster, weights, strengths)
