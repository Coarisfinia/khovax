class_name Profile
extends RefCounted

## The player's profile (#37): what lasts between sessions, outside the simulation. It changes when
## the player obtains something in the world (a Gain, saved at once by ProfileKeeper so a crash
## loses nothing), never because of a tick itself. Integers and ids only, like everything that
## feeds a simulation. Saved as versioned JSON by ProfileSave (#276). Quest progress (#184) is kept
## here too, advanced by the same gains against the quest definitions it's given, and so are the
## player's personal color (#233), which only views read, and their standings with the factions
## (#483).
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
## Each quest started and not finished, by id: the step it's on and the count within it.
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
	for species: String in result.dominated_species:
		_dominate(species)
		_advance_quests("dominated", species)
	for _chest: int in result.chests_opened:
		_advance_quests("opened", "")
	for place: String in result.places_reached:
		_advance_quests("reached", place)
	for piece: String in result.pieces_entered:
		_advance_quests("entered", piece)
	for instance_name: String in result.instances_entered:
		_advance_quests(QuestStep.INSTANCE_ENTERED, instance_name)
	for material: String in result.materials:
		materials[material] = materials.get(material, 0) + result.materials[material]
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


## Adds a newly dominated monster of `species`, with the next id.
## Why `typed` can't be a character's name, in words, or "": it has to have something besides
## spaces,
## and at most NAME_LIMIT characters.
static func name_problem(typed: String) -> String:
	if typed.strip_edges().is_empty():
		return "A name needs at least one character besides spaces."
	if typed.strip_edges().length() > NAME_LIMIT:
		return "A name can have at most %d characters." % NAME_LIMIT
	return ""


func _dominate(species: String) -> void:
	dominated_monsters.append(DominatedMonster.new(next_monster_id, species))
	if carried.size() < CARRY_LIMIT:
		carried.append(next_monster_id)
	next_monster_id += 1


## Counts one fact (a `condition`, with the species of a domination, the place reached, or the
## piece or instance entered) toward every quest in the book whose current step asks for it, in id
## order, so quests finished together are listed in the same order on every machine. A step that
## reaches its count hands over to the next one, and the last step finishes the quest. Saved
## progress that no longer fits the quest (its data changed since) settles at the next fact of any
## kind: a step already at its count is complete, and a step past the last one finishes the quest.
func _advance_quests(condition: String, what: String) -> void:
	var ids: Array[String] = []
	ids.assign(quest_book.keys())
	ids.sort()
	for id: String in ids:
		var quest: QuestDefinition = quest_book[id]
		var progress: QuestProgress = _progress_of(id)
		var step: QuestStep = quest.step_at(progress.step)
		var open: bool = step != null and progress.count < step.count
		if quests_done.has(id) or (open and not step.counts(condition, what)):
			continue
		progress.count += 1 if open else 0
		if step != null and progress.count >= step.count:
			progress.step += 1
			progress.count = 0
		quest_progress[id] = progress
		if progress.step >= quest.steps.size():
			var _finished: bool = quest_progress.erase(id)
			quests_done.append(id)


## The step each open quest in the book is on, by quest id in id order: every quest not finished
## yet, started or not (#300: what quest markers point at).
func open_steps() -> Dictionary[String, QuestStep]:
	var steps: Dictionary[String, QuestStep] = {}
	var ids: Array[String] = []
	ids.assign(quest_book.keys())
	ids.sort()
	for id: String in ids:
		var step: QuestStep = quest_book[id].step_at(_progress_of(id).step)
		if step != null and not quests_done.has(id):
			steps[id] = step
	return steps


## The progress of quest `id`: a fresh one when it hasn't started.
func _progress_of(id: String) -> QuestProgress:
	return quest_progress.get(id, QuestProgress.new())


## Why `result` can't be taken over (an empty species, place, piece or instance, a nameless or
## negative material, or more than the save can hold), or "".
func _result_problem(result: Gain) -> String:
	if next_monster_id + result.dominated_species.size() > MAX_NUMBER:
		return "the profile can't hold more monsters"
	for species: String in result.dominated_species:
		if species.is_empty():
			return "a dominated monster has no species"
	if result.chests_opened < 0 or result.chests_opened > MAX_NUMBER:
		return "the opened chests' count is invalid"
	if result.places_reached.has(""):
		return "a place reached has no id"
	if result.pieces_entered.has(""):
		return "a region piece entered has no id"
	if result.instances_entered.has(""):
		return "an instance entered has no name"
	for material: String in result.materials:
		var count: int = result.materials[material]
		if material.is_empty() or count < 0 or materials.get(material, 0) + count > MAX_NUMBER:
			return "material %s has an invalid count" % material
	return ""


## The species of the monsters the player carries (#53), in their carried order: the first is their
## companion (#338) until they choose another (#55).
func carried_species() -> PackedStringArray:
	var species: PackedStringArray = []
	for monster_id: int in carried:
		for monster: DominatedMonster in dominated_monsters:
			if monster.id == monster_id:
				var _added: bool = species.append(monster.species)
	return species


## Whether a dominated monster has this id.
func has_monster(monster_id: int) -> bool:
	for monster: DominatedMonster in dominated_monsters:
		if monster.id == monster_id:
			return true
	return false
