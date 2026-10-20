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
## The quests facts advance, by id (QuestContent.cached): content, not saved. Progress for a
## quest that isn't here is kept untouched, on purpose: a quest missing from one build's data
## (dropped by mistake, or not shipped yet) picks up where the player left it once it's back.
var book: Dictionary[String, QuestDefinition] = {}


## Counts `fact`: an item obtained as many times as obtained (`count_obtained`), any other fact
## once (`count`). Returns the quests it finished, in the order finished.
func advance(fact: QuestFact) -> Array[QuestDefinition]:
	if fact.condition == QuestStep.OBTAINED:
		return count_obtained(fact, fact.amount)
	return count(fact)


## Counts `fact`, then every event the quests it advanced emitted (#575), in the order emitted:
## each as a fact of its own, which can start side quests waiting on it. Only a side quest's start
## waits on an event, and each starts once, so the events always run out. An event happens in the
## whole world, so it counts nowhere in particular. Returns the quests it finished, in the order
## finished.
func count(fact: QuestFact) -> Array[QuestDefinition]:
	var done: Array[QuestDefinition] = []
	var pending: Array[String] = _advance(fact, done)
	while not pending.is_empty():
		var event: String = pending.pop_front()
		pending.append_array(_advance_event(event, done))
	return done


## Counts the event `event` a quest emitted as a fact of its own (`_advance`).
func _advance_event(event: String, done: Array[QuestDefinition]) -> Array[String]:
	return _advance(QuestFact.new(QuestStep.EMITTED, event), done)


## Counts `amount` of the item `fact` names as obtained (#686), one at a time, so one gain can
## finish a step and count toward the next; it stops once no open step asks for the item, so a
## large amount costs no more than the steps asking for it. Returns the quests it finished, in the
## order finished.
func count_obtained(fact: QuestFact, amount: int) -> Array[QuestDefinition]:
	var done: Array[QuestDefinition] = []
	for _counted: int in amount:
		var asked: bool = false
		for step: QuestStep in open_steps().values():
			asked = asked or step.counts(fact.condition, fact.what, fact.where)
		if not asked:
			break
		done.append_array(count(fact))
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
