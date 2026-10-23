class_name SpeciesModels
extends RefCounted
## The model each species' monsters wear (#1223), wild or a companion, as its data names it
## (Species.model). Each is loaded once and kept: a figure for every monster of a species
## instantiates the same scene.

## Each species' model, by species id, once loaded.
static var _scenes: Dictionary[String, PackedScene] = {}


## The model monsters of `species_id` wear, or null when none loads (an error). A species that
## doesn't load wears the first loaded
## species' model, in id order, so its figure still stands; the species' own error is
## SpeciesContent's.
static func scene_of(species_id: String) -> PackedScene:
	if _scenes.has(species_id):
		return _scenes[species_id]
	var species: Dictionary[String, Species] = SpeciesContent.cached().species
	var known: Species = species.get(species_id)
	if known == null:
		for other_id: String in species:
			if known == null or other_id < known.id:
				known = species[other_id]
	if known == null:
		return null
	var scene: PackedScene = load(known.model) as PackedScene
	if scene == null:
		push_error("%s's model %s doesn't load" % [known.id, known.model])
	_scenes[species_id] = scene
	return scene
