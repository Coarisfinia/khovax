class_name QuestStep
extends RefCounted
## One step of a quest (#184): a single condition, met `count` times. It's checked only against what
## the player obtains (a Gain), never inside the simulation.

## A step's fields, as the quest schema (data/schemas/quests.schema.json) allows them.
const FIELDS: Array[String] = ["condition", "species", "place", "piece", "count"]
## The conditions a step can have, each counted from facts a Gain carries: `dominated`, a wild
## monster this player dominated (of `species`, or any); `opened`, a treasure chest this player got
## loot from; `reached`, the place `place` this player stepped into (#339); `entered`, the region
## piece `piece` this player entered (#350). Defeating a monster waits until its event exists.
const CONDITIONS: Array[String] = ["dominated", "opened", "reached", "entered"]

var condition: String = ""
## The species a `dominated` step asks for, or "" for any.
var species: String = ""
## That species' name, as the player reads it (#351), or "".
var species_name: String = ""
## The place a `reached` step asks for, as region legends name it (TileTrigger.REACH).
var place: String = ""
## The region piece an `entered` step asks for, by its file name.
var piece: String = ""
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


## Why `step`'s place or piece, read from `data`, doesn't fit, or "": a reached step names a place
## and an entered step a piece (#350), each as an id, and no other step names either.
static func _where_problem(data: Dictionary, step: QuestStep) -> String:
	var wanted: Dictionary[String, String] = { "place": "reached", "piece": "entered" }
	for field: String in wanted:
		var value: String = step.place if field == "place" else step.piece
		if (step.condition == wanted[field]) != data.has(field):
			return "its %s is what a %s step asks for, and only that" % [field, wanted[field]]
		if data.has(field) and not TileTrigger.is_place_id(value):
			return "its %s must be an id, lowercase words joined by underscores" % field
	return ""


## Whether one fact of `fact_condition` (a domination of a species, a chest, a place reached or a
## piece entered) counts here; `what` is the species dominated, the place reached or the piece
## entered.
func counts(fact_condition: String, what: String) -> bool:
	if condition == "reached":
		return fact_condition == condition and place == what
	if condition == "entered":
		return fact_condition == condition and piece == what
	return fact_condition == condition and (species.is_empty() or species == what)
