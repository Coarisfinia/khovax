class_name QuestDefinition
extends RefCounted
## A quest (#184), read from content data (the quests slice's data/, #72, #412): a
## player-facing name and a list of steps, each one condition met a number of times, or a choice
## between ways on. A quest is one quest chain (#573): its steps follow each other in the file's
## order, except where a step's choices lead to the steps they name, and it ends after a step tagged
## as its chain's end, or after its last step. A quest without choices is one path from its first
## step to its last. Each player's progress through it lives in their profile
## (Profile.quest_progress), advanced by what they obtain. A side quest (#473) starts only when the
## player enters the area it names; every other quest is open from the start. Finishing a quest,
## by whichever end, can move the player's standing with a faction (#532).

## A quest file's fields, as its schema (slices/quests/data/quests.schema.json) allows them.
const FIELDS: Array[String] = ["id", "name", "steps", PathMark.FIELD, "starts_on", "standing"]

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
	# A start that read is an object: QuestStep.parse refuses anything else.
	var data: Dictionary = entry if entry is Dictionary else {}
	if starts_on.problem.is_empty():
		starts_on.problem = Content.unknown_field(data, QuestStep.CONDITION_FIELDS)
	if not starts_on.problem.is_empty():
		return "its start: " + starts_on.problem
	if not QuestStep.PLACE_CONDITIONS.has(starts_on.condition):
		return "its start must be one of %s" % [QuestStep.PLACE_CONDITIONS]
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
	return _check_links()


## Why the steps don't hold together as one chain, or "": no two share an id, every choice leads to
## a step that exists, and a step ends this quest's chain, never another's. Whether every path
## reaches an end is checked apart (#576).
func _check_links() -> String:
	for index: int in steps.size():
		var step: QuestStep = steps[index]
		if not step.id.is_empty() and index_of(step.id) != index:
			return "step %d: its id %s is another step's too" % [index, step.id]
		if not step.ends.is_empty() and step.ends != id:
			return "step %d: it ends the chain %s, not its own, %s" % [index, step.ends, id]
		for choice: QuestStep in step.choices:
			if index_of(choice.next) < 0:
				return "step %d: a choice leads to %s, which no step is" % [index, choice.next]
	return ""


## Its name as the player reads it: with its path mark in words after it (#471).
func shown_name() -> String:
	return PathMark.tagged(name, path)


## The step at `index`, or null past the last one (a saved step whose quest was cut short since).
func step_at(index: int) -> QuestStep:
	return steps[index] if index >= 0 and index < steps.size() else null


## The index of the step with the id `step_id`, the first one when two share it, or -1 when none
## has it.
func index_of(step_id: String) -> int:
	for index: int in steps.size():
		if steps[index].id == step_id:
			return index
	return -1


## The index of the step that comes after the step at `index` once it's done, by the fact
## (`fact_condition`, `what`, as QuestStep.counts reads them) that did it: the step the choice it
## took leads to (the first choice's, for saved progress settling on a fact that takes none), past
## the last step when it ends the chain, or the next one in the file.
func next_index(index: int, fact_condition: String, what: String) -> int:
	var step: QuestStep = step_at(index)
	if step == null or not step.ends.is_empty():
		return steps.size()
	if step.choices.is_empty():
		return index + 1
	var choice: QuestStep = step.choice_for(fact_condition, what)
	return index_of(choice.next if choice != null else step.choices[0].next)


## The choice of the step at `index` that leads to the step at `to`, or null when none does.
func choice_to(index: int, to: int) -> QuestStep:
	var step: QuestStep = step_at(index)
	if step == null:
		return null
	for choice: QuestStep in step.choices:
		if index_of(choice.next) == to:
			return choice
	return null


## The indices of the steps sure to follow the step at `index`, in order: the ones after it in the
## file, up to the next choice or the chain's end, where what follows isn't known yet.
func steps_after(index: int) -> Array[int]:
	var after: Array[int] = []
	var at: int = index
	while (at >= 0 and at + 1 < steps.size() and steps[at].ends.is_empty()
			and steps[at].choices.is_empty()):
		at += 1
		after.append(at)
	return after
