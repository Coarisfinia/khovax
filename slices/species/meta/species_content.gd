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
