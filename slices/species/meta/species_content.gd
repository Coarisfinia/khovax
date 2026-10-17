class_name SpeciesContent
extends RefCounted
## The species' and abilities' content data (#279, #222), which the species slice owns (#412): one
## JSONC file per entry, a species directly in its data/ (its own kind, so no folder repeats the
## slice's name, #442) and an ability in data/abilities/, each checked against its schema in data/
## in CI. Everything else reads them through this.

const SPECIES_DIR: String = "res://slices/species/data/"
const ABILITIES_DIR: String = "res://slices/species/data/abilities/"


## Every species file in `directory`, read and checked.
static func load_species(directory: String = SPECIES_DIR) -> Content:
	var content: Content = Content.new()
	for file_name: String in DirAccess.get_files_at(directory):
		if file_name.ends_with(".jsonc"):
			var text: String = FileAccess.get_file_as_string(directory + file_name)
			content.problem = content.add_species(file_name.get_basename(), text)
			if not content.problem.is_empty():
				content.problem = file_name + ": " + content.problem
				return content
	return content


## Every ability file in `directory`, read and checked (#222).
static func load_abilities(directory: String = ABILITIES_DIR) -> Content:
	var content: Content = Content.new()
	for file_name: String in DirAccess.get_files_at(directory):
		if file_name.ends_with(".jsonc"):
			var text: String = FileAccess.get_file_as_string(directory + file_name)
			var ability: Ability = Ability.parse(file_name.get_basename(), text)
			if not ability.problem.is_empty():
				content.problem = file_name + ": " + ability.problem
				return content
			content.abilities[ability.id] = ability
	return content
