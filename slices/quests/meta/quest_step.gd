class_name QuestStep
extends RefCounted
## One step of a quest (#184): a single condition, met `count` times. It's checked only against what
## the player obtains (a Gain), never inside the simulation.

## A step's fields, as the quest schema (slices/quests/data/quests.schema.json) allows them.
const FIELDS: Array[String] = ["condition", "species", "place", "piece", "instance", "count"]
## The conditions a step can have, each counted from facts a Gain carries: `dominated`, a wild
## monster this player dominated (of `species`, or any); `opened`, a treasure chest this player got
## loot from; `reached`, the place `place` this player stepped into (#339); `entered`, the region
## piece `piece` (#350) or the instance `instance` (#370) this player entered. Defeating a monster
## waits until its event exists.
const CONDITIONS: Array[String] = ["dominated", "opened", "reached", "entered"]
## The fact of an instance entered, which an entered step naming an instance counts; a piece
## entered is the fact `entered`.
const INSTANCE_ENTERED: String = "entered_instance"

var condition: String = ""
## The species a `dominated` step asks for, or "" for any.
var species: String = ""
## That species' name, as the player reads it (#351), or "".
var species_name: String = ""
## The place a `reached` step asks for, as region legends name it (TileTrigger.REACH).
var place: String = ""
## The region piece an `entered` step asks for, by its file name, or "" when it asks for an
## instance.
var piece: String = ""
## The instance an `entered` step asks for, by its blueprint name, or "" when it asks for a piece.
var instance: String = ""
var count: int = 1
## Why the step couldn't be read, or "" when it could.
var problem: String = ""


## A step read from a quest file's step entry; `known_species` are the species a step may name. Its
## `problem` says what's wrong.
static func parse(entry: Variant, known_species: Dictionary[String, Species]) -> QuestStep:
	var step: QuestStep = QuestStep.new()
	if not entry is Dictionary:
		step.problem = "it isn't an object"
		return step
	var data: Dictionary = entry
	step.condition = Content.text_of(data.get("condition"))
	step.species = Content.text_of(data.get("species"))
	step.place = Content.text_of(data.get("place"))
	step.piece = Content.text_of(data.get("piece"))
	step.instance = Content.text_of(data.get("instance"))
	step.count = Content.amount(data.get("count", 1))
	step.problem = Content.unknown_field(data, FIELDS)
	if not step.problem.is_empty():
		return step
	if not CONDITIONS.has(step.condition):
		step.problem = "its condition must be one of %s" % [CONDITIONS]
	elif (data.has("species")
			and (step.condition != "dominated" or not known_species.has(step.species))):
		step.problem = "its species must be one that exists, on a dominated step"
	elif not _where_problem(data, step).is_empty():
		step.problem = _where_problem(data, step)
	elif step.count < 1:
		step.problem = "its count is a whole number from 1 to %d" % Fixed.MAX_AMOUNT
	if step.problem.is_empty() and data.has("species"):
		step.species_name = known_species[step.species].name
	return step


## Why `step`'s place, piece or instance, read from `data`, doesn't fit, or "": a reached step
## names a place and an entered step a piece (#350) or an instance (#370), never both, each as an
## id, and no other step names any. The instance must be a blueprint that exists.
static func _where_problem(data: Dictionary, step: QuestStep) -> String:
	if (step.condition == "reached") != data.has("place"):
		return "its place is what a reached step asks for, and only that"
	if (step.condition == "entered") != (data.has("piece") != data.has("instance")):
		return "its piece or instance is what an entered step asks for, one of them, and only that"
	var named: Dictionary[String, String] = {
		"place": step.place,
		"piece": step.piece,
		"instance": step.instance,
	}
	for field: String in named:
		if data.has(field) and not TileTrigger.is_place_id(named[field]):
			return "its %s must be an id, lowercase words joined by underscores" % field
	if data.has("instance") and not InstanceBlueprints.exists(step.instance):
		return "its instance must be an instance blueprint that exists"
	return ""


## Whether one fact of `fact_condition` (a domination of a species, a chest, a place reached, a
## piece entered or an INSTANCE_ENTERED) counts here; `what` is the species dominated, the place
## reached, or the piece or instance entered.
func counts(fact_condition: String, what: String) -> bool:
	if condition == "reached":
		return fact_condition == condition and place == what
	if condition == "entered" and not instance.is_empty():
		return fact_condition == INSTANCE_ENTERED and instance == what
	if condition == "entered":
		return fact_condition == condition and piece == what
	return fact_condition == condition and (species.is_empty() or species == what)
