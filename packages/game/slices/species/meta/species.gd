class_name Species
extends RefCounted
## What a monster is, dominated or not (a `species`, #45), read from content data (#72): its types,
## its auto attack's type, base stats and its three abilities (#222), its bestiary entry (#1173),
## which its codex page shows, its behaviour traits (#1200) and the model its monsters wear (#1223).
## Everything the simulation reads is integers and ids.

## Its schema, which says the fields a species file may have (SchemaFields, #825).
const SCHEMA: String = "res://slices/species/data/species.schema.json"
## A species' name is one invented word (owner, #717), never a description like "Moss Toad": a
## capital, then small letters. Its schema has the same pattern.
const NAME_PATTERN: String = "^[A-Z][a-z]+$"
## Where the models its monsters wear live (#1223).
const MODELS: String = "res://assets/"

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
## Its bestiary entry (#1173), as Content.codex_of reads it: its entry, then its gloss (codex_entry
## and codex_gloss). One field for both keeps the class within gdstyle's count of variables.
var _codex: Array[String] = ["", ""]
## Its behaviour traits (SpeciesBehaviour, #1200), which its monsters' daily schedule is made from.
var behaviour: Array[String] = []
## The model its monsters wear (#1223), wild or a companion: a res:// path to a glTF model under
## assets/ (SpeciesModels loads it).
var model: String = ""
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
		wrong = entry._read_codex_behaviour_and_model(data)
	return wrong


## Its lore, a short text about it and where its name comes from (#1173).
func codex_entry() -> String:
	return _codex[0]


## What its name means, hand-written (#959), e.g. "the low boom from the shallows".
func codex_gloss() -> String:
	return _codex[1]


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


## Reads its codex entry and gloss, its behaviour traits and its model from `data`; returns why it
## can't, or "".
func _read_codex_behaviour_and_model(data: Dictionary) -> String:
	var codex: Array[String] = Content.codex_of(data.get("codex"))
	if codex.is_empty():
		return "it needs a codex entry and gloss (#1173)"
	_codex = codex
	var wrong: String = SpeciesBehaviour.read(data.get("behaviour"), behaviour)
	return wrong if not wrong.is_empty() else _read_model(data.get("model"))


## Reads the model its monsters wear from `raw`; returns why it can't, or "": a glTF model under
## assets/ that exists.
func _read_model(raw: Variant) -> String:
	model = Content.text_of(raw)
	# Simplified, a path that climbs out of assets/ (`..`) would change.
	var named: bool = model.begins_with(MODELS) and model.simplify_path() == model
	named = named and model.get_extension() in ["glb", "gltf"]
	if not named or not ResourceLoader.exists(model):
		return "it needs a model: a glTF model under %s that exists (#1223)" % MODELS
	return ""
