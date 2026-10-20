class_name ReplayFile
extends RefCounted
## A replay's file format (#35, #281): JSON text, with the seed and the hashes as strings, since
## JSON
## numbers can't hold every 64-bit integer exactly. Every field is checked for its shape as it's
## read, rather than silently read as 0. Recording and playing a replay is Replay's.

## The file format; a replay in another format is refused, not misread. Format 2 added the starting
## world and format 3 the companions (#338); a replay without them has none and still plays. Format
## 4 gave every command its special attack (#410) and format 5 its totem (#423): an older replay's
## commands fire none and place none. Format 8 replaced the companions with every slot's carried
## monsters (#53) and gave every command its swap (#55): an older replay's slots carry just their
## companion, and its commands swap none. Format 9 gave every command its dialog answer (#635): an
## older replay's commands answer none. Format 10 gave every command its territory handed over
## (#638): an older replay's commands hand none over. Format 11 gave every carried monster its short
## id (#700): an older replay's carried monsters get stand-ins by their place (ShortId.stand_in).
## Format 12 gave every command its revive item (#656): an older replay's commands revive none.
## Format 13 gave every command its trap gear (#692): an older replay's commands carry no trap.
## Format 14 gave every command the id of the request from the profile's outbox it carries (#771):
## an older replay's commands carry none, so its hand-overs are applied as they come.
## Format 15 named the features by their ids instead of numbers (#784): an older replay's numbers
## are read as their features' ids (NUMBERED_FEATURES).
const FORMAT: int = 15
## The first format with every slot's carried monsters instead of only its companion.
const CARRIED_FORMAT: int = 8
## The first format with every carried monster's short id.
const SHORT_ID_FORMAT: int = 11
## The first format with the features' ids instead of their numbers.
const NAMED_FEATURES_FORMAT: int = 15
## Each feature's id by the number an older replay names it by (#784): the numbers features had
## before they were named, kept only to read those replays.
const NUMBERED_FEATURES: Dictionary[int, String] = {
	1: MovementFeature.ID,
	2: TrailFeature.ID,
	3: WildMonsterFeature.ID,
	4: DominationFeature.ID,
	5: ChestFeature.ID,
	6: FogFeature.ID,
	7: ExitFeature.ID,
	8: TriggerFeature.ID,
	9: EnrageFeature.ID,
	10: HidingFeature.ID,
	11: DominationLootFeature.ID,
	12: CompanionFeature.ID,
	13: EnteringFeature.ID,
	14: CompanionAttackFeature.ID,
	15: SpecialAttackFeature.ID,
	16: WildAttackFeature.ID,
	17: HealthFeature.ID,
	18: KnockdownFeature.ID,
	19: CompanionSwapFeature.ID,
	20: HarvestFeature.ID,
	21: TypeEffectivenessFeature.ID,
	22: DialogFeature.ID,
	23: TerritoryFeature.ID,
	24: ReviveItemFeature.ID,
	25: SpikesFeature.ID,
	26: NpcFeature.ID,
}
const REQUIRED: Array[String] = ["format", "rules", "instance", "seed", "players", "ticks"]


## The replay as file text.
static func to_text(replay: Replay) -> String:
	var hashes: Dictionary[String, String] = {}
	var carried: Array[Array] = []
	for party: CarriedMonsters in replay.carried:
		carried.append(party.to_data() if party != null else [])
	var sorted: Array[int] = []
	sorted.assign(replay.checkpoints.keys())
	sorted.sort()
	for tick: int in sorted:
		hashes[str(tick)] = str(replay.checkpoints[tick])
	var data: Dictionary[String, Variant] = {
		"format": FORMAT,
		"rules": replay.rules,
		"instance": replay.instance,
		"seed": str(replay.seed_value),
		"players": replay.players,
		"carried": carried,
		"features": replay.features,
		"ticks": replay.ticks,
		"changes": replay.changes,
		"checkpoints": hashes,
	}
	if not replay.start_world.is_empty():
		data["world"] = replay.start_world
	return JSON.stringify(data, "\t", false)


## A replay read from `text`; its `problem` says why when the text isn't a playable replay.
static func parse(text: String) -> Replay:
	var replay: Replay = Replay.new()
	# A JSON object reports a parse error through its result instead of logging it.
	var json: JSON = JSON.new()
	var parsed: Variant = json.data if json.parse(text) == OK else null
	if not parsed is Dictionary:
		replay.problem = "not a replay"
		return replay
	# Every number the game writes is whole, so one that isn't is a damaged replay (#631).
	if not JsonNumbers.all_whole(parsed):
		replay.problem = "not a replay: it holds a number that isn't whole"
		return replay
	var data: Dictionary = JsonNumbers.wholes(parsed)
	replay.problem = _shape_problem(data)
	if not replay.problem.is_empty():
		return replay
	var format: int = _int(data["format"])
	if format < 1 or format > FORMAT:
		replay.problem = "replay format %d, this build reads up to format %d" % [format, FORMAT]
		return replay
	replay.start_world = _start_world(data.get("world", {}))
	if data.has("world") and replay.start_world.is_empty():
		replay.problem = "not a replay: its starting world isn't a world's data"
		return replay
	replay.rules = _int(data["rules"])
	replay.instance = str(data["instance"])
	replay.seed_value = str(data["seed"]).to_int()
	replay.players = _int(data["players"])
	replay.carried = _carried(data, format)
	if replay.carried.has(null):
		replay.problem = "not a replay: its carried monsters aren't short ids with species"
		return replay
	replay.ticks = _int(data["ticks"])
	var listed: Array = data["features"]
	replay.features = _feature_ids(listed, format)
	replay.changes = _ints(data.get("changes"))
	var count: int = _value_count(format)
	if replay.changes.size() % (2 + count) != 0:
		replay.problem = "the recorded commands are cut off"
		return replay
	if count < Command.VALUE_COUNT:
		replay.changes = _widened(replay.changes, count)
	var by_tick: Dictionary = data.get("checkpoints", {})
	for tick: Variant in by_tick:
		replay.checkpoints[str(tick).to_int()] = str(by_tick[tick]).to_int()
	return replay


## How many integers a command is in a replay of `format`: only the move before format 4, the
## special attack too in format 4, the totem too in format 5, the focus too in format 6 (#436), the
## choice to go back to the spawn too in format 7 (#495), the swap too in format 8 (#55), the
## dialog answer too in format 9 (#635), the territory handed over too in formats 10 and 11 (#638),
## the revive item too in format 12 (#656), the trap gear too in format 13 (#692), and the outbox
## request's id too since (#771).
static func _value_count(format: int) -> int:
	if format < 4:
		return 1
	if format < 11:
		return format - 2
	if format < 12:
		return 8
	if format < 13:
		return 9
	if format < 14:
		# Everything but the request's id, which comes last.
		return Command.VALUE_COUNT - 1
	return Command.VALUE_COUNT


## Each slot's carried monsters in the replay's `data` of `format`, null for a slot whose list isn't
## one: its own list, or, in an older format, its species alone (before format 8, the slot's
## companion alone, "" for none), each with the stand-in short id of its place.
static func _carried(data: Dictionary, format: int) -> Array[CarriedMonsters]:
	var parties: Array[CarriedMonsters] = []
	var lists: Array = data.get("carried", [])
	if format >= SHORT_ID_FORMAT:
		for party: Variant in lists:
			parties.append(_valid(CarriedMonsters.of_data(party)))
		return parties
	if format < CARRIED_FORMAT:
		lists = []
		var companions: Array = data.get("companions", [])
		for species: Variant in companions:
			lists.append([species] if str(species) != "" else [])
	for party: Variant in lists:
		var species_list: Array = party
		var named: bool = _all_texts(species_list) and not species_list.has("")
		parties.append(_stood_in(species_list) if named else null)
	return parties


## The species in `species_list`, in order, each with the stand-in short id of its place.
static func _stood_in(species_list: Array) -> CarriedMonsters:
	var party: CarriedMonsters = CarriedMonsters.new()
	for place: int in species_list.size():
		party = party.add(ShortId.stand_in(place + 1), str(species_list[place]))
	return party


## `party` when every short id in it is one, each once, with a named species, null otherwise.
static func _valid(party: CarriedMonsters) -> CarriedMonsters:
	if party == null or party.species.has(""):
		return null
	for place: int in party.size():
		var short_id: String = party.short_ids[place]
		if not ShortId.is_valid(short_id) or party.short_ids.find(short_id) != place:
			return null
	return party


## Changes recorded with `count` integers per command (the tick and slot before them), each
## widened with zeros to a whole command's: no special attack fired, no totem placed, nothing
## focused, no going back to the spawn, no swap, no answer, no territory handed over, no revive
## item, no trap, no request.
static func _widened(old: Array[int], count: int) -> Array[int]:
	var stride: int = 2 + count
	var changes: Array[int] = []
	for i: int in range(0, old.size(), stride):
		changes.append_array(old.slice(i, i + stride))
		for _value: int in Command.VALUE_COUNT - count:
			changes.append(0)
	return changes


## The starting world in a replay's data; empty for none, or for one that isn't a world's data,
## which then fails to set up.
static func _start_world(saved: Variant) -> Dictionary:
	var none: Dictionary = {}
	if not saved is Dictionary:
		return none
	var world: Dictionary = saved
	return world


## Why `data` doesn't have a replay's shape, or "": every field there and of its type, rather than
## silently read as 0.
static func _shape_problem(data: Dictionary) -> String:
	if not data.has_all(REQUIRED):
		return "not a replay: it lacks one of %s" % [REQUIRED]
	for key: String in ["format", "rules", "players", "ticks"]:
		if not _is_number(data[key]):
			return "not a replay: its %s isn't a number" % key
	if not data["seed"] is String or not str(data["seed"]).is_valid_int():
		return "not a replay: its seed isn't a whole number"
	if not _all_numbers(data.get("changes")):
		return "not a replay: its changes aren't a list of numbers"
	if not _all_numbers(data.get("features")) and not _all_texts(data.get("features")):
		return "not a replay: its features aren't a list of numbers or ids"
	if not _all_texts(data.get("companions", [])):
		return "not a replay: its companions aren't a list of species"
	if not _all_lists(data.get("carried", [])):
		return "not a replay: its carried monsters aren't lists"
	var hashes: Variant = data.get("checkpoints", {})
	if not _valid_checkpoints(hashes):
		return "not a replay: its checkpoints aren't ticks with hashes"
	return ""


static func _valid_checkpoints(hashes: Variant) -> bool:
	if not hashes is Dictionary:
		return false
	var by_tick: Dictionary = hashes
	for tick: Variant in by_tick:
		if not str(tick).is_valid_int() or not str(by_tick[tick]).is_valid_int():
			return false
	return true


## Whether `values` is a list of lists, as every format's carried monsters are; what they hold is
## checked as they're read (`_carried`).
static func _all_lists(values: Variant) -> bool:
	if not values is Array:
		return false
	var items: Array = values
	for item: Variant in items:
		if not item is Array:
			return false
	return true


static func _all_texts(values: Variant) -> bool:
	if not values is Array:
		return false
	var items: Array = values
	for item: Variant in items:
		if not item is String:
			return false
	return true


## Whether `value` is a number: by now every number in the replay is an integer.
static func _is_number(value: Variant) -> bool:
	return value is int


static func _all_numbers(values: Variant) -> bool:
	if not values is Array:
		return false
	var items: Array = values
	for item: Variant in items:
		if not _is_number(item):
			return false
	return true


## A number of the replay, already whole, as an integer.
static func _int(value: Variant) -> int:
	var number: int = value
	return number


## The feature ids in a replay of `format`, read from their numbers before format 15 (#784). An
## item of the wrong kind, or a number no feature had, becomes "", which no feature's id is, so the
## replay is refused when it's played.
static func _feature_ids(values: Array, format: int) -> Array[String]:
	var ids: Array[String] = []
	for item: Variant in values:
		var id: String = ""
		if format >= NAMED_FEATURES_FORMAT and item is String:
			id = item
		elif format < NAMED_FEATURES_FORMAT and item is int:
			id = NUMBERED_FEATURES.get(item, "")
		ids.append(id)
	return ids


## A JSON array as integers; empty for anything that isn't an array.
static func _ints(values: Variant) -> Array[int]:
	var result: Array[int] = []
	if values is Array:
		var items: Array = values
		for item: Variant in items:
			result.append(_int(item))
	return result
