class_name Profile
extends RefCounted

## The player's profile (#37): what lasts between sessions, outside the simulation. It changes when
## the player obtains something in the world (a Gain, saved at once by ProfileKeeper so a crash
## loses nothing), never because of a tick itself. Integers and ids only, like everything that
## feeds a simulation. Saved as versioned JSON by ProfileSave (#276). Quest progress (#184) is kept
## here too, advanced by the same gains against the quest definitions it's given, and so are the
## player's personal color (#233), which only views read, and their standings with the factions
## (#483), which finishing a quest can move (#532), their gear (#690), and their leaning toward
## the story's paths (#658), which finishing a path-marked quest moves.
## Active slots at the start (design report: 1, then +1 from a lore quest, +1 at level 50).
const START_SLOTS: int = 1
const MAX_SLOTS: int = 3
## How many dominated monsters a player carries (#53): always three, never more.
const CARRY_LIMIT: int = 3
## The largest id, count or number a save may hold: JSON numbers are doubles, which hold every
## whole number up to 2^53 exactly, and this stays far below it.
const MAX_NUMBER: int = Fixed.MAX_AMOUNT
## The personal color while Auto picks it: the world's default (PersonalColor.of).
const AUTO_COLOR: int = -1
## The largest personal color: white, as 0xRRGGBB.
const MAX_COLOR: int = 0xffffff
## The longest name a character can have, in characters.
const NAME_LIMIT: int = 24

var unlocked_slots: int = START_SLOTS
## Every dominated monster: in the order dominated, until the player orders them (`move_monster`).
var dominated_monsters: Array[DominatedMonster] = []
## The dominated monsters this player carries, by id, in the order the next one comes in when one
## faints (#53, #54): the first three of the player's order (`order`, #430), the first of them their
## companion. Until the player moves one, the first three dominated, in the order dominated.
var carried: Array[int] = []
## The id the next dominated monster gets; ids are never reused.
var next_monster_id: int = 1
## Crafting materials, by id: how many of each.
var materials: Dictionary[String, int] = {}
## Each quest started and not finished, by id: the step it's on, the count within it and the steps
## done.
var quest_progress: Dictionary[String, QuestProgress] = {}
## The ids of the quests finished, in the order finished.
var quests_done: Array[String] = []
## The quests gains advance, by id (QuestContent.load_quests): content, not saved. Progress for a
## quest
## that isn't here is kept untouched, on purpose: a quest missing from one build's data (dropped by
## mistake, or not shipped yet) picks up where the player left it once it's back.
var quest_book: Dictionary[String, QuestDefinition] = {}
## The player's standing with each faction (#483).
var standings: Standings = Standings.new()
## The gear the player owns and what's in their gear slots (#690).
var gear: GearSlots = GearSlots.new()
## How far the player's choices lean them toward harmony and supremacy (#658).
var leaning: PathLeaning = PathLeaning.new()
## The personal color the player chose (#391), as 0xRRGGBB, or AUTO_COLOR. A view's, never the
## simulation's (#233).
var personal_color: int = AUTO_COLOR
## The character's name (#399), the player's own; "" until they name them. Never in the simulation.
var character_name: String = ""
## Why the save couldn't be read, or "" when it could.
var problem: String = ""
## Which of the save's generations it was loaded from: 0 the newest, more when newer ones were
## damaged (SaveStore). Not saved.
var loaded_generation: int = 0


## Takes over what the player just obtained: its dominations and materials, and every quest they
## advance, one fact at a time, so one gain can finish a step and count toward the next. Returns why
## the gain can't be taken over, or "", and changes nothing when it can't: a profile that took over
## a bad gain couldn't be loaded again. ProfileKeeper saves it.
func apply(result: Gain) -> String:
	var refusal: String = _result_problem(result)
	if not refusal.is_empty():
		return refusal
	for i: int in result.dominated_species.size():
		var species: String = result.dominated_species[i]
		var short_ids: Array[String] = result.dominated_short_ids
		_dominate(species, short_ids[i] if i < short_ids.size() else "")
		_count_fact("dominated", species)
	for _chest: int in result.chests_opened:
		_count_fact("opened", "")
	for place: String in result.places_reached:
		_count_fact("reached", place)
	for piece: String in result.pieces_entered:
		_count_fact("entered", piece)
	for instance_name: String in result.instances_entered:
		_count_fact(QuestStep.INSTANCE_ENTERED, instance_name)
	for answer: String in result.answers_chosen:
		_count_fact(QuestStep.ANSWERED, answer)
	for event: String in result.world_events:
		_count_fact(QuestStep.EMITTED, event)
	for material: String in result.materials:
		materials[material] = materials.get(material, 0) + result.materials[material]
		_count_obtained(material, result.materials[material])
	for gear_id: String in result.gear:
		gear.owned[gear_id] = gear.owned.get(gear_id, 0) + result.gear[gear_id]
		_count_obtained(gear_id, result.gear[gear_id])
	return ""


## Counts `amount` of the item `item` just obtained (#686) toward the quests, one at a time, so one
## gain can finish a step and count toward the next; it stops once no open step asks for the item,
## so a large amount costs no more than the steps asking for it.
func _count_obtained(item: String, amount: int) -> void:
	for _counted: int in amount:
		var asked: bool = false
		for step: QuestStep in open_steps().values():
			asked = asked or step.counts("obtained", item)
		if not asked:
			return
		_count_fact("obtained", item)


## Spends one of the item `item` the player holds, as using a revive item does (#656); returns why
## it can't (they hold none), or "", and changes nothing when it can't. The last one spent is gone
## from their materials.
func spend(item: String) -> String:
	var count: int = materials.get(item, 0)
	if count <= 0:
		return "no %s to spend" % item
	if count == 1:
		var _erased: bool = materials.erase(item)
	else:
		materials[item] = count - 1
	return ""


## Every dominated monster's id in the player's order (#430): the carried ones first, in their
## order, then the rest in the order dominated.
func order() -> Array[int]:
	var ids: Array[int] = carried.duplicate()
	for monster: DominatedMonster in dominated_monsters:
		if not ids.has(monster.id):
			ids.append(monster.id)
	return ids


## Moves the dominated monster `monster_id` to `place` in the player's order (#430), clamped to the
## order's ends; the first three become the carried ones. Returns why it can't, or "".
func move_monster(monster_id: int, place: int) -> String:
	var ids: Array[int] = order()
	if not ids.has(monster_id):
		return "no dominated monster %d to move" % monster_id
	ids.erase(monster_id)
	var _placed: int = ids.insert(clampi(place, 0, ids.size()), monster_id)
	var by_id: Dictionary[int, DominatedMonster] = {}
	for monster: DominatedMonster in dominated_monsters:
		by_id[monster.id] = monster
	dominated_monsters.clear()
	for id: int in ids:
		dominated_monsters.append(by_id[id])
	carried.assign(ids.slice(0, CARRY_LIMIT))
	return ""


## Why `typed` can't be a character's name, in words, or "": it has to have something besides
## spaces,
## and at most NAME_LIMIT characters.
static func name_problem(typed: String) -> String:
	if typed.strip_edges().is_empty():
		return "A name needs at least one character besides spaces."
	if typed.strip_edges().length() > NAME_LIMIT:
		return "A name can have at most %d characters." % NAME_LIMIT
	return ""


## Adds a newly dominated monster of `species`, with the next id, keeping `short_id` (#700), or a
## stand-in for "".
func _dominate(species: String, short_id: String) -> void:
	var kept: String = short_id if not short_id.is_empty() else ShortId.stand_in(next_monster_id)
	dominated_monsters.append(DominatedMonster.new(next_monster_id, species, 1, kept))
	if carried.size() < CARRY_LIMIT:
		carried.append(next_monster_id)
	next_monster_id += 1


## Counts one fact, then every event the quests it advanced emitted (#575), in the order emitted:
## each as a fact of its own, which can start side quests waiting on it. Only a side quest's start
## waits on an event, and each starts once, so the events always run out.
func _count_fact(condition: String, what: String) -> void:
	var pending: Array[String] = _advance_quests(condition, what)
	while not pending.is_empty():
		var event: String = pending.pop_front()
		pending.append_array(_advance_quests(QuestStep.EMITTED, event))


## Counts one fact (a `condition`, with the species of a domination, the place reached, the piece or
## instance entered, the answer chosen, or the event emitted) toward every quest in the book whose
## current step asks for it, in id order, so quests finished together are listed in the same order
## on every machine. A step that reaches its count hands over to the next one (on a step with
## choices, #573, the one the choice the fact took leads to), and a step that ends the chain, or
## the last one, finishes the quest.
## Saved progress that no longer fits the quest (its data changed since) settles at the next fact
## of any kind: a step already at its count is complete, and a step past the last one finishes the
## quest.
## A side quest the fact starts (#473) is started first, so the same fact can count toward its first
## step; a side quest not started yet counts nothing. Returns the events the steps done and the
## choices taken emit, in that order.
func _advance_quests(condition: String, what: String) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(quest_book.keys())
	ids.sort()
	var emitted: Array[String] = []
	for id: String in ids:
		if not _started(id) and quest_book[id].starts_on.counts(condition, what):
			quest_progress[id] = _progress_of(id)
	for id: String in ids:
		var quest: QuestDefinition = quest_book[id]
		var progress: QuestProgress = _progress_of(id)
		var step: QuestStep = quest.step_at(progress.step)
		var open: bool = step != null and progress.count < step.count
		var waits: bool = open and not step.counts(condition, what)
		if quests_done.has(id) or not _started(id) or waits:
			continue
		progress.count += 1 if open else 0
		if step != null and progress.count >= step.count:
			emitted.append_array(_emits(step, condition, what))
			progress.move_to(quest.next_index(progress.step, condition, what))
		quest_progress[id] = progress
		if progress.step >= quest.steps.size():
			_finish(quest)
	return emitted


## The events `step`, now done by a fact (`condition`, `what`), emits (#575): its own, then that of
## the choice the fact took, the first one for saved progress settling on a fact that takes none,
## as QuestDefinition.next_index goes on.
static func _emits(step: QuestStep, condition: String, what: String) -> Array[String]:
	var choice: QuestStep = step.choice_for(condition, what)
	if choice == null and not step.choices.is_empty():
		choice = step.choices[0]
	var events: Array[String] = []
	for emitter: QuestStep in [step, choice]:
		if emitter != null and not emitter.emits.is_empty():
			events.append(emitter.emits)
	return events


## Finishes `quest`: it's done, leans the player toward its path (#658), and moves the standing
## with the faction it names (#532), held on the scale by Standings.
func _finish(quest: QuestDefinition) -> void:
	var _finished: bool = quest_progress.erase(quest.id)
	quests_done.append(quest.id)
	leaning.lean(quest.path)
	if quest.standing != null:
		# Its faction's id was checked when the quest was read, so the change can't be refused.
		var _moved: String = standings.change(quest.standing.faction, quest.standing.change)


## The step each open quest in the book is on, by quest id in id order: every quest not finished
## yet, started or not (#300: what quest markers point at), except a side quest the player hasn't
## come upon yet (#473).
func open_steps() -> Dictionary[String, QuestStep]:
	var steps: Dictionary[String, QuestStep] = {}
	var ids: Array[String] = []
	ids.assign(quest_book.keys())
	ids.sort()
	for id: String in ids:
		var step: QuestStep = quest_book[id].step_at(_progress_of(id).step)
		if step != null and not quests_done.has(id) and _started(id):
			steps[id] = step
	return steps


## The progress of quest `id`: a fresh one when it hasn't started.
func _progress_of(id: String) -> QuestProgress:
	return quest_progress.get(id, QuestProgress.new())


## Whether quest `id` has started: a quest without a start always has, and a side quest (#473) once
## the player entered its area, which put its progress in the profile. `id` is in the book.
func _started(id: String) -> bool:
	return quest_book[id].starts_on == null or quest_progress.has(id) or quests_done.has(id)


## Why `result` can't be taken over (an empty species, place, piece, instance, answer or world
## event, a nameless or negative material or gear, or more than the save can hold), or "".
func _result_problem(result: Gain) -> String:
	if next_monster_id + result.dominated_species.size() > MAX_NUMBER:
		return "the profile can't hold more monsters"
	var dominated: String = _dominated_problem(result)
	if not dominated.is_empty():
		return dominated
	if result.chests_opened < 0 or result.chests_opened > MAX_NUMBER:
		return "the opened chests' count is invalid"
	var named: Dictionary[String, Array] = {
		"a place reached has no id": result.places_reached,
		"a region piece entered has no id": result.pieces_entered,
		"an instance entered has no name": result.instances_entered,
		"an answer chosen has no id": result.answers_chosen,
		"a world event has no name": result.world_events,
	}
	for why: String in named:
		if named[why].has(""):
			return why
	var counted: String = _count_problem("material", result.materials, materials)
	return counted if not counted.is_empty() else _count_problem("gear", result.gear, gear.owned)


## Why adding the `found` counts, by id, to the `held` ones can't be done, naming each as `what`,
## or "".
static func _count_problem(
		what: String,
		found: Dictionary[String, int],
		held: Dictionary[String, int],
) -> String:
	for id: String in found:
		var count: int = found[id]
		if id.is_empty() or count < 0 or held.get(id, 0) + count > MAX_NUMBER:
			return "%s %s has an invalid count" % [what, id]
	return ""


## Why `result`'s dominated monsters can't be taken over (one without a species, or a short id
## without a monster or that isn't one, #700), or "".
static func _dominated_problem(result: Gain) -> String:
	if result.dominated_species.has(""):
		return "a dominated monster has no species"
	if result.dominated_short_ids.size() > result.dominated_species.size():
		return "a dominated monster's short id has no species"
	for short_id: String in result.dominated_short_ids:
		if not short_id.is_empty() and not ShortId.is_valid(short_id):
			return "a dominated monster's short id %s isn't one" % short_id
	return ""


## The monsters the player carries (#53), in their carried order: the first is their companion
## (#338) until they choose another (#55).
func carried_monsters() -> Array[DominatedMonster]:
	var monsters: Array[DominatedMonster] = []
	for monster_id: int in carried:
		for monster: DominatedMonster in dominated_monsters:
			if monster.id == monster_id:
				monsters.append(monster)
	return monsters


## Whether a dominated monster has this id.
func has_monster(monster_id: int) -> bool:
	for monster: DominatedMonster in dominated_monsters:
		if monster.id == monster_id:
			return true
	return false
