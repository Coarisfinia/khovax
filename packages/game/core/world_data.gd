class_name WorldData
extends RefCounted
## The world as save data (#119), and reading it back: the format a world is saved in, which
## WorldSave keeps in a file, replays start from and co-op will resync from. World holds the
## instances and runs them; this writes and reads them.

## The format's changes (FormatChanges, #801), one file each. A world is read with every one of them
## and no other, or without only some of INSTANCES_ONLY.
const CHANGES: String = "res://core/format_changes/"
## The format changes that changed only how an instance's state is saved, never the world's own
## data: a save without them is read like one played by other rules (#796), its instances loaded
## fresh, so their states are never read. A change to the world's own data instead gets a step that
## brings an older save's data forward, like the profile's (ProfileSave), or older saves are
## refused.
const INSTANCES_ONLY: Array[String] = ["1137-dominator"]
## The changes of the numbered formats before names (#801), in the order they were numbered: format
## n had the first n - 1. Only the last, format 14, which had them all, is still read.
const NUMBERED: Array[String] = [
	"212-purging",
	"219-ring-seals",
	"338-companions",
	"530-changed-tiles",
	"529-flags-and-variants",
	"53-carried-monsters",
	"655-fainted-monsters",
	"724-world-stores",
	"700-short-ids",
	"784-named-features",
	"802-named-tile-kinds",
	"876-rules-id",
	"1137-dominator",
]


## The whole world as save data (#119): whole numbers, ids, lists and tables only, so it goes into
## JSON as it is, and is the snapshot co-op will resync from later. Its format changes, the seed (in
## two 32-bit halves,
## as JSON holds no 64-bit number exactly), the starting blueprint, the tick, every player's world
## store that isn't empty (#724), in slot order, every loaded instance in name order with its state
## (GameState.to_data), the tick it was left behind (-1 while
## someone is in it) and the variant it was loaded from (#529), every purged blueprint's generation,
## the world's flags, the id of the rules it was played by and
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
				"variant": WorldFlags.variant_of(world, instance_name),
			},
		)
	var purged: Array[Dictionary] = []
	for instance_name: String in StateHash.sorted(world.generations.keys()):
		purged.append({ "name": instance_name, "generation": world.generations[instance_name] })
	var stores: Array[Dictionary] = []
	for slot: int in GameState.MAX_PLAYERS:
		var entries: Array[Dictionary] = world.stores[slot].to_data()
		if not entries.is_empty():
			stores.append({ "slot": slot, "entries": entries })
	return {
		FormatChanges.KEY: FormatChanges.names_in(CHANGES),
		"rules": RulesChanges.id(),
		"seed": [(world.world_seed >> 32) & 0xffff_ffff, world.world_seed & 0xffff_ffff],
		"start": world.start_name,
		"tick": world.tick,
		"stores": stores,
		"generations": purged,
		"flags": world.flags.duplicate(),
		"instances": saved,
		"hash": world.state_hash(),
	}


## The world that `of` saved, loading its instances from `source`, or an empty one whose `problem`
## says why it's refused, whole: data in another format, or that doesn't hash as it did when saved
## (its content changed since). One played by other rules (#796) keeps the world's own data (its
## tick, flags, generations and the players' world stores) and loads its instances fresh, as after
## a purge: an instance can only go on deterministically under the rules it was played by, and is
## arranged anew from its blueprint and seed anyway (`_load_fresh`).
static func to_world(data: Dictionary, source: InstanceSource) -> World:
	var read: DataReader = DataReader.new(data)
	var changes: Array[String] = FormatChanges.read_from(read, CHANGES, NUMBERED)
	var lacking: bool = false
	for change: String in FormatChanges.names_in(CHANGES):
		if not read.failed() and not changes.has(change):
			lacking = true
			if not INSTANCES_ONLY.has(change):
				read.fail("world format without change %s: an older build saved it" % change)
	var fresh: bool = read.text("rules") != RulesChanges.id() or lacking
	var halves: Array[int] = read.wholes("seed", 0, 0xffff_ffff)
	var start: String = read.text("start")
	if not read.failed() and (halves.size() != 2 or not source.exists(start)):
		read.fail("the world's seed or its starting blueprint %s isn't valid" % start)
	if read.failed():
		return World.refused(read.problem)
	var seed_value: int = (halves[0] << 32) | halves[1]
	# Empty at first, so nothing is loaded or laid out before the flags, variants and generations it
	# depends on are back.
	var world: World = World.new(source, seed_value, "", 0)
	_load_stores(world, read)
	world.start_name = start
	# Before any instance loads: each takes it as its world tick, the time of day (#1215), which the
	# save doesn't hold apart.
	world.tick = read.whole("tick", 0, DataReader.MOST)
	# Generations first: they decide the seeds the instances are loaded with.
	for entry: DataReader in read.entries("generations"):
		_load_generation(world, entry, fresh)
	_load_flags(world, read)
	if fresh:
		_load_fresh(world, read)
		return world if not read.failed() else World.refused(read.problem)
	# Every saved variant before any instance loads: an instance's neighbours are read from theirs.
	for entry: DataReader in read.entries("instances"):
		world.variants[entry.text("name")] = entry.text("variant")
	for entry: DataReader in read.entries("instances"):
		_load_instance(world, entry)
	# Every instance's tiles changed in place are back before any sight is worked out: it crosses
	# the seam onto them (#538).
	world.refresh_next_door()
	for entry: DataReader in read.entries("instances"):
		_load_state(world, entry)
	# The starting instance stays loaded: replays and the driver start from it.
	if not read.failed() and not world.instances.has(start):
		read.fail("the starting instance %s isn't among the saved ones" % start)
	var saved_hash: int = read.whole("hash", 0, 0xffff_ffff)
	if not read.failed() and world.state_hash() != saved_hash:
		read.fail("the world doesn't hash as it did when saved: its content changed since")
	return world if not read.failed() else World.refused(read.problem)


## Loads the instances of `world`, saved in `read` under other rules, fresh (#796): the starting
## one,
## and the one each player was in, with them in it again. A player stands on the tile they stood on
## while it's still ground nothing stands on, else on their start in the starting instance, as do
## the players of an instance that no longer exists. Their companions join them by themselves.
static func _load_fresh(world: World, read: DataReader) -> void:
	if world.instance(world.start_name) == null:
		read.fail("the starting instance %s doesn't load" % world.start_name)
		return
	var stood: Dictionary[int, Array] = {}
	for entry: DataReader in read.entries("instances"):
		var flat: Array[int] = entry.read("state").wholes(
			"entities",
			-DataReader.MOST,
			DataReader.MOST,
		)
		# Each entity is its id, slot, q and r.
		for i: int in range(0, flat.size() - 3, 4):
			var slot: int = flat[i + 1]
			if slot >= 0 and slot < GameState.MAX_PLAYERS and not stood.has(slot):
				stood[slot] = [entry.text("name"), Vector2i(flat[i + 2], flat[i + 3])]
	for slot: int in GameState.MAX_PLAYERS:
		if stood.has(slot):
			var instance_name: String = stood[slot][0]
			var tile: Vector2i = stood[slot][1]
			_put_back(world, slot, instance_name, tile)
	for instance_name: String in world.sorted_names():
		if World.has_player(world.instances[instance_name]):
			var _entered: bool = world.left_at.erase(instance_name)


## Puts the player in `slot` back into the freshly loaded instance `instance_name` on `tile`, or on
## their start in the starting instance when it no longer exists or `tile` isn't free ground there.
static func _put_back(world: World, slot: int, instance_name: String, tile: Vector2i) -> void:
	var target: GameState = null
	if world.source.exists(instance_name):
		target = world.instance(instance_name)
	if target != null and target.region.is_walkable(tile):
		var taken: bool = false
		for each: Entity in target.entities:
			taken = taken or each.tile == tile
		if not taken:
			var _back: Entity = target.add_entity(slot, tile)
			return
	var spawn: GameState = world.instances[world.start_name]
	var starts: Array[Vector2i] = spawn.region.starts
	if not starts.is_empty():
		var _spawned: Entity = spawn.add_entity(slot, starts[mini(slot, starts.size() - 1)])


## Loads the instance `entry` names from its blueprint and restores its tiles changed in place.
static func _load_instance(world: World, entry: DataReader) -> void:
	var instance_name: String = entry.text("name")
	if not world.source.exists(instance_name) or world.instances.has(instance_name):
		entry.fail("instance %s doesn't exist or is saved twice" % instance_name)
		return
	var loaded: GameState = world.create_instance(instance_name, 0, entry.text("variant"))
	if loaded == null:
		entry.fail("instance %s doesn't load" % instance_name)
		return
	if not loaded.load_changed_tiles(entry.read("state")):
		return
	world.instances[instance_name] = loaded


## Restores the rest of the saved state of the instance `entry` names, if it loaded, and when it was
## left behind.
static func _load_state(world: World, entry: DataReader) -> void:
	var instance_name: String = entry.text("name")
	var loaded: GameState = world.instances.get(instance_name)
	if loaded == null or entry.failed():
		return
	loaded.load_data(entry.read("state"))
	# Left behind exactly when nobody is in it, and not so long ago that a step would have purged
	# it.
	var left: int = entry.whole("left_at", -1, world.tick)
	if World.has_player(loaded) != (left < 0):
		entry.fail("instance %s's left_at %d doesn't fit who is in it" % [instance_name, left])
	elif (left >= 0
			and instance_name != world.start_name
			and world.tick - left >= world.purge_ticks()):
		entry.fail("instance %s was left behind long enough to be purged" % instance_name)
	elif left >= 0:
		world.left_at[instance_name] = left


## Restores every player's world store from the save into `world` (#724), before any instance
## loads, so every instance shares them (#828): each slot once, entries as PlayerStore reads them.
static func _load_stores(world: World, read: DataReader) -> void:
	var seen: Array[int] = []
	for saved: DataReader in read.entries("stores"):
		var slot: int = saved.whole("slot", 0, GameState.MAX_PLAYERS - 1)
		if seen.has(slot):
			saved.fail("slot %d's world store is saved twice" % slot)
			return
		seen.append(slot)
		for entry: DataReader in saved.entries("entries"):
			world.stores[slot].load_entry(entry)


## Restores the generation of the purged blueprint `entry` names, the starting one's too (#727).
## An instance is purged only inside a step, at most once a tick, which also keeps `seed_for`'s
## draws bounded. Loading `fresh` under other rules (#796), one whose blueprint is gone is dropped.
static func _load_generation(world: World, entry: DataReader, fresh: bool) -> void:
	var instance_name: String = entry.text("name")
	if fresh and not entry.failed() and not world.source.exists(instance_name):
		return
	if not world.source.exists(instance_name) or world.generations.has(instance_name):
		entry.fail("purged instance %s can't be, or is saved twice" % instance_name)
		return
	world.generations[instance_name] = entry.whole("generation", 1, world.tick)


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
		WorldFlags.set_flag(world, str(flag))
