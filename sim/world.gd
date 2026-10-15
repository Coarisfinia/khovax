class_name World
extends RefCounted
## The world (#139, #148): every instance it has loaded, by blueprint name, each a GameState of
## its own. Each tick it steps every instance a player is in, in name order, and leaves the others
## loaded but still (until #119 purges them). Every instance's seed comes from the world's seed and
## its name, so the same world loads the same instance the same way however and whenever it's
## reached. Players walk from one instance into the next through exits (#154). Deterministic, like
## everything in sim/.

## The format of the world's save data (`to_data`); data in another one is refused.
const FORMAT: int = 1

## The world's seed, which every instance's own seed is drawn from.
var world_seed: int = 0
## Ticks the world has run. An instance nobody is in doesn't step, so its own tick can lag behind.
var tick: int = 0
## Every loaded instance, by blueprint name.
var instances: Dictionary[String, GameState] = {}
## Why the world couldn't be set up, or "" when it could.
var problem: String = ""
## The blueprint the world starts in: the origin of the world's layout (#187).
var start_name: String = ""
## Each reachable instance's place in the world, worked out once (`offset`).
var _offsets: Dictionary[String, Vector2i] = {}
## Each blueprint's region for the world's seed, arranged once for the layout.
var _regions: Dictionary[String, Region] = {}
## The first problem laying out the web met, or "".
var _layout_problem: String = ""


## A world that starts in the blueprint `start` with `players` players in it; with no `start`, an
## empty one, which only a refused save gives (`from_data`).
func _init(seed_value: int, start: String, players: int = 1) -> void:
	world_seed = seed_value
	start_name = start
	if start.is_empty():
		return
	var first: GameState = InstanceBlueprints.create(start, seed_for(start), players)
	if first == null:
		problem = "the starting instance %s doesn't load" % start
		return
	instances[start] = first


## The seed of the instance loaded from the blueprint `instance_name`: drawn from the world's seed,
## with the name as the stream.
func seed_for(instance_name: String) -> int:
	return Rng.new(world_seed, name_code(instance_name)).next_u32()


## The instance loaded from `instance_name`, loading it with nobody in it the first time, or null
## when it can't load.
func instance(instance_name: String) -> GameState:
	if not instances.has(instance_name):
		var loaded: GameState = InstanceBlueprints.create(instance_name, seed_for(instance_name), 0)
		if loaded == null:
			return null
		instances[instance_name] = loaded
	return instances[instance_name]


## Where tile (0, 0) of the instance `instance_name` lies in the world (#187): every instance of
## the web has a fixed place, so walking out of one exit lands on the tile right next to it in the
## next. Worked out from the web outward from the starting instance: if this instance's exit on `a`
## leads out side `d` into one whose way back is `b`, that one lies at this one's offset plus
## `a + direction(d) - b`. The simulation keeps each instance's own coordinates; views add this.
## Vector2i.ZERO for an instance the web doesn't reach.
func offset(instance_name: String) -> Vector2i:
	if _offsets.is_empty():
		_lay_out()
	return _offsets.get(instance_name, Vector2i.ZERO)


## Why the web can't be laid out as one world, or "" (#187): an exit whose target has no way back to
## it, a second way into an instance that doesn't fit where the first placed it, or two instances
## that would lie on the same tile. The world flow checks it over many seeds, since arranged
## regions vary with them.
func layout_problem() -> String:
	if _offsets.is_empty():
		_lay_out()
	if not _layout_problem.is_empty():
		return _layout_problem
	var taken: Dictionary[Vector2i, String] = {}
	var names: Array[String] = []
	names.assign(_offsets.keys())
	names.sort()
	for instance_name: String in names:
		for tile: Vector2i in _region(instance_name).sorted_tiles():
			var placed: Vector2i = tile + _offsets[instance_name]
			if taken.has(placed):
				return "%s and %s would overlap on %s" % [taken[placed], instance_name, placed]
			taken[placed] = instance_name
	return ""


## Places every instance the web reaches, breadth first from the starting instance, checking every
## exit against the places already given; the first exit that doesn't fit is `_layout_problem`.
func _lay_out() -> void:
	_offsets[start_name] = Vector2i.ZERO
	var queue: Array[String] = [start_name]
	while not queue.is_empty():
		var from: String = queue.pop_front()
		var region: Region = _region(from)
		for i: int in region.exits.size():
			var target: String = region.exit_blueprints[i]
			var back: Vector3i = _way_back(target, from)
			var exit: Vector3i = region.exits[i]
			var outside: Vector2i = Vector2i(exit.x, exit.y) + Hex.DIRECTIONS[exit.z]
			var placed: Vector2i = _offsets[from] + outside - Vector2i(back.x, back.y)
			if back.z < 0:
				_note("%s's exit to %s has no way back" % [from, target])
			elif not _offsets.has(target):
				_offsets[target] = placed
				queue.append(target)
			elif _offsets[target] != placed:
				_note("%s doesn't fit where %s's exit leads into it" % [target, from])


## The exit in `instance_name` that leads back to `from` as (q, r, side), or z = -1 when there's
## none.
func _way_back(instance_name: String, from: String) -> Vector3i:
	var region: Region = _region(instance_name)
	for i: int in region.exits.size():
		if region.exit_blueprints[i] == from:
			return region.exits[i]
	return Vector3i(0, 0, -1)


## The region of the blueprint `instance_name` for the world's seed, arranged once.
func _region(instance_name: String) -> Region:
	if not _regions.has(instance_name):
		_regions[instance_name] = InstanceBlueprints.region_of(
			instance_name,
			seed_for(instance_name),
		)
	return _regions[instance_name]


## Keeps the first layout problem found.
func _note(found: String) -> void:
	if _layout_problem.is_empty():
		_layout_problem = found


## The names of the instances a player is in, in name order: the ones that step.
func active() -> Array[String]:
	var names: Array[String] = []
	for instance_name: String in _sorted_names():
		if _has_player(instances[instance_name]):
			names.append(instance_name)
	return names


## Advances every instance a player is in by one tick, with the tick's commands by slot, then moves
## every player who walked out through an exit into the instance it leads to (#154). Moving them
## only after every instance has stepped means no one steps twice in a tick.
func step(commands: Array[Command]) -> void:
	tick += 1
	var leaving: Array[Array] = []
	for instance_name: String in active():
		var state: GameState = instances[instance_name]
		Simulation.step(state, commands)
		for event: RefCounted in state.events:
			if event is ExitTaken:
				leaving.append([instance_name, event])
	for move: Array in leaving:
		var from: String = move[0]
		var taken: ExitTaken = move[1]
		_walk_through(from, taken)


## The player in `slot`, in whichever instance they are, or null.
func player(slot: int) -> Entity:
	for instance_name: String in _sorted_names():
		var found: Entity = instances[instance_name].player(slot)
		if found != null:
			return found
	return null


## The name of the instance the player in `slot` is in, or "".
func instance_of(slot: int) -> String:
	for instance_name: String in _sorted_names():
		if instances[instance_name].player(slot) != null:
			return instance_name
	return ""


## Moves the player who took `taken` in `from` into the instance it leads to, onto the exit there
## that leads back: an east exit arrives from the west. They stay if that instance can't load or
## has no way back.
func _walk_through(from: String, taken: ExitTaken) -> void:
	var target: GameState = instance(taken.target)
	if target == null:
		return
	var arrival: Vector2i = Vector2i.ZERO
	var found: bool = false
	for i: int in target.region.exits.size():
		if target.region.exit_blueprints[i] == from and not found:
			arrival = Vector2i(target.region.exits[i].x, target.region.exits[i].y)
			found = true
	if not found:
		return
	instances[from].remove_entity(taken.entity_id)
	var _arrived: Entity = target.add_entity(taken.slot, arrival)


## A fingerprint of every loaded instance, in name order, each with its name.
func state_hash() -> int:
	var result: int = _mix(2_166_136_261, tick)
	for instance_name: String in _sorted_names():
		result = _mix(result, name_code(instance_name))
		result = _mix(result, instances[instance_name].state_hash())
	return result


## The whole world as save data (#119): whole numbers, ids, lists and tables only, so it goes into
## JSON as it is, and is the snapshot co-op will resync from later. The seed (in two 32-bit halves,
## as JSON holds no 64-bit number exactly), the starting blueprint, the tick, every loaded instance
## in name order with its state (GameState.to_data), the rules version it was played by and its
## hash, which `from_data` checks. Regions aren't saved: no rule changes one while it's loaded,
## so each is arranged again from its blueprint and seed.
func to_data() -> Dictionary:
	var saved: Array[Dictionary] = []
	for instance_name: String in _sorted_names():
		saved.append({ "name": instance_name, "state": instances[instance_name].to_data() })
	return {
		"format": FORMAT,
		"rules": Simulation.RULES_VERSION,
		"seed": [(world_seed >> 32) & 0xffff_ffff, world_seed & 0xffff_ffff],
		"start": start_name,
		"tick": tick,
		"instances": saved,
		"hash": state_hash(),
	}


## The world `to_data` saved, or an empty one whose `problem` says why it's refused, whole: data
## in another format, or played by other rules (a world can only go on deterministically under the
## rules it was played by), or that doesn't hash as it did when saved (its content changed since).
static func from_data(data: Dictionary) -> World:
	var read: DataReader = DataReader.new(data)
	var format: int = read.whole("format", 0, DataReader.MOST)
	var rules: int = read.whole("rules", 0, DataReader.MOST)
	if not read.failed() and format != FORMAT:
		read.fail("world format %d, this build reads format %d" % [format, FORMAT])
	if not read.failed() and rules != Simulation.RULES_VERSION:
		read.fail("played by rules %d, this build has %d" % [rules, Simulation.RULES_VERSION])
	var halves: Array[int] = read.wholes("seed", 0, 0xffff_ffff)
	var start: String = read.text("start")
	if not read.failed() and (halves.size() != 2 or not InstanceBlueprints.exists(start)):
		read.fail("the world's seed or its starting blueprint %s isn't valid" % start)
	if read.failed():
		return refused(read.problem)
	var world: World = World.new((halves[0] << 32) | halves[1], start, 0)
	world.instances.clear()
	world.tick = read.whole("tick", 0, DataReader.MOST)
	for entry: DataReader in read.entries("instances"):
		world._load_instance(entry)
	# The starting instance stays loaded: replays and the driver start from it.
	if not read.failed() and not world.instances.has(start):
		read.fail("the starting instance %s isn't among the saved ones" % start)
	var saved_hash: int = read.whole("hash", 0, 0xffff_ffff)
	if not read.failed() and world.state_hash() != saved_hash:
		read.fail("the world doesn't hash as it did when saved: its content changed since")
	return world if not read.failed() else refused(read.problem)


## Loads the instance `entry` names from its blueprint and restores its saved state into it.
func _load_instance(entry: DataReader) -> void:
	var instance_name: String = entry.text("name")
	if not InstanceBlueprints.exists(instance_name) or instances.has(instance_name):
		entry.fail("instance %s doesn't exist or is saved twice" % instance_name)
		return
	var loaded: GameState = InstanceBlueprints.create(instance_name, seed_for(instance_name), 0)
	if loaded == null:
		entry.fail("instance %s doesn't load" % instance_name)
		return
	loaded.load_data(entry.read("state"))
	instances[instance_name] = loaded


## An empty world refused for `why`.
static func refused(why: String) -> World:
	var empty: World = World.new(0, "")
	empty.problem = why
	return empty


## A 32-bit number for a blueprint name, the same on every platform: its characters, mixed in.
static func name_code(instance_name: String) -> int:
	var code: int = 2_166_136_261
	for i: int in instance_name.length():
		code = _mix(code, instance_name.unicode_at(i))
	return code


func _sorted_names() -> Array[String]:
	var names: Array[String] = []
	names.assign(instances.keys())
	names.sort()
	return names


static func _has_player(state: GameState) -> bool:
	for slot: int in GameState.MAX_PLAYERS:
		if state.player(slot) != null:
			return true
	return false


## One step of 32-bit FNV-1a, as GameState.state_hash mixes its values.
static func _mix(current: int, word: int) -> int:
	return ((current ^ (word & 0xffff_ffff)) * 16_777_619) & 0xffff_ffff
