class_name Content
extends RefCounted
## The game's content data (#72): JSONC files under data/, one per entry, checked against their
## schema in CI (data/schemas/) and here for what a schema can't check: ids unique and matching
## their file, types from the type chart, and two types never from the same family.

const SPECIES_DIR: String = "res://data/species/"
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


## Reads one species file's text, named `file_id`; returns why it can't, or "".
func add_species(file_id: String, text: String) -> String:
	var json: JSON = JSON.new()
	if json.parse(Jsonc.strip(text)) != OK or not json.data is Dictionary:
		return "not a JSON object"
	var data: Dictionary = json.data
	var entry: Species = Species.new()
	entry.id = str(data.get("id", ""))
	entry.hp = _amount(data.get("hp"))
	entry.strength = _amount(data.get("strength"))
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


## A whole JSON number from 1 to Fixed.MAX_AMOUNT, or 0 for anything else.
static func _amount(value: Variant) -> int:
	if not (value is int or value is float):
		return 0
	var number: float = value
	if number != floorf(number) or number < 1.0 or number > Fixed.MAX_AMOUNT:
		return 0
	var whole: int = type_convert(value, TYPE_INT)
	return whole
