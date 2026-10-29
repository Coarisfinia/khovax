class_name WildMonsterFactory
extends RefCounted
## Builds an instance's wild monster feature (#823) from its blueprint's species weights and every
## species' strength (#219) and the first form of its line (#1697); when the species don't load,
## its monsters push on nothing, and its babies are of their own species.


static func build(setup: FeatureSetup) -> WildMonsterFeature:
	var roster: Array[String] = []
	roster.assign(setup.wild_species.keys())
	var weights: Array[int] = []
	weights.assign(setup.wild_species.values())
	var content: SpeciesContent = SpeciesContent.cached()
	var strengths: Dictionary[String, int] = {}
	var first_forms: Dictionary[String, String] = {}
	for species_id: String in content.species:
		strengths[species_id] = content.species[species_id].strength
		# Only ascensions that check out lead back to a first form: a chain that came back round
		# would never end, so content that doesn't load has babies of their own species.
		if content.problem.is_empty():
			first_forms[species_id] = content.first_form(species_id)
	return WildMonsterFeature.new(roster, weights, strengths, first_forms)
