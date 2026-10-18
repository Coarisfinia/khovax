class_name ExploredSave
extends RefCounted
## The ground this machine's player has explored (#215), kept beside the world in its file
## (WorldSave.EXPLORED): the player's view, not the world's state, so it's read apart from the
## world, never enters its hash or replays, and bad memory never refuses the world. The fog slice
## owns it (#506), so the world's save never names it.

## The format. Format 2 notes each instance's generation (#212); format 1 had none, from before
## purging: generation 0.
const FORMAT: int = 2
## The farthest a remembered tile's coordinate lies from zero: a tile holds 32-bit numbers.
const MOST_COORDINATE: int = 0x7fff_ffff


## The ground `explored` as what lies beside the world in its file (WorldSave.save).
static func beside(explored: ExploredGround) -> Dictionary:
	return { WorldSave.EXPLORED: explored_data(explored) }


## Reads the ground explored in the world saved at `path` into `into`;
## returns why it's refused, whole, leaving `into` empty, or "". A world saved without the key
## (before it was kept) has none; a key with anything malformed under it, null too, is refused.
static func load_into(path: String, into: ExploredGround) -> String:
	into.clear()
	if not SaveStore.exists(path):
		return ""
	var saved: SaveRead = SaveStore.read_save(path)
	if not saved.problem.is_empty():
		return saved.problem
	var parsed: Variant = WorldSave.json_of(saved.text)
	var table: Dictionary = parsed if parsed is Dictionary else {}
	var problem: String = _read(
		table[WorldSave.EXPLORED],
		into,
	) if table.has(WorldSave.EXPLORED) else ""
	if not problem.is_empty():
		into.clear()
	return problem


## The ground `explored` as save data: its format, and per instance in name order its generation
## and its tiles, as q and r after one another in tile order (DataReader.flat).
static func explored_data(explored: ExploredGround) -> Dictionary:
	var names: Array[String] = []
	names.assign(explored.tiles_in.keys())
	names.sort()
	var instances: Array[Dictionary] = []
	for instance_name: String in names:
		var tiles: Array[Vector2i] = []
		tiles.assign(explored.tiles_in[instance_name].keys())
		tiles.sort()
		instances.append(
			{
				"name": instance_name,
				"generation": explored.generations[instance_name],
				"tiles": DataReader.flat(tiles),
			},
		)
	return { "format": FORMAT, "instances": instances }


## Reads the explored ground `data` (as `explored_data` wrote it) into `into`; returns the first
## problem, or "".
static func _read(data: Variant, into: ExploredGround) -> String:
	if not data is Dictionary or not WorldSave.has_whole_numbers(data):
		return "not explored ground, or it holds a number that isn't whole"
	var read: DataReader = DataReader.new(WorldSave.whole_numbers(data))
	var format: int = read.whole("format", 0, DataReader.MOST)
	if not read.failed() and (format < 1 or format > FORMAT):
		read.fail("explored ground format %d, this build reads %d" % [format, FORMAT])
	for entry: DataReader in read.entries("instances"):
		var instance_name: String = entry.text("name")
		if not InstanceBlueprints.exists(instance_name) or into.tiles_in.has(instance_name):
			entry.fail("explored instance %s doesn't exist or is saved twice" % instance_name)
		var numbers: Array[int] = entry.wholes("tiles", -MOST_COORDINATE, MOST_COORDINATE)
		if numbers.size() % 2 != 0:
			entry.fail("the tiles explored in %s hold half a tile" % instance_name)
		var generation: int = entry.whole("generation", 0, DataReader.MOST) if format > 1 else 0
		var tiles: Dictionary[Vector2i, bool] = into.tiles_of(instance_name, generation)
		for i: int in range(0, numbers.size() - 1, 2):
			tiles[Vector2i(numbers[i], numbers[i + 1])] = true
	return read.problem
