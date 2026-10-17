class_name Content
extends RefCounted
## The game's content data (#72): JSONC files, one per entry, under data/ or, for a kind a slice
## owns, under that slice's data/ (#412), checked against their schema in CI and here for what a
## schema can't check, each by its own kind: ids
## unique and matching their file. Species are checked by Species (#279) and abilities by Ability,
## read by the species slice
## (SpeciesContent), loot tables (#90) by
## LootTable, tile blueprints (#116) by TileBlueprint, and quests
## (#184) by QuestDefinition against the species, read by the quests slice (QuestContent). Here too:
## the field helpers they all use.

const LOOT_TABLES_DIR: String = "res://data/loot_tables/"
const TILES_DIR: String = "res://data/tiles/"

## Every species, by id.
var species: Dictionary[String, Species] = {}
## Every loot table, by id.
var loot_tables: Dictionary[String, LootTable] = {}
## Every tile blueprint, by id.
var tiles: Dictionary[String, TileBlueprint] = {}
## Every quest, by id.
var quests: Dictionary[String, QuestDefinition] = {}
## Every ability, by id (#222).
var abilities: Dictionary[String, Ability] = {}
## Why the content couldn't be read, or "" when it could.
var problem: String = ""


## Every loot table file in `directory`, read and checked.
static func load_loot_tables(directory: String = LOOT_TABLES_DIR) -> Content:
	var content: Content = Content.new()
	for file_name: String in DirAccess.get_files_at(directory):
		if file_name.ends_with(".jsonc"):
			var text: String = FileAccess.get_file_as_string(directory + file_name)
			var table: LootTable = LootTableFile.parse(file_name.get_basename(), text)
			if not table.problem.is_empty():
				content.problem = file_name + ": " + table.problem
				return content
			content.loot_tables[table.id] = table
	return content


## Every tile blueprint file in `directory`, read and checked.
static func load_tiles(directory: String = TILES_DIR) -> Content:
	var content: Content = Content.new()
	var numbers: Dictionary[int, bool] = {}
	for file_name: String in DirAccess.get_files_at(directory):
		if file_name.ends_with(".jsonc"):
			var text: String = FileAccess.get_file_as_string(directory + file_name)
			var tile: TileBlueprint = TileBlueprint.parse(file_name.get_basename(), text)
			if tile.problem.is_empty() and numbers.has(tile.number):
				tile.problem = "its number %d is another tile blueprint's" % tile.number
			if not tile.problem.is_empty():
				content.problem = file_name + ": " + tile.problem
				return content
			content.tiles[tile.id] = tile
			numbers[tile.number] = true
	return content


## Reads one species file's text, named `file_id`, and adds it; returns why it can't, or "". Its id
## must be one no species read before has.
func add_species(file_id: String, text: String) -> String:
	var entry: Species = Species.parse(file_id, text)
	# A repeated id is refused as that first, whatever else is wrong with the file, as before #279.
	if not entry.id.is_empty() and species.has(entry.id):
		return "its id must match the file name and be unique"
	if entry.problem.is_empty():
		species[entry.id] = entry
	return entry.problem


## Whether `text` is an id: a lowercase letter, then lowercase letters, digits and underscores.
static func is_id(text: String) -> bool:
	var pattern: RegEx = RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	return pattern.search(text) != null


## A whole JSON number from 1 to Fixed.MAX_AMOUNT, or 0 for anything else.
static func amount(value: Variant) -> int:
	if not (value is int or value is float):
		return 0
	var number: float = value
	if number != floorf(number) or number < 1.0 or number > Fixed.MAX_AMOUNT:
		return 0
	var whole: int = type_convert(value, TYPE_INT)
	return whole


## Why `data` has a field outside `allowed`, or "".
static func unknown_field(data: Dictionary, allowed: Array[String]) -> String:
	for key: Variant in data:
		if not allowed.has(str(key)):
			return "field %s isn't allowed here" % key
	return ""


## `value` if it's a string, or "" for anything else, so that e.g. `true` never reads as an id.
static func text_of(value: Variant) -> String:
	var text: String = value if value is String else ""
	return text
