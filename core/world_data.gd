class_name WorldData
extends RefCounted
## The world as save data (#119), and reading it back: the format a world is saved in, which
## WorldSave keeps in a file, replays start from and co-op will resync from. World holds the
## instances and runs them; this writes and reads them.

## The format of the world's save data (`of`); data in another one is refused. Format 1 had no
## purging, format 2 no ring seals, format 3 no companions and format 4 no tiles changed in place
## (#530), format 5 no flags or variants (#529); the first three's saves were played by older
## rules, which `to_world` refuses anyway.
const FORMAT: int = 6


## The whole world as save data (#119): whole numbers, ids, lists and tables only, so it goes into
## JSON as it is, and is the snapshot co-op will resync from later. The seed (in two 32-bit halves,
## as JSON holds no 64-bit number exactly), the starting blueprint, the tick, each slot's companion
## species (#338, only the slots that bring one), every loaded instance
## in name order with its state (GameState.to_data), the tick it was left behind (-1 while
## someone is in it) and the variant it was loaded from (#529), every purged blueprint's generation,
## the world's flags, the rules version it was played by and
## its hash, which `to_world` checks. Regions aren't saved whole: each is arranged again from its
## blueprint and seed, and only the tiles rules changed in it since (#530) come with its state.
static func of(world: World) -> Dictionary:
	var saved: Array[Dictionary] = []
	for instance_name: String in world.sorted_names():
		saved.append(
			{
				"name": instance_name,
				"state": world.instances[instance_name].to_data(),
				"left_at": world.left_at.get(instance_name, -1),
				"variant": world.variant_of(instance_name),
			},
		)
	var purged: Array[Dictionary] = []
	for instance_name: String in _sorted(world.generations.keys()):
		purged.append({ "name": instance_name, "generation": world.generations[instance_name] })
	var companions: Array[Dictionary] = []
	for slot: int in GameState.MAX_PLAYERS:
		if not world.companions[slot].is_empty():
			companions.append({ "slot": slot, "species": world.companions[slot] })
	return {
		"format": FORMAT,
		"rules": Simulation.RULES_VERSION,
		"seed": [(world.world_seed >> 32) & 0xffff_ffff, world.world_seed & 0xffff_ffff],
		"start": world.start_name,
		"tick": world.tick,
		"companions": companions,
		"generations": purged,
		"flags": world.flags.duplicate(),
		"instances": saved,
		"hash": world.state_hash(),
	}


## The world that `of` saved, loading its instances from `source`, or an empty one whose `problem`
## says why it's refused, whole: data in another format, or played by other rules (a world can only
## go on deterministically under the rules it was played by), or that doesn't hash as it did when
## saved (its content changed since).
static func to_world(data: Dictionary, source: InstanceSource) -> World:
	var read: DataReader = DataReader.new(data)
	var format: int = read.whole("format", 0, DataReader.MOST)
	var rules: int = read.whole("rules", 0, DataReader.MOST)
	if not read.failed() and format != FORMAT:
		read.fail("world format %d, this build reads format %d" % [format, FORMAT])
	if not read.failed() and rules != Simulation.RULES_VERSION:
		read.fail("played by rules %d, this build has %d" % [rules, Simulation.RULES_VERSION])
	var halves: Array[int] = read.wholes("seed", 0, 0xffff_ffff)
	var start: String = read.text("start")
	if not read.failed() and (halves.size() != 2 or not source.exists(start)):
		read.fail("the world's seed or its starting blueprint %s isn't valid" % start)
	if read.failed():
		return World.refused(read.problem)
	var seed_value: int = (halves[0] << 32) | halves[1]
	# Empty at first, so nothing is loaded or laid out before the flags, variants and generations it
	# depends on are back.
	var world: World = World.new(source, seed_value, "", 0, _companions(read))
	world.start_name = start
	world.tick = read.whole("tick", 0, DataReader.MOST)
	# Generations first: they decide the seeds the instances are loaded with.
	for entry: DataReader in read.entries("generations"):
		_load_generation(world, entry)
	_load_flags(world, read)
	# Every saved variant before any instance loads: an instance's neighbours are read from theirs.
	for entry: DataReader in read.entries("instances"):
		world.variants[entry.text("name")] = entry.text("variant")
	for entry: DataReader in read.entries("instances"):
		_load_instance(world, entry)
	# The starting instance stays loaded: replays and the driver start from it.
	if not read.failed() and not world.instances.has(start):
		read.fail("the starting instance %s isn't among the saved ones" % start)
	var saved_hash: int = read.whole("hash", 0, 0xffff_ffff)
	if not read.failed() and world.state_hash() != saved_hash:
		read.fail("the world doesn't hash as it did when saved: its content changed since")
	return world if not read.failed() else World.refused(read.problem)


## Loads the instance `entry` names from its blueprint and restores its saved state into it.
static func _load_instance(world: World, entry: DataReader) -> void:
	var instance_name: String = entry.text("name")
	if not world.source.exists(instance_name) or world.instances.has(instance_name):
		entry.fail("instance %s doesn't exist or is saved twice" % instance_name)
		return
	var loaded: GameState = world.create_instance(instance_name, 0, entry.text("variant"))
	if loaded == null:
		entry.fail("instance %s doesn't load" % instance_name)
		return
	loaded.load_data(entry.read("state"))
	world.instances[instance_name] = loaded
	# Left behind exactly when nobody is in it, and not so long ago that a step would have purged
	# it.
	var left: int = entry.whole("left_at", -1, world.tick)
	if World.has_player(loaded) != (left < 0):
		entry.fail("instance %s's left_at %d doesn't fit who is in it" % [instance_name, left])
	elif left >= 0 and instance_name != world.start_name and world.tick - left >= World.PURGE_TICKS:
		entry.fail("instance %s was left behind long enough to be purged" % instance_name)
	elif left >= 0:
		world.left_at[instance_name] = left


## Each slot's companion species from the save, by slot, "" for a slot that brings none: every
## species named, each slot at most once.
static func _companions(read: DataReader) -> Array[String]:
	var species: Array[String] = []
	var _sized: int = species.resize(GameState.MAX_PLAYERS)
	for entry: DataReader in read.entries("companions"):
		var slot: int = entry.whole("slot", 0, GameState.MAX_PLAYERS - 1)
		var named: String = entry.text("species")
		if named.is_empty() or not species[slot].is_empty():
			entry.fail("slot %d's companion is nameless or saved twice" % slot)
		species[slot] = named
	return species


## Restores the generation of the purged blueprint `entry` names; the starting instance is never
## purged. An instance is purged at most once a tick (or, by a flag, once before the first), which
## also keeps `seed_for`'s draws bounded.
static func _load_generation(world: World, entry: DataReader) -> void:
	var instance_name: String = entry.text("name")
	var known: bool = world.source.exists(instance_name) and instance_name != world.start_name
	if not known or world.generations.has(instance_name):
		entry.fail("purged instance %s can't be, or is saved twice" % instance_name)
		return
	world.generations[instance_name] = entry.whole("generation", 1, world.tick + 1)


## Restores the world's flags (#529): each named, at most once.
static func _load_flags(world: World, read: DataReader) -> void:
	var value: Variant = read.data.get("flags")
	if not value is Array:
		read.fail("flags isn't a list")
		return
	var flag_list: Array = value
	for flag: Variant in flag_list:
		if not flag is String or str(flag).is_empty() or world.flags.has(str(flag)):
			read.fail("a flag is nameless, not text, or saved twice")
			return
		world.set_flag(str(flag))


static func _sorted(keys: Array) -> Array[String]:
	var names: Array[String] = []
	names.assign(keys)
	names.sort()
	return names
