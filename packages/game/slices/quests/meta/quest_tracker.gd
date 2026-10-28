class_name QuestTracker
extends RefCounted
## The player's quests (#184, #817): which they started and how far they are, which they finished,
## and the quest book the facts they gain advance them against. Kept in the profile and saved with
## it; what finishing a quest gives (standing, path leaning, a territory's hand-over) is the
## profile's, which takes the quests `count` returns as finished.

## Each quest started and not finished, by id: the step it's on, the count within it and the steps
## done.
var progress: Dictionary[String, QuestProgress] = {}
## The ids of the quests finished, in the order finished.
var finished: Array[String] = []
## The side quests (#473) started and not finished, in the order started: the newest last, which
## the player follows unless they picked another (`focused`, #1298).
var started: Array[String] = []
## The quest the player picked to follow (#1298), or "" when they follow the newest one. Kept while
## it's open; once it's finished, they follow the newest again.
var focus: String = ""
## The quests facts advance, by id (QuestContent.cached): content, not saved. Progress for a
## quest that isn't here is kept untouched, on purpose: a quest missing from one build's data
## (dropped by mistake, or not shipped yet) picks up where the player left it once it's back.
var book: Dictionary[String, QuestDefinition] = {}


## Counts `fact`: an item obtained as many times as obtained (`count_obtained`), any other fact
## once (`count`), adding the events the quests it advanced emitted (#575) to `emitted`, in the
## order emitted. Returns the quests it finished, in the order finished.
func advance(fact: QuestFact, emitted: Array[String] = []) -> Array[QuestDefinition]:
	if fact.condition == QuestStep.OBTAINED:
		return count_obtained(fact, fact.amount, emitted)
	return count(fact, emitted)


## Counts `fact`, adding the events the quests it advanced emitted (#575) to `emitted`, in the
## order emitted. They don't count here: they go into the world (QuestEventFeature), and count
## once it raises them back (WorldChanged, owner, #755), on every player's quests alike, so none
## counts twice. Returns the quests it finished, in the order finished.
func count(fact: QuestFact, emitted: Array[String] = []) -> Array[QuestDefinition]:
	var done: Array[QuestDefinition] = []
	emitted.append_array(_advance(fact, done))
	return done


## Counts `amount` of the item `fact` names as obtained (#686), one at a time, so one gain can
## finish a step and count toward the next; it stops once no open step asks for the item, so a
## large amount costs no more than the steps asking for it. Adds the events emitted to `emitted`;
## returns the quests it finished, in the order finished.
func count_obtained(
	fact: QuestFact,
	amount: int,
	emitted: Array[String] = [],
) -> Array[QuestDefinition]:
	var done: Array[QuestDefinition] = []
	for _counted: int in amount:
		var asked: bool = false
		for step: QuestStep in open_steps().values():
			asked = asked or step.counts(fact.condition, fact.what, fact.where)
		if not asked:
			break
		done.append_array(count(fact, emitted))
	return done


## Counts `fact` toward every quest in the book whose current step asks for it, in id order, so
## quests finished together are listed in the same order on every machine, adding those it finishes
## to `done`. A step that reaches its count hands over to the next one (on a step with choices,
## #573, the one the choice the fact took leads to), and a step that ends the chain, or the last
## one, finishes the quest.
## Saved progress that no longer fits the quest (its data changed since) settles at the next fact
## of any kind: a step already at its count is complete, and a step past the last one finishes the
## quest.
## A side quest the fact starts (#473) is started first, so the same fact can count toward its first
## step; a side quest not started yet counts nothing. Returns the events the steps done and the
## choices taken emit, in that order.
func _advance(fact: QuestFact, done: Array[QuestDefinition]) -> Array[String]:
	var ids: Array[String] = _ids()
	var emitted: Array[String] = []
	for id: String in ids:
		if not _started(id) and book[id].starts_on.counts(fact.condition, fact.what, fact.where):
			progress[id] = progress_of(id)
			started.append(id)
	for id: String in ids:
		var quest: QuestDefinition = book[id]
		var at: QuestProgress = progress_of(id)
		var step: QuestStep = quest.step_at(at.step)
		var open: bool = step != null and at.count < step.count
		var waits: bool = open and not step.counts(fact.condition, fact.what, fact.where)
		if finished.has(id) or not _started(id) or waits:
			continue
		at.count += 1 if open else 0
		if step != null and at.count >= step.count:
			emitted.append_array(_emits(step, fact))
			at.move_to(quest.next_index(at.step, fact.condition, fact.what, fact.where))
		progress[id] = at
		if at.step >= quest.steps.size():
			var _ended: bool = progress.erase(id)
			started.erase(id)
			focus = "" if focus == id else focus
			finished.append(id)
			done.append(quest)
	return emitted


## The events `step`, now done by `fact`, emits (#575): its own, then that of the choice the fact
## took, the first one for saved progress settling on a fact that takes none, as
## QuestDefinition.next_index goes on.
static func _emits(step: QuestStep, fact: QuestFact) -> Array[String]:
	var choice: QuestStep = step.choice_for(fact.condition, fact.what, fact.where)
	if choice == null and not step.choices.is_empty():
		choice = step.choices[0]
	var events: Array[String] = []
	for emitter: QuestStep in [step, choice]:
		if emitter != null and not emitter.emits.is_empty():
			events.append(emitter.emits)
	return events


## The step each open quest in the book is on, by quest id in id order: every quest not finished
## yet, started or not (#300: what quest markers point at), except a side quest the player hasn't
## come upon yet (#473).
func open_steps() -> Dictionary[String, QuestStep]:
	var steps: Dictionary[String, QuestStep] = {}
	for id: String in _ids():
		var step: QuestStep = book[id].step_at(progress_of(id).step)
		if step != null and not finished.has(id) and _started(id):
			steps[id] = step
	return steps


## The open quest the player follows (#1298), the only one the quest list and the Survey show
## large: the one they picked (`focus`) while it's open, else the side quest they started last
## that's still open, else the first open quest in id order; "" when none is open.
func focused() -> String:
	var steps: Dictionary[String, QuestStep] = open_steps()
	if steps.has(focus):
		return focus
	for at: int in range(started.size() - 1, -1, -1):
		# A save from before the order was kept lists every quest with progress (QuestSave).
		if steps.has(started[at]) and book[started[at]].starts_on != null:
			return started[at]
	for id: String in steps:
		return id
	return ""


## The progress of quest `id`: a fresh one when it hasn't started.
func progress_of(id: String) -> QuestProgress:
	return progress.get(id, QuestProgress.new())


## The ids of the quests in the book, in order.
func _ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(book.keys())
	ids.sort()
	return ids


## Whether quest `id` has started: a quest without a start always has, and a side quest (#473) once
## the player entered its area, which put its progress here. `id` is in the book.
func _started(id: String) -> bool:
	return book[id].starts_on == null or progress.has(id) or finished.has(id)
