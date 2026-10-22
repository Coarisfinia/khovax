class_name BestiarySave
extends RefCounted
## The player's bestiary's part of the profile's save (#1173): what they've learned about each
## species (`bestiary`), kept in the profile's file by BestiaryKeeper, its companion. Ids and
## integers only, every value checked as it's read, and brought up to date from older formats at
## the profile's save format (ProfileSave.FORMAT), like the quests' part (QuestSave).

## The save format that brought the bestiary: older saves start with an empty one.
const SINCE_FORMAT: int = 17
const KEY: String = "bestiary"


## `bestiary` as save data, by key: each species' level and habitat, in id order.
static func beside(bestiary: Bestiary) -> Dictionary:
	var by_id: Dictionary = {}
	var ids: Array[String] = []
	ids.assign(bestiary.levels.keys())
	ids.sort()
	for id: String in ids:
		by_id[id] = { "level": bestiary.level_of(id), "habitat": bestiary.habitat_of(id) }
	return { KEY: by_id }


## Brings the save `data`, in save format `format`, up to the current one.
static func migrate(data: Dictionary, format: int) -> void:
	# Format 16 to 17: the player has learned nothing about any species yet (#1173).
	if format < SINCE_FORMAT:
		data[KEY] = {}


## Reads the current-format save `data`'s bestiary into `bestiary`, which has nothing yet; returns
## why it can't, or "".
static func read(bestiary: Bestiary, data: Dictionary) -> String:
	var stored: Variant = data.get(KEY)
	if not stored is Dictionary:
		return "the save lacks its bestiary"
	var by_id: Dictionary = stored
	for id: Variant in by_id:
		var entry: Dictionary = by_id[id] if by_id[id] is Dictionary else {}
		var level: int = JsonNumbers.whole(entry.get("level"), Bestiary.SEEN, Bestiary.KNOWN, 0)
		var habitat: Variant = entry.get("habitat")
		if not Content.is_id(str(id)) or level == 0 or entry.size() != 2 or not habitat is Array:
			return "species %s in the save's bestiary is malformed" % id
		bestiary.learn(str(id), level, "")
		var places: Array = habitat
		for place: Variant in places:
			var where: String = Content.text_of(place)
			if not Content.is_id(where) or bestiary.habitat_of(str(id)).has(where):
				return "species %s's habitat in the save is malformed" % id
			bestiary.learn(str(id), level, where)
	return ""
