class_name QuestDefinition
extends RefCounted
## A quest (#184), read from content data (the quests slice's data/, #72, #412): a
## player-facing name and a list of steps, each one condition met a number of times, or a choice
## between ways on. A quest is one quest chain (#573): its steps follow each other in the file's
## order, except where a step's choices lead to the steps they name, and it ends after a step tagged
## as its chain's end. A quest without choices is one path from its first step to its last, which
## is tagged as the end; in every quest, every path must reach a tagged end (#576, QuestPaths).
## Each player's progress through it lives in their profile (QuestTracker.progress), advanced by
## what they obtain. A side quest (#473) starts only when the player enters the area it names, or
## once a quest emits the event it names (#575); every other quest is open from the start.
## Finishing a quest, by whichever end, can move the player's standing with a faction (#532), and
## finishing a territory quest hands its instance to its faction (#638); its steps all count only
## there (#769).

## Its schema, which says the fields a quest file and its parts may have (SchemaFields, #825).
const SCHEMA: String = "res://slices/quests/data/quests.schema.json"

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
## The alignment finishing it enforces (#1326), one per faction, applied after `standing`; none
## when it enforces none.
var alignment: Array[QuestAlignment] = []
## The territory finishing it hands over (#638); null for a quest that isn't a territory quest.
var territory: QuestTerritory = null
## Whether finishing it ends the main story (#1333), which puts the player in the postgame
## (Profile.postgame).
var ends_story: bool = false
## The materials finishing it gives (#1348), by id: how many of each; none when it gives none.
var materials: Dictionary[String, int] = {}
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
	var parsed: Variant = Content.object_of(text)
	if parsed == null:
		quest.problem = Content.NOT_AN_OBJECT
		return quest
	var data: Dictionary = parsed
	quest.id = Content.text_of(data.get("id"))
	quest.name = Content.text_of(data.get("name"))
	quest.path = PathMark.read(data)
	quest.problem = quest._read_fields(data)
	if quest.problem.is_empty():
		quest.problem = quest._check(file_id, data.get("steps"), known_species)
	if quest.problem.is_empty() and data.has("starts_on"):
		quest.problem = quest._check_start(data.get("starts_on"))
	if quest.problem.is_empty():
		quest.problem = quest._read_factions(data)
	if quest.problem.is_empty() and data.has("materials"):
		quest.problem = quest._read_materials(data.get("materials"))
	if quest.problem.is_empty() and data.has("territory"):
		quest.territory = QuestTerritory.parse(data.get("territory"))
		if not quest.territory.problem.is_empty():
			quest.problem = "its territory: " + quest.territory.problem
		else:
			quest.problem = quest._territory_steps_problem()
	return quest


## Reads the marks `data` gives this quest, its end of the main story (#1333); returns why the
## data has a field a quest's schema doesn't, or a mark isn't true or false, or "".
func _read_fields(data: Dictionary) -> String:
	var unknown: String = Content.unknown_field(data, SchemaFields.at(SCHEMA))
	var ends: Variant = data.get("ends_story", false)
	ends_story = ends is bool and ends
	if unknown.is_empty() and not ends is bool:
		return "its ends_story must be true or false"
	return unknown


## Why a step or choice of this territory quest doesn't happen in its territory, or "": each names
## the territory's instance as where it counts (#769), the ground rules in AGENTS.md.
func _territory_steps_problem() -> String:
	for index: int in steps.size():
		for trigger: QuestStep in steps[index].triggers():
			if trigger.instance != territory.instance:
				return "step %d: a territory quest's steps name its instance %s" % [
					index, territory.instance,
				]
	return ""


## Why the materials finishing it gives, read from `entry`, are wrong, or "": at least one, each
## named by an id and given a whole count from 1 to what a profile can hold.
func _read_materials(entry: Variant) -> String:
	var given: Dictionary = entry if entry is Dictionary else {}
	if given.is_empty():
		return "its materials must name one or more materials, each with a count"
	for key: Variant in given:
		var material: String = str(key) if key is String else ""
		var count: int = JsonNumbers.whole(given[key], 1, Profile.MAX_NUMBER, 0)
		if not Content.is_id(material) or count == 0:
			return "its materials must give each id a whole count from 1"
		materials[material] = count
	return ""


## Why the side quest's start, read from `entry`, is wrong, or "": a reached, entered or emitted
## condition with the place, piece, instance or event it names, met once.
func _check_start(entry: Variant) -> String:
	starts_on = QuestStep.parse(entry, {})
	# A start that read is an object: QuestStep.parse refuses anything else.
	var data: Dictionary = entry if entry is Dictionary else {}
	if starts_on.problem.is_empty() and data.has("count"):
		return "its start happens once, so it has no count"
	if starts_on.problem.is_empty():
		var fields: Array[String] = SchemaFields.at(SCHEMA, QuestStep.START_POINTER)
		starts_on.problem = Content.unknown_field(data, fields)
	if not starts_on.problem.is_empty():
		return "its start: " + starts_on.problem
	if not QuestStep.START_CONDITIONS.has(starts_on.condition):
		return "its start must be one of %s" % [QuestStep.START_CONDITIONS]
	return ""


## Why the read fields are wrong, or "", and the steps read from `raw_steps` when they aren't.
func _check(
	file_id: String,
	raw_steps: Variant,
	known_species: Dictionary[String, Species],
) -> String:
	var wrong_id: String = Content.id_problem(id, file_id)
	if not wrong_id.is_empty():
		return wrong_id
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
		if step.condition == QuestStep.EMITTED:
			return "step %d: only a side quest's start waits on an event" % index
		steps.append(step)
	var links: String = _check_links()
	return links if not links.is_empty() else QuestPaths.problem(self)


## Why the steps don't hold together as one chain, or "": no two share an id, every choice leads to
## a step that exists, and a step ends this quest's chain, never another's. Whether every path
## reaches an end is QuestPaths' check (#576).
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


## Its name as the player reads it: its text tags showing the names they stand for (#733), and its
## path mark in words after it (#471).
func shown_name() -> String:
	return PathMark.tagged(TextTags.shown(name), path)


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
## (`fact_condition`, `what` and `where`, as QuestStep.counts reads them) that did it: the step the
## choice it took leads to (the first choice's, for saved progress settling on a fact that takes
## none), past the last step when it ends the chain, or the next one in the file.
func next_index(index: int, fact_condition: String, what: String, where: String) -> int:
	var step: QuestStep = step_at(index)
	if step == null or not step.ends.is_empty():
		return steps.size()
	if step.choices.is_empty():
		return index + 1
	var choice: QuestStep = step.choice_for(fact_condition, what, where)
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


## Reads how finishing it moves and enforces the player's standings (#532, #1326) from the quest
## file's `data` into `standing` and `alignment`; returns why they can't be read, or "".
func _read_factions(data: Dictionary) -> String:
	if data.has("standing"):
		standing = QuestStanding.parse(data.get("standing"))
		if not standing.problem.is_empty():
			return "its standing: " + standing.problem
	return _read_alignment(data.get("alignment")) if data.has("alignment") else ""


## Reads the alignment `entries` it enforces (#1326) into `alignment`; returns why they can't be
## read (not a list, an empty one, an entry that doesn't read, or a faction named twice), or "".
func _read_alignment(entries: Variant) -> String:
	var listed: Array = entries if entries is Array else []
	if listed.is_empty():
		return "its alignment must be a list of at least one faction"
	for entry: Variant in listed:
		var read: QuestAlignment = QuestAlignment.parse(entry)
		if not read.problem.is_empty():
			return "its alignment: " + read.problem
		for earlier: QuestAlignment in alignment:
			if earlier.faction == read.faction:
				return "its alignment names %s twice" % read.faction
		alignment.append(read)
	return ""
