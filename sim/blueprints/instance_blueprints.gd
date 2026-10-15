class_name InstanceBlueprints
extends RefCounted
## Instance blueprints (#117): what an instance is loaded from, by name. A blueprint is a region
## and the features an instance has, in their step order. The region is a fixed region file,
## regions/<name>.region, or region pieces in regions/<name>/ that the seed arranges and, unless
## the blueprint keeps its layout, turns (#57, #127). The players start on the region's starts. A
## blueprint switches game rules on and off by listing them, and they can change during a run. One
## with an instance loot table (#90) has treasure chests too, rolling on it (#124).

## The playground: the hand-made region regions/basic.region, walking, a trail per player, the wild
## monsters the region places, catching them with a ring, and fog of war.
const BASIC: String = "basic"
## The load test's (#101): a big region full of wild monsters, the same rules as every instance.
const LOAD: String = "load"
## The first region arranged from region pieces (#57): a glade the seed puts together, east of the
## basic instance (#140).
const GLADE: String = "glade"
## A boss-style arena (#127): one region piece that is never turned, so it plays as it is drawn.
const ARENA: String = "arena"
const NAMES: Array[String] = [BASIC, LOAD, GLADE, ARENA]
## The blueprints whose region pieces keep the layout they're drawn in: the seed doesn't turn them.
## Every instance in the web of exits is one, so an exit always leads out the same way (#120).
const UNTURNED: Array[String] = [GLADE, ARENA]
## Each blueprint's instance loot table (data/loot_tables/), by blueprint: what its chests hold.
const LOOT_TABLES: Dictionary[String, String] = { GLADE: "glade" }
## Which species live in each blueprint, and how likely each is, for the wild monster spots its
## region doesn't name (#133): species id to weight.
const WILD_SPECIES: Dictionary[String, Dictionary] = {
	BASIC: { "moss_toad": 3, "storm_finch": 1 },
	LOAD: { "moss_toad": 1, "storm_finch": 1 },
	GLADE: { "moss_toad": 1 },
	ARENA: { "moss_toad": 1 },
}
const REGIONS: String = "res://regions/"
## The region piece an arranged region starts from, holding the players' starts.
const START_PIECE: String = "start.region"


## Whether a blueprint of this name exists.
static func exists(instance_name: String) -> bool:
	return NAMES.has(instance_name)


## A new instance from the named blueprint, as its state, with `players` players in slots 0 and
## up (none for an instance loaded before anyone walks in, #148), or null (with an error) for an
## unknown name, an unreadable region, more players than the region has starts, or an invalid
## feature order.
static func create(instance_name: String, seed_value: int, players: int = 1) -> GameState:
	if not exists(instance_name):
		push_error("unknown instance blueprint: " + instance_name)
		return null
	var region: Region = region_of(instance_name, seed_value)
	if not region.problem.is_empty():
		push_error("instance %s has a broken region: %s" % [instance_name, region.problem])
		return null
	if players < 0 or players > region.starts.size():
		var limits: Array = [instance_name, region.starts.size(), players]
		push_error("instance %s takes 0 to %d players, not %d" % limits)
		return null
	var ordered: Array[Feature] = [
		MovementFeature.new(),
		TrailFeature.new(),
		_wild_monsters(instance_name),
		CatchFeature.new(),
		FogFeature.new(),
	]
	if LOOT_TABLES.has(instance_name):
		var table: LootTable = _loot_table(LOOT_TABLES[instance_name])
		if table == null:
			push_error("instance %s's loot table doesn't load" % instance_name)
			return null
		ordered.append(ChestFeature.new(table))
	var state: GameState = GameState.new(region, seed_value, ordered)
	if not state.problem.is_empty():
		push_error("instance %s has an invalid feature order: %s" % [instance_name, state.problem])
		return null
	for slot: int in players:
		# Can't be refused: the count is checked above and every slot is new.
		var _player: Entity = state.add_entity(slot, region.starts[slot])
	return state


## The named blueprint's region for `seed_value`: its region file as it is, or its region pieces
## arranged, the start piece first and the others by file name, and turned unless it's UNTURNED.
## Its `problem` says what's wrong.
static func region_of(instance_name: String, seed_value: int) -> Region:
	var path: String = REGIONS + instance_name + ".region"
	if FileAccess.file_exists(path):
		return Region.parse(FileAccess.get_file_as_string(path))
	var folder: String = REGIONS + instance_name + "/"
	var files: Array[String] = []
	for file: String in DirAccess.get_files_at(folder):
		if file.ends_with(".region") and file != START_PIECE:
			files.append(file)
	files.sort()
	files.push_front(START_PIECE)
	var pieces: Array[Region] = []
	pieces.assign(files.map(func(file: String) -> Region: return _piece(folder + file)))
	for piece: Region in pieces:
		if not piece.problem.is_empty():
			return piece
	return RegionArranger.arrange(pieces, seed_value, not UNTURNED.has(instance_name))


## Why the named blueprint's exits don't hold together, or "" (#140): each leads to a blueprint that
## exists and has an exit leading back on the opposite side, so a way out always has a way back.
## The web is checked by the world flow, not each time an instance loads.
static func exit_problem(instance_name: String) -> String:
	var region: Region = region_of(instance_name, 0)
	for i: int in region.exits.size():
		var target: String = region.exit_blueprints[i]
		if not exists(target):
			return "%s's exit leads to %s, which doesn't exist" % [instance_name, target]
		var back: Region = region_of(target, 0)
		var side: int = posmod(region.exits[i].z + 3, Hex.DIRECTIONS.size())
		var found: bool = false
		for j: int in back.exits.size():
			found = found or (back.exit_blueprints[j] == instance_name and back.exits[j].z == side)
		if not found:
			return "%s has no exit back to %s on side %d" % [target, instance_name, side]
	return ""


## The basic instance, as `create` makes it.
static func basic(seed_value: int, players: int = 1) -> GameState:
	return create(BASIC, seed_value, players)


## The wild monster feature with the named blueprint's species list.
static func _wild_monsters(instance_name: String) -> WildMonsterFeature:
	var species: Dictionary = WILD_SPECIES.get(instance_name, { })
	var roster: Array[String] = []
	var weights: Array[int] = []
	for species_id: Variant in species:
		var weight: int = species[species_id]
		roster.append(str(species_id))
		weights.append(weight)
	return WildMonsterFeature.new(roster, weights)


## The instance loot table with this id, or null when the tables don't load or it isn't one.
static func _loot_table(table_id: String) -> LootTable:
	var content: Content = Content.load_loot_tables()
	var table: LootTable = content.loot_tables.get(table_id)
	if not content.problem.is_empty() or table == null or table.kind != LootTable.INSTANCE:
		return null
	return table


static func _piece(path: String) -> Region:
	var piece: Region = Region.parse(FileAccess.get_file_as_string(path))
	if not piece.problem.is_empty():
		piece.problem = "%s: %s" % [path, piece.problem]
	return piece
