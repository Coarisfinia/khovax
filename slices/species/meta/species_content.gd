class_name SpeciesContent
extends RefCounted
## The species' and abilities' content data (#279, #222), which the species slice owns (#412): one
## JSONC file per entry, a species directly in its data/ (its own kind, so no folder repeats the
## slice's name, #442) and an ability in data/abilities/, each checked against its schema in data/
## in CI. Everything else reads them through this.

const SPECIES_DIR: String = "res://slices/species/data/"
const ABILITIES_DIR: String = "res://slices/species/data/abilities/"


## Every species file in `directory`, read and checked.
static func load_species(directory: String = SPECIES_DIR) -> SpeciesData:
	var content: SpeciesData = SpeciesData.new()
	var texts: Dictionary[String, String] = Content.texts_in(directory)
	for file_id: String in texts:
		content.problem = content.add_species(file_id, texts[file_id])
		if not content.problem.is_empty():
			content.problem = file_id + ".jsonc: " + content.problem
			return content
	return content


## Every ability file in `directory`, read and checked (#222).
static func load_abilities(directory: String = ABILITIES_DIR) -> SpeciesData:
	var content: SpeciesData = SpeciesData.new()
	var texts: Dictionary[String, String] = Content.texts_in(directory)
	for file_id: String in texts:
		var ability: Ability = Ability.parse(file_id, texts[file_id])
		if not ability.problem.is_empty():
			content.problem = file_id + ".jsonc: " + ability.problem
			return content
		content.abilities[ability.id] = ability
	return content


## The species, read once per instance `setup` (FeatureSetup); species that don't load are an
## error, and there are none then.
static func species_for(setup: FeatureSetup) -> SpeciesData:
	return setup.shared("species", _checked_species)


## Every species' special (#410), by species id, read once per instance `setup`. A special that
## doesn't load is an error, and its species has none.
static func specials_for(setup: FeatureSetup) -> Dictionary[String, Ability]:
	var species: SpeciesData = species_for(setup)
	return setup.shared(
		"specials",
		func() -> Dictionary[String, Ability]: return _specials(species),
	)


static func _checked_species() -> SpeciesData:
	var content: SpeciesData = load_species()
	if not content.problem.is_empty():
		push_error("the species don't load: " + content.problem)
	return content


static func _specials(content: SpeciesData) -> Dictionary[String, Ability]:
	var abilities: SpeciesData = load_abilities()
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
