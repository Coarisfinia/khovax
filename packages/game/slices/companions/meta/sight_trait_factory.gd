class_name SightTraitFactory
extends RefCounted
## Builds an instance's sight trait feature (#962, #823) with every species' sight trait, from the
## species content.


static func build(_setup: FeatureSetup) -> SightTraitFeature:
	var content: SpeciesContent = SpeciesContent.cached()
	var sights: Dictionary[String, int] = {}
	for species_id: String in content.species:
		var species: Species = content.species[species_id]
		if species.sight > 0:
			sights[species_id] = species.sight
	return SightTraitFeature.new(sights)
