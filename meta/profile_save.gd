class_name ProfileSave
extends RefCounted
## A profile's save format (#37, #276): versioned JSON, integers and ids only. A save in a newer
## format is refused, and an older one is brought up to date in `parse`, one step at a time, before
## it's read, every value checked as it's read. What the profile holds and how it changes is
## Profile's.

## The save format. Bump it with a migration from the format before.
const FORMAT: int = 3


## The profile as save text.
static func to_text(profile: Profile) -> String:
	var monsters: Array = []
	for monster: CapturedMonster in profile.captured_monsters:
		monsters.append(monster.to_data())
	var sorted_materials: Dictionary = {}
	var names: Array[String] = []
	names.assign(profile.materials.keys())
	names.sort()
	for material: String in names:
		sorted_materials[material] = profile.materials[material]
	var data: Dictionary[String, Variant] = {
		"format": FORMAT,
		"unlocked_slots": profile.unlocked_slots,
		"next_monster_id": profile.next_monster_id,
		"captured_monsters": monsters,
		"materials": sorted_materials,
		"quest_progress": _progress_data(profile),
		"quests_done": profile.quests_done,
	}
	return JSON.stringify(data, "\t", false)


## The quest progress as save data, by quest id in order.
static func _progress_data(profile: Profile) -> Dictionary:
	var data: Dictionary = {}
	var ids: Array[String] = []
	ids.assign(profile.quest_progress.keys())
	ids.sort()
	for id: String in ids:
		var progress: QuestProgress = profile.quest_progress[id]
		data[id] = { "step": progress.step, "count": progress.count }
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
	profile.problem = _read(profile, data)
	return profile


## Format 1 to 2: there are no runs (#183, #197), so their count is dropped.
static func _migrate_to_2(data: Dictionary) -> void:
	var _dropped: bool = data.erase("runs_finished")


## Format 2 to 3: quests (#184) start with no progress.
static func _migrate_to_3(data: Dictionary) -> void:
	data["quest_progress"] = {}
	data["quests_done"] = []


## Reads current-format data into this profile; returns why it can't, or "".
static func _read(profile: Profile, data: Dictionary) -> String:
	profile.unlocked_slots = _int(data.get("unlocked_slots"))
	profile.next_monster_id = _int(data.get("next_monster_id"))
	var slots: int = profile.unlocked_slots
	if slots < Profile.START_SLOTS or slots > Profile.MAX_SLOTS or profile.next_monster_id < 1:
		return "the save's slots or next id are out of range"
	var monsters: Variant = data.get("captured_monsters")
	var stored: Variant = data.get("materials")
	if not monsters is Array or not stored is Dictionary:
		return "the save lacks its monsters or materials"
	var monster_list: Array = monsters
	for entry: Variant in monster_list:
		var monster: CapturedMonster = _monster(entry)
		if (monster == null
				or monster.id >= profile.next_monster_id
				or profile.has_monster(monster.id)):
			return "a captured monster in the save is malformed or its id isn't unique"
		profile.captured_monsters.append(monster)
	var by_name: Dictionary = stored
	for material: Variant in by_name:
		var count: int = _int(by_name[material])
		if count < 0 or str(material).is_empty():
			return "material %s has an invalid count" % material
		profile.materials[str(material)] = count
	return _read_quests(profile, data)


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


## A quest's progress from save data, or null when it's malformed: a step and a count, each a
## whole number from 0 to Profile.MAX_NUMBER.
static func _quest_progress(entry: Variant) -> QuestProgress:
	if not entry is Dictionary:
		return null
	var data: Dictionary = entry
	var progress: QuestProgress = QuestProgress.new(_int(data.get("step")), _int(data.get("count")))
	if progress.step < 0 or progress.count < 0 or data.size() != 2:
		return null
	return progress


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


## A whole JSON number from 0 to Profile.MAX_NUMBER as an integer; -1 for anything else, so a
## fraction or
## an out-of-range number is refused instead of rounded.
static func _int(value: Variant) -> int:
	if not (value is int or value is float):
		return -1
	var number: float = value
	if number != floorf(number) or number < 0.0 or number > Profile.MAX_NUMBER:
		return -1
	var whole: int = type_convert(value, TYPE_INT)
	return whole
