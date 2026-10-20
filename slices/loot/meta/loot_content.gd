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
	var texts: Dictionary[String, String] = Content.texts_in(directory)
	for file_id: String in texts:
		var table: LootTable = LootTableFile.parse(file_id, texts[file_id])
		if not table.problem.is_empty():
			content.problem = file_id + ".jsonc: " + table.problem
			return content
		content.loot_tables[table.id] = table
	return content


## Every table of `kind` in `directory` (DIR or HARVEST_DIR), by its id, which is its species' id,
## read once per instance `setup` (FeatureSetup). Tables that don't load are an error, and there are
## none then.
static func species_tables_for(
	setup: FeatureSetup,
	directory: String,
	kind: String,
) -> Dictionary[String, LootTable]:
	var content: LootData = tables_for(setup, directory)
	var species_tables: Dictionary[String, LootTable] = {}
	for table: LootTable in content.loot_tables.values():
		if table.kind == kind:
			species_tables[table.id] = table
	return species_tables


## The instance's loot table (FeatureSetup.loot_table), which a blank and the loot on its ground
## roll on, or null when it has none or it doesn't load.
static func instance_table_for(setup: FeatureSetup) -> LootTable:
	return table_for(setup, setup.loot_table, LootTable.INSTANCE)


## The loot table with this id and `kind`, read once per instance `setup`, or null when the tables
## don't load or it isn't one.
static func table_for(setup: FeatureSetup, table_id: String, kind: String) -> LootTable:
	var table: LootTable = tables_for(setup, DIR).loot_tables.get(table_id)
	if table == null or table.kind != kind:
		return null
	return table


## Every loot table file in `directory`, read once per instance `setup`; tables that don't load
## are an error, and there are none then.
static func tables_for(setup: FeatureSetup, directory: String) -> LootData:
	return setup.shared(directory, func() -> LootData: return _checked(directory))


static func _checked(directory: String) -> LootData:
	var content: LootData = load_loot_tables(directory)
	if not content.problem.is_empty():
		push_error("the loot tables don't load: " + content.problem)
		content.loot_tables.clear()
	return content
