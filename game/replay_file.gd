class_name ReplayFile
extends RefCounted
## A replay's file format (#35, #281): JSON text, with the seed and the hashes as strings, since
## JSON
## numbers can't hold every 64-bit integer exactly. Every field is checked for its shape as it's
## read, rather than silently read as 0. Recording and playing a replay is Replay's.

## The file format; a replay in another format is refused, not misread. Format 2 added the starting
## world and format 3 the companions (#338); a replay without them has none and still plays. Format
## 4 gave every command its special attack (#410) and format 5 its totem (#423): an older replay's
## commands fire none and place none.
const FORMAT: int = 6
const REQUIRED: Array[String] = ["format", "rules", "instance", "seed", "players", "ticks"]


## The replay as file text.
static func to_text(replay: Replay) -> String:
	var hashes: Dictionary[String, String] = {}
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
		"companions": replay.companions,
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
	var data: Dictionary = parsed
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
	var companions: Array = data.get("companions", [])
	replay.companions.assign(companions)
	replay.ticks = _int(data["ticks"])
	replay.features = _ints(data.get("features"))
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
## special attack too in format 4, the totem too in format 5, and the focus too since (#436).
static func _value_count(format: int) -> int:
	if format < 4:
		return 1
	if format < 6:
		return format - 2
	return Command.VALUE_COUNT


## Changes recorded with `count` integers per command (the tick and slot before them), each
## widened with zeros to a whole command's: no special attack fired, no totem placed, nothing
## focused.
static func _widened(old: Array[int], count: int) -> Array[int]:
	var stride: int = 2 + count
	var changes: Array[int] = []
	for i: int in range(0, old.size(), stride):
		changes.append_array(old.slice(i, i + stride))
		for _value: int in Command.VALUE_COUNT - count:
			changes.append(0)
	return changes


## The starting world in a replay's data, with JSON's numbers whole again; empty for none, or for
## one that isn't a world's data, which then fails to set up.
static func _start_world(saved: Variant) -> Dictionary:
	var none: Dictionary = {}
	if not saved is Dictionary or not WorldSave.has_whole_numbers(saved):
		return none
	var world: Dictionary = WorldSave.whole_numbers(saved)
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
	for key: String in ["changes", "features"]:
		if not _all_numbers(data.get(key)):
			return "not a replay: its %s aren't a list of numbers" % key
	if not _all_texts(data.get("companions", [])):
		return "not a replay: its companions aren't a list of species"
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


static func _all_texts(values: Variant) -> bool:
	if not values is Array:
		return false
	var items: Array = values
	for item: Variant in items:
		if not item is String:
			return false
	return true


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


static func _all_numbers(values: Variant) -> bool:
	if not values is Array:
		return false
	var items: Array = values
	for item: Variant in items:
		if not _is_number(item):
			return false
	return true


## A JSON number (or anything else) as an integer.
static func _int(value: Variant) -> int:
	var number: int = type_convert(value, TYPE_INT)
	return number


## A JSON array as integers; empty for anything that isn't an array.
static func _ints(values: Variant) -> Array[int]:
	var result: Array[int] = []
	if values is Array:
		var items: Array = values
		for item: Variant in items:
			result.append(_int(item))
	return result
