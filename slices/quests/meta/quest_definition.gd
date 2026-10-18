class_name QuestDefinition
extends RefCounted
## A quest (#184), read from content data (the quests slice's data/, #72, #412): a
## player-facing name and an ordered
## list of steps, each one condition met a number of times. Each player's progress through it lives
## in their profile (Profile.quest_progress), advanced by what they obtain. A side quest (#473)
## starts only when the player enters the area it names; every other quest is open from the start.
## Finishing a quest can move the player's standing with a faction (#532).

## A quest file's fields, as its schema (slices/quests/data/quests.schema.json) allows them.
const FIELDS: Array[String] = ["id", "name", "steps", PathMark.FIELD, "starts_on", "standing"]
## The conditions a side quest can start on: stepping into a place, or entering a region piece or
## an instance.
const START_CONDITIONS: Array[String] = ["reached", "entered"]

var id: String = ""
## The player-facing name.
var name: String = ""
var steps: Array[QuestStep] = []
## Its path mark (#471): PathMark.NONE, HARMONY, SUPREMACY or BOTH.
var path: String = PathMark.NONE
## What starts a side quest, written like a step that's met once; null for a quest open from the
## start.
var starts_on: QuestStep = null
## How finishing it moves the player's standing with a faction; null when it doesn't.
var standing: QuestStanding = null
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
	quest.path = PathMark.read(data)
	quest.problem = Content.unknown_field(data, FIELDS)
	if quest.problem.is_empty():
		quest.problem = quest._check(file_id, data.get("steps"), known_species)
	if quest.problem.is_empty() and data.has("starts_on"):
		quest.problem = quest._check_start(data.get("starts_on"))
	if quest.problem.is_empty() and data.has("standing"):
		quest.standing = QuestStanding.parse(data.get("standing"))
		if not quest.standing.problem.is_empty():
			quest.problem = "its standing: " + quest.standing.problem
	return quest


## Why the side quest's start, read from `entry`, is wrong, or "": a reached or entered condition
## with the place, piece or instance it names, met once.
func _check_start(entry: Variant) -> String:
	starts_on = QuestStep.parse(entry, {})
	if not starts_on.problem.is_empty():
		return "its start: " + starts_on.problem
	if not START_CONDITIONS.has(starts_on.condition):
		return "its start must be one of %s" % [START_CONDITIONS]
	# A start that read is an object: QuestStep.parse refuses anything else.
	var data: Dictionary = entry if entry is Dictionary else {}
	if data.has("count"):
		return "its start happens once, so it has no count"
	return ""


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
	if path.is_empty():
		return PathMark.PROBLEM
	var entries: Array = raw_steps if raw_steps is Array else []
	if entries.is_empty():
		return "it needs at least one step"
	for index: int in entries.size():
		var step: QuestStep = QuestStep.parse(entries[index], known_species)
		if not step.problem.is_empty():
			return "step %d: %s" % [index, step.problem]
		steps.append(step)
	return ""


## Its name as the player reads it: with its path mark in words after it (#471).
func shown_name() -> String:
	return PathMark.tagged(name, path)


## The step at `index`, or null past the last one (a saved step whose quest was cut short since).
func step_at(index: int) -> QuestStep:
	return steps[index] if index >= 0 and index < steps.size() else null
