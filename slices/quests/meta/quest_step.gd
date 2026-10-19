class_name QuestStep
extends RefCounted
## One step of a quest (#184): a single condition, met `count` times, or a choice between ways on
## (#573), each a place to reach or an area to enter, which the Survey marks, or an answer to give
## in a dialog (#636), leading to a step of its own. It's checked only against what the player
## obtains (a Gain), never inside the simulation.
## A step, a choice or a step that ends the chain can emit an event once it's done or taken (#575),
## which can start a side quest (`QuestDefinition.starts_on`).

## A step's fields, as the quest schema (slices/quests/data/quests.schema.json) allows them.
const FIELDS: Array[String] = [
	"id",
	"condition",
	"species",
	"target",
	"item",
	"place",
	"piece",
	"instance",
	"dialog",
	"answer",
	"count",
	"event",
	"choices",
	"ends",
	"emits",
]
## The fields of a step's condition, which a step with choices has none of.
const CONDITION_FIELDS: Array[String] = [
	"condition",
	"species",
	"target",
	"item",
	"place",
	"piece",
	"instance",
	"dialog",
	"answer",
	"event",
	"count",
]
## A choice's fields: where it's taken, or the answer that takes it, the step it leads to, and the
## event it emits.
const CHOICE_FIELDS: Array[String] = [
	"condition",
	"place",
	"piece",
	"instance",
	"dialog",
	"answer",
	"next",
	"emits",
]
## The condition met by an answer the player chose in a dialog (#636), named by `dialog` and
## `answer`, as the dialogs' files name them.
const ANSWERED: String = "answered"
## The conditions a choice can have: being somewhere, which a marker points at (stepping into a
## place, or entering a region piece or an instance), or an answer chosen.
const CHOICE_CONDITIONS: Array[String] = ["reached", "entered", ANSWERED]
## The condition met by an event a quest emitted (#575), or one that changed the world (#707, such
## as glade_purified), named by `event`: only a side quest's start waits on one, since a step
## waiting on it would have nothing to show the player.
const EMITTED: String = "emitted"
## The conditions a side quest's start can have: being somewhere, or an event emitted.
const START_CONDITIONS: Array[String] = ["reached", "entered", EMITTED]
## The conditions a step can have, each counted from facts a Gain carries: `dominated`, a wild
## monster this player dominated (the `quarry`: of `species`, or any, or the one quest target
## `target` a region's legend marks, #625); `opened`, a treasure chest this player got loot from;
## `reached`, the place `place` this player stepped into (#339); `entered`, the region
## piece `piece` (#350) or the instance `instance` (#370) this player entered; `answered`, the
## answer `answer` this player chose in the dialog `dialog` (#636); `obtained`, one of the item
## `item` this player obtained (#686), counted one per item. Defeating a monster waits until its
## event exists.
const CONDITIONS: Array[String] = [
	"dominated",
	"opened",
	"reached",
	"entered",
	ANSWERED,
	"obtained",
]
## The fact of a quest target dominated (#625), which a dominated step naming a target counts; a
## domination of a species is the fact `dominated`.
const TARGET_DOMINATED: String = "dominated_target"
## The fact of an instance entered, which an entered step naming an instance counts; a piece
## entered is the fact `entered`.
const INSTANCE_ENTERED: String = "entered_instance"

## Its id, which choices name to lead to it, or "" when nothing does (#573).
var id: String = ""
## The quest chain it closes once done (#573), its quest's id, or "" when the quest goes on.
var ends: String = ""
## The ways on a branching step offers, each a reached, entered or answered condition with the
## step it leads to in `next`; empty on a step with a condition of its own.
var choices: Array[QuestStep] = []
## On a choice, the id of the step it leads to.
var next: String = ""
## The event it emits once it's done, or once it's taken on a choice (#575), or "" for none.
var emits: String = ""
## The event an `emitted` condition asks for.
var event: String = ""
## What the step asks for, or "" on a step with choices.
var condition: String = ""
## The wild monster a `dominated` step asks for (#625): any, on any other step.
var quarry: QuestQuarry = QuestQuarry.new()
## The item an `obtained` step asks for, by its id, as loot tables name it: a material or a piece
## of gear (#694).
var item: String = ""
## The place a `reached` step asks for, as region legends name it (TileTrigger.REACH).
var place: String = ""
## The region piece an `entered` step asks for, by its file name, or "" when it asks for an
## instance.
var piece: String = ""
## The instance an `entered` step asks for, by its blueprint name, or "" when it asks for a piece.
var instance: String = ""
## The answer an `answered` step asks for (#636); its fields are "" on any other step.
var answer: QuestAnswer = QuestAnswer.new()
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
	step.id = Content.text_of(data.get("id"))
	step.ends = Content.text_of(data.get("ends"))
	step.emits = Content.text_of(data.get("emits"))
	step.problem = Content.unknown_field(data, FIELDS)
	if step.problem.is_empty():
		step.problem = _tag_problem(data, step)
	if step.problem.is_empty() and data.has("choices"):
		step.problem = step._read_choices(data)
	elif step.problem.is_empty():
		step._read_condition(data, known_species)
	return step


## Why `step`'s id, end or emitted event, read from `data`, is wrong, or "": each an id when it's
## there.
static func _tag_problem(data: Dictionary, step: QuestStep) -> String:
	if data.has("id") and not Content.is_id(step.id):
		return "its id must be lowercase words joined by underscores"
	if data.has("ends") and not Content.is_id(step.ends):
		return "the chain it ends must be a quest's id"
	if data.has("emits") and not Content.is_id(step.emits):
		return "the event it emits must be lowercase words joined by underscores"
	return ""


## Reads the choices of a branching step from `data`; returns why they're wrong, or "": two or more,
## each where a marker points with the step it leads to, and no condition of the step's own, nor an
## end, since a choice always leads on.
func _read_choices(data: Dictionary) -> String:
	for field: String in CONDITION_FIELDS:
		if data.has(field):
			return "a step with choices has no %s of its own" % field
	if data.has("ends"):
		return "a step with choices leads on, so it doesn't end its chain"
	var entries: Array = data["choices"] if data["choices"] is Array else []
	if entries.size() < 2:
		return "its choices are a list of two or more"
	for index: int in entries.size():
		var choice: QuestStep = _choice(entries[index])
		if not choice.problem.is_empty():
			return "choice %d: %s" % [index, choice.problem]
		choices.append(choice)
	return ""


## A choice read from `entry`: a reached, entered or answered condition, met once, and the step it
## leads to. Its `problem` says what's wrong.
static func _choice(entry: Variant) -> QuestStep:
	var data: Dictionary = entry if entry is Dictionary else {}
	var choice: QuestStep = QuestStep.new()
	choice.problem = Content.unknown_field(data, CHOICE_FIELDS)
	if entry is Dictionary and choice.problem.is_empty():
		var trigger: Dictionary = data.duplicate()
		var _without_next: bool = trigger.erase("next")
		choice = parse(trigger, {})
	elif choice.problem.is_empty():
		choice.problem = "it isn't an object"
	choice.next = Content.text_of(data.get("next"))
	if choice.problem.is_empty() and not CHOICE_CONDITIONS.has(choice.condition):
		choice.problem = "its condition must be one of %s" % [CHOICE_CONDITIONS]
	elif choice.problem.is_empty() and not Content.is_id(choice.next):
		choice.problem = "the step it leads to must be named by its id"
	return choice


## Reads the condition of a step that has one from `data`; `known_species` are the species it may
## name. Sets `problem` when it's wrong.
func _read_condition(data: Dictionary, known_species: Dictionary[String, Species]) -> void:
	condition = Content.text_of(data.get("condition"))
	var species_id: String = Content.text_of(data.get("species"))
	quarry.target = Content.text_of(data.get("target"))
	item = Content.text_of(data.get("item"))
	place = Content.text_of(data.get("place"))
	piece = Content.text_of(data.get("piece"))
	instance = Content.text_of(data.get("instance"))
	answer.dialog = Content.text_of(data.get("dialog"))
	answer.id = Content.text_of(data.get("answer"))
	event = Content.text_of(data.get("event"))
	count = Content.amount(data.get("count", 1))
	if not CONDITIONS.has(condition) and condition != EMITTED:
		problem = "its condition must be one of %s" % [CONDITIONS]
	elif data.has("species") and (condition != "dominated" or not known_species.has(species_id)):
		problem = "its species must be one that exists, on a dominated step"
	elif data.has("target") and (condition != "dominated" or data.has("species") or count != 1):
		problem = "its target is one monster a dominated step asks for, once, instead of a species"
	elif not _where_problem(data, self).is_empty():
		problem = _where_problem(data, self)
	elif count < 1:
		problem = "its count is a whole number from 1 to %d" % Fixed.MAX_AMOUNT
	if problem.is_empty() and data.has("species"):
		quarry.species = known_species[species_id]


## Why `step`'s place, piece, instance, dialog and answer, event or item, read from `data`, doesn't
## fit, or "": a reached step names a place, an entered step a piece (#350) or an instance (#370),
## never both, an answered step a dialog and its answer (#636), an emitted condition an event
## (#575) and an obtained step an item (#686), each as an id, and no other step names any; a
## dominated step's quest target is an id too (#625). Whether
## the dialog has the answer is QuestContent's check, which reads the dialogs. The instance must
## be a blueprint that exists.
static func _where_problem(data: Dictionary, step: QuestStep) -> String:
	if (step.condition == EMITTED) != data.has("event"):
		return "its event is what an emitted condition asks for, and only that"
	if (step.condition == "obtained") != data.has("item"):
		return "its item is what an obtained step asks for, and only that"
	if (step.condition == "reached") != data.has("place"):
		return "its place is what a reached step asks for, and only that"
	if (step.condition == "entered") != (data.has("piece") != data.has("instance")):
		return "its piece or instance is what an entered step asks for, one of them, and only that"
	var answered: bool = step.condition == ANSWERED
	if answered != data.has("dialog") or answered != data.has("answer"):
		return "its dialog and answer are what an answered step asks for, both, and only that"
	var named: Dictionary[String, String] = {
		"place": step.place,
		"piece": step.piece,
		"instance": step.instance,
		"dialog": step.answer.dialog,
		"answer": step.answer.id,
		"event": step.event,
		"item": step.item,
		"target": step.quarry.target,
	}
	for field: String in named:
		if data.has(field) and not TileTrigger.is_place_id(named[field]):
			return "its %s must be an id, lowercase words joined by underscores" % field
	if data.has("instance") and not InstanceBlueprints.exists(step.instance):
		return "its instance must be an instance blueprint that exists"
	return ""


## What the player can do to finish it, each a step of its own: its choices, or the step itself.
func triggers() -> Array[QuestStep]:
	var own: Array[QuestStep] = [self]
	return choices if not choices.is_empty() else own


## The choice one fact of `fact_condition` takes, `what` as `counts` reads it, or null when it takes
## none (or the step has no choices).
func choice_for(fact_condition: String, what: String) -> QuestStep:
	for choice: QuestStep in choices:
		if choice.counts(fact_condition, what):
			return choice
	return null


## Whether one fact of `fact_condition` (a domination of a species, a TARGET_DOMINATED, a chest, a
## place reached, a piece entered, an INSTANCE_ENTERED, an answer ANSWERED, an event EMITTED or an
## item obtained) counts here, toward any of its choices on a branching step; `what` is the species
## or the quest target dominated, the
## place reached, the piece or instance entered, the answer chosen as `answer_key` names it, the
## event emitted or the item obtained.
func counts(fact_condition: String, what: String) -> bool:
	if not choices.is_empty():
		return choice_for(fact_condition, what) != null
	if condition == EMITTED:
		return fact_condition == condition and event == what
	if condition == ANSWERED:
		return fact_condition == condition and answer.key() == what
	if condition == "reached":
		return fact_condition == condition and place == what
	if condition == "obtained":
		return fact_condition == condition and item == what
	if condition == "entered" and not instance.is_empty():
		return fact_condition == INSTANCE_ENTERED and instance == what
	if condition == "entered":
		return fact_condition == condition and piece == what
	if not quarry.target.is_empty():
		return fact_condition == TARGET_DOMINATED and quarry.target == what
	return fact_condition == condition and quarry.fits(what, "")


## The answer `answer_id` of the dialog `dialog_id` as one fact (#636): both ids, which never hold
## the slash between them.
static func answer_key(dialog_id: String, answer_id: String) -> String:
	return dialog_id + "/" + answer_id
