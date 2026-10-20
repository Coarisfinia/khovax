class_name ProfileSave
extends RefCounted
## A profile's save format (#37, #276): versioned JSON, integers and ids only. A save in a newer
## format is refused, and an older one is brought up to date in `parse`, one step at a time, before
## it's read, every value checked as it's read. What the profile holds and how it changes is
## Profile's.

## The save format. Bump it with a migration from the format before.
const FORMAT: int = 14
## The first quest's id before format 5, and since (#317).
const OLD_FIRST_QUEST: String = "first_catch"
const NEW_FIRST_QUEST: String = "first_domination"
## The species ids before format 14, each to its id since: a species' id is its name (#763).
const OLD_SPECIES: Dictionary[String, String] = {
	"moss_toad": "ombulumo",
	"storm_finch": "tikazzir",
}
## The quest ids before format 14 that named a species by its old id, each to its id since (#763).
const OLD_QUESTS: Dictionary[String, String] = { "three_moss_toads": "three_ombulumo" }


## The profile as save text.
static func to_text(profile: Profile) -> String:
	var monsters: Array = []
	for monster: DominatedMonster in profile.dominated_monsters:
		monsters.append(monster.to_data())
	var data: Dictionary[String, Variant] = {
		"format": FORMAT,
		"unlocked_slots": profile.unlocked_slots,
		"next_monster_id": profile.next_monster_id,
		"dominated_monsters": monsters,
		"carried": profile.carried,
		"materials": _sorted(profile.materials),
		"quest_progress": _progress_data(profile),
		"quests_done": profile.quests_done,
		"personal_color": profile.personal_color,
		"character_name": profile.character_name,
		"standings": _sorted(profile.standings.by_faction),
		"gear": _sorted(profile.gear.owned),
		"equipped": _sorted(profile.gear.equipped),
		"path_leaning": {
			"harmony": profile.leaning.harmony,
			"supremacy": profile.leaning.supremacy,
		},
		"outbox": profile.outbox.to_data(),
	}
	return JSON.stringify(data, "\t", false)


## `by_id` with its keys in order, so a save reads the same on every machine.
static func _sorted(by_id: Dictionary) -> Dictionary:
	var sorted: Dictionary = {}
	var ids: Array = by_id.keys()
	ids.sort()
	for id: Variant in ids:
		sorted[id] = by_id[id]
	return sorted


## The quest progress as save data, by quest id in order.
static func _progress_data(profile: Profile) -> Dictionary:
	var data: Dictionary = {}
	var ids: Array[String] = []
	ids.assign(profile.quest_progress.keys())
	ids.sort()
	for id: String in ids:
		var progress: QuestProgress = profile.quest_progress[id]
		data[id] = { "step": progress.step, "count": progress.count, "done": progress.done }
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
	_migrate(data, format)
	profile.problem = _read(profile, data)
	return profile


## Brings `data` in save format `format` up to the current one, oldest step first.
static func _migrate(data: Dictionary, format: int) -> void:
	# The step from format n to n + 1 is at n - 1, so a save in format n takes every one from there.
	var steps: Array[Callable] = [
		_migrate_to_2,
		_migrate_to_3,
		_migrate_to_4,
		_migrate_to_5,
		_migrate_to_6,
		_migrate_to_7,
		_migrate_to_8,
		_migrate_to_9,
		_migrate_to_10,
		_migrate_to_11,
		_migrate_to_12,
		_migrate_to_13,
		_migrate_to_14,
	]
	for step: int in range(format - 1, steps.size()):
		steps[step].call(data)


## Format 1 to 2: there are no runs (#183, #197), so their count is dropped.
static func _migrate_to_2(data: Dictionary) -> void:
	var _dropped: bool = data.erase("runs_finished")


## Format 2 to 3: quests (#184) start with no progress.
static func _migrate_to_3(data: Dictionary) -> void:
	data["quest_progress"] = {}
	data["quests_done"] = []


## Format 3 to 4: a player carries three monsters (#53), the first three they dominated until their
## base exists. Their key is still `captured_monsters` here, until format 5.
static func _migrate_to_4(data: Dictionary) -> void:
	var carried: Array = []
	var monsters: Variant = data.get("captured_monsters")
	var monster_list: Array = monsters if monsters is Array else []
	for entry: Variant in monster_list.slice(0, Profile.CARRY_LIMIT):
		var fields: Dictionary = entry if entry is Dictionary else {}
		carried.append(fields.get("id"))
	data["carried"] = carried


## Format 4 to 5: monsters are dominated, not captured (#317), so their key and the first quest's
## id are renamed.
static func _migrate_to_5(data: Dictionary) -> void:
	if data.has("captured_monsters"):
		data["dominated_monsters"] = data["captured_monsters"]
		var _renamed: bool = data.erase("captured_monsters")
	_rename_quest(data, OLD_FIRST_QUEST, NEW_FIRST_QUEST)


## Format 5 to 6: the personal color (#391) starts on Auto.
static func _migrate_to_6(data: Dictionary) -> void:
	data["personal_color"] = Profile.AUTO_COLOR


## Format 6 to 7: the character isn't named yet (#399).
static func _migrate_to_7(data: Dictionary) -> void:
	data["character_name"] = ""


## Format 7 to 8: the player is neutral with every faction (#483).
static func _migrate_to_8(data: Dictionary) -> void:
	data["standings"] = {}


## Format 8 to 9: a quest's progress keeps the steps done (#573). Quests had no choices before, so
## every step before the one it's on was done, in order: at most QuestProgress.MAX_DONE of them,
## the latest.
static func _migrate_to_9(data: Dictionary) -> void:
	var progress: Variant = data.get("quest_progress")
	var by_id: Dictionary = progress if progress is Dictionary else {}
	for id: Variant in by_id:
		if by_id[id] is Dictionary:
			var entry: Dictionary = by_id[id]
			var at: int = _int(entry.get("step"))
			entry["done"] = range(maxi(0, at - QuestProgress.MAX_DONE), maxi(0, at))


## Format 9 to 10: the player owns no gear, and their gear slots are empty (#690).
static func _migrate_to_10(data: Dictionary) -> void:
	data["gear"] = {}
	data["equipped"] = {}


## Format 10 to 11: the player leans toward neither path yet (#658). Quests finished before count
## for nothing: the save has no quest data to tell which were path-marked.
static func _migrate_to_11(data: Dictionary) -> void:
	data["path_leaning"] = { "harmony": 0, "supremacy": 0 }


## Format 11 to 12: every dominated monster gets a short id (#700): a stand-in drawn from its id,
## since the one it had in the wild wasn't kept.
static func _migrate_to_12(data: Dictionary) -> void:
	for fields: Dictionary in _monster_entries(data):
		fields["short_id"] = ShortId.stand_in(_int(fields.get("id")))


## The save `data`'s dominated monsters that are tables, for a migration to change in place.
static func _monster_entries(data: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var monsters: Variant = data.get("dominated_monsters")
	var monster_list: Array = monsters if monsters is Array else []
	for entry: Variant in monster_list:
		if entry is Dictionary:
			var fields: Dictionary = entry
			entries.append(fields)
	return entries


## Renames the quest `old_id` to `new_id` in the save `data`'s progress and finished quests.
static func _rename_quest(data: Dictionary, old_id: String, new_id: String) -> void:
	var progress: Variant = data.get("quest_progress")
	var by_id: Dictionary = progress if progress is Dictionary else {}
	if by_id.has(old_id):
		by_id[new_id] = by_id[old_id]
		var _moved: bool = by_id.erase(old_id)
	var done: Variant = data.get("quests_done")
	if done is Array:
		var done_list: Array = done
		var at: int = done_list.find(old_id)
		if at >= 0:
			done_list[at] = new_id


## Format 12 to 13: the outbox is empty (#771). A territory quest finished before had its hand-over
## sent then.
static func _migrate_to_13(data: Dictionary) -> void:
	data["outbox"] = []


## Format 13 to 14: a species' id is its name (#763), so every dominated monster's old species id
## and every quest id that named one are renamed.
static func _migrate_to_14(data: Dictionary) -> void:
	for fields: Dictionary in _monster_entries(data):
		fields["species"] = OLD_SPECIES.get(fields.get("species"), fields.get("species"))
	for old_id: String in OLD_QUESTS:
		_rename_quest(data, old_id, OLD_QUESTS[old_id])


## Reads current-format data into this profile; returns why it can't, or "".
static func _read(profile: Profile, data: Dictionary) -> String:
	profile.unlocked_slots = _int(data.get("unlocked_slots"))
	profile.next_monster_id = _int(data.get("next_monster_id"))
	var slots: int = profile.unlocked_slots
	if slots < Profile.START_SLOTS or slots > Profile.MAX_SLOTS or profile.next_monster_id < 1:
		return "the save's slots or next id are out of range"
	var monsters: Variant = data.get("dominated_monsters")
	var stored: Variant = data.get("materials")
	if not monsters is Array or not stored is Dictionary:
		return "the save lacks its monsters or materials"
	var monster_list: Array = monsters
	for entry: Variant in monster_list:
		var monster: DominatedMonster = _monster(entry)
		if (monster == null
				or monster.id >= profile.next_monster_id
				or profile.has_monster(monster.id)):
			return "a dominated monster in the save is malformed or its id isn't unique"
		profile.dominated_monsters.append(monster)
	var by_name: Dictionary = stored
	var counted: String = _read_counts(by_name, profile.materials)
	if not counted.is_empty():
		return "material " + counted
	profile.personal_color = _color(data.get("personal_color"))
	if profile.personal_color < Profile.AUTO_COLOR:
		return "the save's personal color is invalid"
	var named: Variant = data.get("character_name", "")
	if not named is String:
		return "the save's character name isn't text"
	profile.character_name = named
	if (not profile.character_name.is_empty()
			and not Profile.name_problem(profile.character_name).is_empty()):
		return "the save's character name is invalid"
	var problem: String = ""
	# Each reads its part once the parts before it were sound.
	for reader: Callable in [
		_read_carried,
		_read_standings,
		_read_leaning,
		_read_gear,
		_read_quests,
		_read_outbox,
	]:
		if problem.is_empty():
			problem = reader.call(profile, data)
	return problem


## Reads a save's counts by id, `stored`, into `counts`; returns why one can't be (its id is empty,
## or its count isn't a whole number from 0), or "".
static func _read_counts(stored: Dictionary, counts: Dictionary[String, int]) -> String:
	for id: Variant in stored:
		var count: int = _int(stored[id])
		if count < 0 or str(id).is_empty():
			return "%s has an invalid count" % id
		counts[str(id)] = count
	return ""


## Reads the save's gear and what's in each gear slot (#690); returns why it can't, or "".
static func _read_gear(profile: Profile, data: Dictionary) -> String:
	var owned: Variant = data.get("gear")
	var equipped: Variant = data.get("equipped")
	if not owned is Dictionary or not equipped is Dictionary:
		return "the save lacks its gear"
	var by_id: Dictionary = owned
	var counted: String = _read_counts(by_id, profile.gear.owned)
	if not counted.is_empty():
		return "gear " + counted
	var by_slot: Dictionary = equipped
	for slot: Variant in by_slot:
		var gear_id: String = Content.text_of(by_slot[slot])
		if gear_id.is_empty() or not profile.gear.equip(str(slot), gear_id).is_empty():
			return "the gear in slot %s in the save isn't owned, or the slot isn't one" % slot
	return ""


## Reads the save's standings with the factions into this profile; returns why it can't, or "".
static func _read_standings(profile: Profile, data: Dictionary) -> String:
	var stored: Variant = data.get("standings")
	if not stored is Dictionary:
		return "the save lacks its standings"
	var by_faction: Dictionary = stored
	for faction: Variant in by_faction:
		var standing: int = _standing(by_faction[faction])
		# Neutral is never saved, so a 0 is as wrong as a standing out of range.
		if standing == 0 or not profile.standings.change(str(faction), standing).is_empty():
			return "the standing with faction %s in the save is invalid" % faction
	return ""


## Reads the save's leaning toward the paths (#658) into this profile; returns why it can't, or "":
## a count for each path, each a whole number from 0 to Profile.MAX_NUMBER, and nothing else.
static func _read_leaning(profile: Profile, data: Dictionary) -> String:
	var stored: Variant = data.get("path_leaning")
	var leaning: Dictionary = stored if stored is Dictionary else {}
	profile.leaning.harmony = _int(leaning.get("harmony"))
	profile.leaning.supremacy = _int(leaning.get("supremacy"))
	if leaning.size() != 2 or profile.leaning.harmony < 0 or profile.leaning.supremacy < 0:
		return "the save's path leaning is invalid"
	return ""


## Reads which dominated monsters the save's player carries; returns why it can't, or "".
static func _read_carried(profile: Profile, data: Dictionary) -> String:
	var carried: Variant = data.get("carried")
	if not carried is Array:
		return "the save lacks its carried monsters"
	var ids: Array = carried
	if ids.size() > Profile.CARRY_LIMIT:
		return "a carried monster too many: at most %d" % Profile.CARRY_LIMIT
	for entry: Variant in ids:
		var id: int = _int(entry)
		if not profile.has_monster(id) or profile.carried.has(id):
			return "a carried monster isn't one of the save's, or is carried twice"
		profile.carried.append(id)
	return ""


## Reads the save's quest progress into this profile; returns why it can't, or "".
static func _read_quests(profile: Profile, data: Dictionary) -> String:
	var started: Variant = data.get("quest_progress")
	var done: Variant = data.get("quests_done")
	if not started is Dictionary or not done is Array:
		return "the save lacks its quest progress"
	var done_list: Array = done
	for id: Variant in done_list:
		var text: String = Content.text_of(id)
		if not Content.is_id(text) or profile.quests_done.has(text):
			return "a finished quest in the save has no valid id or is there twice"
		profile.quests_done.append(text)
	var by_id: Dictionary = started
	for id: Variant in by_id:
		var progress: QuestProgress = _quest_progress(by_id[id])
		if progress == null or not Content.is_id(str(id)) or profile.quests_done.has(str(id)):
			return "quest %s's progress in the save is malformed or it's finished" % id
		profile.quest_progress[str(id)] = progress
	return ""


## Reads the save's outbox (#771) into this profile; returns why it can't, or "".
static func _read_outbox(profile: Profile, data: Dictionary) -> String:
	return profile.outbox.load_data(data.get("outbox"))


## A quest's progress from save data, or null when it's malformed: a step and a count, each a
## whole number from 0 to Profile.MAX_NUMBER, and the steps done (#573), at most
## QuestProgress.MAX_DONE of them, each such a number too.
static func _quest_progress(entry: Variant) -> QuestProgress:
	if not entry is Dictionary:
		return null
	var data: Dictionary = entry
	var progress: QuestProgress = QuestProgress.new(_int(data.get("step")), _int(data.get("count")))
	var done: Variant = data.get("done")
	if progress.step < 0 or progress.count < 0 or data.size() != 3 or not done is Array:
		return null
	var done_list: Array = done
	if done_list.size() > QuestProgress.MAX_DONE:
		return null
	for index: Variant in done_list:
		if _int(index) < 0:
			return null
		progress.done.append(_int(index))
	return progress


## A dominated monster from save data, or null when it's malformed.
static func _monster(entry: Variant) -> DominatedMonster:
	if not entry is Dictionary:
		return null
	var data: Dictionary = entry
	var monster: DominatedMonster = DominatedMonster.new(
		_int(data.get("id")),
		str(data.get("species", "")),
		_int(data.get("level")),
		Content.text_of(data.get("short_id")),
	)
	var named: bool = not monster.species.is_empty() and ShortId.is_valid(monster.short_id)
	if monster.id < 1 or not named or monster.level < 1:
		return null
	return monster


## A personal color from save data: Profile.AUTO_COLOR, or a color as 0xRRGGBB; below AUTO_COLOR
## for anything else.
static func _color(value: Variant) -> int:
	# AUTO_COLOR sits right below the colors, so one range takes both.
	return JsonNumbers.whole(value, Profile.AUTO_COLOR, Profile.MAX_COLOR, Profile.AUTO_COLOR - 1)


## A standing from save data: a whole JSON number from Standings.LOWEST to Standings.HIGHEST;
## 0, which a save never holds, for anything else.
static func _standing(value: Variant) -> int:
	return JsonNumbers.whole(value, Standings.LOWEST, Standings.HIGHEST, 0)


## A whole JSON number from 0 to Profile.MAX_NUMBER as an integer; -1 for anything else, so a
## fraction or an out-of-range number is refused instead of rounded.
static func _int(value: Variant) -> int:
	return JsonNumbers.whole(value, 0, Profile.MAX_NUMBER, -1)
