class_name InstanceBlueprints
extends RefCounted
## Instance blueprints (#117): what an instance is loaded from, by name. A blueprint is a region and
## the features an instance has. The region is a fixed region file, regions/<name>.md, or region
## pieces in regions/<name>/ that the seed arranges and, if the blueprint is turned, turns (#57,
## #127). The players start on the region's starts. A blueprint switches game rules on and off by
## listing them (Blueprint.features), what its region holds brings the features that run it
## (RegionFeatures), and they can change during a session; each slice builds its
## own feature (FeatureFactories). What tells blueprints apart is content data, one file each
## (Blueprint, #823).

## The names the code and the tests load blueprints by; the blueprints themselves are the files in
## BlueprintContent.DIR. The playground (#338), which only the tests play (#712).
const BASIC: String = "basic"
## The load test's (#101).
const LOAD: String = "load"
## The glade, where the world starts (#712).
const GLADE: String = "glade"
## A boss-style arena (#127).
const ARENA: String = "arena"
## Room for the upcoming features (#689).
const FOREST: String = "forest"
const OUTPOST: String = "outpost"
## The corrupted glade (#541): the flag that corrupts the glade, and the variant it chooses
## (glade.jsonc). Its corrupting monster emits GLADE_PURIFIED when it faints
## (regions/glade_corrupted.md), whose flag purifies it.
const CORRUPTED_GLADE: String = "glade_corrupted"
const GLADE_PURIFIED: String = "glade_purified"
const REGIONS: String = "res://regions/"
## The region piece an arranged region starts from, holding the players' starts.
const START_PIECE: String = "start.md"


## The name of every blueprint there is, in file name order.
static func names() -> Array[String]:
	var all: Array[String] = []
	all.assign(BlueprintContent.cached().blueprints.keys())
	return all


## The named blueprint's content data, or null when there's none.
static func blueprint(instance_name: String) -> Blueprint:
	return BlueprintContent.cached().blueprints.get(instance_name)


## Whether a blueprint of this name exists.
static func exists(instance_name: String) -> bool:
	return BlueprintContent.cached().blueprints.has(instance_name)


## The variant of the named blueprint that the world's `flags` choose (Blueprint.variants), or "".
static func variant(instance_name: String, flags: Array[String]) -> String:
	var named: Blueprint = blueprint(instance_name)
	if named == null:
		return ""
	for chosen_by: PackedStringArray in named.variants:
		if flags.has(chosen_by[0]):
			return chosen_by[1]
	return ""


## A new instance from the named blueprint, as its state, with `players` players in slots 0 and
## up (none for an instance loaded before anyone walks in, #148), from its `variant_name`'s region
## ("" for its own), or null (with an error) for an unknown name, an unreadable region, more players
## than the region has starts, or an invalid feature order.
static func create(
	instance_name: String,
	seed_value: int,
	players: int = 1,
	variant_name: String = "",
) -> GameState:
	var region: Region = _region_for(instance_name, seed_value, players, variant_name)
	if region == null:
		return null
	var ordered: Array[Feature] = FeatureFactories.build(
		_features(blueprint(instance_name), region),
		_setup(instance_name, region),
	)
	var state: GameState = GameState.new(region, seed_value, ordered)
	if not state.problem.is_empty():
		push_error("instance %s has an invalid feature order: %s" % [instance_name, state.problem])
		return null
	for slot: int in players:
		# Can't be refused: the count is checked above and every slot is new.
		var _player: Entity = state.add_entity(slot, region.starts[slot])
	return state


## The region a new instance of the named blueprint's `variant_name` is loaded with for
## `seed_value` and `players` players, or null (with an error) for an unknown name, an unreadable
## region or more players than the region has starts.
static func _region_for(
	instance_name: String,
	seed_value: int,
	players: int,
	variant_name: String,
) -> Region:
	if not exists(instance_name):
		push_error("unknown instance blueprint: " + instance_name)
		return null
	var region: Region = region_of(instance_name, seed_value, variant_name)
	if not region.problem.is_empty():
		push_error("instance %s has a broken region: %s" % [instance_name, region.problem])
		return null
	if players < 0 or players > region.starts.size():
		var limits: Array = [instance_name, region.starts.size(), players]
		push_error("instance %s takes 0 to %d players, not %d" % limits)
		return null
	return region


## The named blueprint's region for `seed_value`, from its `variant_name`'s region (#529) or, for
## "", its own: the region file as it is, or its region pieces arranged, the start piece first and
## the others by file name, and turned if the blueprint is. Its `problem` says what's wrong.
static func region_of(instance_name: String, seed_value: int, variant_name: String = "") -> Region:
	var region_name: String = variant_name if not variant_name.is_empty() else instance_name
	var path: String = REGIONS + region_name + ".md"
	if FileAccess.file_exists(path):
		return read_region(FileAccess.get_file_as_string(path))
	var folder: String = REGIONS + region_name + "/"
	var files: Array[String] = []
	for file: String in DirAccess.get_files_at(folder):
		if file.ends_with(".md") and file != START_PIECE:
			files.append(file)
	files.sort()
	files.push_front(START_PIECE)
	var pieces: Array[Region] = []
	pieces.assign(files.map(func(file: String) -> Region: return _piece(folder + file)))
	for piece: Region in pieces:
		if not piece.problem.is_empty():
			return piece
	var named: Blueprint = blueprint(instance_name)
	return RegionArranger.arrange(pieces, seed_value, named != null and named.turned)


## The region a Markdown region document describes (RegionDocument), with what every slice places
## on its ground read by that slice (#824).
static func read_region(text: String) -> Region:
	return RegionDocument.parse(text, RegionFeatures.readers())


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


## The ids of the features an instance of `named` in `region` has: the rules its blueprint lists,
## what its region holds (RegionFeatures, #879), and treasure chests when it has a chest table, so
## a variant whose region has none keeps them.
static func _features(named: Blueprint, region: Region) -> Array[String]:
	var listed: Array[String] = named.features.duplicate()
	listed.append_array(RegionFeatures.of(region))
	if not named.chest_table.is_empty():
		listed.append(ChestFeature.ID)
	return listed


## What the named blueprint's features are built from (FeatureSetup) for an instance in `region`.
static func _setup(instance_name: String, region: Region) -> FeatureSetup:
	var named: Blueprint = blueprint(instance_name)
	var setup: FeatureSetup = FeatureSetup.new()
	setup.instance = instance_name
	setup.region = region
	setup.loot_table = named.loot_table
	setup.chest_table = named.chest_table
	setup.wild_species = named.wild_species
	return setup


## The region piece in the file at `path`, every tile of it named after the file (#350).
static func _piece(path: String) -> Region:
	var piece: Region = read_region(FileAccess.get_file_as_string(path))
	if not piece.problem.is_empty():
		piece.problem = "%s: %s" % [path, piece.problem]
	var piece_id: String = path.get_file().get_basename()
	for tile: Vector2i in piece.terrain:
		piece.piece_of[tile] = piece_id
	return piece
