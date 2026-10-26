class_name ProfileSave
extends RefCounted
## A profile's save format (#37, #276): versioned JSON, integers and ids only. A save in a newer
## format is refused, and an older one is brought up to date in `parse`, one step at a time, before
## it's read, every value checked as it's read. What the profile holds and how it changes is
## Profile's. What later slices keep in the profile's file, like the player's quests, their
## companions (ProfileCompanion, #855) bring up to date, read and write, keyed to the same format.

## The save format. Bump it with a migration from the format before.
const FORMAT: int = 21
## The species ids before format 14, each to its id since: a species' id is its name (#763).
const OLD_SPECIES: Dictionary[String, String] = {
	"moss_toad": "ombulumo",
	"storm_finch": "tikazzir",
}
## The faction ids before format 15, each to its id since: a faction's id is its name (#909, #976).
const OLD_FACTIONS: Dictionary[String, String] = { "cartographers_guild": "amvrel_velmarai" }
## The instances the territory quests of format 14 hand over (#638): a hand-over of one still in the
## outbox is coded by its faction's old id (Territory.code), so it's coded anew.
const OLD_TERRITORIES: Array[String] = ["forest", "outpost"]
## The instance ids before format 16, each to its Land-speech id since (#909, #975).
const OLD_INSTANCES: Dictionary[String, String] = {
	"glade": "lumwen_hoal",
	"forest": "morwe_wudhen",
	"castle": "dhorvone_stolm",
	"outpost": "edhra_tewk",
	"mountain_pass": "brekhal_varn",
	"arena": "hrunde_orl",
}
## The factions of format 15, whose hand-overs of an old instance a save's outbox may still hold.
const FACTIONS_AT_15: Array[String] = ["amvrel_velmarai"]


## The profile as save text, with its `companions`' parts beside it.
static func to_text(profile: Profile, companions: Array[ProfileCompanion] = []) -> String:
	var monsters: Array = []
	for monster: DominatedMonster in profile.dominated_monsters:
		monsters.append(monster.to_data())
	var data: Dictionary[String, Variant] = {
		"format": FORMAT,
		"unlocked_slots": profile.unlocked_slots,
		"dominated_monsters": monsters,
		"carried": profile.carried,
		"materials": _sorted(profile.materials),
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
	for companion: ProfileCompanion in companions:
		data.merge(companion.beside())
	return JSON.stringify(data, "\t", false)


## `by_id` with its keys in order, so a save reads the same on every machine.
static func _sorted(by_id: Dictionary) -> Dictionary:
	var sorted: Dictionary = {}
	var ids: Array = by_id.keys()
	ids.sort()
	for id: Variant in ids:
		sorted[id] = by_id[id]
	return sorted


## A profile read from a save's text, its `companions` taking over their parts once the profile's
## own are sound; its `problem` says why when the text isn't a valid save.
static func parse(text: String, companions: Array[ProfileCompanion] = []) -> Profile:
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
	for companion: ProfileCompanion in companions:
		companion.migrate(data, format)
	profile.problem = _read(profile, data)
	for companion: ProfileCompanion in companions:
		if profile.problem.is_empty():
			profile.problem = companion.read(data)
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
		_migrate_to_15,
		_migrate_to_16,
		_migrate_to_17,
		_migrate_to_18,
		_migrate_to_19,
		_migrate_to_20,
		_migrate_to_21,
	]
	for step: int in range(format - 1, steps.size()):
		steps[step].call(data)


## Format 1 to 2: there are no runs (#183, #197), so their count is dropped.
static func _migrate_to_2(data: Dictionary) -> void:
	var _dropped: bool = data.erase("runs_finished")


## Format 2 to 3: quests (#184) start, which keep their own keys (QuestSave).
static func _migrate_to_3(_data: Dictionary) -> void:
	return


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


## Format 4 to 5: monsters are dominated, not captured (#317), so their key is renamed.
static func _migrate_to_5(data: Dictionary) -> void:
	if data.has("captured_monsters"):
		data["dominated_monsters"] = data["captured_monsters"]
		var _renamed: bool = data.erase("captured_monsters")


## Format 5 to 6: the personal color (#391) starts on Auto.
static func _migrate_to_6(data: Dictionary) -> void:
	data["personal_color"] = Profile.AUTO_COLOR


## Format 6 to 7: the character isn't named yet (#399).
static func _migrate_to_7(data: Dictionary) -> void:
	data["character_name"] = ""


## Format 7 to 8: the player is neutral with every faction (#483).
static func _migrate_to_8(data: Dictionary) -> void:
	data["standings"] = {}


## Format 8 to 9: a quest's progress keeps the steps done (#573), which the quests' own keys hold
## (QuestSave).
static func _migrate_to_9(_data: Dictionary) -> void:
	return


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


## Format 12 to 13: the outbox is empty (#771). A territory quest finished before had its hand-over
## sent then.
static func _migrate_to_13(data: Dictionary) -> void:
	data["outbox"] = []


## Format 13 to 14: a species' id is its name (#763), so every dominated monster's old species id
## is renamed (the quest ids that named one are QuestSave's).
static func _migrate_to_14(data: Dictionary) -> void:
	for fields: Dictionary in _monster_entries(data):
		fields["species"] = OLD_SPECIES.get(fields.get("species"), fields.get("species"))


## Format 14 to 15: a faction's id is its name (#976), so the standings with a faction by its old
## id move to its new one, and so do the territory hand-overs still in the outbox, whose data codes
## the faction (Territory.code).
static func _migrate_to_15(data: Dictionary) -> void:
	var stored: Variant = data.get("standings")
	var by_faction: Dictionary = stored if stored is Dictionary else {}
	var recoded: Dictionary[int, int] = {}
	for old_id: String in OLD_FACTIONS:
		var new_id: String = OLD_FACTIONS[old_id]
		if by_faction.has(old_id):
			by_faction[new_id] = by_faction[old_id]
			var _moved: bool = by_faction.erase(old_id)
		for instance_name: String in OLD_TERRITORIES:
			recoded[Territory.code(instance_name, old_id)] = Territory.code(instance_name, new_id)
	_recode_territories(data, recoded)


## Format 15 to 16: the instances have Land-speech ids (#975), so a territory hand-over still in the
## outbox carries the code of the old id's flag, and gets the new one's (the quest ids that named an
## instance are QuestSave's).
static func _migrate_to_16(data: Dictionary) -> void:
	var renamed: Dictionary[int, int] = {}
	for old_id: String in OLD_INSTANCES:
		for faction_id: String in FACTIONS_AT_15:
			var new_code: int = Territory.code(OLD_INSTANCES[old_id], faction_id)
			renamed[Territory.code(old_id, faction_id)] = new_code
	_recode_territories(data, renamed)


## Format 16 to 17: the bestiary (#1173) starts, which keeps its own key (BestiarySave).
static func _migrate_to_17(_data: Dictionary) -> void:
	return


## Format 17 to 18: the codex book (#1174) keeps the names the player has met, its own key
## (CodexKeeper).
static func _migrate_to_18(_data: Dictionary) -> void:
	return


## Format 18 to 19: dominated monsters earn progress toward their next level (#1251), none yet.
static func _migrate_to_19(data: Dictionary) -> void:
	for fields: Dictionary in _monster_entries(data):
		fields["progress"] = 0


## Format 19 to 20: the profile keys its dominated monsters on their short ids (#754), so the
## carried ones are named by theirs, and the numbers and the next one go. A number the save
## couldn't hold before (below 1, from the next one up, or held twice) loses its monster's short
## id, and a carried number no monster has stays, so reading refuses either as it did the numbers.
static func _migrate_to_20(data: Dictionary) -> void:
	var next: int = _int(data.get("next_monster_id"))
	var short_ids: Dictionary[int, String] = {}
	for fields: Dictionary in _monster_entries(data):
		var number: int = _int(fields.get("id"))
		if number < 1 or number >= next or short_ids.has(number):
			fields["short_id"] = ""
		short_ids[number] = Content.text_of(fields.get("short_id"))
		var _numbered: bool = fields.erase("id")
	var carried: Variant = data.get("carried")
	var numbers: Array = carried if carried is Array else []
	for place: int in numbers.size():
		numbers[place] = short_ids.get(_int(numbers[place]), numbers[place])
	var _next: bool = data.erase("next_monster_id")


## Format 20 to 21: the quests keep the one the player follows (#1298) and the order side quests
## started in, their own keys (QuestSave).
static func _migrate_to_21(_data: Dictionary) -> void:
	return


## Gives each territory hand-over still in the save `data`'s outbox whose code `recoded` names the
## code it maps to.
static func _recode_territories(data: Dictionary, recoded: Dictionary[int, int]) -> void:
	var outbox: Variant = data.get("outbox")
	var requests: Array = outbox if outbox is Array else []
	for entry: Variant in requests:
		var fields: Dictionary = entry if entry is Dictionary else {}
		var kind: int = JsonNumbers.whole(fields.get("kind"), 0, DataReader.MOST, -1)
		var code: int = JsonNumbers.whole(fields.get("data"), 0, DataReader.MOST, -1)
		if kind == OutboxEntry.TERRITORY and recoded.has(code):
			fields["data"] = recoded[code]


## Reads current-format data into this profile; returns why it can't, or "".
static func _read(profile: Profile, data: Dictionary) -> String:
	profile.unlocked_slots = _int(data.get("unlocked_slots"))
	var slots: int = profile.unlocked_slots
	if slots < Profile.START_SLOTS or slots > Profile.MAX_SLOTS:
		return "the save's slots are out of range"
	var monsters: Variant = data.get("dominated_monsters")
	var stored: Variant = data.get("materials")
	if not monsters is Array or not stored is Dictionary:
		return "the save lacks its monsters or materials"
	var monster_list: Array = monsters
	for entry: Variant in monster_list:
		var monster: DominatedMonster = _monster(entry)
		if monster == null or profile.has_monster(monster.short_id):
			return "a dominated monster in the save is malformed or its short id isn't unique"
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
		var id: String = Content.text_of(entry)
		if not profile.has_monster(id) or profile.carried.has(id):
			return "a carried monster isn't one of the save's, or is carried twice"
		profile.carried.append(id)
	return ""


## Reads the save's outbox (#771) into this profile; returns why it can't, or "".
static func _read_outbox(profile: Profile, data: Dictionary) -> String:
	return profile.outbox.load_data(data.get("outbox"))


## A dominated monster from save data, or null when it's malformed.
static func _monster(entry: Variant) -> DominatedMonster:
	if not entry is Dictionary:
		return null
	var data: Dictionary = entry
	var monster: DominatedMonster = DominatedMonster.new(
		str(data.get("species", "")),
		_int(data.get("level")),
		Content.text_of(data.get("short_id")),
		_int(data.get("progress")),
	)
	var named: bool = not monster.species.is_empty() and ShortId.is_valid(monster.short_id)
	if not named or monster.level < 1:
		return null
	# Progress always stays below what its level needs.
	if monster.progress < 0 or monster.progress >= DominatedMonster.progress_needed(monster.level):
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
