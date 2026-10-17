class_name QuestContent
extends RefCounted
## The quests' content data (#184), which the quests slice owns (#412): one JSONC file per quest in
## its data/quests/, checked against data/quests.schema.json beside it in CI, and here against the
## species. Everything else reads the quests through this.

const DIR: String = "res://slices/quests/data/quests/"


## Every quest file in `directory`, read and checked; the species its steps name must be in
## `species_directory`.
static func load_quests(
	directory: String = DIR,
	species_directory: String = SpeciesContent.SPECIES_DIR,
) -> Content:
	var content: Content = SpeciesContent.load_species(species_directory)
	if not content.problem.is_empty():
		return content
	# Sorted, so the quests are read in the same order on every machine.
	var file_names: Array[String] = []
	file_names.assign(DirAccess.get_files_at(directory))
	file_names.sort()
	for file_name: String in file_names:
		if file_name.ends_with(".jsonc"):
			var text: String = FileAccess.get_file_as_string(directory + file_name)
			var quest: QuestDefinition = QuestDefinition.parse(
				file_name.get_basename(),
				text,
				content.species,
			)
			if not quest.problem.is_empty():
				content.problem = file_name + ": " + quest.problem
				return content
			content.quests[quest.id] = quest
	return content
