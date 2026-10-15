class_name Profile
extends RefCounted
## The player's profile (#37): what lasts between sessions, outside the simulation. It changes when
## the player obtains something in the world (a Gain, saved at once by ProfileKeeper so a crash
## loses nothing), never because of a tick itself. Integers and ids only, like everything that
## feeds a simulation. Saved as versioned JSON: a save in a newer format is refused, and an older
## one is brought up to date in `parse`, one step at a time, before it's read. Quest progress
## (#184) is kept here too, advanced by the same gains against the quest definitions it's given.

## The save format. Bump it with a migration from the format before.
const FORMAT: int = 3
## Active slots at the start (design report: 1, then +1 from a lore quest, +1 at level 50).
const START_SLOTS: int = 1
const MAX_SLOTS: int = 3
## The largest id, count or number a save may hold: JSON numbers are doubles, which hold every
## whole number up to 2^53 exactly, and this stays far below it.
const MAX_NUMBER: int = Fixed.MAX_AMOUNT

var unlocked_slots: int = START_SLOTS
## Every captured monster, in the order caught.
var captured_monsters: Array[CapturedMonster] = []
## The id the next captured monster gets; ids are never reused.
var next_monster_id: int = 1
## Crafting materials, by id: how many of each.
var materials: Dictionary[String, int] = {}
## Each quest started and not finished, by id: the step it's on and the count within it.
var quest_progress: Dictionary[String, QuestProgress] = {}
## The ids of the quests finished, in the order finished.
var quests_done: Array[String] = []
## The quests gains advance, by id (Content.load_quests): content, not saved. Progress kept for a
## quest that isn't here is kept as it is.
var quest_book: Dictionary[String, QuestDefinition] = {}
## Why the save couldn't be read, or "" when it could.
var problem: String = ""
## Which of the save's generations it was loaded from: 0 the newest, more when newer ones were
## damaged (SaveStore). Not saved.
var loaded_generation: int = 0


## Takes over what the player just obtained: its catches and materials, and every quest they
## advance, one fact at a time, so one gain can finish a step and count toward the next. Returns why
## the gain can't
## be taken over, or "", and changes nothing when it can't: a profile that took over a bad gain
## couldn't be loaded again. ProfileKeeper saves it.
func apply(result: Gain) -> String:
	var refusal: String = _result_problem(result)
	if not refusal.is_empty():
		return refusal
	for species: String in result.caught_species:
		_capture(species)
		_advance_quests("caught", species)
	for _chest: int in result.chests_opened:
		_advance_quests("opened", "")
	for material: String in result.materials:
		materials[material] = materials.get(material, 0) + result.materials[material]
	return ""


## Adds a newly captured monster of `species`, with the next id.
func _capture(species: String) -> void:
	captured_monsters.append(CapturedMonster.new(next_monster_id, species))
	next_monster_id += 1


## Counts one fact (a `condition`, with the species of a catch) toward every quest in the book
## whose current step asks for it. A step that reaches its count hands over to the next one, and
## the last step finishes the quest.
func _advance_quests(condition: String, species: String) -> void:
	for id: String in quest_book:
		var quest: QuestDefinition = quest_book[id]
		var progress: QuestProgress = _progress_of(id)
		var step: QuestStep = quest.step_at(progress.step)
		if quests_done.has(id) or step == null or not step.counts(condition, species):
			continue
		progress.count += 1
		if progress.count >= step.count:
			progress.step += 1
			progress.count = 0
		quest_progress[id] = progress
		if progress.step == quest.steps.size():
			var _finished: bool = quest_progress.erase(id)
			quests_done.append(id)


## The progress of quest `id`: a fresh one when it hasn't started.
func _progress_of(id: String) -> QuestProgress:
	return quest_progress.get(id, QuestProgress.new())


## Why `result` can't be taken over (an empty species, a nameless or negative material, or more
## than the save can hold), or "".
func _result_problem(result: Gain) -> String:
	if next_monster_id + result.caught_species.size() > MAX_NUMBER:
		return "the profile can't hold more monsters"
	for species: String in result.caught_species:
		if species.is_empty():
			return "a caught monster has no species"
	if result.chests_opened < 0 or result.chests_opened > MAX_NUMBER:
		return "the opened chests' count is invalid"
	for material: String in result.materials:
		var count: int = result.materials[material]
		if material.is_empty() or count < 0 or materials.get(material, 0) + count > MAX_NUMBER:
			return "material %s has an invalid count" % material
	return ""


func to_text() -> String:
	var monsters: Array = []
	for monster: CapturedMonster in captured_monsters:
		monsters.append(monster.to_data())
	var sorted_materials: Dictionary = {}
	var names: Array[String] = []
	names.assign(materials.keys())
	names.sort()
	for material: String in names:
		sorted_materials[material] = materials[material]
	var data: Dictionary[String, Variant] = {
		"format": FORMAT,
		"unlocked_slots": unlocked_slots,
		"next_monster_id": next_monster_id,
		"captured_monsters": monsters,
		"materials": sorted_materials,
		"quest_progress": _progress_data(),
		"quests_done": quests_done,
	}
	return JSON.stringify(data, "\t", false)


## The quest progress as save data, by quest id in order.
func _progress_data() -> Dictionary:
	var data: Dictionary = {}
	var ids: Array[String] = []
	ids.assign(quest_progress.keys())
	ids.sort()
	for id: String in ids:
		data[id] = { "step": quest_progress[id].step, "count": quest_progress[id].count }
	return data


## A profile read from a save's text; its `problem` says why when the text isn't a valid save.
static func parse(text: String) -> Profile:
	var profile: Profile = Profile.new()
	var json: JSON = JSON.new()
	var parsed: Variant = json.data if json.parse(text) == OK else null
	if not parsed is Dictionary:
		profile.problem = "not a profile save"
		return profile
	var data: Dictionary = parsed
	var format: int = _int(data.get("format"))
	if format > FORMAT or format < 1:
		profile.problem = "save format %d, this build reads up to format %d" % [format, FORMAT]
		return profile
	# Migrations from older formats, oldest first.
	if format < 2:
		_migrate_to_2(data)
	if format < 3:
		_migrate_to_3(data)
	profile.problem = profile._read(data)
	return profile


## Format 1 to 2: there are no runs (#183, #197), so their count is dropped.
static func _migrate_to_2(data: Dictionary) -> void:
	var _dropped: bool = data.erase("runs_finished")


## Format 2 to 3: quests (#184) start with no progress.
static func _migrate_to_3(data: Dictionary) -> void:
	data["quest_progress"] = {}
	data["quests_done"] = []


## Reads current-format data into this profile; returns why it can't, or "".
func _read(data: Dictionary) -> String:
	unlocked_slots = _int(data.get("unlocked_slots"))
	next_monster_id = _int(data.get("next_monster_id"))
	if unlocked_slots < START_SLOTS or unlocked_slots > MAX_SLOTS or next_monster_id < 1:
		return "the save's slots or next id are out of range"
	var monsters: Variant = data.get("captured_monsters")
	var stored: Variant = data.get("materials")
	if not monsters is Array or not stored is Dictionary:
		return "the save lacks its monsters or materials"
	var monster_list: Array = monsters
	for entry: Variant in monster_list:
		var monster: CapturedMonster = _monster(entry)
		if monster == null or monster.id >= next_monster_id or _has_monster(monster.id):
			return "a captured monster in the save is malformed or its id isn't unique"
		captured_monsters.append(monster)
	var by_name: Dictionary = stored
	for material: Variant in by_name:
		var count: int = _int(by_name[material])
		if count < 0 or str(material).is_empty():
			return "material %s has an invalid count" % material
		materials[str(material)] = count
	return _read_quests(data)


## Reads the save's quest progress into this profile; returns why it can't, or "".
func _read_quests(data: Dictionary) -> String:
	var started: Variant = data.get("quest_progress")
	var done: Variant = data.get("quests_done")
	if not started is Dictionary or not done is Array:
		return "the save lacks its quest progress"
	var done_list: Array = done
	for id: Variant in done_list:
		var text: String = Content.text_of(id)
		if text.is_empty() or quests_done.has(text):
			return "a finished quest in the save has no id or is there twice"
		quests_done.append(text)
	var by_id: Dictionary = started
	for id: Variant in by_id:
		var progress: QuestProgress = _quest_progress(by_id[id])
		if progress == null or str(id).is_empty() or quests_done.has(str(id)):
			return "quest %s's progress in the save is malformed or it's finished" % id
		quest_progress[str(id)] = progress
	return ""


## A quest's progress from save data, or null when it's malformed.
static func _quest_progress(entry: Variant) -> QuestProgress:
	if not entry is Dictionary:
		return null
	var data: Dictionary = entry
	var progress: QuestProgress = QuestProgress.new(_int(data.get("step")), _int(data.get("count")))
	if progress.step < 0 or progress.count < 0 or data.size() != 2:
		return null
	return progress


func _has_monster(monster_id: int) -> bool:
	for monster: CapturedMonster in captured_monsters:
		if monster.id == monster_id:
			return true
	return false


## A captured monster from save data, or null when it's malformed.
static func _monster(entry: Variant) -> CapturedMonster:
	if not entry is Dictionary:
		return null
	var data: Dictionary = entry
	var monster: CapturedMonster = CapturedMonster.new(
		_int(data.get("id")),
		str(data.get("species", "")),
		_int(data.get("level")),
	)
	if monster.id < 1 or monster.species.is_empty() or monster.level < 1:
		return null
	return monster


## A whole JSON number from 0 to MAX_NUMBER as an integer; -1 for anything else, so a fraction or
## an out-of-range number is refused instead of rounded.
static func _int(value: Variant) -> int:
	if not (value is int or value is float):
		return -1
	var number: float = value
	if number != floorf(number) or number < 0.0 or number > MAX_NUMBER:
		return -1
	var whole: int = type_convert(value, TYPE_INT)
	return whole
