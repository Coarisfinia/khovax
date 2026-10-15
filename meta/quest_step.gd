class_name QuestStep
extends RefCounted
## One step of a quest (#184): a single condition, met `count` times. It's checked only against what
## the player obtains (a Gain), never inside the simulation.

## A step's fields, as the quest schema (data/schemas/quests.schema.json) allows them.
const FIELDS: Array[String] = ["condition", "species", "count"]
## The conditions a step can have, each counted from facts a Gain carries: `caught`, a wild monster
## this player caught (of `species`, or any); `opened`, a treasure chest this player got loot from.
## Reaching a place and defeating a monster wait until their events exist.
const CONDITIONS: Array[String] = ["caught", "opened"]

var condition: String = ""
## The species a `caught` step asks for, or "" for any.
var species: String = ""
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
	step.count = Content.amount(data.get("count", 1))
	step.problem = Content.unknown_field(data, FIELDS)
	if not step.problem.is_empty():
		return step
	if not CONDITIONS.has(step.condition):
		step.problem = "its condition must be one of %s" % [CONDITIONS]
	elif (data.has("species")
			and (step.condition != "caught" or not known_species.has(step.species))):
		step.problem = "its species must be one that exists, on a caught step"
	elif step.count < 1:
		step.problem = "its count is a whole number from 1 to %d" % Fixed.MAX_AMOUNT
	return step


## Whether one fact of `fact_condition` (a catch of `caught_species`, or a chest) counts here.
func counts(fact_condition: String, caught_species: String) -> bool:
	return fact_condition == condition and (species.is_empty() or species == caught_species)
