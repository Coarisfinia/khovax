class_name Species
extends RefCounted
## What a monster is, dominated or not (a `species`, #45), read from content data (#72): its types,
## its auto attack's type, base stats and its three abilities (#222), its bestiary entry (#1173),
## which its codex page shows, and its behaviour traits (#1200). Everything the simulation reads is
## integers and ids.

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
## Its abilities' ids (the species slice's data/abilities/): its special attack and its two passives
## (#222).
var special: String = ""
var player_passive: String = ""
var self_passive: String = ""
## Its sight trait (#962): how many steps further a player who carries it sees, 0 for none.
var sight: int = 0
## Its bestiary entry (#1173): its lore, a short text about it and where its name comes from, and
## what its name means, hand-written (#959), e.g. "the low boom from the shallows".
var codex_entry: String = ""
var codex_gloss: String = ""
## Its behaviour traits (SpeciesBehaviour, #1200), which its monsters' daily schedule is made from.
var behaviour: Array[String] = []
## Why the species couldn't be read, or "" when it could.
var problem: String = ""


## Reads its speed, strike type, abilities and sight trait from a species file's `data`; returns why
## it can't, or "". Whether the abilities exist is checked against the ability data (Content).
func read_kit(data: Dictionary) -> String:
	speed = Content.amount(data.get("speed"))
	strike_type = Content.text_of(data.get("strike_type"))
	special = Content.text_of(data.get("special"))
	player_passive = Content.text_of(data.get("player_passive"))
	self_passive = Content.text_of(data.get("self_passive"))
	if data.has("sight"):
		sight = JsonNumbers.whole(data.get("sight"), 1, FogFeature.MOST_WIDER, 0)
		if sight == 0:
			return "its sight is a whole number of steps from 1 to %d" % FogFeature.MOST_WIDER
	if speed < 1:
		return "speed is a whole number from 1 to %d" % Fixed.MAX_AMOUNT
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
	var parsed: Variant = Content.object_of(text)
	if parsed == null:
		entry.problem = Content.NOT_AN_OBJECT
		return entry
	var data: Dictionary = parsed
	entry.problem = _read(entry, file_id, data)
	return entry


## Reads `data` into `entry`; returns why it can't, or "".
static func _read(entry: Species, file_id: String, data: Dictionary) -> String:
	var fields: Array[String] = SchemaFields.at(SCHEMA)
	for key: Variant in data:
		if not fields.has(str(key)):
			return "field %s isn't a species field" % key
	# Set even when it's wrong, so SpeciesContent refuses a repeated id as that first.
	entry.id = Content.text_of(data.get("id"))
	var wrong_id: String = Content.id_problem(entry.id, file_id)
	if not wrong_id.is_empty():
		return wrong_id
	entry.hp = Content.amount(data.get("hp"))
	entry.strength = Content.amount(data.get("strength"))
	var given_types: Variant = data.get("types")
	if given_types is Array:
		var type_list: Array = given_types
		for type: Variant in type_list:
			entry.types.append(str(type))
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
	if wrong.is_empty():
		wrong = entry._read_codex_and_behaviour(data)
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


## Reads its codex entry and gloss and its behaviour traits from `data`; returns why it can't, or
## "".
func _read_codex_and_behaviour(data: Dictionary) -> String:
	if not _read_codex(data.get("codex")):
		return "it needs a codex entry and gloss (#1173)"
	return SpeciesBehaviour.read(data.get("behaviour"), behaviour)


## Whether `raw` holds a codex entry and gloss, each with more than spaces; reads them.
func _read_codex(raw: Variant) -> bool:
	var codex: Array[String] = Content.codex_of(raw)
	if codex.is_empty():
		return false
	codex_entry = codex[0]
	codex_gloss = codex[1]
	return true
