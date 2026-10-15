class_name WorldSave
extends RefCounted
## The world's file (#119): the persistent world, saved next to the profile and apart from it, so
## loading the game puts every player back exactly where they were. Kept like every save
## (SaveStore, #179: an envelope with a checksum, older generations, written atomically). What's
## in it is World.to_data as JSON; reading it back turns JSON's numbers into whole numbers first,
## so the simulation only ever sees integers. Beside the world, under EXPLORED, lies the ground this
## machine's player has explored in it (#215): the player's view, not the world's state, so it's
## read apart from the world, never enters its hash or replays, and bad memory never refuses the
## world. Kept in the world's file, it's saved with the world and goes with it.

const PATH: String = "user://world.json"
## The key of the explored ground beside the world's data, and its format.
const EXPLORED: String = "explored"
const EXPLORED_FORMAT: int = 1
## The farthest a remembered tile's coordinate lies from zero: a tile holds 32-bit numbers.
const MOST_COORDINATE: int = 0x7fff_ffff


## The world saved at `path`; null when there's none, or an empty world whose `problem` says why
## the save is refused (no intact generation, not a world, another format or rules version).
static func load_from(path: String = PATH) -> World:
	if not SaveStore.exists(path):
		return null
	var saved: SaveRead = SaveStore.read_save(path)
	if not saved.problem.is_empty():
		return World.refused(saved.problem)
	return parse(saved.text)


## Saves `world` at `path`, with the ground `explored` in it (per instance name, its tiles);
## returns why it couldn't, or "".
static func save(
		world: World,
		path: String = PATH,
		explored: Dictionary[String, Dictionary] = {},
) -> String:
	return SaveStore.write_save(path, to_text(world, explored))


static func to_text(world: World, explored: Dictionary[String, Dictionary] = {}) -> String:
	var data: Dictionary = world.to_data()
	data[EXPLORED] = explored_data(explored)
	return JSON.stringify(data)


## The world in `text`, or an empty one whose `problem` says why it's refused.
static func parse(text: String) -> World:
	var parsed: Variant = _json(text)
	if parsed is Dictionary:
		# The explored ground is read apart (`load_explored`): bad memory doesn't refuse the world.
		var table: Dictionary = parsed
		var _apart: bool = table.erase(EXPLORED)
	if not parsed is Dictionary or not has_whole_numbers(parsed):
		return World.refused("not a world save, or it holds a number that isn't whole")
	var data: Dictionary = whole_numbers(parsed)
	return World.from_data(data)


## Reads the ground explored in the world saved at `path` into `into`, per instance name its tiles;
## returns why it's refused, whole, leaving `into` empty, or "". A world saved without any (before
## it was kept) has none.
static func load_explored(path: String, into: Dictionary[String, Dictionary]) -> String:
	into.clear()
	if not SaveStore.exists(path):
		return ""
	var saved: SaveRead = SaveStore.read_save(path)
	if not saved.problem.is_empty():
		return saved.problem
	var parsed: Variant = _json(saved.text)
	var table: Dictionary = parsed if parsed is Dictionary else {}
	var data: Variant = table.get(EXPLORED)
	var problem: String = _read_explored(data, into) if data != null else ""
	if not problem.is_empty():
		into.clear()
	return problem


## The ground `explored` as save data: its format, and per instance in name order its tiles, as q
## and r after one another in tile order (DataReader.flat).
static func explored_data(explored: Dictionary[String, Dictionary]) -> Dictionary:
	var names: Array[String] = []
	names.assign(explored.keys())
	names.sort()
	var instances: Array[Dictionary] = []
	for instance_name: String in names:
		var tiles: Array[Vector2i] = []
		tiles.assign(explored[instance_name].keys())
		tiles.sort()
		instances.append({ "name": instance_name, "tiles": DataReader.flat(tiles) })
	return { "format": EXPLORED_FORMAT, "instances": instances }


## Reads the explored ground `data` (as `explored_data` wrote it) into `into`; returns the first
## problem, or "".
static func _read_explored(data: Variant, into: Dictionary[String, Dictionary]) -> String:
	if not data is Dictionary or not has_whole_numbers(data):
		return "not explored ground, or it holds a number that isn't whole"
	var read: DataReader = DataReader.new(whole_numbers(data))
	var format: int = read.whole("format", 0, DataReader.MOST)
	if not read.failed() and format != EXPLORED_FORMAT:
		read.fail("explored ground format %d, this build reads %d" % [format, EXPLORED_FORMAT])
	for entry: DataReader in read.entries("instances"):
		var instance_name: String = entry.text("name")
		if not InstanceBlueprints.exists(instance_name) or into.has(instance_name):
			entry.fail("explored instance %s doesn't exist or is saved twice" % instance_name)
		var numbers: Array[int] = entry.wholes("tiles", -MOST_COORDINATE, MOST_COORDINATE)
		if numbers.size() % 2 != 0:
			entry.fail("the tiles explored in %s hold half a tile" % instance_name)
		var tiles: Dictionary[Vector2i, bool] = {}
		for i: int in range(0, numbers.size() - 1, 2):
			tiles[Vector2i(numbers[i], numbers[i + 1])] = true
		into[instance_name] = tiles
	return read.problem


## The value in the JSON `text`, or null when it isn't JSON.
static func _json(text: String) -> Variant:
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
