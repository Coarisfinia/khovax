class_name Content
extends RefCounted
## The game's content data (#72): JSONC files under data/, one per entry, checked against their
## schema in CI (data/schemas/) and here for what a schema can't check: ids unique and matching
## their file, types from the type chart, and two types never from the same family. Loot tables
## (#90) are read here too, checked by LootTable, tile blueprints (#116), checked by
## TileBlueprint, and quests (#184), checked by QuestDefinition against the species.

const SPECIES_DIR: String = "res://data/species/"
const LOOT_TABLES_DIR: String = "res://data/loot_tables/"
const TILES_DIR: String = "res://data/tiles/"
const QUESTS_DIR: String = "res://data/quests/"
## A species file's fields, as its schema (data/schemas/species.schema.json) allows them.
const SPECIES_FIELDS: Array[String] = ["id", "types", "hp", "strength"]
## The type chart (#68): five families, each with its Lesser and Greater type, by family id.
## Families have no names; each is shown as an icon in a circle on its color.
const FAMILIES: Array[Array] = [
	["mana", "arcane"],
	["shadow", "abyss"],
	["might", "titan"],
	["growth", "nature"],
	["breeze", "tempest"],
]

## Every species, by id.
var species: Dictionary[String, Species] = {}
## Every loot table, by id.
var loot_tables: Dictionary[String, LootTable] = {}
## Every tile blueprint, by id.
var tiles: Dictionary[String, TileBlueprint] = {}
## Every quest, by id.
var quests: Dictionary[String, QuestDefinition] = {}
## Why the content couldn't be read, or "" when it could.
var problem: String = ""


## The family id of a type, or -1 for a type that isn't on the chart.
static func family_of(type: String) -> int:
	for family: int in FAMILIES.size():
		if FAMILIES[family].has(type):
			return family
	return -1


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


## Every loot table file in `directory`, read and checked.
static func load_loot_tables(directory: String = LOOT_TABLES_DIR) -> Content:
	var content: Content = Content.new()
	for file_name: String in DirAccess.get_files_at(directory):
		if file_name.ends_with(".jsonc"):
			var text: String = FileAccess.get_file_as_string(directory + file_name)
			var table: LootTable = LootTable.parse(file_name.get_basename(), text)
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


## Every quest file in `directory`, read and checked; the species its steps name must be in
## `species_directory`.
static func load_quests(
	directory: String = QUESTS_DIR,
	species_directory: String = SPECIES_DIR,
) -> Content:
	var content: Content = load_species(species_directory)
	if not content.problem.is_empty():
		return content
	for file_name: String in DirAccess.get_files_at(directory):
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


## Reads one species file's text, named `file_id`; returns why it can't, or "".
func add_species(file_id: String, text: String) -> String:
	var json: JSON = JSON.new()
	if json.parse(Jsonc.strip(text)) != OK or not json.data is Dictionary:
		return "not a JSON object"
	var data: Dictionary = json.data
	for key: Variant in data:
		if not SPECIES_FIELDS.has(str(key)):
			return "field %s isn't a species field" % key
	var id: Variant = data.get("id")
	var text_id: String = id if id is String else ""
	if not is_id(text_id):
		return "its id must be lowercase words joined by underscores"
	var entry: Species = Species.new()
	entry.id = text_id
	entry.hp = amount(data.get("hp"))
	entry.strength = amount(data.get("strength"))
	var types: Variant = data.get("types")
	if types is Array:
		var type_list: Array = types
		for type: Variant in type_list:
			entry.types.append(str(type))
	if entry.id != file_id or species.has(entry.id):
		return "its id must match the file name and be unique"
	if entry.hp < 1 or entry.strength < 1:
		return "hp and strength are whole numbers from 1 to %d" % Fixed.MAX_AMOUNT
	return _check_types(entry)


func _check_types(entry: Species) -> String:
	if entry.types.is_empty() or entry.types.size() > 2:
		return "a species has one or two types"
	var families: Array[int] = []
	for type: String in entry.types:
		var family: int = family_of(type)
		if family < 0 or families.has(family):
			return "type %s isn't on the chart, or two types share a family" % type
		families.append(family)
	species[entry.id] = entry
	return ""


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
