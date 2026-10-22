class_name Profile
extends RefCounted

## The player's profile (#37): what lasts between sessions, outside the simulation. It changes when
## the player obtains something in the world (a Gain, saved at once by ProfileKeeper so a crash
## loses nothing), never because of a tick itself. Integers and ids only, like everything that
## feeds a simulation. Saved as versioned JSON by ProfileSave (#276), with what later slices keep
## in its file beside it, like the player's quests (ProfileCompanion, #855). The player's personal
## color (#233), which only views read, is kept here too, and so are their standings with the
## factions (#483), which finishing a quest can move (#532), their gear (#690), and their leaning
## toward the story's paths (#658), which finishing a path-marked quest moves, and its outbox
## (#771): what it asks the world to do, like the hand-over of a territory quest it finished (#638).
## Active slots at the start (design report: 1, then +1 from a lore quest, +1 at level 50).
const START_SLOTS: int = 1
const MAX_SLOTS: int = 3
## How many dominated monsters a player carries (#53), which their carry requests make room for.
const CARRY_LIMIT: int = CarryRequest.MOST_CARRIED
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
## The player's standing with each faction (#483).
var standings: Standings = Standings.new()
## The gear the player owns and what's in their gear slots (#690).
var gear: GearSlots = GearSlots.new()
## How far the player's choices lean them toward harmony and supremacy (#658).
var leaning: PathLeaning = PathLeaning.new()
## The requests the profile asked the world to carry out and the world hasn't acknowledged yet
## (#771).
var outbox: Outbox = Outbox.new()
## The personal color the player chose (#391), as 0xRRGGBB, or AUTO_COLOR. A view's, never the
## simulation's (#233).
var personal_color: int = AUTO_COLOR
## The character's name (#399), the player's own; "" until they name them. Never in the simulation.
var character_name: String = ""
## Why the save couldn't be read, or "" when it could.
var problem: String = ""


## Takes over what the player just obtained: its dominations and its loot. Returns why the gain
## can't be taken over, or "", and changes nothing when it can't: a profile that took over a bad
## gain couldn't be loaded again. ProfileKeeper saves it. What it means to the player's quests is
## counted apart (QuestKeeper).
func apply(result: Gain) -> String:
	var refusal: String = _result_problem(result)
	if not refusal.is_empty():
		return refusal
	for i: int in result.dominated_species.size():
		var short_ids: Array[String] = result.dominated_short_ids
		_dominate(result.dominated_species[i], short_ids[i] if i < short_ids.size() else "")
	for material: String in result.materials:
		materials[material] = materials.get(material, 0) + result.materials[material]
	for gear_id: String in result.gear:
		gear.owned[gear_id] = gear.owned.get(gear_id, 0) + result.gear[gear_id]
	return ""


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


## Why `result` can't be taken over (an empty species, a nameless or negative material or gear, or
## more than the save can hold), or "".
func _result_problem(result: Gain) -> String:
	if next_monster_id + result.dominated_species.size() > MAX_NUMBER:
		return "the profile can't hold more monsters"
	var dominated: String = _dominated_problem(result)
	if not dominated.is_empty():
		return dominated
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
