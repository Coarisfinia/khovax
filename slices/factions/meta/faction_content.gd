class_name FactionContent
extends RefCounted
## The factions' content data (#483), which the factions slice owns (#412): one JSONC file per
## faction directly in its data/ (its own kind, so no folder repeats the slice's name, #442),
## checked against factions.schema.json beside them in CI. Everything else reads the factions
## through this.

const DIR: String = "res://slices/factions/data/"

## Every faction, by id.
var factions: Dictionary[String, Faction] = {}
## Why the data couldn't be read, or "" when it could.
var problem: String = ""


## Every faction file in `directory`, read and checked.
static func load_factions(directory: String = DIR) -> FactionContent:
	var content: FactionContent = FactionContent.new()
	for file_name: String in DirAccess.get_files_at(directory):
		if file_name.ends_with(".jsonc"):
			var text: String = FileAccess.get_file_as_string(directory + file_name)
			var faction: Faction = Faction.parse(file_name.get_basename(), text)
			if not faction.problem.is_empty():
				content.problem = file_name + ": " + faction.problem
				return content
			content.factions[faction.id] = faction
	return content
