class_name SpeciesContent
extends Content
## The species' content data (#279), which the species slice owns (#412): one JSONC file per
## species directly in its data/ (its own kind, so no folder repeats the slice's name, #442),
## checked against its schema there in CI. Everything else reads them through this; their abilities
## are AbilityContent's.

const DIR: String = "res://slices/species/data/"

## Every species, by id.
var species: Dictionary[String, Species] = {}


## Every species file in `directory`, read and checked.
static func load_species(directory: String = DIR) -> SpeciesContent:
	var content: SpeciesContent = SpeciesContent.new()
	content.read(directory)
	return content


## The species, read once per instance `setup` (FeatureSetup); species that don't load are an
## error, and there are none then.
static func species_for(setup: FeatureSetup) -> SpeciesContent:
	return setup.shared("species", _checked_species)


## Every species' special (#410), by species id, read once per instance `setup`. A special that
## doesn't load is an error, and its species has none.
static func specials_for(setup: FeatureSetup) -> Dictionary[String, Ability]:
	var known: SpeciesContent = species_for(setup)
	return setup.shared(
		"specials",
		func() -> Dictionary[String, Ability]: return _specials(known),
	)


static func _checked_species() -> SpeciesContent:
	var content: SpeciesContent = load_species()
	if not content.problem.is_empty():
		push_error("the species don't load: " + content.problem)
	return content


static func _specials(content: SpeciesContent) -> Dictionary[String, Ability]:
	var abilities: AbilityContent = AbilityContent.load_abilities()
	if not abilities.problem.is_empty():
		push_error("the abilities don't load: " + abilities.problem)
	var specials: Dictionary[String, Ability] = {}
	for species_id: String in content.species:
		var special: Ability = abilities.abilities.get(content.species[species_id].special)
		if special == null or special.kind != Ability.SPECIAL:
			push_error("%s's special doesn't load" % species_id)
			continue
		specials[species_id] = special
	return specials


## Its id must be one no species read before has.
func add(file_id: String, text: String) -> String:
	var entry: Species = Species.parse(file_id, text)
	# A repeated id is refused as that first, whatever else is wrong with the file, as before #279.
	if not entry.id.is_empty() and species.has(entry.id):
		return "its id must match the file name and be unique"
	if entry.problem.is_empty():
		species[entry.id] = entry
	return entry.problem
