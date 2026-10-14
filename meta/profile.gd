class_name Profile
extends RefCounted
## The player's profile (#37): what lasts between runs, outside the simulation. It changes when the
## player obtains something in a run (a Gain, saved at once by ProfileKeeper so a crash loses
## nothing) and when a run finishes, never because of a tick itself. Integers and ids only, like
## everything that feeds a simulation. Saved as versioned JSON: a save in a newer format is refused,
## and once a second format exists, an older one is brought up to date in `parse`, one step at a
## time, before it's read.

## The save format. Bump it with a migration from the format before.
const FORMAT: int = 1
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
var runs_finished: int = 0
## Why the save couldn't be read, or "" when it could.
var problem: String = ""


## Takes over what the player just obtained: its catches and materials. Returns why the gain can't
## be taken over, or "", and changes nothing when it can't: a profile that took over a bad gain
## couldn't be loaded again. ProfileKeeper saves it.
func apply(result: Gain) -> String:
	var refusal: String = _result_problem(result)
	if not refusal.is_empty():
		return refusal
	for species: String in result.caught_species:
		_capture(species)
	for material: String in result.materials:
		materials[material] = materials.get(material, 0) + result.materials[material]
	return ""


## Adds a newly captured monster of `species`, with the next id.
func _capture(species: String) -> void:
	captured_monsters.append(CapturedMonster.new(next_monster_id, species))
	next_monster_id += 1


## Why `result` can't be taken over (an empty species, a nameless or negative material, or more
## than the save can hold), or "".
func _result_problem(result: Gain) -> String:
	if next_monster_id + result.caught_species.size() > MAX_NUMBER:
		return "the profile can't hold more monsters"
	for species: String in result.caught_species:
		if species.is_empty():
			return "a caught monster has no species"
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
		"runs_finished": runs_finished,
	}
	return JSON.stringify(data, "\t", false)


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
	# FORMAT 1 is the first; migrations from older formats go here, oldest first.
	profile.problem = profile._read(data)
	return profile


## Reads current-format data into this profile; returns why it can't, or "".
func _read(data: Dictionary) -> String:
	unlocked_slots = _int(data.get("unlocked_slots"))
	next_monster_id = _int(data.get("next_monster_id"))
	runs_finished = _int(data.get("runs_finished"))
	var counters_valid: bool = next_monster_id >= 1 and runs_finished >= 0
	if unlocked_slots < START_SLOTS or unlocked_slots > MAX_SLOTS or not counters_valid:
		return "the save's slots, next id or run count are out of range"
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
	return ""


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
