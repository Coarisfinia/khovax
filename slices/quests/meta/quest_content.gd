class_name QuestContent
extends RefCounted
## The quests' content data (#184), which the quests slice owns (#412): one JSONC file per quest
## directly in its data/ (its own kind, so no folder repeats the slice's name, #442), checked
## against quests.schema.json beside them in CI, and here against the species. Everything else
## reads the quests through this.

const DIR: String = "res://slices/quests/data/"


## Every quest file in `directory`, read and checked; the species its steps name must be in
## `species_directory`, and the faction whose standing it moves (#532) in `faction_directory`.
static func load_quests(
	directory: String = DIR,
	species_directory: String = SpeciesContent.SPECIES_DIR,
	faction_directory: String = FactionContent.DIR,
) -> QuestData:
	var species: SpeciesData = SpeciesContent.load_species(species_directory)
	var factions: FactionContent = FactionContent.load_factions(faction_directory)
	var content: QuestData = QuestData.new()
	content.species = species.species
	content.problem = species.problem + factions.problem
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
			if quest.standing != null and not factions.factions.has(quest.standing.faction):
				quest.problem = "its standing's faction must be one that exists"
			if not quest.problem.is_empty():
				content.problem = file_name + ": " + quest.problem
				return content
			content.quests[quest.id] = quest
	return content
