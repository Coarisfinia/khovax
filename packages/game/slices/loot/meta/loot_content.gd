class_name LootContent
extends Content
## The loot tables' content data (#90), which the loot slice owns (#412): one JSONC file per table,
## and one harvest table per species in data/harvest_tables/ (#687), each checked against the
## schema beside it in CI. The loot tables are the resource packs' (#1953): the ones the packs list,
## so a player's pack can add or replace one; the default pack's lie in the slice's
## data/loot_tables/. Everything else reads them through this.

## The loot tables' key in the content cache (ContentCatalog), and the source that reads them.
const KEY: String = "loot_tables"
## The harvest tables' folder, which is also their key: they're read from it, not from a pack.
const HARVEST_DIR: String = "res://slices/loot/data/harvest_tables/"

## Every loot table, by id.
var loot_tables: Dictionary[String, LootTable] = {}


## Every table of `source`, read and checked: the loot tables the resource packs list
## (ResourcePacks.loot_tables) for KEY, or every harvest table file in HARVEST_DIR.
static func load_loot_tables(source: String = KEY) -> LootContent:
	if source == KEY:
		return load_files(ResourcePacks.loot_tables())
	var content: LootContent = LootContent.new()
	content.read(source)
	return content


## Every loot table in `files` (each res:// path by its id), read and checked: a file that's missing
## or broken is the problem.
static func load_files(files: Dictionary[String, String]) -> LootContent:
	var content: LootContent = LootContent.new()
	content.read_files(files)
	return content


## Every table of `source` (KEY or HARVEST_DIR), read once per session (ContentCatalog); tables that
## don't load are an error, and there are none then.
static func cached(source: String = KEY) -> LootContent:
	return ContentCatalog.kept(source, _checked.bind(source))


## Every table of `kind` in `source` (KEY or HARVEST_DIR), by its id, which is its species' id.
static func species_tables_for(source: String, kind: String) -> Dictionary[String, LootTable]:
	var species_tables: Dictionary[String, LootTable] = {}
	for table: LootTable in cached(source).loot_tables.values():
		if table.kind == kind:
			species_tables[table.id] = table
	return species_tables


## The instance's loot table (FeatureSetup.loot_table), which a blank and the loot on its ground
## roll on, or null when it has none or it doesn't load.
static func instance_table_for(setup: FeatureSetup) -> LootTable:
	return table_for(setup.loot_table, LootTable.INSTANCE)


## The loot table with this id and `kind`, or null when the tables don't load or it isn't one.
static func table_for(table_id: String, kind: String) -> LootTable:
	var table: LootTable = cached().loot_tables.get(table_id)
	if table == null or table.kind != kind:
		return null
	return table


static func _checked(source: String) -> LootContent:
	var content: LootContent = load_loot_tables(source)
	if not content.problem.is_empty():
		push_error("the loot tables don't load: " + content.problem)
		content.loot_tables.clear()
	return content


func add(file_id: String, text: String) -> String:
	var table: LootTable = LootTableFile.parse(file_id, text)
	if table.problem.is_empty():
		loot_tables[table.id] = table
	return table.problem
