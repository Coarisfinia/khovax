class_name PackFactory
extends RefCounted
## Builds an instance's pack feature (#1205) with every species' types, which a `pack_type`
## monster bands by; when the species don't load, monsters band only with their own species.


static func build(_setup: FeatureSetup) -> PackFeature:
	var content: SpeciesContent = SpeciesContent.cached()
	var types: Dictionary[String, Array] = {}
	for species_id: String in content.species:
		types[species_id] = content.species[species_id].types
	return PackFeature.new(types)
