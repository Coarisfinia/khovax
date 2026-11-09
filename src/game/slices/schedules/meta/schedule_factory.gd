class_name ScheduleFactory
extends RefCounted
## Builds an instance's schedule feature (#1201) with every species' behaviour traits (#1200); when
## the species don't load, its monsters wander all day.


static func build(_setup: FeatureSetup) -> ScheduleFeature:
	var content: SpeciesContent = SpeciesContent.cached()
	var traits: Dictionary[String, Array] = {}
	for species_id: String in content.species:
		traits[species_id] = content.species[species_id].behaviour
	return ScheduleFeature.new(traits)
