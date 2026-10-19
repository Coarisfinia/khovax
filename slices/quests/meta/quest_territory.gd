class_name QuestTerritory
extends RefCounted
## The territory a territory quest hands over (#638): finishing it hands the instance to the
## faction (Territory), whoever held it before.

## A territory entry's fields, as the quest schema (slices/quests/data/quests.schema.json) allows
## them.
const FIELDS: Array[String] = ["instance", "faction"]

## The instance's blueprint name.
var instance: String = ""
## The faction's id; QuestContent checks that it exists.
var faction: String = ""
## Why the entry couldn't be read, or "" when it could.
var problem: String = ""


## The territory read from a quest file's `territory` entry. Its `problem` says what's wrong.
static func parse(entry: Variant) -> QuestTerritory:
	var territory: QuestTerritory = QuestTerritory.new()
	if not entry is Dictionary:
		territory.problem = "it isn't an object"
		return territory
	var data: Dictionary = entry
	territory.instance = Content.text_of(data.get("instance"))
	territory.faction = Content.text_of(data.get("faction"))
	territory.problem = Content.unknown_field(data, FIELDS)
	if territory.problem.is_empty() and not (
		Content.is_id(territory.instance) and Content.is_id(territory.faction)
	):
		territory.problem = "it names an instance and a faction, each an id"
	return territory
