class_name LootContent
extends RefCounted
## The loot tables' content data (#90), which the loot slice owns (#412): one JSONC file per table
## in its data/loot_tables/, and one harvest table per species in data/harvest_tables/ (#687), each
## checked against the schema beside it in CI. Everything else reads them through this.

const DIR: String = "res://slices/loot/data/loot_tables/"
const HARVEST_DIR: String = "res://slices/loot/data/harvest_tables/"


## Every loot table file in `directory` (DIR, or HARVEST_DIR for the harvest tables), read and
## checked.
static func load_loot_tables(directory: String = DIR) -> LootData:
	var content: LootData = LootData.new()
	for file_name: String in DirAccess.get_files_at(directory):
		if file_name.ends_with(".jsonc"):
			var text: String = FileAccess.get_file_as_string(directory + file_name)
			var table: LootTable = LootTableFile.parse(file_name.get_basename(), text)
			if not table.problem.is_empty():
				content.problem = file_name + ": " + table.problem
				return content
			content.loot_tables[table.id] = table
	return content
