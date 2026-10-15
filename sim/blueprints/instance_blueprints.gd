class_name InstanceBlueprints
extends RefCounted
## Instance blueprints (#117): what an instance is loaded from, by name. A blueprint is a region
## and the features an instance has, in their step order. The region is a fixed region file,
## regions/<name>.region, or region pieces in regions/<name>/ that the seed arranges and, unless
## the blueprint keeps its layout, turns (#57, #127). The players start on the region's starts. A
## blueprint switches game rules on and off by listing them, and they can change during a run.

## The playground: the hand-made region regions/basic.region, walking, a trail per player, the wild
## monsters the region places, and catching them with a ring.
const BASIC: String = "basic"
## The load test's (#101): a big region full of wild monsters, the same rules as every instance.
const LOAD: String = "load"
## The first region arranged from region pieces (#57): a glade the seed puts together and turns.
const GLADE: String = "glade"
## A boss-style arena (#127): one region piece that is never turned, so it plays as it is drawn.
const ARENA: String = "arena"
const NAMES: Array[String] = [BASIC, LOAD, GLADE, ARENA]
## The blueprints whose region pieces keep the layout they're drawn in: the seed doesn't turn them.
const UNTURNED: Array[String] = [ARENA]
const REGIONS: String = "res://regions/"
## The region piece an arranged region starts from, holding the players' starts.
const START_PIECE: String = "start.region"


## Whether a blueprint of this name exists.
static func exists(instance_name: String) -> bool:
	return NAMES.has(instance_name)


## A new instance from the named blueprint, as its state, with `players` players in slots 0 and
## up, or null (with an error) for an unknown name, an unreadable region, more players than the
## region has starts, or an invalid feature order.
static func create(instance_name: String, seed_value: int, players: int = 1) -> GameState:
	if not exists(instance_name):
		push_error("unknown instance blueprint: " + instance_name)
		return null
	var region: Region = region_of(instance_name, seed_value)
	if not region.problem.is_empty():
		push_error("instance %s has a broken region: %s" % [instance_name, region.problem])
		return null
	if players < 1 or players > region.starts.size():
		var limits: Array = [instance_name, region.starts.size(), players]
		push_error("instance %s takes 1 to %d players, not %d" % limits)
		return null
	var ordered: Array[Feature] = [
		MovementFeature.new(),
		TrailFeature.new(),
		WildMonsterFeature.new(),
		CatchFeature.new(),
	]
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


## The basic instance, as `create` makes it.
static func basic(seed_value: int, players: int = 1) -> GameState:
	return create(BASIC, seed_value, players)


static func _piece(path: String) -> Region:
	var piece: Region = Region.parse(FileAccess.get_file_as_string(path))
	if not piece.problem.is_empty():
		piece.problem = "%s: %s" % [path, piece.problem]
	return piece
