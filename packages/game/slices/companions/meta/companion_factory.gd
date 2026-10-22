class_name CompanionFactory
extends RefCounted
## Builds an instance's companion feature (#338, #823) with every species' reach, from its stats.


static func build(_setup: FeatureSetup) -> CompanionFeature:
	var content: SpeciesContent = SpeciesContent.cached()
	var reaches: Dictionary[String, int] = {}
	for species_id: String in content.species:
		var stats: Species = content.species[species_id]
		reaches[species_id] = CompanionFeature.reach_of(stats.hp, stats.strength, stats.speed)
	return CompanionFeature.new(reaches)
