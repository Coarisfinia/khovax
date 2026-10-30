class_name InstanceBlueprints
extends RefCounted
## Instance blueprints (#117): what an instance is loaded from, by name. A blueprint is a region and
## the features an instance has. The region is a fixed region file, regions/<name>.md, or region
## pieces in regions/<name>/ that the seed arranges and, if the blueprint is turned, turns (#57,
## #127). The players start on the region's starts. A blueprint switches game rules on and off by
## naming a rule set and the rules it adds or drops (Blueprint.features, #941), what its region
## holds brings the features that run it (RegionFeatures), and they can change during a session;
## each slice builds its own feature (FeatureFactories). What tells blueprints apart is content
## data, one file each (Blueprint, #823). The game names no instance: the realms say where the world
## starts and where each exit leads (#865), and only the tests and tools name the ones they load
## (#915).

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


## The name of the blueprint one of whose variants loads the region of its own `region_id`
## (Blueprint.variant_codex, #1448), or "" when none does.
static func variant_owner(region_id: String) -> String:
	for instance_name: String in names():
		if blueprint(instance_name).variant_codex.has(region_id):
			return instance_name
	return ""


## The player-facing name of the place `id`, untranslated (#1710): an instance's, its blueprint's
## name, or a variant's region of its own's (Blueprint.variant_names, #1448); "" for neither.
static func place_name(id: String) -> String:
	var named: Blueprint = blueprint(id)
	if named != null:
		return named.name
	var owner: String = variant_owner(id)
	return blueprint(owner).variant_names.get(id, "") if not owner.is_empty() else ""


## The name the player reads for the place `id` (place_name), translated, or "Unknown place" for
## one there isn't.
static func name_of(id: String) -> String:
	var untranslated: String = place_name(id)
	if untranslated.is_empty():
		return TranslationServer.tr("Unknown place")
	return TranslationServer.tr(untranslated)


## A new instance from the named blueprint, as its state, with `players` players in slots 0 and
## up (none for an instance loaded before anyone walks in, #148), from its `variant_name`'s region
## ("" for its own), starting at the world's tick `world_tick` (#1215), or null (with an error) for
## an unknown name, an unreadable region, more players than the region has starts, or an invalid
## feature order.
static func create(
	instance_name: String,
	seed_value: int,
	players: int = 1,
	variant_name: String = "",
	world_tick: int = 0,
) -> GameState:
	var region: Region = _region_for(instance_name, seed_value, players, variant_name)
	if region == null:
		return null
	var ordered: Array[Feature] = features_for(instance_name, region)
	var state: GameState = GameState.new(region, seed_value, ordered, world_tick)
	if not state.problem.is_empty():
		push_error("instance %s has an invalid feature order: %s" % [instance_name, state.problem])
		return null
	for slot: int in players:
		# Can't be refused: the count is checked above and every slot is new.
		var _player: Entity = state.add_entity(slot, region.starts[slot])
	return state


## The features an instance of the named blueprint has on `region`, in their order: its rules,
## what the region holds and its treasure chests (`_features`), built from its setup. The flows
## put them on a region of their own too.
static func features_for(instance_name: String, region: Region) -> Array[Feature]:
	return FeatureFactories.build(
		_features(blueprint(instance_name), region),
		_setup(instance_name, region),
	)


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
	var files: RegionFiles = RegionFiles.cached(region_name)
	if files.whole:
		var whole: String = files.texts.values()[0]
		return _lead_exits(read_region(whole), instance_name)
	var texts: Dictionary[String, String] = _piece_texts(instance_name, region_name)
	var pieces: Array[Region] = []
	for path: String in _piece_order(texts):
		var text: String = texts.get(path, "")
		var piece: Region = _piece(path, text)
		if not piece.problem.is_empty():
			return piece
		pieces.append(piece)
	var named: Blueprint = blueprint(instance_name)
	var arranged: Region = RegionArranger.arrange(
		pieces,
		seed_value,
		named != null and named.turned,
	)
	return _lead_exits(arranged, instance_name)


## The text of each region piece of the region `region_name`, by its path. A variant's folder
## without a start piece holds only the pieces it changes (#1590), so the rest are those of the
## blueprint `instance_name`, when its region is pieces too: its pieces then arrange like the
## blueprint's own for every seed, as long as each keeps its piece's shape and connectors. A folder
## with a start piece is a whole region of its own.
static func _piece_texts(instance_name: String, region_name: String) -> Dictionary[String, String]:
	var files: RegionFiles = RegionFiles.cached(region_name)
	var texts: Dictionary[String, String] = files.texts.duplicate()
	var own: RegionFiles = RegionFiles.cached(instance_name)
	var changed: Array[String] = []
	for path: String in files.texts:
		changed.append(path.get_file())
	if region_name == instance_name or own.whole or changed.has(START_PIECE):
		return texts
	for path: String in own.texts:
		if not changed.has(path.get_file()):
			texts[path] = own.texts[path]
	return texts


## The paths of the region pieces in `texts`, the start piece first and the others by file name.
static func _piece_order(texts: Dictionary[String, String]) -> Array[String]:
	var paths: Array[String] = []
	var start: String = ""
	for path: String in texts:
		if path.get_file() == START_PIECE:
			start = path
		else:
			paths.append(path)
	paths.sort_custom(func(a: String, b: String) -> bool: return a.get_file() < b.get_file())
	paths.push_front(start)
	return paths


## `region`, the named blueprint's, with each exit leading to the instance its realm draws beside
## the blueprint's on the exit's side (#865); its `problem` says when one leads nowhere.
static func _lead_exits(region: Region, instance_name: String) -> Region:
	if region.exits.is_empty() or not region.problem.is_empty():
		return region
	var realm: Realm = Realms.holding(instance_name)
	for i: int in region.exits.size():
		var side: int = region.exits[i].z
		region.exit_blueprints[i] = realm.beside(instance_name, side) if realm != null else ""
		if region.exit_blueprints[i].is_empty():
			var problem: String = "%s's exit to the %s leads to no instance in its realm"
			region.problem = problem % [instance_name, LegendMeaning.SIDES[side]]
			return region
	return region


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


## The region piece in the file at `path`, whose text is `text`, every tile of it named after the
## file (#350).
static func _piece(path: String, text: String) -> Region:
	var piece: Region = read_region(text)
	if not piece.problem.is_empty():
		piece.problem = "%s: %s" % [path, piece.problem]
	var piece_id: String = path.get_file().get_basename()
	for tile: Vector2i in piece.terrain:
		piece.piece_of[tile] = piece_id
	return piece
