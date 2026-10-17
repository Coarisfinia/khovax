class_name QuestDefinition
extends RefCounted
## A quest (#184), read from content data (the quests slice's data/quests/, #72, #412): a
## player-facing name and an ordered
## list of steps, each one condition met a number of times. Each player's progress through it lives
## in their profile (Profile.quest_progress), advanced by what they obtain.

## A quest file's fields, as its schema (slices/quests/data/quests.schema.json) allows them.
const FIELDS: Array[String] = ["id", "name", "steps"]

var id: String = ""
## The player-facing name.
var name: String = ""
var steps: Array[QuestStep] = []
## Why the quest couldn't be read, or "" when it could.
var problem: String = ""


## A quest read from a quest file's text, named `file_id`; its steps may name `known_species`. Its
## `problem` says what's wrong.
static func parse(
	file_id: String,
	text: String,
	known_species: Dictionary[String, Species],
) -> QuestDefinition:
	var quest: QuestDefinition = QuestDefinition.new()
	var json: JSON = JSON.new()
	if json.parse(Jsonc.strip(text)) != OK or not json.data is Dictionary:
		quest.problem = "not a JSON object"
		return quest
	var data: Dictionary = json.data
	quest.id = Content.text_of(data.get("id"))
	quest.name = Content.text_of(data.get("name"))
	quest.problem = Content.unknown_field(data, FIELDS)
	if quest.problem.is_empty():
		quest.problem = quest._check(file_id, data.get("steps"), known_species)
	return quest


## Why the read fields are wrong, or "", and the steps read from `raw_steps` when they aren't.
func _check(
	file_id: String,
	raw_steps: Variant,
	known_species: Dictionary[String, Species],
) -> String:
	if id != file_id or not Content.is_id(id):
		return "its id must match the file name and be lowercase words with underscores"
	if name.strip_edges().is_empty():
		return "it needs a name"
	var entries: Array = raw_steps if raw_steps is Array else []
	if entries.is_empty():
		return "it needs at least one step"
	for index: int in entries.size():
		var step: QuestStep = QuestStep.parse(entries[index], known_species)
		if not step.problem.is_empty():
			return "step %d: %s" % [index, step.problem]
		steps.append(step)
	return ""


## The step at `index`, or null past the last one (a saved step whose quest was cut short since).
func step_at(index: int) -> QuestStep:
	return steps[index] if index >= 0 and index < steps.size() else null
