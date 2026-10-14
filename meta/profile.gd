class_name Profile
extends RefCounted
## The player's profile (#37): what lasts between runs, outside the simulation. It changes only at a
## run's boundaries, when a run's result is applied, never per tick. Integers and ids only, like
## everything that feeds a simulation. Saved as versioned JSON: a save in a newer format is refused,
## and once a second format exists, an older one is brought up to date in `parse`, one step at a
## time, before it's read.

## The save format. Bump it with a migration from the format before.
const FORMAT: int = 1
## Active slots at the start (design report: 1, then +1 from a lore quest, +1 at level 50).
const START_SLOTS: int = 1
const MAX_SLOTS: int = 3

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


## Takes over what a finished run brought back: its catches and materials.
func apply(result: RunResult) -> void:
	for species: String in result.caught_species:
		captured_monsters.append(CapturedMonster.new(next_monster_id, species))
		next_monster_id += 1
	for material: String in result.materials:
		materials[material] = materials.get(material, 0) + result.materials[material]
	runs_finished += 1


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
	if unlocked_slots < START_SLOTS or unlocked_slots > MAX_SLOTS or runs_finished < 0:
		return "the save's slots or run count are out of range"
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
		if count < 0:
			return "material %s has a negative count" % material
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


## A JSON number (or anything else) as an integer; -1 for anything that isn't a number.
static func _int(value: Variant) -> int:
	if not (value is int or value is float):
		return -1
	var number: int = type_convert(value, TYPE_INT)
	return number
