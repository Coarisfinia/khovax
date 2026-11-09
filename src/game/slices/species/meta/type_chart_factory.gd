class_name TypeChartFactory
extends RefCounted
## Builds an instance's type chart feature (#626, #823) with every species' types, its auto attack's
## type and its special's type, from the species and ability data.


static func build(_setup: FeatureSetup) -> TypeEffectivenessFeature:
	var content: SpeciesContent = SpeciesContent.cached()
	var types: Dictionary[String, PackedStringArray] = {}
	var auto_types: Dictionary[String, String] = {}
	for species_id: String in content.species:
		types[species_id] = PackedStringArray(content.species[species_id].types)
		auto_types[species_id] = content.species[species_id].strike_type
	var special_types: Dictionary[String, String] = {}
	var specials: Dictionary[String, Ability] = content.specials()
	for species_id: String in specials:
		special_types[species_id] = specials[species_id].strike_type
	return TypeEffectivenessFeature.new(types, auto_types, special_types)
