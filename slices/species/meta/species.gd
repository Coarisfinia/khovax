class_name Species
extends RefCounted
## What a monster is, dominated or not (a `species`, #45), read from content data (#72): its types,
## its auto attack's type, base stats, wild archetype and its three abilities (#222). Everything
## here is integers and ids, ready for the simulation.

const ARCHETYPES: Array[String] = ["charger", "burrower", "flyer", "swarm", "pusher"]
## Its schema, which says the fields a species file may have (SchemaFields, #825).
const SCHEMA: String = "res://slices/species/data/species.schema.json"
## A species' name is one invented word (owner, #717), never a description like "Moss Toad": a
## capital, then small letters. Its schema has the same pattern.
const NAME_PATTERN: String = "^[A-Z][a-z]+$"

var id: String = ""
## What the player reads (#351); code and saves use the id.
var name: String = ""
## One or two types (#68); dual types are the norm later in the game.
var types: Array[String] = []
## Its auto attack's type, from the chart, whatever fits it rather than one of its own (owner on
## #626).
var strike_type: String = ""
var hp: int = 0
var strength: int = 0
## Higher is faster (#222).
var speed: int = 0
## How it behaves as a wild monster against rings: one of ARCHETYPES (#222).
var archetype: String = ""
## Its abilities' ids (the species slice's data/abilities/): its special attack and its two passives
## (#222).
var special: String = ""
var player_passive: String = ""
var self_passive: String = ""
## Why the species couldn't be read, or "" when it could.
var problem: String = ""


## Reads its speed, archetype, strike type and abilities from a species file's `data`; returns why
## it can't, or "". Whether the abilities exist is checked against the ability data (Content).
func read_kit(data: Dictionary) -> String:
	speed = Content.amount(data.get("speed"))
	strike_type = Content.text_of(data.get("strike_type"))
	archetype = Content.text_of(data.get("archetype"))
	special = Content.text_of(data.get("special"))
	player_passive = Content.text_of(data.get("player_passive"))
	self_passive = Content.text_of(data.get("self_passive"))
	if speed < 1:
		return "speed is a whole number from 1 to %d" % Fixed.MAX_AMOUNT
	if not ARCHETYPES.has(archetype):
		return "its archetype is one of %s" % [ARCHETYPES]
	if TypeChart.family_of(strike_type) < 0:
		return "its strike type is a type on the chart"
	for ability: String in [special, player_passive, self_passive]:
		if not Content.is_id(ability):
			return "it names a special and two passives by their ids"
	return ""


## A species read from a species file's text, named `file_id`, and checked against the type chart
## (#279); its `problem` says what's wrong.
static func parse(file_id: String, text: String) -> Species:
	var entry: Species = Species.new()
	var json: JSON = JSON.new()
	if json.parse(Jsonc.strip(text)) != OK or not json.data is Dictionary:
		entry.problem = "not a JSON object"
		return entry
	var data: Dictionary = json.data
	entry.problem = _read(entry, file_id, data)
	return entry


## Reads `data` into `entry`; returns why it can't, or "".
static func _read(entry: Species, file_id: String, data: Dictionary) -> String:
	var fields: Array[String] = SchemaFields.at(SCHEMA)
	for key: Variant in data:
		if not fields.has(str(key)):
			return "field %s isn't a species field" % key
	var given_id: Variant = data.get("id")
	var text_id: String = given_id if given_id is String else ""
	if not Content.is_id(text_id):
		return "its id must be lowercase words joined by underscores"
	entry.id = text_id
	entry.hp = Content.amount(data.get("hp"))
	entry.strength = Content.amount(data.get("strength"))
	var given_types: Variant = data.get("types")
	if given_types is Array:
		var type_list: Array = given_types
		for type: Variant in type_list:
			entry.types.append(str(type))
	if entry.id != file_id:
		return "its id must match the file name and be unique"
	if entry.hp < 1 or entry.strength < 1:
		return "hp and strength are whole numbers from 1 to %d" % Fixed.MAX_AMOUNT
	var wrong: String = entry._types_problem()
	if wrong.is_empty():
		wrong = entry.read_kit(data)
	entry.name = Content.text_of(data.get("name"))
	if wrong.is_empty() and RegEx.create_from_string(NAME_PATTERN).search(entry.name) == null:
		wrong = "it needs a name: one invented word, capitalised (#717)"
	# Code, data and saves name a species by its id, which is its name (owner, #763).
	if wrong.is_empty() and entry.id != entry.name.to_lower():
		wrong = "its id must be its name in lower case (#763)"
	return wrong


## Why its types don't fit the chart, or "": one or two, from the chart, never two of one family.
func _types_problem() -> String:
	if types.is_empty() or types.size() > 2:
		return "a species has one or two types"
	var families: Array[int] = []
	for type: String in types:
		var family: int = TypeChart.family_of(type)
		if family < 0 or families.has(family):
			return "type %s isn't on the chart, or two types share a family" % type
		families.append(family)
	return ""
