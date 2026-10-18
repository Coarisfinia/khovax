# TODO_REFACTOR_IF_POSSIBLE: IGNORE_DETERMINISM_CHECK (JSON text, whose numbers arrive as floats)
class_name WorldSave
extends RefCounted
## The world's file (#119): the persistent world, saved next to the profile and apart from it, so
## loading the game puts every player back exactly where they were. Kept like every save
## (SaveStore, #179: an envelope with a checksum, older generations, written atomically). What's
## in it is WorldData.of as JSON; reading it back turns JSON's numbers into whole numbers first,
## so the simulation only ever sees integers. Beside the world lies what its owners keep with it
## (BESIDE), read apart by them: the ground this machine's player has explored, under EXPLORED,
## which
## the fog slice reads and writes (ExploredSave, #215, #506). It's saved with the world and goes
## with it, but never enters its hash or replays, and bad memory never refuses the world.

const PATH: String = "user://world.json"
## The key of the explored ground beside the world's data.
const EXPLORED: String = "explored"
## Every key that lies beside the world's data in its file, read apart from the world.
const BESIDE: Array[String] = [EXPLORED]


## The world saved at `path`; null when there's none, or an empty world whose `problem` says why
## the save is refused (no intact generation, not a world, another format or rules version).
static func load_from(path: String = PATH) -> World:
	if not SaveStore.exists(path):
		return null
	var saved: SaveRead = SaveStore.read_save(path)
	if not saved.problem.is_empty():
		return World.refused(saved.problem)
	return parse(saved.text)


## Saves `world` at `path`, with what lies `beside` it (by key, from BESIDE); returns why it
## couldn't, or "".
static func save(world: World, path: String = PATH, beside: Dictionary = {}) -> String:
	return SaveStore.write_save(path, to_text(world, beside))


static func to_text(world: World, beside: Dictionary = {}) -> String:
	var data: Dictionary = WorldData.of(world)
	data.merge(beside)
	return JSON.stringify(data)


## The world in `text`, or an empty one whose `problem` says why it's refused.
static func parse(text: String) -> World:
	var parsed: Variant = json_of(text)
	if parsed is Dictionary:
		# What lies beside is read apart by its owner: bad memory doesn't refuse the world.
		var table: Dictionary = parsed
		for key: String in BESIDE:
			var _apart: bool = table.erase(key)
	if not parsed is Dictionary or not has_whole_numbers(parsed):
		return World.refused("not a world save, or it holds a number that isn't whole")
	var data: Dictionary = whole_numbers(parsed)
	return WorldData.to_world(data, BlueprintSource.new())


## The value in the JSON `text`, or null when it isn't JSON.
static func json_of(text: String) -> Variant:
	# A JSON object reports a parse error through its result instead of logging it.
	var json: JSON = JSON.new()
	return json.data if json.parse(text) == OK else null


## Whether every number in `value`, however deep in lists and tables, is whole and at most
## DataReader.MOST from zero, so `whole_numbers` turns it into an integer exactly.
static func has_whole_numbers(value: Variant) -> bool:
	if value is float:
		var number: float = value
		return number == floorf(number) and absf(number) <= DataReader.MOST
	if value is Array:
		var items: Array = value
		return items.all(has_whole_numbers)
	if value is Dictionary:
		var table: Dictionary = value
		return table.values().all(has_whole_numbers)
	return true


## `value` with every number in it an integer: JSON reads every number as a float. Only for a
## value `has_whole_numbers` holds for.
static func whole_numbers(value: Variant) -> Variant:
	if value is float:
		var whole: int = type_convert(value, TYPE_INT)
		return whole
	if value is Array:
		var items: Array = value
		return items.map(whole_numbers)
	if value is Dictionary:
		var table: Dictionary = value
		var converted: Dictionary = {}
		for key: Variant in table:
			converted[key] = whole_numbers(table[key])
		return converted
	return value
